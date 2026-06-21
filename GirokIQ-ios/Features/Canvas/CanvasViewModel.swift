import Foundation
import Combine
import SwiftUI
import PencilKit
import Realtime
import Photos
import UIKit

extension Notification.Name {
    static let lassoDrawingMutated = Notification.Name("girokiq.lassoDrawingMutated")
}

/// Data driving the brief rough→clean morph shown when a stroke snaps to a shape.
/// Points are in canvas space and projected to screen by the overlay.
struct ShapeSnapMorph: Identifiable {
    let id = UUID()
    let fromPoints: [CGPoint]
    let toPoints: [CGPoint]
    let closed: Bool
    let color: Color
    let width: CGFloat
}

// MARK: - Canvas ViewModel

// MARK: - Canvas ViewModel

@MainActor
final class CanvasViewModel: ObservableObject {

    // MARK: - Properties

    @Published var pages: [DrawingPage] = [DrawingPage(title: "Page 1")]
    @Published var currentPageIndex: Int = 0
    @Published var selectedTool: DrawingTool = .pen
    @Published var strokeColor: Color = Color(hex: UserDefaults.standard.string(forKey: "savedStrokeColorHex") ?? "#FFFFFE") {
        didSet { 
            UserDefaults.standard.set(strokeColor.hexString, forKey: "savedStrokeColorHex")
            updateCurrentToolMemory()
        }
    }
    @Published var strokeWidth: CGFloat = UserDefaults.standard.double(forKey: "savedStrokeWidth") == 0 ? 2.0 : CGFloat(UserDefaults.standard.double(forKey: "savedStrokeWidth")) {
        didSet { 
            UserDefaults.standard.set(Double(strokeWidth), forKey: "savedStrokeWidth")
            updateCurrentToolMemory()
        }
    }
    @Published var strokeOpacity: Double = UserDefaults.standard.double(forKey: "savedStrokeOpacity") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "savedStrokeOpacity") {
        didSet { 
            UserDefaults.standard.set(strokeOpacity, forKey: "savedStrokeOpacity")
            updateCurrentToolMemory()
        }
    }
    @Published var strokeStyle: StrokeStyle = .solid
    @Published var penStyle: PKInkingTool.InkType = {
        let saved = UserDefaults.standard.string(forKey: "savedPenStyle") ?? "pen"
        switch saved {
        case "fountainPen": return .fountainPen
        case "monoline": return .monoline
        case "watercolor": return .watercolor
        case "crayon": return .crayon
        default: return .pen
        }
    }() {
        didSet {
            let name: String
            switch penStyle {
            case .fountainPen: name = "fountainPen"
            case .monoline: name = "monoline"
            case .watercolor: name = "watercolor"
            case .crayon: name = "crayon"
            default: name = "pen"
            }
            UserDefaults.standard.set(name, forKey: "savedPenStyle")
        }
    }
    @Published var eraserType: PKEraserTool.EraserType = UserDefaults.standard.string(forKey: "savedEraserType") == "vector" ? .vector : .bitmap {
        didSet { UserDefaults.standard.set(eraserType == .vector ? "vector" : "bitmap", forKey: "savedEraserType") }
    }
    @Published var backgroundPattern: BackgroundPattern = .grid
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var restoredViewport: CanvasViewportState?
    // Initial value is .zero — the correct size is written by PKCanvasRepresentable's 
    // updateUIView on the first render pass, before any user interaction can occur. 
    // Using UIScreen.main.bounds.size here was both deprecated (iOS 16+) and wrong 
    // in Split View / Stage Manager contexts. 
    var canvasViewSize: CGSize = .zero
    @Published var showProperties: Bool = true
    @Published var isSaving: Bool = false
    @Published var palmRejectionEnabled: Bool = true
    @Published var isToolbarVisible: Bool = true
    @Published var isShapeSnappingEnabled: Bool = UserDefaults.standard.bool(forKey: "shapeSnapEnabled") {
        didSet { UserDefaults.standard.set(isShapeSnappingEnabled, forKey: "shapeSnapEnabled") }
    }
    /// Active rough→clean morph for the shape-snap transition (nil when idle).
    @Published var shapeSnapMorph: ShapeSnapMorph?
    @Published var forceDrawingUpdate: Bool = false
    @Published var isRegionCaptureMode: Bool = false
    @Published var showCanvasImagePicker: Bool = false
    @Published var pendingImageInsertionPoint: CGPoint? = nil
    @Published var inlineAIHighlightRect: CGRect? = nil

    // MARK: - Keyboard / Viewport (Text Tool)
    @Published var keyboardHeight: CGFloat = 0
    /// Scroll/zoom surface that represents the current viewport.
    /// Infinite canvas: PKCanvasView. Fixed canvas: outer UIScrollView.
    weak var viewportScrollView: UIScrollView?

    // MARK: - Canvas Context Menu (empty-canvas long press)
    /// Anchor point in canvas space (same coordinate system as CanvasElement.positionX/Y).
    @Published var canvasContextMenuPoint: CGPoint? = nil
    private var isChangingTool = false

    // Per-tool memory: remember last-used color + width per tool
    @Published var toolMemory: [DrawingTool: ToolSettings] = {
        if let data = UserDefaults.standard.data(forKey: "toolMemory"),
           let decoded = try? JSONDecoder().decode([DrawingTool: ToolSettings].self, from: data) {
            return decoded
        }
        return [:]
    }() {
        didSet {
            if let encoded = try? JSONEncoder().encode(toolMemory) {
                UserDefaults.standard.set(encoded, forKey: "toolMemory")
            }
        }
    }

    // Per-tool customization: preset colors + user colors + preset widths
    @Published var toolCustomizations: [DrawingTool: ToolCustomization] = {
        if let data = UserDefaults.standard.data(forKey: "toolCustomizations"),
           let decoded = try? JSONDecoder().decode([DrawingTool: ToolCustomization].self, from: data) {
            return decoded
        }
        return [:]
    }() {
        didSet {
            if let encoded = try? JSONEncoder().encode(toolCustomizations) {
                UserDefaults.standard.set(encoded, forKey: "toolCustomizations")
            }
        }
    }

    private(set) var notebook: Notebook?
    var notebookId: UUID?
    var userId: UUID?

    // Web presence: tracks whether this notebook is also open on the web app
    @Published var webPresence: [PresenceEntry] = []
    var isOpenOnWeb: Bool { !webPresence.isEmpty }
    private var presenceChannel: RealtimeChannelV2?

    // Photo Library State
    @Published var hasPhotoAccess: Bool = false
    @Published var recentPhotos: [PHAsset] = []
    @Published var recentPhotoImages: [PHAsset: UIImage] = [:]

    // UndoManager forwarded from PKCanvasView
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    /// Reference to the PKCanvasView's undoManager, set by PKCanvasRepresentable
    weak var pkUndoManager: UndoManager?

    /// Cached page thumbnails keyed by page ID.
    /// Regenerated only when drawing data changes, not on every frame.
    @Published var pageThumbnails: [UUID: UIImage] = [:]

    private let service = SupabaseService.shared
    private var autoSaveTask: Task<Void, Never>?
    private var toolbarHideTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var drawingSerializationTask: Task<Void, Never>?
    private var shapeSnapTask: Task<Void, Never>?
    private var liveDrawingCache: [UUID: PKDrawing] = [:]
    private var pendingSerializedDrawingData: [UUID: Data] = [:]
    private var lastKnownStrokeCounts: [UUID: Int] = [:]
    var currentPage: DrawingPage {
        get { pages[currentPageIndex] }
        set { pages[currentPageIndex] = newValue }
    }

    var currentDrawing: PKDrawing {
        let page = pages[currentPageIndex]
        if let cached = liveDrawingCache[page.id] {
            return cached
        }
        let drawing = page.pkDrawing
        liveDrawingCache[page.id] = drawing
        lastKnownStrokeCounts[page.id] = drawing.strokes.count
        return drawing
    }

    private func resolvedDrawing(for page: DrawingPage) -> PKDrawing {
        if let cached = liveDrawingCache[page.id] {
            return cached
        }
        return page.pkDrawing
    }

    private func resolvedDrawingData(for page: DrawingPage) -> Data? {
        if let pending = pendingSerializedDrawingData[page.id] {
            return pending
        }
        if let cached = liveDrawingCache[page.id] {
            return PencilKitBridge.serialize(cached)
        }
        return page.drawingData
    }

    func setCanvasViewSizeIfNeeded(_ size: CGSize) {
        guard canvasViewSize != size else { return }
        canvasViewSize = size
    }

    // MARK: - Export
    func exportNotebookPDF() -> URL? {
        let drawings = pages.map { resolvedDrawing(for: $0) }
        let pdfData = PencilKitBridge.renderPDF(from: drawings)

        let safeName = (notebook?.name ?? "GirokIQ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(safeName)-\(Date().timeIntervalSince1970).pdf"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: url)
            return url
        } catch {
            print("[Canvas] Failed to export PDF: \(error)")
            return nil
        }
    }

    func exportNotebookArchive() -> URL? {
        guard let notebook else { return nil }

        let snapshotPages = pages.enumerated().map { index, page in
            NotebookTransferPage(
                title: page.title,
                pageIndex: index,
                type: "canvas",
                backgroundPattern: page.backgroundPattern.rawValue,
                drawingData: resolvedDrawingData(for: page),
                elements: page.elements
            )
        }

        let package = NotebookTransferPackage(
            version: 1,
            notebook: NotebookTransferNotebook(
                name: notebook.name,
                canvasType: notebook.canvasType,
                pageDimensions: notebook.pageDimensions,
                backgroundPattern: notebook.backgroundPattern,
                backgroundColorHex: notebook.backgroundColorHex
            ),
            pages: snapshotPages
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(package)
            let safeName = notebook.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeName).girokiq")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("[Canvas] Failed to export notebook archive: \(error)")
            return nil
        }
    }

    // MARK: - Context Summary

    func canvasContextSummary() -> String {
        var summary = "Canvas Type: \(notebook?.canvasType ?? "unknown")\n"
        
        let page = currentPage
        summary += "Elements on page:\n"
        
        // 1. Analyze PencilKit Ink
        let strokes = resolvedDrawing(for: page).strokes
        summary += "- \(strokes.count) handwritten ink strokes\n"
        
        // 2. Images
        let imageElements = page.elements.filter { $0.type == "image" }
        if !imageElements.isEmpty {
            summary += "- \(imageElements.count) images\n"
        }
        
        let textElements = page.elements.filter { $0.type == "text" }
        if !textElements.isEmpty {
            summary += "- \(textElements.count) text blocks\n"
        }
        
        return summary
    }

    // MARK: - Loading

    func loadNotebook(notebook: Notebook, userId: UUID) async {
        let notebookId = notebook.id
        self.notebook = notebook
        self.notebookId = notebookId
        self.userId = userId
        self.restoredViewport = Self.loadViewportState(for: notebookId)
        
        // Restore the notebook-level background pattern so the canvas opens
        // with the correct pattern instead of always falling back to .grid.
        if let pattern = BackgroundPattern(rawValue: notebook.backgroundPattern) {
            self.backgroundPattern = pattern
        }
        
        do {
            let fetchedPages = try await LocalDatabase.shared.fetchPages(notebookId: notebookId)
            
            if fetchedPages.isEmpty {
                // First time opening the notebook: create an initial page
                let newPageId = UUID()
                let initialPage = Page(
                    id: newPageId,
                    userId: userId,
                    notebookId: notebookId,
                    title: "Page 1",
                    pageIndex: 0,
                    type: "canvas",
                    settings: PageSettings(backgroundPattern: backgroundPattern.rawValue)
                )
                try await LocalDatabase.shared.savePage(initialPage)
                
                self.pages = [DrawingPage(id: newPageId, title: "Page 1", backgroundPattern: backgroundPattern, order: 0)]
                self.liveDrawingCache[newPageId] = PKDrawing()
                self.lastKnownStrokeCounts[newPageId] = 0
            } else {
                // Load existing pages
                self.pages = fetchedPages.map { tuple in
                    let bgPattern = BackgroundPattern(rawValue: tuple.page.settings?.backgroundPattern ?? "grid") ?? .grid
                    return DrawingPage(
                        id: tuple.page.id,
                        title: tuple.page.title,
                        drawingData: tuple.drawingData,
                        backgroundPattern: bgPattern,
                        order: tuple.page.pageIndex,
                        elements: tuple.page.settings?.elements ?? []
                    )
                }
                self.liveDrawingCache.removeAll()
                self.pendingSerializedDrawingData.removeAll()
                self.lastKnownStrokeCounts = Dictionary(
                    uniqueKeysWithValues: self.pages.map { page in
                        let count = page.drawingData.flatMap(PencilKitBridge.deserialize)?.strokes.count ?? 0
                        return (page.id, count)
                    }
                )
            }
            self.currentPageIndex = 0
            
            // Generate thumbnails for all pages
            for (index, _) in self.pages.enumerated() {
                self.regenerateThumbnail(for: index)
            }
        } catch {
            print("Failed to load notebook pages: \(error)")
        }
    }

    func updateViewport(offset: CGSize, scale: CGFloat) {
        // This is called from UIScrollView delegate callbacks and UIView.layoutSubviews,
        // which can run while SwiftUI is mid-update (notably when the canvas first appears
        // and during pan/zoom). Writing these @Published values synchronously there trips
        // "Modifying state during view update, this will cause undefined behavior."
        // Defer to the next runloop tick so the observable writes land outside the active
        // update pass. The live canvas (ink + background) tracks the scroll view directly,
        // so only the conditional SwiftUI overlays read these — a one-tick defer is invisible.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.canvasOffset = offset
            self.canvasScale = scale
            guard let notebookId = self.notebookId else { return }
            let state = CanvasViewportState(offsetX: offset.width, offsetY: offset.height, scale: scale)
            self.restoredViewport = state
            Self.saveViewportState(state, for: notebookId)
        }
    }

    func finalizeViewport(offset: CGSize, scale: CGFloat) {
        updateViewport(offset: offset, scale: scale)
    }

    /// Returns the viewport to the user's work. If the page has ink or elements the
    /// view re-centers (and zooms to fit) their bounding box; otherwise it snaps back
    /// to the centre of the canvas. Used by the "recenter" control so the user can
    /// always find their content after panning/zooming away.
    func recenterViewport(animated: Bool = true) {
        guard let scrollView = viewportScrollView else { return }
        let viewSize = scrollView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        // Union of ink bounds and element rects, in canvas space.
        var content = currentDrawing.bounds
        for el in currentPage.elements {
            let rect = CGRect(
                x: el.positionX, y: el.positionY,
                width: CGFloat(el.width ?? 200), height: CGFloat(el.height ?? 200)
            )
            content = (content.isNull || content.isEmpty) ? rect : content.union(rect)
        }

        let minZoom = scrollView.minimumZoomScale
        let maxZoom = scrollView.maximumZoomScale

        let targetScale: CGFloat
        let centerCanvas: CGPoint

        if content.isNull || content.isEmpty {
            // Nothing drawn yet — return to the middle of the canvas at a comfortable zoom.
            targetScale = min(max(1.0, minZoom), maxZoom)
            centerCanvas = CGPoint(x: scrollView.contentSize.width / 2,
                                   y: scrollView.contentSize.height / 2)
        } else {
            let padding: CGFloat = 120
            let fitScale = min(viewSize.width / (content.width + padding),
                               viewSize.height / (content.height + padding))
            // Never zoom past 1.5× when fitting a small amount of content.
            targetScale = min(max(fitScale, minZoom), min(maxZoom, 1.5))
            centerCanvas = CGPoint(x: content.midX, y: content.midY)
        }

        // screen = canvas * scale - contentOffset → solve for the offset that puts
        // centerCanvas at the middle of the viewport.
        let targetOffset = CGPoint(
            x: centerCanvas.x * targetScale - viewSize.width / 2,
            y: centerCanvas.y * targetScale - viewSize.height / 2
        )

        scrollView.setZoomScale(targetScale, animated: animated)
        scrollView.setContentOffset(targetOffset, animated: animated)

        finalizeViewport(offset: CGSize(width: targetOffset.x, height: targetOffset.y), scale: targetScale)
        HapticEngine.light()
    }

    private static func viewportStorageKey(for notebookId: UUID) -> String {
        "notebookViewport_\(notebookId.uuidString)"
    }

    private static func loadViewportState(for notebookId: UUID) -> CanvasViewportState? {
        guard let data = UserDefaults.standard.data(forKey: viewportStorageKey(for: notebookId)) else { return nil }
        return try? JSONDecoder().decode(CanvasViewportState.self, from: data)
    }

    private static func saveViewportState(_ state: CanvasViewportState, for notebookId: UUID) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: viewportStorageKey(for: notebookId))
        }
    }

    private func cacheDrawing(_ drawing: PKDrawing, for pageId: UUID) {
        liveDrawingCache[pageId] = drawing
        lastKnownStrokeCounts[pageId] = drawing.strokes.count
    }

    private func setCurrentPageDrawingSerialized(_ drawing: PKDrawing, forceViewUpdate: Bool = false) {
        let pageId = pages[currentPageIndex].id
        let data = PencilKitBridge.serialize(drawing)
        cacheDrawing(drawing, for: pageId)
        pendingSerializedDrawingData[pageId] = data
        pages[currentPageIndex].drawingData = data
        if forceViewUpdate {
            forceDrawingUpdate = true
        }
    }

    private func scheduleDrawingPersistence(for pageId: UUID, drawing: PKDrawing) {
        drawingSerializationTask?.cancel()
        drawingSerializationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }

            let data = await Task.detached(priority: .utility) {
                PencilKitBridge.serialize(drawing)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.pendingSerializedDrawingData[pageId] = data
                if let pageIndex = self.pages.firstIndex(where: { $0.id == pageId }) {
                    self.pages[pageIndex].drawingData = data
                }
                self.scheduleAutoSave(for: pageId, drawingData: data)
            }
        }
    }

    // MARK: - Undo / Redo (forwarded to PKCanvasView)

    func updateNotebookPattern(_ pattern: BackgroundPattern) {
        backgroundPattern = pattern

        // Update all existing pages' pattern in memory
        for index in pages.indices {
            pages[index].backgroundPattern = pattern
        }

        // Persist the notebook-level setting
        guard var nb = notebook else { return }
        nb.backgroundPattern = pattern.rawValue
        self.notebook = nb

        Task {
            do {
                try await service.updateNotebook(nb)
            } catch {
                print("[Canvas] Failed to persist pattern change: \(error)")
            }
        }
    }

    func undo() {
        pkUndoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        pkUndoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = pkUndoManager?.canUndo ?? false
        canRedo = pkUndoManager?.canRedo ?? false
    }

    // MARK: - Lasso Actions (forwarded to PKCanvasView via UIResponder)

    func clearPage() {
        let pageId = pages[currentPageIndex].id
        pages[currentPageIndex].drawingData = nil
        pages[currentPageIndex].strokes.removeAll()
        liveDrawingCache[pageId] = PKDrawing()
        pendingSerializedDrawingData[pageId] = nil
        lastKnownStrokeCounts[pageId] = 0
    }

    func addPage() {
        guard let notebookId = self.notebookId, let userId = self.userId else { return }
        
        let newPageId = UUID()
        let newOrder = pages.count
        let newPage = DrawingPage(id: newPageId, title: "Page \(newOrder + 1)", backgroundPattern: backgroundPattern, order: newOrder)
        pages.append(newPage)
        liveDrawingCache[newPageId] = PKDrawing()
        lastKnownStrokeCounts[newPageId] = 0
        currentPageIndex = pages.count - 1
        
        let initialPage = Page(
            id: newPageId,
            userId: userId,
            notebookId: notebookId,
            title: newPage.title,
            pageIndex: newOrder,
            type: "canvas",
            settings: PageSettings(backgroundPattern: backgroundPattern.rawValue)
        )
        
        Task.detached(priority: .utility) {
            do {
                try await LocalDatabase.shared.savePage(initialPage)
            } catch {
                print("Failed to save new page: \(error)")
            }
        }
    }

    func deletePage(at index: Int) {
        guard pages.count > 1 else { return } // Do not allow deleting the last page
        guard index >= 0 && index < pages.count else { return }

        let pageToDelete = pages[index]
        let pageId = pageToDelete.id

        // Update pages array
        pages.remove(at: index)

        // Adjust currentPageIndex
        if currentPageIndex >= index && currentPageIndex > 0 {
            currentPageIndex -= 1
        }
        
        // Remove from thumbnails cache
        pageThumbnails[pageId] = nil
        liveDrawingCache[pageId] = nil
        pendingSerializedDrawingData[pageId] = nil
        lastKnownStrokeCounts[pageId] = nil

        Task.detached(priority: .utility) {
            do {
                // Delete from local DB
                try await LocalDatabase.shared.deletePage(id: pageId)
                // Delete from Supabase
                try await SupabaseService.shared.deletePage(id: pageId)
            } catch {
                print("Failed to delete page: \(error)")
            }
        }
    }

    // MARK: - Lasso Selection State
    
    // MARK: - Selection State
    @Published var selectedElementIds: Set<UUID> = []
    @Published var selectedStrokes: Set<UUID> = []
    
    // MARK: - Custom Lasso Selection State
    /// Bounding box of all selected strokes + elements in canvas space.
    /// Set by commitLassoSelection(). Nil when nothing is selected.
    @Published var lassoSelectionBox: CGRect? = nil
    /// Whether the lasso bounding box + edit menu are visible.
    @Published var isLassoSelectionActive: Bool = false
    /// Indices into currentPage.pkDrawing.strokes that are currently selected.
    /// Using indices because PKStroke has no stable ID.
    @Published var selectedPKStrokeIndices: Set<Int> = []

    // MARK: - Shared Canvas Interaction Helpers

    func textElementID(at canvasPoint: CGPoint) -> UUID? {
        currentPage.elements
            .reversed()
            .first(where: { element in
                guard element.type == "text" else { return false }
                let width = CGFloat(element.width ?? 200)
                let height = CGFloat(element.height ?? 32)
                let rect = CGRect(
                    x: element.positionX,
                    y: element.positionY,
                    width: width,
                    height: height
                )
                return rect.contains(canvasPoint)
            })?.id
    }

    func handleTextToolCanvasTap(at canvasPoint: CGPoint) {
        guard selectedTool == .text else { return }

        if let hitId = textElementID(at: canvasPoint) {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            selectedElementIds = [hitId]
            return
        }

        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        selectedElementIds = []
        addTextElement(at: canvasPoint)
    }

    var selectedObjectCanvasRect: CGRect? {
        guard selectedElementIds.count == 1,
              let id = selectedElementIds.first,
              let element = currentPage.elements.first(where: { $0.id == id }) else { return nil }

        let width = CGFloat(element.width ?? 200)
        let height = CGFloat(element.height ?? 200)
        return CGRect(x: element.positionX, y: element.positionY, width: width, height: height)
    }

    var selectedElement: CanvasElement? {
        guard selectedElementIds.count == 1,
              let id = selectedElementIds.first else { return nil }
        return currentPage.elements.first(where: { $0.id == id })
    }

    func duplicateSelectedElement() {
        guard let element = selectedElement else { return }
        let newId = UUID()
        let duplicate = CanvasElement(
            id: newId,
            pageId: element.pageId,
            userId: element.userId,
            type: element.type,
            content: element.content,
            positionX: element.positionX + 24,
            positionY: element.positionY + 24,
            width: element.width,
            height: element.height,
            rotation: element.rotation,
            zIndex: currentPage.elements.count,
            style: element.style,
            userResized: element.userResized,
            createdAt: Date(),
            updatedAt: Date()
        )
        addElement(duplicate)
        selectedElementIds = [newId]
    }

    func deleteSelectedElement() {
        guard let id = selectedElement?.id else { return }
        removeElement(id: id)
    }
    
    // MARK: - Live Lasso (driven by a pencil-only recognizer on the canvas host)

    /// In-progress lasso polygon in screen space. The visual overlay
    /// (`CustomLassoGestureView`) renders this; commit happens on lift.
    @Published var liveLassoPoints: [CGPoint] = []

    func beginLiveLasso(at point: CGPoint) {
        guard selectedTool == .lasso, !isRegionCaptureMode else { return }
        liveLassoPoints = [point]
    }

    func appendLiveLasso(_ point: CGPoint) {
        guard selectedTool == .lasso, !isRegionCaptureMode, !liveLassoPoints.isEmpty else { return }
        liveLassoPoints.append(point)
    }

    func endLiveLasso() {
        let pts = liveLassoPoints
        liveLassoPoints = []
        guard selectedTool == .lasso, pts.count > 2 else { return }
        commitLassoSelection(polygon: pts)
    }

    func cancelLiveLasso() {
        liveLassoPoints = []
    }

    /// Called when the user lifts the pencil. polygon is in screen space — this
    /// function converts to canvas space, runs hit testing, and commits the selection.
    func commitLassoSelection(polygon: [CGPoint]) {
        guard polygon.count > 2 else {
            print("[Lasso] Polygon too small (\(polygon.count) points) — skipping")
            return
        }
        
        // Convert screen-space polygon to PencilKit canvas space.
        // canvasOffset = PKCanvasView.contentOffset (scroll position)
        // canvasScale = PKCanvasView.zoomScale
        // Formula: canvasPoint = (screenPoint + contentOffset) / zoomScale
        let canvasPolygon = polygon.map { pt in
            CGPoint(
                x: (pt.x + canvasOffset.width) / canvasScale,
                y: (pt.y + canvasOffset.height) / canvasScale
            )
        }
        
        // Log the polygon bounding box so we can compare to stroke positions
        let polyXs = canvasPolygon.map { $0.x }
        let polyYs = canvasPolygon.map { $0.y }
        let polyBBox = CGRect(
            x: polyXs.min()!, y: polyYs.min()!,
            width: polyXs.max()! - polyXs.min()!,
            height: polyYs.max()! - polyYs.min()!
        )
        print("[Lasso] Polygon canvas bbox: \(polyBBox.debugDescription)")
        print("[Lasso] canvasOffset=\(canvasOffset) canvasScale=\(canvasScale)")
        
        // Hit-test PencilKit strokes (these are the actual ink strokes on screen)
        let pkStrokes = currentDrawing.strokes
        print("[Lasso] PKDrawing has \(pkStrokes.count) strokes to test")
        
        // For each PKStroke, test if its renderBounds center is inside the polygon.
        // renderBounds is already in canvas coordinate space (matches canvasPolygon).
        var hitPKStrokeIndices: [Int] = []
        for (i, stroke) in pkStrokes.enumerated() {
            let center = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
            let hit = pointInPolygon(center, polygon: canvasPolygon)
            print("[Lasso] Stroke \(i) renderBounds=\(stroke.renderBounds.debugDescription) center=\(center) hit=\(hit)")
            if hit { hitPKStrokeIndices.append(i) }
        }
        
        // Hit-test canvas elements (image blocks)
        let hitElements = currentPage.elements.filter { el in
            let w = el.width ?? 200; let h = el.height ?? 200
            // positionX/Y is top-left corner — check center for lasso hit test
            let c = CGPoint(x: el.positionX + w / 2, y: el.positionY + h / 2)
            let hit = pointInPolygon(c, polygon: canvasPolygon)
            print("[Lasso] Element '\(el.type)' pos=(\(el.positionX), \(el.positionY)) hit=\(hit)")
            return hit
        }
        
        print("[Lasso] Result: \(hitPKStrokeIndices.count) PK strokes, \(hitElements.count) elements selected")
        
        // Nothing hit — clear and return
        guard !hitPKStrokeIndices.isEmpty || !hitElements.isEmpty else {
            print("[Lasso] Nothing selected — clearing")
            clearLassoSelection()
            return
        }
        
        // Store hit PK stroke indices so applyLassoColorChange can find them
        selectedPKStrokeIndices = Set(hitPKStrokeIndices)
        selectedElementIds = Set(hitElements.map { $0.id })
        
        // Compute unified bounding box in canvas space
        var rects: [CGRect] = []
        rects += hitPKStrokeIndices.map { pkStrokes[$0].renderBounds }
        rects += hitElements.map { el in
            let w = el.width ?? 200; let h = el.height ?? 200
            // positionX/Y is now top-left corner
            return CGRect(x: el.positionX, y: el.positionY, width: w, height: h)
        }
        
        let combined = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let padded = combined.insetBy(dx: -12, dy: -12)
        
        lassoSelectionBox = padded
        isLassoSelectionActive = true
        print("[Lasso] Selection box set: \(padded.debugDescription)")
    }
    
    func clearLassoSelection() {
        selectedStrokes = []
        selectedPKStrokeIndices = []
        selectedElementIds = []
        lassoSelectionBox = nil
        isLassoSelectionActive = false
    }
    
    /// Ray-casting point-in-polygon (same algorithm as DrawingCanvasView coordinator).
    /// Duplicated here so CanvasViewModel has no dependency on the view layer.
    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            if ((yi > point.y) != (yj > point.y)) &&
                (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        return inside
    }
    
    /// Change the color of all selected strokes.
    func applyLassoColorChange(_ newColor: Color) {
        guard !selectedPKStrokeIndices.isEmpty else { return }
        let uiColor = UIColor(newColor)
        var allStrokes = currentDrawing.strokes
        
        for i in selectedPKStrokeIndices where i < allStrokes.count {
            let old = allStrokes[i]
            let newInk = PKInk(old.ink.inkType, color: uiColor)
            allStrokes[i] = PKStroke(ink: newInk, path: old.path, transform: old.transform, mask: old.mask)
        }
        
        let newDrawing = PKDrawing(strokes: allStrokes)
        setCurrentPageDrawingSerialized(newDrawing, forceViewUpdate: true)
        objectWillChange.send()
        scheduleAutoSave()
        print("[Lasso] Color changed on \(selectedPKStrokeIndices.count) strokes")
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }
    
    /// Scale all selected strokes and elements from the bounding box top-left anchor.
    func applyLassoResize(scale: CGFloat) {
        guard let bbox = lassoSelectionBox, scale > 0 else { return }
        let origin = bbox.origin
        let t = CGAffineTransform.identity
            .translatedBy(x: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -origin.x, y: -origin.y)
        
        // Scale PK strokes via their transform
        if !selectedPKStrokeIndices.isEmpty {
            var allStrokes = currentDrawing.strokes
            for i in selectedPKStrokeIndices where i < allStrokes.count {
                let old = allStrokes[i]
                allStrokes[i] = PKStroke(ink: old.ink, path: old.path,
                                         transform: old.transform.concatenating(t),
                                         mask: old.mask)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setCurrentPageDrawingSerialized(newDrawing, forceViewUpdate: true)
        }
        
        // Scale elements
        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            let el = pages[currentPageIndex].elements[i]
            pages[currentPageIndex].elements[i].positionX = origin.x + (el.positionX - origin.x) * scale
            pages[currentPageIndex].elements[i].positionY = origin.y + (el.positionY - origin.y) * scale
            pages[currentPageIndex].elements[i].width = max(40, (el.width ?? 200) * scale)
            pages[currentPageIndex].elements[i].height = max(40, (el.height ?? 200) * scale)
        }
        
        lassoSelectionBox = CGRect(x: origin.x, y: origin.y,
                                   width: bbox.width * scale, height: bbox.height * scale)
        objectWillChange.send()
        scheduleElementSave()
        scheduleAutoSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }
    
    /// Move all selected strokes and elements by the given translation in canvas space.
    func applyLassoMove(translation: CGSize) {
        guard let bbox = lassoSelectionBox else { return }
        
        let t = CGAffineTransform(translationX: translation.width, y: translation.height)
        
        // Move PK strokes via their transform
        if !selectedPKStrokeIndices.isEmpty {
            var allStrokes = currentDrawing.strokes
            for i in selectedPKStrokeIndices where i < allStrokes.count {
                let old = allStrokes[i]
                allStrokes[i] = PKStroke(ink: old.ink, path: old.path,
                                         transform: old.transform.concatenating(t),
                                         mask: old.mask)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setCurrentPageDrawingSerialized(newDrawing, forceViewUpdate: true)
        }
        
        // Move elements
        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            pages[currentPageIndex].elements[i].positionX += translation.width
            pages[currentPageIndex].elements[i].positionY += translation.height
        }
        
        lassoSelectionBox = bbox.offsetBy(dx: translation.width, dy: translation.height)
        objectWillChange.send()
        scheduleElementSave()
        scheduleAutoSave()
    }

    func moveSelection(dx: CGFloat, dy: CGFloat) {
        let t = CGAffineTransform(translationX: dx, y: dy)
        if !selectedPKStrokeIndices.isEmpty {
            var allStrokes = currentDrawing.strokes
            for i in selectedPKStrokeIndices where i < allStrokes.count {
                let old = allStrokes[i]
                allStrokes[i] = PKStroke(ink: old.ink, path: old.path,
                                         transform: old.transform.concatenating(t),
                                         mask: old.mask)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setCurrentPageDrawingSerialized(newDrawing)
        }
        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            pages[currentPageIndex].elements[i].positionX += dx
            pages[currentPageIndex].elements[i].positionY += dy
        }
        if let box = lassoSelectionBox {
            lassoSelectionBox = box.offsetBy(dx: dx, dy: dy)
        }
        objectWillChange.send()
        scheduleAutoSave()
        scheduleElementSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Cut: copy to pasteboard then delete.
    func cutSelection() {
        copySelection()
        deleteSelectedLassoContent()
    }

    /// Copy selected PK strokes as PKDrawing data to UIPasteboard.
    func copySelection() {
        guard !selectedPKStrokeIndices.isEmpty else { return }
        let allStrokes = currentDrawing.strokes
        let selected = selectedPKStrokeIndices.sorted().compactMap {
            $0 < allStrokes.count ? allStrokes[$0] : nil
        }
        let drawing = PKDrawing(strokes: selected)
        let data = PencilKitBridge.serialize(drawing)
        UIPasteboard.general.setData(data, forPasteboardType: "com.apple.ink.drawing")
        print("[Lasso] Copied \(selected.count) strokes to pasteboard")
    }

    /// Paste PKDrawing from UIPasteboard, offset slightly so it's visible.
    func pasteSelection() {
        guard let data = UIPasteboard.general.data(forPasteboardType: "com.apple.ink.drawing"),
              let drawing = PencilKitBridge.deserialize(data) else { return }
        let offset = CGAffineTransform(translationX: 24, y: 24)
        let offsetStrokes = drawing.strokes.map { s in
            PKStroke(ink: s.ink, path: s.path, transform: s.transform.concatenating(offset), mask: s.mask)
        }
        var allStrokes = currentDrawing.strokes
        let startIndex = allStrokes.count
        allStrokes.append(contentsOf: offsetStrokes)
        let newDrawing = PKDrawing(strokes: allStrokes)
        setCurrentPageDrawingSerialized(newDrawing)
        
        // Select the pasted strokes
        selectedPKStrokeIndices = Set(startIndex..<allStrokes.count)
        let rects = offsetStrokes.map { $0.renderBounds }
        if let first = rects.first {
            let combined = rects.dropFirst().reduce(first) { $0.union($1) }
            lassoSelectionBox = combined.insetBy(dx: -12, dy: -12)
            isLassoSelectionActive = true
        }
        objectWillChange.send()
        scheduleAutoSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Duplicate: paste a copy of the current selection in place (offset 24pt).
    func duplicateSelection() {
        guard !selectedPKStrokeIndices.isEmpty else { return }
        let allStrokes = currentDrawing.strokes
        let selected = selectedPKStrokeIndices.sorted().compactMap {
            $0 < allStrokes.count ? allStrokes[$0] : nil
        }
        let offset = CGAffineTransform(translationX: 24, y: 24)
        let duped = selected.map { s in
            PKStroke(ink: s.ink, path: s.path, transform: s.transform.concatenating(offset), mask: s.mask)
        }
        var newAll = allStrokes
        let startIndex = newAll.count
        newAll.append(contentsOf: duped)
        setCurrentPageDrawingSerialized(PKDrawing(strokes: newAll))
        
        selectedPKStrokeIndices = Set(startIndex..<newAll.count)
        let rects = duped.map { $0.renderBounds }
        if let first = rects.first {
            let combined = rects.dropFirst().reduce(first) { $0.union($1) }
            lassoSelectionBox = combined.insetBy(dx: -12, dy: -12)
            isLassoSelectionActive = true
        }
        objectWillChange.send()
        scheduleAutoSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Delete all selected strokes and elements, then clear the selection.
    func deleteSelectedLassoContent() {
        // Delete PK strokes by rebuilding drawing without selected indices
        if !selectedPKStrokeIndices.isEmpty {
            let allStrokes = currentDrawing.strokes
            let remaining = allStrokes.indices
                .filter { !selectedPKStrokeIndices.contains($0) }
                .map { allStrokes[$0] }
            let newDrawing = PKDrawing(strokes: remaining)
            setCurrentPageDrawingSerialized(newDrawing, forceViewUpdate: true)
        }
        
        pages[currentPageIndex].elements.removeAll { selectedElementIds.contains($0.id) }
        clearLassoSelection()
        objectWillChange.send()
        scheduleElementSave()
        scheduleAutoSave()
    }
    
    /// Render the selected strokes as a UIImage cropped to the lasso bounding box.
    /// Returns nil if nothing is selected or the bounding box is empty.
    func screenshotSelection() -> UIImage? {
        guard !selectedPKStrokeIndices.isEmpty,
              let bbox = lassoSelectionBox,
              bbox.width > 0, bbox.height > 0 else { return nil }

        let allStrokes = currentDrawing.strokes
        let selectedStrokes = selectedPKStrokeIndices.sorted().compactMap {
            $0 < allStrokes.count ? allStrokes[$0] : nil
        }
        let selectionDrawing = PKDrawing(strokes: selectedStrokes)

        // Render at 2x Retina scale for crisp output
        let scale: CGFloat = 2.0
        
        // Add padding around the bounding box so strokes don't touch the edge
        let padding: CGFloat = 24.0
        let paddedSize = CGSize(width: bbox.width + (padding * 2), height: bbox.height + (padding * 2))

        // Resolve notebook background color (default white)
        var bgColor = UIColor.white
        if let hex = notebook?.backgroundColorHex {
            let normalized = hex.uppercased()
            bgColor = normalized == "#0F0F0E" ? UIColor.gBackground : UIColor(hex: hex)
        }

        // Must resolve the dynamic color so it doesn't render incorrectly in graphics context
        bgColor = bgColor.resolvedColor(with: UITraitCollection.current)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: paddedSize, format: format)
        let image = renderer.image { ctx in
            // Fill background
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: paddedSize))
            
            // Draw strokes: shift so bounding box origin maps to (0,0) plus our padding
            // PKDrawing.image(from:scale:) renders strokes at their absolute canvas positions,
            // so we pass a rect anchored at bbox.origin to crop correctly.
            let strokeImage = selectionDrawing.image(from: bbox, scale: scale)
            strokeImage.draw(in: CGRect(x: padding, y: padding, width: bbox.width, height: bbox.height))
        }

        return image
    }
    
    private var elementSaveTask: Task<Void, Never>?
    
    func addElement(_ element: CanvasElement) {
        pages[currentPageIndex].elements.append(element)
        // Explicitly trigger an update since it's a nested array
        objectWillChange.send()
        scheduleElementSave()
    }
    
    func addTextElement(at canvasPoint: CGPoint) {
        guard let pageId = currentPage.id as UUID?,
              let userId = self.userId else { return }

        let textOrigin = CGPoint(
            x: canvasPoint.x - TextElementMetrics.editorInsets.left,
            y: canvasPoint.y - TextElementMetrics.editorInsets.top
        )

        let newElement = CanvasElement(
            pageId: pageId,
            userId: userId,
            type: "text",
            content: "\u{200B}",          // zero-width space sentinel
            positionX: Double(textOrigin.x),
            positionY: Double(textOrigin.y),
            width: 200,
            height: 32, // font size (16pt default) + vertical padding (8pt top + 8pt bottom)
            rotation: 0,
            zIndex: currentPage.elements.count
        )

        addElement(newElement)
        selectedElementIds = [newElement.id]
        objectWillChange.send()
    }

    func beginImageInsertion(at canvasPoint: CGPoint) {
        pendingImageInsertionPoint = canvasPoint
        selectedElementIds = []
        showCanvasImagePicker = true
    }

    func cancelPendingImageInsertion() {
        pendingImageInsertionPoint = nil
        showCanvasImagePicker = false
    }

    func completePendingImageInsertion() {
        pendingImageInsertionPoint = nil
        showCanvasImagePicker = false
    }

    var imageInsertionPlaceholderSize: CGSize {
        let width = max(120, min(240, canvasViewSize.width * 0.32 / max(canvasScale, 0.25)))
        return CGSize(width: width, height: width)
    }
    
    func insertImage(_ asset: PHAsset) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        // fastFormat delivers a good-quality version quickly, then the
        // opportunistic second callback delivers the full quality version.
        // We use the first result that arrives and ignore subsequent callbacks.
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        // 2048×2048 is visually lossless at any canvas display size while
        // being ~6× smaller in memory than a full-resolution 48 MP photo.
        let targetSize = CGSize(width: 2048, height: 2048)
        var didHandle = false

        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { [weak self] image, info in
            guard let self = self, let image = image else { return }
            // opportunistic mode calls back twice (degraded then full).
            // Only process the first result that looks complete.
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !isDegraded, !didHandle else { return }
            didHandle = true
            
            // Generate a unique filename and save to local Documents directory
            let fileName = UUID().uuidString + ".jpg"
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
            } catch {
                print("Failed to save image locally: \(error)")
                return
            }

            ImageCache.shared.store(image, for: fileName)
            
            Task { @MainActor in
                self.insertResolvedImage(image, fileName: fileName, at: self.pendingImageInsertionPoint)
            }
        }
    }

    func insertImage(_ image: UIImage, at canvasPoint: CGPoint? = nil) {
        let fileName = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to save image locally: \(error)")
            return
        }

        ImageCache.shared.store(image, for: fileName)
        insertResolvedImage(image, fileName: fileName, at: canvasPoint)
    }

    private func insertResolvedImage(_ image: UIImage, fileName: String, at canvasPoint: CGPoint?) {
        let viewSize = canvasViewSize
        let insertionCenter = canvasPoint ?? CGPoint(
            x: (viewSize.width / 2 + canvasOffset.width) / max(canvasScale, 0.25),
            y: (viewSize.height / 2 + canvasOffset.height) / max(canvasScale, 0.25)
        )

        let placeholderWidth = Double(imageInsertionPlaceholderSize.width)
        let aspectRatio = image.size.width > 0
            ? Double(image.size.height / image.size.width) : 1.0
        let blockWidth = min(300, placeholderWidth)
        let blockHeight = blockWidth * aspectRatio

        let newElement = CanvasElement(
            pageId: currentPage.id,
            userId: userId ?? UUID(),
            type: "image",
            content: fileName,
            positionX: Double(insertionCenter.x) - blockWidth / 2,
            positionY: Double(insertionCenter.y) - blockHeight / 2,
            width: blockWidth,
            height: blockHeight,
            rotation: 0,
            zIndex: currentPage.elements.count
        )

        currentPage.elements.append(newElement)
        selectedElementIds = [newElement.id]
        objectWillChange.send()
        scheduleElementSave()
        completePendingImageInsertion()
    }

    func updateElement(_ element: CanvasElement) {
        print("[VM] updateElement id=\(element.id) userResized=\(element.userResized) w=\(element.width ?? 0) h=\(element.height ?? 0)")
        if let index = pages[currentPageIndex].elements.firstIndex(where: { $0.id == element.id }) {
            pages[currentPageIndex].elements[index] = element
            objectWillChange.send()
            scheduleElementSave()
        }
    }
    
    func removeElement(id: UUID) {
        pages[currentPageIndex].elements.removeAll { $0.id == id }
        selectedElementIds.remove(id)
        objectWillChange.send()
        scheduleElementSave()
    }
    
    private func scheduleElementSave() {
        elementSaveTask?.cancel()
        elementSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await saveCanvasElements()
        }
    }
    
    private func saveCanvasElements() async {
        guard let pageId = currentPage.id as UUID? else { return }
        let elements = currentPage.elements
        await Task.detached(priority: .utility) {
            do {
                try await LocalDatabase.shared.saveCanvasElements(elements, forPageId: pageId)
            } catch {
                print("Local element save error: \(error)")
            }
            for el in elements {
                try? await SupabaseService.shared.upsertCanvasElement(el)
            }
        }.value
    }

    // MARK: - Unified Lasso Resize
    
    // MARK: - Tool Selection (with per-tool memory)

    func selectTool(_ tool: DrawingTool) {
        // Clean up any empty text blocks before switching tools
        if tool != .text {
            let emptyTextIds = pages[currentPageIndex].elements
                .filter { $0.type == "text" && ($0.content == nil || $0.content == "\u{200B}" || $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) == "") }
                .map { $0.id }
            if !emptyTextIds.isEmpty {
                pages[currentPageIndex].elements.removeAll { emptyTextIds.contains($0.id) }
                selectedElementIds = selectedElementIds.subtracting(emptyTextIds)
                objectWillChange.send()
                scheduleElementSave()
            }
        }

        isChangingTool = true
        defer { isChangingTool = false }

        // Save current tool settings before switching
        updateCurrentToolMemory()

        // Clear any active lasso selection when switching tools
        if tool != .lasso { clearLassoSelection() }

        // isLassoActive removed — custom lasso manages its own state
        selectedStrokes.removeAll()
        selectedElementIds = []
        selectedTool = tool

        // Ensure customization exists for drawing tools.
        _ = ensureToolCustomization(for: tool)

        if tool == .image {
            requestPhotoAccessAndFetch()
        }

        // Restore saved settings or use tool defaults
        if let saved = toolMemory[tool] {
            strokeColor = Color(hex: saved.colorHex)
            strokeWidth = saved.width
            strokeOpacity = saved.opacity
        } else {
            strokeWidth = tool.defaultWidth
            strokeOpacity = tool.defaultOpacity
        }
    }
    
    private func updateCurrentToolMemory() {
        guard !isChangingTool else { return }
        if selectedTool != .eraser && selectedTool != .lasso && selectedTool != .selection && selectedTool != .text {
            toolMemory[selectedTool] = ToolSettings(colorHex: strokeColor.hexString, width: strokeWidth, opacity: strokeOpacity)
        }
    }

    // MARK: - Tool Customization API

    @discardableResult
    func ensureToolCustomization(for tool: DrawingTool) -> ToolCustomization {
        if let existing = toolCustomizations[tool] { return existing }
        let created = ToolCustomization.defaults(for: tool)
        toolCustomizations[tool] = created
        return created
    }

    func presetColors(for tool: DrawingTool) -> [Color] {
        let c = ensureToolCustomization(for: tool)
        return c.presetColorHexes.map { Color(hex: $0) }
    }

    func extraColors(for tool: DrawingTool) -> [Color] {
        let c = ensureToolCustomization(for: colorCustomizableTools.first ?? tool)
        return c.extraColorHexes.map { Color(hex: $0) }
    }

    func addExtraColor(_ color: Color, for tool: DrawingTool) {
        let hex = color.hexString.uppercased()
        for colorTool in colorCustomizableTools {
            var c = ensureToolCustomization(for: colorTool)
            guard !c.presetColorHexes.contains(hex) else { continue }
            if !c.extraColorHexes.contains(hex) {
                c.extraColorHexes.append(hex)
                toolCustomizations[colorTool] = c
            }
        }
    }

    func removeExtraColor(at index: Int, for tool: DrawingTool) {
        let extras = extraColors(for: tool)
        guard extras.indices.contains(index) else { return }
        removeSelectedCustomColorFromColorTools(color: extras[index])
    }

    func widthPresets(for tool: DrawingTool) -> [CGFloat] {
        let c = ensureToolCustomization(for: tool)
        return c.widthPresets.map { CGFloat($0) }
    }

    func setWidthPreset(for tool: DrawingTool, index: Int, to width: CGFloat) {
        var c = ensureToolCustomization(for: tool)
        guard c.widthPresets.indices.contains(index) else { return }
        c.widthPresets[index] = Double(width)
        toolCustomizations[tool] = c
    }

    func canDeleteSelectedCustomColor(for tool: DrawingTool) -> Bool {
        let hex = strokeColor.hexString.uppercased()
        let c = ensureToolCustomization(for: colorCustomizableTools.first ?? tool)
        return c.extraColorHexes.contains(hex)
    }

    func removeSelectedCustomColorFromColorTools(color: Color? = nil) {
        let hex = (color ?? strokeColor).hexString.uppercased()
        var removed = false

        for colorTool in colorCustomizableTools {
            var c = ensureToolCustomization(for: colorTool)
            let before = c.extraColorHexes.count
            c.extraColorHexes.removeAll { $0 == hex }
            if c.extraColorHexes.count != before {
                removed = true
                toolCustomizations[colorTool] = c
            }
            if var memory = toolMemory[colorTool], memory.colorHex.uppercased() == hex {
                memory.colorHex = c.presetColorHexes.first ?? Color.strokePresets.first?.hexString ?? "#FFFFFE"
                toolMemory[colorTool] = memory
            }
        }

        if removed, strokeColor.hexString.uppercased() == hex {
            let fallback = presetColors(for: selectedTool).first ?? Color.strokePresets.first ?? Color(hex: "#FFFFFE")
            strokeColor = fallback
        }
    }

    private var colorCustomizableTools: [DrawingTool] {
        [.pen, .pencil, .marker]
    }

    // MARK: - Drawing Changed Callback

    /// Called by PKCanvasRepresentable when the drawing changes.
    /// `fromPencil` indicates whether the change came from Apple Pencil (true) or finger (false).
    func drawingDidChange(_ drawing: PKDrawing, fromPencil: Bool = true) {
        let pageId = pages[currentPageIndex].id
        let previousStrokeCount = lastKnownStrokeCounts[pageId] ?? liveDrawingCache[pageId]?.strokes.count ?? 0

        // Any drawing change invalidates a pending snap. If the user keeps writing,
        // the recognised stroke is no longer the last one, so don't snap it.
        shapeSnapTask?.cancel()
        if shapeSnapMorph != nil { shapeSnapMorph = nil }

        cacheDrawing(drawing, for: pageId)
        refreshUndoState()
        scheduleDrawingPersistence(for: pageId, drawing: drawing)
        scheduleThumbnailRegeneration(for: currentPageIndex)

        // Shape snapping (GoodNotes-style): recognise the just-finished stroke and,
        // if it's confidently a shape — or the user held the pencil at the end —
        // snap it after a short pause so continuous handwriting is never disturbed.
        if isShapeSnappingEnabled,
           drawing.strokes.count > previousStrokeCount,
           let lastStroke = drawing.strokes.last {
            let pts = lastStroke.path.map { $0.location }
            if let recognition = ShapeSnapper.recognize(from: pts) {
                let hold = ShapeSnapper.endHoldDuration(of: lastStroke)
                let heldToSnap = hold >= 0.25
                let shouldSnap = recognition.confidence >= 0.62 || (heldToSnap && recognition.confidence >= 0.42)
                if shouldSnap {
                    scheduleShapeSnap(
                        recognition: recognition,
                        original: lastStroke,
                        roughPoints: pts,
                        strokeCount: drawing.strokes.count,
                        pageId: pageId,
                        immediate: heldToSnap
                    )
                }
            }
        }

        // Toolbar auto-hide removed — hiding mid-session disrupts canvas rendering.
    }

    // MARK: - Shape Snap

    private func scheduleShapeSnap(
        recognition: ShapeSnapper.Recognition,
        original: PKStroke,
        roughPoints: [CGPoint],
        strokeCount: Int,
        pageId: UUID,
        immediate: Bool
    ) {
        shapeSnapTask?.cancel()
        shapeSnapTask = Task { [weak self] in
            // Wait for a brief pause unless the user explicitly held to snap. A new
            // stroke cancels this task, so writing flows never trigger a snap.
            if !immediate {
                try? await Task.sleep(for: .seconds(0.3))
                if Task.isCancelled { return }
            }
            await MainActor.run {
                self?.commitShapeSnap(
                    recognition: recognition,
                    original: original,
                    roughPoints: roughPoints,
                    strokeCount: strokeCount,
                    pageId: pageId
                )
            }
        }
    }

    private func commitShapeSnap(
        recognition: ShapeSnapper.Recognition,
        original: PKStroke,
        roughPoints: [CGPoint],
        strokeCount: Int,
        pageId: UUID
    ) {
        // Bail if the page changed or strokes were added/removed in the meantime.
        guard pages[currentPageIndex].id == pageId,
              var strokes = liveDrawingCache[pageId]?.strokes,
              strokes.count == strokeCount,
              let lastIdx = strokes.indices.last else { return }

        let shape = ShapeSnapper.straightenShape(recognition.shape)
        let idealStroke = ShapeSnapper.createStroke(from: shape, originalStroke: original)

        // Play a rough→clean morph on top while the page still shows the rough stroke.
        let sampleCount = 48
        let from = ShapeSnapper.resample(roughPoints, count: sampleCount)
        let to = ShapeSnapper.outlinePoints(for: shape, count: sampleCount)
        let inkColor = Color(original.ink.color)
        let inkWidth = original.path.first?.size.width ?? 3
        shapeSnapMorph = ShapeSnapMorph(
            fromPoints: from,
            toPoints: to,
            closed: shape.isClosed,
            color: inkColor,
            width: inkWidth
        )
        HapticEngine.light()

        // After the morph settles, swap the rough stroke for the clean one in a single
        // step (preserves a clean undo: one undo restores the hand-drawn stroke).
        shapeSnapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.26))
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                self.shapeSnapMorph = nil
                guard self.pages[self.currentPageIndex].id == pageId,
                      var current = self.liveDrawingCache[pageId]?.strokes,
                      current.count == strokeCount else { return }
                current[lastIdx] = idealStroke
                let snapped = PKDrawing(strokes: current)
                self.cacheDrawing(snapped, for: pageId)
                self.forceDrawingUpdate = true
                self.refreshUndoState()
                self.scheduleDrawingPersistence(for: pageId, drawing: snapped)
                self.scheduleThumbnailRegeneration(for: self.currentPageIndex)
            }
        }
    }

    // MARK: - Thumbnail Cache

    /// Debounced entry point called during active drawing.
    /// Waits 0.8s after the last stroke before actually rendering.
    private func scheduleThumbnailRegeneration(for pageIndex: Int) {
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.regenerateThumbnail(for: pageIndex)
        }
    }

    /// Regenerate the thumbnail for a page on a background thread.
    /// Call directly when an immediate render is needed (e.g. on initial load).
    /// During drawing, use scheduleThumbnailRegeneration instead.
    func regenerateThumbnail(for pageIndex: Int) {
        let page = pages[pageIndex]
        let pageId = page.id
        let drawing = resolvedDrawing(for: page)
        guard !drawing.strokes.isEmpty else {
            pageThumbnails[pageId] = nil
            return
        }
        // Capture screen scale on main thread before going off-thread
        let scale = UIScreen.main.scale
        Task.detached(priority: .utility) { [weak self] in
            let bounds = drawing.bounds.isEmpty
                ? CGRect(origin: .zero, size: CGSize(width: 56, height: 74))
                : drawing.bounds
            let image = drawing.image(from: bounds, scale: scale)
            await MainActor.run { [weak self] in
                self?.pageThumbnails[pageId] = image
            }
        }
    }

    // MARK: - Toolbar Auto-Hide

    /// Called when the user begins drawing with Apple Pencil — hides toolbar after delay.
    func startToolbarHideTimer() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hideToolbar()
        }
    }

    private func hideToolbar() {
        animateMotionSafe { [self] in isToolbarVisible = false }
    }

    /// Called when a finger tap is detected — shows toolbar and cancels any pending hide.
    func showToolbar() {
        toolbarHideTask?.cancel()
        if !isToolbarVisible {
            animateMotionSafe(GAnimation.springFast) { [self] in isToolbarVisible = true }
        }
    }

    // MARK: - Canvas Context Menu
    func showCanvasContextMenu(at canvasPoint: CGPoint) {
        canvasContextMenuPoint = canvasPoint
    }

    func hideCanvasContextMenu() {
        canvasContextMenuPoint = nil
    }

    // MARK: - Keyboard Helpers
    func setViewportScrollView(_ scrollView: UIScrollView?) {
        viewportScrollView = scrollView
    }

    func updateKeyboardHeight(_ height: CGFloat) {
        keyboardHeight = max(0, height)
        if keyboardHeight > 0 {
            // Delay one runloop so the keyboard/layout settle before scrolling.
            DispatchQueue.main.async { [weak self] in
                self?.ensureSelectedTextVisible()
            }
        }
    }

    func ensureSelectedTextVisible(extraPadding: CGFloat = 18) {
        guard selectedTool == .text,
              keyboardHeight > 0,
              let id = selectedElementIds.first,
              let el = currentPage.elements.first(where: { $0.id == id && $0.type == "text" }),
              let scrollView = viewportScrollView
        else { return }

        let w = CGFloat(el.width ?? 200)
        let h = CGFloat(el.height ?? 32)
        let rectCanvas = CGRect(x: el.positionX, y: el.positionY, width: w, height: h)

        // Project canvas-space element rect into viewport (screen) space:
        // screen = canvas * scale - offset
        let s = canvasScale
        let ox = canvasOffset.width
        let oy = canvasOffset.height
        let rectScreen = CGRect(
            x: rectCanvas.minX * s - ox,
            y: rectCanvas.minY * s - oy,
            width: rectCanvas.width * s,
            height: rectCanvas.height * s
        )

        // Visible height above keyboard and below the persistent top chrome.
        let persistentTopChrome: CGFloat = 48 + 46
        let visibleBottom = canvasViewSize.height - keyboardHeight - extraPadding
        let visibleTop = persistentTopChrome + extraPadding

        var newOffsetY = canvasOffset.height

        if rectScreen.maxY > visibleBottom {
            // Need to scroll down (increase contentOffset.y)
            let delta = rectScreen.maxY - visibleBottom
            newOffsetY += delta
        } else if rectScreen.minY < visibleTop {
            // Need to scroll up (decrease contentOffset.y)
            let delta = visibleTop - rectScreen.minY
            newOffsetY = max(0, newOffsetY - delta)
        } else {
            return // already visible
        }

        let target = CGPoint(x: scrollView.contentOffset.x, y: newOffsetY)
        scrollView.setContentOffset(target, animated: true)
    }

    var canCopySelection: Bool {
        if !selectedPKStrokeIndices.isEmpty { return true }
        if let id = selectedElementIds.first,
           let el = currentPage.elements.first(where: { $0.id == id }),
           el.type == "text",
           let content = el.content,
           !content.replacingOccurrences(of: "\u{200B}", with: "").isEmpty {
            return true
        }
        return false
    }

    func copyForCanvasMenu() {
        if !selectedPKStrokeIndices.isEmpty {
            copySelection()
            return
        }
        if let id = selectedElementIds.first,
           let el = currentPage.elements.first(where: { $0.id == id }),
           el.type == "text" {
            let str = (el.content ?? "").replacingOccurrences(of: "\u{200B}", with: "")
            UIPasteboard.general.string = str
        }
    }

    func pasteForCanvasMenu(at canvasPoint: CGPoint) {
        // Prefer ink paste if present.
        if UIPasteboard.general.data(forPasteboardType: "com.apple.ink.drawing") != nil {
            pasteSelection()
            return
        }
        if let str = UIPasteboard.general.string, !str.isEmpty {
            addTextElement(at: canvasPoint)
            if let id = selectedElementIds.first,
               let idx = currentPage.elements.firstIndex(where: { $0.id == id }) {
                var el = currentPage.elements[idx]
                el.content = str
                el.updatedAt = Date()
                updateElement(el)
            }
            selectTool(.text)
        }
    }

    /// Shows toolbar temporarily then hides again (for programmatic reveals).
    func showToolbarTemporarily() {
        animateMotionSafe(GAnimation.springFast) { [self] in isToolbarVisible = true }
    }

    // MARK: - Auto-Save (1.5s debounce)

    private func scheduleAutoSave(for pageId: UUID? = nil, drawingData: Data? = nil) {
        let resolvedPageId = pageId ?? pages[currentPageIndex].id
        let resolvedData = drawingData ?? pendingSerializedDrawingData[resolvedPageId] ?? pages.first(where: { $0.id == resolvedPageId })?.drawingData
        guard let resolvedData else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.performAutoSave(pageId: resolvedPageId, drawingData: resolvedData)
        }
    }
    
    /// Forces an immediate save of the current drawing data, cancelling any pending debounced save.
    func flushSave() async {
        autoSaveTask?.cancel()
        drawingSerializationTask?.cancel()

        let pageId = pages[currentPageIndex].id
        if let cachedDrawing = liveDrawingCache[pageId] {
            let serialized = await Task.detached(priority: .utility) {
                PencilKitBridge.serialize(cachedDrawing)
            }.value
            pendingSerializedDrawingData[pageId] = serialized
            pages[currentPageIndex].drawingData = serialized
            await performAutoSave(pageId: pageId, drawingData: serialized)
        } else if let drawingData = pages[currentPageIndex].drawingData {
            await performAutoSave(pageId: pageId, drawingData: drawingData)
        }
    }

    private func performAutoSave(pageId: UUID, drawingData: Data) async {
        isSaving = true
        // Save to local database on a background thread — never blocks the UI
        await Task.detached(priority: .utility) {
            do {
                try await LocalDatabase.shared.saveDrawingData(drawingData, forPageId: pageId)
            } catch {
                print("Auto-save error: \(error)")
            }
        }.value
        pendingSerializedDrawingData[pageId] = nil
        isSaving = false
    }

    // MARK: - Presence

    /// Join the Supabase Presence channel for the current notebook.
    /// Call when the canvas opens.
    func joinPresence(notebookId: UUID, userId: UUID) {
        presenceChannel = service.joinNotebookPresence(
            notebookId: notebookId,
            userId: userId
        ) { [weak self] webUsers in
            Task { @MainActor [weak self] in
                self?.webPresence = webUsers
            }
        }
    }

    /// Leave the presence channel. Call when the canvas closes.
    func leavePresence() {
        guard let channel = presenceChannel else { return }
        presenceChannel = nil
        webPresence = []
        Task {
            await service.leaveNotebookPresence(channel)
        }
    }

    /// Build the "Open in Web" deep link URL for the current notebook.
    func webURL(notebookId: UUID) -> URL? {
        URL(string: "https://app.girokiq.app/notebook/\(notebookId.uuidString)")
    }

    // MARK: - Photo Access

    func requestPhotoAccessAndFetch() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            hasPhotoAccess = true
            fetchRecentPhotos()
        case .notDetermined:
            Task {
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    if newStatus == .authorized || newStatus == .limited {
                        self.hasPhotoAccess = true
                        self.fetchRecentPhotos()
                    } else {
                        self.hasPhotoAccess = false
                    }
                }
            }
        default:
            hasPhotoAccess = false
        }
    }

    private func fetchRecentPhotos() {
        guard hasPhotoAccess else { return }
        
        Task.detached(priority: .userInitiated) {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 5
            
            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let imageManager = PHImageManager.default()
            
            let targetSize = CGSize(width: 100, height: 100)
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true // safe on detached task
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            
            var fetchedAssets: [PHAsset] = []
            var fetchedImages: [PHAsset: UIImage] = [:]
            
            for i in 0..<fetchResult.count {
                let asset = fetchResult.object(at: i)
                fetchedAssets.append(asset)
                
                imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { image, _ in
                    if let image = image {
                        fetchedImages[asset] = image
                    }
                }
            }
            
            let finalAssets = Array(fetchedAssets.prefix(5))
            let finalImages = fetchedImages
            await MainActor.run { [weak self] in
                self?.recentPhotos = finalAssets
                self?.recentPhotoImages = finalImages
            }
        }
    }

    // MARK: - Sync

    /// Sync strokes to Supabase. Builds the payload on the main actor,
    /// then dispatches the network call to a background thread so it never stalls the UI.
    func syncToSupabase(userId: UUID, pageId: UUID) async {
        isSaving = true
        let remoteStrokes = currentPage.strokes.map { stroke -> RemoteStroke in
            RemoteStroke(
                id: stroke.id,
                pageId: pageId,
                userId: userId,
                color: stroke.color.hexString,
                width: stroke.width,
                points: Data(), // serialize point data
                createdAt: Date(),
                updatedAt: Date(),
                deleted: stroke.isErased,
                deviceId: UIDevice.current.identifierForVendor?.uuidString
            )
        }
        // Perform network I/O off the main thread
        let service = self.service
        await Task.detached(priority: .utility) {
            do {
                try await service.upsertStrokes(remoteStrokes)
            } catch {
                print("Sync error: \(error)")
            }
        }.value
        isSaving = false
    }
}

// MARK: - Per-Tool Settings

struct ToolSettings: Codable {
    var colorHex: String
    var width: CGFloat
    var opacity: Double
}

struct ToolCustomization: Codable {
    /// Exactly 5 preset colors (non-deletable in UI).
    var presetColorHexes: [String]
    /// User-added colors (deletable).
    var extraColorHexes: [String]
    /// Exactly 3 width presets.
    var widthPresets: [Double]

    static func defaults(for tool: DrawingTool) -> ToolCustomization {
        let presetColors = Array(Color.strokePresets.prefix(5)).map { $0.hexString.uppercased() }

        func widthTriplet(defaultWidth: CGFloat) -> [Double] {
            let w0 = max(0.5, defaultWidth * 0.6)
            let w1 = max(0.5, defaultWidth)
            let w2 = max(0.5, defaultWidth * 1.6)
            return [Double(w0), Double(w1), Double(w2)]
        }

        let widths: [Double]
        switch tool {
        case .pen:
            widths = widthTriplet(defaultWidth: 2.0)
        case .pencil:
            widths = widthTriplet(defaultWidth: 1.5)
        case .marker:
            widths = widthTriplet(defaultWidth: 8.0)
        default:
            widths = widthTriplet(defaultWidth: tool.defaultWidth)
        }

        return ToolCustomization(
            presetColorHexes: presetColors,
            extraColorHexes: [],
            widthPresets: widths
        )
    }
}

struct CanvasViewportState: Codable, Equatable {
    var offsetX: CGFloat
    var offsetY: CGFloat
    var scale: CGFloat
}

struct NotebookTransferPackage: Codable {
    var version: Int
    var notebook: NotebookTransferNotebook
    var pages: [NotebookTransferPage]
}

struct NotebookTransferNotebook: Codable {
    var name: String
    var canvasType: String
    var pageDimensions: PageDimensions?
    var backgroundPattern: String
    var backgroundColorHex: String
}

struct NotebookTransferPage: Codable {
    var title: String
    var pageIndex: Int
    var type: String
    var backgroundPattern: String
    var drawingData: Data?
    var elements: [CanvasElement]
}
