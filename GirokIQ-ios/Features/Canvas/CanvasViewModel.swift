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

private struct DrawingHistorySignature: Equatable {
    var strokeCount: Int
    var byteCount: Int
    var sampleHash: Int
}

private struct PageHistorySnapshot {
    var drawingData: Data?
    var drawingSignature: DrawingHistorySignature
    var elements: [CanvasElement]
    var elementsSignature: Int
    var sizeInBytes: Int
}

private struct PageHistory {
    var snapshots: [PageHistorySnapshot]
    var currentIndex: Int
    var totalBytes: Int
}

// MARK: - Canvas ViewModel

// MARK: - Canvas ViewModel

@MainActor
final class CanvasViewModel: ObservableObject {

    private static func initialStrokeWidth() -> CGFloat {
        if UserDefaults.standard.object(forKey: "savedStrokeWidth") != nil {
            return CGFloat(UserDefaults.standard.double(forKey: "savedStrokeWidth"))
        }
        let fallback = UserDefaults.standard.object(forKey: "defaultStrokeWidth") as? Double ?? 2.0
        return CGFloat(fallback)
    }

    // MARK: - Properties

    @Published var pages: [DrawingPage] = [DrawingPage(title: "Page 1")]
    @Published var currentPageIndex: Int = 0 {
        didSet {
            saveCurrentPageSelection()
            refreshUndoState()
            primeCurrentPageCaches()
            Task { [weak self] in
                await self?.preloadCurrentPageDrawings()
            }
        }
    }
    @Published var selectedTool: DrawingTool = .pen
    @Published var strokeColor: Color = Color(hex: UserDefaults.standard.string(forKey: "savedStrokeColorHex") ?? "#FFFFFE") {
        didSet { 
            UserDefaults.standard.set(strokeColor.hexString, forKey: "savedStrokeColorHex")
            updateCurrentToolMemory()
        }
    }
    @Published var strokeWidth: CGFloat = CanvasViewModel.initialStrokeWidth() {
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
    @Published var eraserType: PKEraserTool.EraserType = {
        let saved = UserDefaults.standard.string(forKey: "savedEraserType") ?? "precise"
        switch saved {
        case "vector", "object":
            return .vector
        case "bitmap":
            return .fixedWidthBitmap
        default:
            return .fixedWidthBitmap
        }
    }() {
        didSet {
            UserDefaults.standard.set(eraserType == .vector ? "object" : "precise", forKey: "savedEraserType")
        }
    }
    @Published var eraserWidth: CGFloat = {
        if UserDefaults.standard.object(forKey: "savedEraserWidth") != nil {
            return CGFloat(UserDefaults.standard.double(forKey: "savedEraserWidth"))
        }
        return 20.0
    }() {
        didSet {
            UserDefaults.standard.set(Double(eraserWidth), forKey: "savedEraserWidth")
        }
    }
    @Published var backgroundPattern: BackgroundPattern = .grid
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var restoredViewport: CanvasViewportState?
    /// Changes every time a notebook is loaded. Canvas host views use this to
    /// re-apply the saved viewport even if UIKit views are reused.
    @Published var viewportRestoreToken: UUID = UUID()
    private var shouldPersistViewportUpdates = false
    private var liveCanvasOffset: CGSize = .zero
    private var liveCanvasScale: CGFloat = 1.0
    // Initial value is .zero — the correct size is written by PKCanvasRepresentable's 
    // updateUIView on the first render pass, before any user interaction can occur. 
    // Using UIScreen.main.bounds.size here was both deprecated (iOS 16+) and wrong 
    // in Split View / Stage Manager contexts. 
    var canvasViewSize: CGSize = .zero
    @Published var showProperties: Bool = true
    @Published var isSaving: Bool = false
    @Published var palmRejectionEnabled: Bool = {
        let fingerDrawingEnabled = UserDefaults.standard.bool(forKey: "fingerDrawing")
        if fingerDrawingEnabled {
            return false
        }
        if UserDefaults.standard.object(forKey: "palmRejection") != nil {
            return UserDefaults.standard.bool(forKey: "palmRejection")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(palmRejectionEnabled, forKey: "palmRejection")
            UserDefaults.standard.set(!palmRejectionEnabled, forKey: "fingerDrawing")
        }
    }
    @Published var isToolbarVisible: Bool = true
    @Published var isShapeSnappingEnabled: Bool = UserDefaults.standard.bool(forKey: "shapeSnapEnabled") {
        didSet { UserDefaults.standard.set(isShapeSnappingEnabled, forKey: "shapeSnapEnabled") }
    }
    /// Active rough→clean morph for the shape-snap transition (nil when idle).
    @Published var shapeSnapMorph: ShapeSnapMorph?
    @Published var forceDrawingUpdate: Bool = false
    @Published var isPreviewingLassoMove: Bool = false
    @Published var isPreviewingLassoResize: Bool = false
    @Published var lassoFloatingImage: UIImage? = nil
    @Published var lassoFloatingCanvasRect: CGRect? = nil
    @Published var lassoMoveTranslation: CGSize = .zero
    @Published var lassoResizeScale: CGFloat = 1.0
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
    @Published var quotaNoticeMessage: String?
    private let quotaService = CloudStorageQuotaService.shared

    // Web presence: tracks whether this notebook is also open on the web app
    @Published var webPresence: [PresenceEntry] = []
    var isOpenOnWeb: Bool { !webPresence.isEmpty }
    private var presenceChannel: RealtimeChannelV2?

    // Photo Library State
    @Published var hasPhotoAccess: Bool = false
    @Published var photoAccessStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var recentPhotos: [PHAsset] = []
    @Published var recentPhotoImages: [PHAsset: UIImage] = [:]

    // UndoManager forwarded from PKCanvasView
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    /// Reference to the PKCanvasView's undoManager, set by PKCanvasRepresentable
    weak var pkUndoManager: UndoManager?
    weak var canvasCoordinateHostView: UIView?
    weak var canvasCoordinateContentView: UIView?

    /// Cached page thumbnails keyed by page ID.
    /// Regenerated only when drawing data changes, not on every frame.
    @Published var pageThumbnails: [UUID: UIImage] = [:]

    private let service = SupabaseService.shared
    private var autoSaveTasks: [UUID: Task<Void, Never>] = [:]
    private var toolbarHideTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var drawingSerializationTasks: [UUID: Task<Void, Never>] = [:]
    private var drawingWarmupTasks: [UUID: Task<Void, Never>] = [:]
    private var shapeSnapTask: Task<Void, Never>?
    private var liveDrawingCache: [UUID: PKDrawing] = [:]
    private var pendingSerializedDrawingData: [UUID: Data] = [:]
    private var lastRemoteNotebookRefreshAt: Date?
    private var lastKnownStrokeCounts: [UUID: Int] = [:]
    private let canvasImagesBucket = "canvas-images"
    private let maxHistoryBytesPerPage = 16 * 1_048_576
    private let inkPasteboardType = "com.apple.ink.drawing"
    private let elementPasteboardType = "com.girokiq.canvas-elements"
    private var pageHistories: [UUID: PageHistory] = [:]
    private var isApplyingHistorySnapshot = false
    var currentPage: DrawingPage {
        get { pages[currentPageIndex] }
        set { pages[currentPageIndex] = newValue }
    }

    var currentDrawing: PKDrawing {
        currentDrawingForCanvasDisplay()
    }

    private func resolvedDrawing(for page: DrawingPage) -> PKDrawing {
        if let cached = liveDrawingCache[page.id] {
            return cached
        }
        return page.pkDrawing
    }

    func currentDrawingForCanvasDisplay() -> PKDrawing {
        let page = pages[currentPageIndex]
        if let cached = liveDrawingCache[page.id] {
            return cached
        }
        if let drawingData = pendingSerializedDrawingData[page.id] ?? page.drawingData {
            preloadDrawingIfNeeded(
                for: page.id,
                drawingData: drawingData,
                refreshCurrentPage: true
            )
        }
        return PKDrawing()
    }

    private func resolvedDrawingData(for page: DrawingPage) -> Data? {
        if let pending = pendingSerializedDrawingData[page.id] {
            return pending
        }
        return page.drawingData
    }

    private func preloadDrawingIfNeeded(
        for pageId: UUID,
        drawingData: Data,
        refreshCurrentPage: Bool = false
    ) {
        guard liveDrawingCache[pageId] == nil else { return }
        guard drawingWarmupTasks[pageId] == nil else { return }

        drawingWarmupTasks[pageId] = Task { [weak self] in
            let drawing = await Task.detached(priority: .utility) {
                PencilKitBridge.deserialize(drawingData)
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            await MainActor.run {
                self.drawingWarmupTasks[pageId] = nil
                guard let drawing else { return }
                self.cacheDrawing(drawing, for: pageId)
                if refreshCurrentPage,
                   self.pages.indices.contains(self.currentPageIndex),
                   self.pages[self.currentPageIndex].id == pageId {
                    self.forceDrawingUpdate = true
                }
            }
        }
    }

    private func preloadCurrentPageDrawings(radius: Int = 1) async {
        guard pages.indices.contains(currentPageIndex) else { return }

        let lowerBound = max(0, currentPageIndex - radius)
        let upperBound = min(pages.count - 1, currentPageIndex + radius)

        for index in lowerBound...upperBound {
            let page = pages[index]
            guard liveDrawingCache[page.id] == nil,
                  let drawingData = pendingSerializedDrawingData[page.id] ?? page.drawingData else { continue }
            preloadDrawingIfNeeded(
                for: page.id,
                drawingData: drawingData,
                refreshCurrentPage: index == currentPageIndex
            )
        }
    }

    private func preferredReloadPageID(in fetchedPages: [(page: Page, drawingData: Data?)]) -> UUID? {
        let availablePageIDs = Set(fetchedPages.map(\.page.id))

        if pages.indices.contains(currentPageIndex) {
            let currentID = pages[currentPageIndex].id
            if availablePageIDs.contains(currentID) {
                return currentID
            }
        }

        if let notebookId {
            let key = Self.currentPageStorageKey(for: notebookId)
            if let storedPageID = UserDefaults.standard.string(forKey: key),
               let restoredID = UUID(uuidString: storedPageID),
               availablePageIDs.contains(restoredID) {
                return restoredID
            }
        }

        return fetchedPages.first?.page.id
    }

    private func warmedReloadDrawings(
        for fetchedPages: [(page: Page, drawingData: Data?)]
    ) async -> [UUID: PKDrawing] {
        guard let targetPageID = preferredReloadPageID(in: fetchedPages),
              let tuple = fetchedPages.first(where: { $0.page.id == targetPageID }) else {
            return [:]
        }

        let incomingDrawingData = tuple.drawingData
        let previousDrawingData = pendingSerializedDrawingData[targetPageID]
            ?? pages.first(where: { $0.id == targetPageID })?.drawingData

        if previousDrawingData == incomingDrawingData,
           let cachedDrawing = liveDrawingCache[targetPageID] {
            return [targetPageID: cachedDrawing]
        }

        guard let incomingDrawingData else { return [:] }

        let drawing = await Task.detached(priority: .userInitiated) {
            PencilKitBridge.deserialize(incomingDrawingData)
        }.value

        guard let drawing else { return [:] }
        return [targetPageID: drawing]
    }

    private func drawingSignature(for data: Data?, strokeCount: Int) -> DrawingHistorySignature {
        guard let data else {
            return DrawingHistorySignature(strokeCount: strokeCount, byteCount: 0, sampleHash: 0)
        }

        var hasher = Hasher()
        hasher.combine(data.count)

        let sampleSize = min(1024, data.count)
        for byte in data.prefix(sampleSize) {
            hasher.combine(byte)
        }
        if data.count > sampleSize {
            for byte in data.suffix(sampleSize) {
                hasher.combine(byte)
            }
        }

        return DrawingHistorySignature(
            strokeCount: strokeCount,
            byteCount: data.count,
            sampleHash: hasher.finalize()
        )
    }

    private func elementsSignature(for elements: [CanvasElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element)
        }
        return hasher.finalize()
    }

    private func pageSnapshot(
        for pageId: UUID,
        drawingDataOverride: Data? = nil,
        strokeCountOverride: Int? = nil
    ) -> PageHistorySnapshot? {
        guard let page = pages.first(where: { $0.id == pageId }) else { return nil }
        let drawingData = drawingDataOverride ?? resolvedDrawingData(for: page)
        let elements = page.elements
        let strokeCount = strokeCountOverride ?? lastKnownStrokeCounts[page.id] ?? liveDrawingCache[page.id]?.strokes.count ?? 0
        let estimatedElementsBytes = max(elements.count * 256, 0)

        return PageHistorySnapshot(
            drawingData: drawingData,
            drawingSignature: drawingSignature(for: drawingData, strokeCount: strokeCount),
            elements: elements,
            elementsSignature: elementsSignature(for: elements),
            sizeInBytes: (drawingData?.count ?? 0) + estimatedElementsBytes
        )
    }

    private func initializePageHistory(for pageId: UUID) {
        guard let snapshot = pageSnapshot(for: pageId) else { return }
        pageHistories[pageId] = PageHistory(snapshots: [snapshot], currentIndex: 0, totalBytes: snapshot.sizeInBytes)
    }

    private func initializeAllPageHistories() {
        pageHistories.removeAll()
        primeCurrentPageCaches()
        refreshUndoState()
    }

    private func captureHistoryNow(
        for pageId: UUID,
        drawingDataOverride: Data? = nil,
        strokeCountOverride: Int? = nil
    ) {
        guard !isApplyingHistorySnapshot else { return }
        if pageHistories[pageId] == nil {
            initializePageHistory(for: pageId)
        }
        guard var history = pageHistories[pageId],
              let snapshot = pageSnapshot(
                for: pageId,
                drawingDataOverride: drawingDataOverride,
                strokeCountOverride: strokeCountOverride
              ) else { return }

        if history.snapshots.indices.contains(history.currentIndex),
           history.snapshots[history.currentIndex].drawingSignature == snapshot.drawingSignature,
           history.snapshots[history.currentIndex].elementsSignature == snapshot.elementsSignature {
            refreshUndoState()
            return
        }

        if history.currentIndex < history.snapshots.count - 1 {
            let retainedSnapshots = Array(history.snapshots.prefix(history.currentIndex + 1))
            history.totalBytes = retainedSnapshots.reduce(0) { $0 + $1.sizeInBytes }
            history.snapshots = retainedSnapshots
        }

        history.snapshots.append(snapshot)
        history.totalBytes += snapshot.sizeInBytes
        while history.totalBytes > maxHistoryBytesPerPage, history.snapshots.count > 1 {
            let removed = history.snapshots.removeFirst()
            history.totalBytes -= removed.sizeInBytes
            history.currentIndex = max(0, history.currentIndex - 1)
        }
        history.currentIndex = history.snapshots.count - 1
        pageHistories[pageId] = history
        refreshUndoState()
    }

    private func restoreHistorySnapshot(_ snapshot: PageHistorySnapshot, for pageId: UUID) {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageId }) else { return }

        isApplyingHistorySnapshot = true
        pages[pageIndex].elements = snapshot.elements
        pages[pageIndex].drawingData = snapshot.drawingData
        pendingSerializedDrawingData[pageId] = snapshot.drawingData

        let finalizeRestore: @MainActor (PKDrawing) -> Void = { [weak self] restoredDrawing in
            guard let self else { return }
            self.cacheDrawing(restoredDrawing, for: pageId)

            if self.currentPageIndex == pageIndex {
                self.clearLassoSelection()
                self.selectedElementIds = []
                self.forceDrawingUpdate = true
            }

            self.objectWillChange.send()
            self.scheduleElementSave()
            self.scheduleDrawingPersistence(for: pageId, drawing: restoredDrawing)
            self.scheduleThumbnailRegeneration(for: pageIndex)
            self.isApplyingHistorySnapshot = false
            self.refreshUndoState()
        }

        guard let drawingData = snapshot.drawingData else {
            finalizeRestore(PKDrawing())
            return
        }

        Task { [weak self] in
            let restoredDrawing = await Task.detached(priority: .userInitiated) {
                PencilKitBridge.deserialize(drawingData) ?? PKDrawing()
            }.value

            guard let self else { return }
            await finalizeRestore(restoredDrawing)
        }
    }

    func setCanvasViewSizeIfNeeded(_ size: CGSize) {
        guard canvasViewSize != size else { return }
        canvasViewSize = size
    }

    // MARK: - Export
    func exportNotebookPDF(pageIndices: [Int]? = nil) -> URL? {
        let selectedPages: [DrawingPage]
        if let pageIndices {
            selectedPages = pageIndices.compactMap { pages.indices.contains($0) ? pages[$0] : nil }
        } else {
            selectedPages = pages
        }

        let pageImages: [UIImage] = selectedPages.map { page in
            let drawing = resolvedDrawing(for: page)
            let elements = page.elements
            let rect = pageExportRect(for: page, drawing: drawing, elements: elements)

            let request = CanvasCompositeRenderer.RenderRequest(
                drawing: drawing,
                elements: elements,
                canvasRect: rect,
                backgroundPattern: page.backgroundPattern,
                backgroundColor: .gBackground,
                scale: 2.0,
                padding: notebook?.canvasType == "fixed" ? 0 : 36
            )
            return CanvasCompositeRenderer.renderImage(request)
        }
        let pdfData = PencilKitBridge.renderPDF(from: pageImages)

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

    private func compositeContentBounds(drawing: PKDrawing, elements: [CanvasElement]) -> CGRect {
        var content = drawing.bounds
        for el in elements {
            let rect = CGRect(
                x: el.positionX,
                y: el.positionY,
                width: CGFloat(el.width ?? 200),
                height: CGFloat(el.height ?? 200)
            )
            content = (content.isNull || content.isEmpty) ? rect : content.union(rect)
        }
        return content
    }

    private func pageExportRect(for page: DrawingPage, drawing: PKDrawing, elements: [CanvasElement]) -> CGRect {
        if notebook?.canvasType == "fixed", let dims = notebook?.pageDimensions {
            return CGRect(origin: .zero, size: CGSize(width: dims.widthPt, height: dims.heightPt))
        }

        let contentBounds = compositeContentBounds(drawing: drawing, elements: elements)
        if contentBounds.isNull || contentBounds.isEmpty {
            return CGRect(origin: .zero, size: CGSize(width: 612, height: 792))
        }
        return contentBounds
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
        let snapshotAssets = NotebookTransferSupport.imageAssets(from: snapshotPages)

        let package = NotebookTransferPackage(
            version: 2,
            notebook: NotebookTransferNotebook(
                name: notebook.name,
                canvasType: notebook.canvasType,
                pageDimensions: notebook.pageDimensions,
                backgroundPattern: notebook.backgroundPattern,
                backgroundColorHex: notebook.backgroundColorHex
            ),
            pages: snapshotPages,
            assets: snapshotAssets
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
        let resolvedNotebook = (try? await LocalDatabase.shared.fetchNotebook(id: notebookId)) ?? notebook
        self.notebook = resolvedNotebook
        self.notebookId = notebookId
        self.userId = userId
        self.restoredViewport = Self.loadViewportState(for: notebookId)
        self.shouldPersistViewportUpdates = false
        self.viewportRestoreToken = UUID()
        let initialViewport = restoredViewport
        let initialOffset = CGSize(
            width: initialViewport?.offsetX ?? 0,
            height: initialViewport?.offsetY ?? 0
        )
        let initialScale = initialViewport?.scale ?? 1.0
        self.canvasOffset = initialOffset
        self.canvasScale = initialScale
        self.liveCanvasOffset = initialOffset
        self.liveCanvasScale = initialScale
        
        // Restore the notebook-level background pattern so the canvas opens
        // with the correct pattern instead of always falling back to .grid.
        if let pattern = BackgroundPattern(rawValue: resolvedNotebook.backgroundPattern) {
            self.backgroundPattern = pattern
        }
        
        do {
            var fetchedPages = try await LocalDatabase.shared.fetchPages(notebookId: notebookId)
            let localLooksLikePlaceholderOnly = !fetchedPages.isEmpty && fetchedPages.allSatisfy { tuple in
                let elements = tuple.page.settings?.elements ?? []
                let hasDrawing = (tuple.drawingData?.isEmpty == false)
                let hasElements = !elements.isEmpty
                return tuple.page.pageIndex == 0 &&
                    tuple.page.title == "Page 1" &&
                    !hasDrawing &&
                    !hasElements
            }
            
            if fetchedPages.isEmpty || localLooksLikePlaceholderOnly {
                // No meaningful local pages yet. Before creating or trusting a placeholder page,
                // pull the notebook's real remote pages so cross-device notebook content appears.
                if Configuration.cloudSyncEnabled,
                   let remotePages = try? await service.fetchPages(notebookId: notebookId),
                   !remotePages.isEmpty
                {
                    if localLooksLikePlaceholderOnly {
                        for tuple in fetchedPages {
                            try await LocalDatabase.shared.deletePage(id: tuple.page.id, syncStatus: .synced)
                        }
                    }
                    for remotePage in remotePages {
                        try await LocalDatabase.shared.savePage(remotePage, syncStatus: .synced)
                        if let remoteElements = try? await service.fetchCanvasElements(pageId: remotePage.id) {
                            try await LocalDatabase.shared.saveCanvasElements(remoteElements, forPageId: remotePage.id, syncStatus: .synced)
                        }
                        if let base64 = remotePage.settings?.drawingData,
                           let data = Data(base64Encoded: base64) {
                            try await LocalDatabase.shared.savePageDrawing(data, pageId: remotePage.id, syncStatus: .synced)
                        }
                    }
                    fetchedPages = try await LocalDatabase.shared.fetchPages(notebookId: notebookId)
                }
            }

            if fetchedPages.isEmpty {
                // Truly first-time notebook with no remote pages yet: create an initial local page.
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
                let warmedDrawings = await warmedReloadDrawings(for: fetchedPages)
                await MainActor.run {
                    self.applyLoadedPages(fetchedPages, warmedDrawings: warmedDrawings)
                    self.lastRemoteNotebookRefreshAt = Date()
                }
            }
            self.restoreCurrentPageSelection()
            self.initializeAllPageHistories()
            self.primeCurrentPageCaches()
            await preloadCurrentPageDrawings()
        } catch {
            print("Failed to load notebook pages: \(error)")
        }
    }

    private func applyLoadedPages(
        _ fetchedPages: [(page: Page, drawingData: Data?)],
        warmedDrawings: [UUID: PKDrawing] = [:]
    ) {
        let existingPagesByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        let previousCache = liveDrawingCache
        let previousPendingData = pendingSerializedDrawingData
        let previousStrokeCounts = lastKnownStrokeCounts
        let previousThumbnails = pageThumbnails

        var nextPages: [DrawingPage] = []
        var nextLiveDrawingCache: [UUID: PKDrawing] = [:]
        var nextPendingSerializedDrawingData: [UUID: Data] = [:]
        var nextStrokeCounts: [UUID: Int] = [:]
        var nextThumbnails: [UUID: UIImage] = [:]

        for tuple in fetchedPages {
            let bgPattern = BackgroundPattern(rawValue: tuple.page.settings?.backgroundPattern ?? "grid") ?? .grid
            let page = DrawingPage(
                id: tuple.page.id,
                title: tuple.page.title,
                drawingData: tuple.drawingData,
                backgroundPattern: bgPattern,
                order: tuple.page.pageIndex,
                elements: tuple.page.settings?.elements ?? []
            )
            nextPages.append(page)

            let pageID = page.id
            let previousDrawingData = previousPendingData[pageID] ?? existingPagesByID[pageID]?.drawingData
            let drawingUnchanged = previousDrawingData == tuple.drawingData

            if let warmedDrawing = warmedDrawings[pageID] {
                nextLiveDrawingCache[pageID] = warmedDrawing
                nextStrokeCounts[pageID] = warmedDrawing.strokes.count
            } else if drawingUnchanged, let cachedDrawing = previousCache[pageID] {
                nextLiveDrawingCache[pageID] = cachedDrawing
                nextStrokeCounts[pageID] = previousStrokeCounts[pageID] ?? cachedDrawing.strokes.count
            }

            if drawingUnchanged,
               let pendingData = previousPendingData[pageID],
               pendingData == tuple.drawingData {
                nextPendingSerializedDrawingData[pageID] = pendingData
            }

            if drawingUnchanged, let thumbnail = previousThumbnails[pageID] {
                nextThumbnails[pageID] = thumbnail
            }
        }

        self.pages = nextPages
        self.liveDrawingCache = nextLiveDrawingCache
        self.pendingSerializedDrawingData = nextPendingSerializedDrawingData
        self.lastKnownStrokeCounts = nextStrokeCounts
        self.pageThumbnails = nextThumbnails
    }

    func refreshNotebookFromRemote() async {
        guard Configuration.cloudSyncEnabled else { return }
        guard let notebookId, let userId else { return }
        _ = userId

        do {
            let pendingPageIDs = try await LocalDatabase.shared.pendingChangeIDs(table: "page")
            let remotePages = try await service.fetchPages(notebookId: notebookId)

            for remotePage in remotePages where !pendingPageIDs.contains(remotePage.id.uuidString) {
                try await LocalDatabase.shared.savePage(remotePage, syncStatus: .synced)
                if let remoteElements = try? await service.fetchCanvasElements(pageId: remotePage.id) {
                    try await LocalDatabase.shared.saveCanvasElements(remoteElements, forPageId: remotePage.id, syncStatus: .synced)
                }
                if let base64 = remotePage.settings?.drawingData,
                   let data = Data(base64Encoded: base64) {
                    try await LocalDatabase.shared.savePageDrawing(data, pageId: remotePage.id, syncStatus: .synced)
                }
            }

            let fetchedPages = try await LocalDatabase.shared.fetchPages(notebookId: notebookId)
            let warmedDrawings = await warmedReloadDrawings(for: fetchedPages)
            await MainActor.run {
                self.applyLoadedPages(fetchedPages, warmedDrawings: warmedDrawings)
                self.restoreCurrentPageSelection()
                self.initializeAllPageHistories()
                self.primeCurrentPageCaches()
                self.lastRemoteNotebookRefreshAt = Date()
            }
            await preloadCurrentPageDrawings()
        } catch {
            print("Failed to refresh notebook from remote: \(error)")
        }
    }

    func shouldRefreshFromSceneActivation(
        userId: UUID,
        minimumInterval: TimeInterval = 180
    ) async -> Bool {
        guard Configuration.cloudSyncEnabled, let notebookId else { return false }

        let now = Date()
        if let lastRemoteNotebookRefreshAt,
           now.timeIntervalSince(lastRemoteNotebookRefreshAt) < minimumInterval {
            return false
        }

        let remoteNotebooks = (try? await service.fetchNotebooks(userId: userId)) ?? []
        guard let remoteNotebook = remoteNotebooks.first(where: { $0.id == notebookId }) else {
            return false
        }

        let localNotebookUpdatedAt = (try? await LocalDatabase.shared.fetchNotebook(id: notebookId))?.updatedAt
            ?? notebook?.updatedAt
            ?? .distantPast

        guard remoteNotebook.updatedAt > localNotebookUpdatedAt else {
            lastRemoteNotebookRefreshAt = now
            return false
        }

        return true
    }

    func updateViewport(offset: CGSize, scale: CGFloat) {
        // Track live UIKit scroll state without publishing every frame into SwiftUI.
        liveCanvasOffset = offset
        liveCanvasScale = scale
    }

    func finalizeViewport(offset: CGSize, scale: CGFloat) {
        liveCanvasOffset = offset
        liveCanvasScale = scale
        canvasOffset = offset
        canvasScale = scale
        shouldPersistViewportUpdates = true
        guard let notebookId else { return }
        let state = CanvasViewportState(offsetX: offset.width, offsetY: offset.height, scale: scale)
        restoredViewport = state
        Self.saveViewportState(state, for: notebookId)
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

    private static func currentPageStorageKey(for notebookId: UUID) -> String {
        "notebookCurrentPage_\(notebookId.uuidString)"
    }

    private func saveCurrentPageSelection() {
        guard let notebookId, pages.indices.contains(currentPageIndex) else { return }
        UserDefaults.standard.set(
            pages[currentPageIndex].id.uuidString,
            forKey: Self.currentPageStorageKey(for: notebookId)
        )
    }

    private func restoreCurrentPageSelection() {
        guard let notebookId else { return }
        let key = Self.currentPageStorageKey(for: notebookId)
        guard let storedPageID = UserDefaults.standard.string(forKey: key),
              let pageUUID = UUID(uuidString: storedPageID),
              let restoredIndex = pages.firstIndex(where: { $0.id == pageUUID }) else {
            currentPageIndex = 0
            return
        }
        currentPageIndex = restoredIndex
    }

    private func cacheDrawing(_ drawing: PKDrawing, for pageId: UUID) {
        liveDrawingCache[pageId] = drawing
        lastKnownStrokeCounts[pageId] = drawing.strokes.count
    }

    private func primeCurrentPageCaches(radius: Int = 1) {
        guard pages.indices.contains(currentPageIndex) else { return }

        let lowerBound = max(0, currentPageIndex - radius)
        let upperBound = min(pages.count - 1, currentPageIndex + radius)

        for index in lowerBound...upperBound {
            let pageId = pages[index].id
            if pageHistories[pageId] == nil {
                initializePageHistory(for: pageId)
            }
            if pageThumbnails[pageId] == nil {
                regenerateThumbnail(for: index)
            }
        }
    }

    private func setCurrentPageDrawingSerialized(
        _ drawing: PKDrawing,
        forceViewUpdate: Bool = false,
        captureHistory: Bool = false,
        saveImmediately: Bool = false,
        schedulePersistence: Bool = true
    ) {
        let pageId = pages[currentPageIndex].id
        cacheDrawing(drawing, for: pageId)
        refreshUndoState()
        if forceViewUpdate {
            forceDrawingUpdate = true
        }
        guard schedulePersistence else { return }
        serializeDrawingSnapshot(
            for: pageId,
            drawing: drawing,
            delayNanoseconds: 0,
            captureHistory: captureHistory,
            saveImmediately: saveImmediately
        )
    }

    private func serializeDrawingSnapshot(
        for pageId: UUID,
        drawing: PKDrawing,
        delayNanoseconds: UInt64,
        captureHistory: Bool,
        saveImmediately: Bool
    ) {
        drawingSerializationTasks.removeValue(forKey: pageId)?.cancel()
        drawingSerializationTasks[pageId] = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }

            let data = await Task.detached(priority: .utility) {
                PencilKitBridge.serialize(drawing)
            }.value

            guard !Task.isCancelled else { return }
            guard let self else { return }

            await MainActor.run {
                self.pendingSerializedDrawingData[pageId] = data
                if let pageIndex = self.pages.firstIndex(where: { $0.id == pageId }) {
                    self.pages[pageIndex].drawingData = data
                }
                if captureHistory {
                    self.captureHistoryNow(
                        for: pageId,
                        drawingDataOverride: data,
                        strokeCountOverride: drawing.strokes.count
                    )
                }
                self.drawingSerializationTasks[pageId] = nil
            }

            if saveImmediately {
                await self.performAutoSave(pageId: pageId, drawingData: data)
            } else {
                await MainActor.run {
                    self.scheduleAutoSave(for: pageId, drawingData: data)
                }
            }
        }
    }

    private func scheduleDrawingPersistence(for pageId: UUID, drawing: PKDrawing) {
        serializeDrawingSnapshot(
            for: pageId,
            drawing: drawing,
            delayNanoseconds: 1_500_000_000,
            captureHistory: true,
            saveImmediately: true
        )
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
        nb.updatedAt = Date()
        self.notebook = nb

        Task {
            do {
                try await LocalDatabase.shared.saveNotebook(nb)

                for drawingPage in pages {
                    if var page = try await LocalDatabase.shared.fetchPage(id: drawingPage.id)?.page {
                        if page.settings == nil {
                            page.settings = PageSettings()
                        }
                        page.settings?.backgroundPattern = pattern.rawValue
                        page.updatedAt = Date()
                        try await LocalDatabase.shared.savePage(page)
                    }
                }

                if await canWriteToCloud() {
                    try await service.updateNotebook(nb)
                }
            } catch {
                print("[Canvas] Failed to persist pattern change: \(error)")
            }
        }
    }

    func undo() {
        let pageId = currentPage.id
        guard var history = pageHistories[pageId], history.currentIndex > 0 else { return }
        history.currentIndex -= 1
        pageHistories[pageId] = history
        restoreHistorySnapshot(history.snapshots[history.currentIndex], for: pageId)
        refreshUndoState()
    }

    func redo() {
        let pageId = currentPage.id
        guard var history = pageHistories[pageId],
              history.currentIndex < history.snapshots.count - 1 else { return }
        history.currentIndex += 1
        pageHistories[pageId] = history
        restoreHistorySnapshot(history.snapshots[history.currentIndex], for: pageId)
        refreshUndoState()
    }

    func refreshUndoState() {
        let pageId = currentPage.id
        let history = pageHistories[pageId]
        let newCanUndo = (history?.currentIndex ?? 0) > 0
        let newCanRedo = (history?.currentIndex ?? 0) < ((history?.snapshots.count ?? 1) - 1)
        if canUndo != newCanUndo {
            canUndo = newCanUndo
        }
        if canRedo != newCanRedo {
            canRedo = newCanRedo
        }
    }

    // MARK: - Lasso Actions (forwarded to PKCanvasView via UIResponder)

    func clearPage() {
        let pageId = pages[currentPageIndex].id
        pages[currentPageIndex].drawingData = nil
        pages[currentPageIndex].strokes.removeAll()
        liveDrawingCache[pageId] = PKDrawing()
        pendingSerializedDrawingData[pageId] = nil
        lastKnownStrokeCounts[pageId] = 0
        captureHistoryNow(for: pageId)
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
        initializePageHistory(for: newPageId)
        
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

    func pageHasContent(at index: Int) -> Bool {
        guard pages.indices.contains(index) else { return false }
        let page = pages[index]
        if !page.elements.isEmpty { return true }
        if let cached = liveDrawingCache[page.id], !cached.strokes.isEmpty { return true }
        if let data = pendingSerializedDrawingData[page.id] ?? page.drawingData,
           let drawing = PencilKitBridge.deserialize(data),
           !drawing.strokes.isEmpty {
            return true
        }
        return false
    }

    func deletePage(at index: Int) {
        guard pages.count > 1 else { return } // Do not allow deleting the last page
        guard index >= 0 && index < pages.count else { return }

        let pageToDelete = pages[index]
        let pageId = pageToDelete.id

        // Update pages array
        pages.remove(at: index)
        reindexPagesInMemory()

        // Adjust currentPageIndex
        if currentPageIndex >= index && currentPageIndex > 0 {
            currentPageIndex -= 1
        }
        
        // Remove from thumbnails cache
        pageThumbnails[pageId] = nil
        liveDrawingCache[pageId] = nil
        pendingSerializedDrawingData[pageId] = nil
        lastKnownStrokeCounts[pageId] = nil
        pageHistories[pageId] = nil

        Task(priority: .utility) {
            do {
                // Delete from local DB
                try await LocalDatabase.shared.deletePage(id: pageId)
                if Configuration.cloudSyncEnabled, await self.canWriteToCloud() {
                    try await SupabaseService.shared.deletePage(id: pageId)
                    try? await LocalDatabase.shared.markSynced(table: "page", id: pageId.uuidString)
                }
            } catch {
                print("Failed to delete page: \(error)")
            }
        }

        persistPageOrder()
    }

    func movePage(from sourceIndex: Int, to destinationIndex: Int) {
        guard pages.indices.contains(sourceIndex),
              pages.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }

        let movingPage = pages.remove(at: sourceIndex)
        pages.insert(movingPage, at: destinationIndex)
        reindexPagesInMemory()

        if currentPageIndex == sourceIndex {
            currentPageIndex = destinationIndex
        } else if sourceIndex < currentPageIndex && destinationIndex >= currentPageIndex {
            currentPageIndex -= 1
        } else if sourceIndex > currentPageIndex && destinationIndex <= currentPageIndex {
            currentPageIndex += 1
        }

        persistPageOrder()
    }

    private func reindexPagesInMemory() {
        for index in pages.indices {
            pages[index].order = index
        }
    }

    private func persistPageOrder() {
        let snapshot = pages.enumerated().map { ($0.offset, $0.element) }
        Task.detached(priority: .utility) {
            for (index, drawingPage) in snapshot {
                do {
                    let existing = try await LocalDatabase.shared.fetchPage(id: drawingPage.id)
                    guard var page = existing?.page else { continue }
                    page.pageIndex = index
                    page.updatedAt = Date()
                    page.settings?.backgroundPattern = drawingPage.backgroundPattern.rawValue
                    page.settings?.elements = drawingPage.elements
                    try await LocalDatabase.shared.savePage(page)
                    if Configuration.cloudSyncEnabled {
                        var remotePage = page
                        var remoteSettings = remotePage.settings ?? PageSettings()
                        remoteSettings.drawingData = existing?.drawingData?.base64EncodedString()
                        remotePage.settings = remoteSettings
                        try await SupabaseService.shared.updatePage(remotePage)
                    }
                } catch {
                    print("Failed to persist page order for \(drawingPage.id): \(error)")
                }
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
    @Published var lassoContentBounds: CGRect? = nil
    /// Whether the lasso bounding box + edit menu are visible.
    @Published var isLassoSelectionActive: Bool = false
    /// Indices into currentPage.pkDrawing.strokes that are currently selected.
    /// Using indices because PKStroke has no stable ID.
    @Published var selectedPKStrokeIndices: Set<Int> = []
    private var lassoFloatedStrokes: [PKStroke] = []
    private var lassoRemainingDrawing: PKDrawing? = nil
    private let lassoSelectionPadding: CGFloat = 12

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
                ).insetBy(dx: -12, dy: -10)
                return rect.contains(canvasPoint)
            })?.id
    }

    func handleTextToolCanvasTap(at canvasPoint: CGPoint) {
        guard selectedTool == .text else { return }

        if let hitId = textElementID(at: canvasPoint) {
            selectedElementIds = [hitId]
            DispatchQueue.main.async { [weak self] in
                self?.ensureSelectedTextVisible()
            }
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
    private var liveLassoCanvasPoints: [CGPoint] = []

    func setCanvasCoordinateViews(hostView: UIView?, contentView: UIView?) {
        canvasCoordinateHostView = hostView
        canvasCoordinateContentView = contentView
    }

    func projectCanvasPointToViewport(_ point: CGPoint) -> CGPoint {
        guard let hostView = canvasCoordinateHostView,
              let contentView = canvasCoordinateContentView else {
            let scale = liveCanvasScale
            let offset = liveCanvasOffset
            return CGPoint(
                x: point.x * scale - offset.width,
                y: point.y * scale - offset.height
            )
        }
        return contentView.convert(point, to: hostView)
    }

    func projectCanvasRectToViewport(_ rect: CGRect) -> CGRect {
        guard let hostView = canvasCoordinateHostView,
              let contentView = canvasCoordinateContentView else {
            let scale = liveCanvasScale
            let offset = liveCanvasOffset
            return CGRect(
                x: rect.minX * scale - offset.width,
                y: rect.minY * scale - offset.height,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }
        return contentView.convert(rect, to: hostView)
    }

    func projectCanvasTranslationToViewport(_ translation: CGSize) -> CGSize {
        let origin = projectCanvasPointToViewport(.zero)
        let translated = projectCanvasPointToViewport(
            CGPoint(x: translation.width, y: translation.height)
        )
        return CGSize(
            width: translated.x - origin.x,
            height: translated.y - origin.y
        )
    }

    func beginLiveLasso(at screenPoint: CGPoint, canvasPoint: CGPoint? = nil) {
        guard selectedTool == .lasso, !isRegionCaptureMode else { return }
        liveLassoPoints = [screenPoint]
        liveLassoCanvasPoints = [canvasPoint ?? screenPoint]
    }

    func appendLiveLasso(_ screenPoint: CGPoint, canvasPoint: CGPoint? = nil) {
        guard selectedTool == .lasso, !isRegionCaptureMode, !liveLassoPoints.isEmpty else { return }
        liveLassoPoints.append(screenPoint)
        liveLassoCanvasPoints.append(canvasPoint ?? screenPoint)
    }

    func endLiveLasso() {
        let screenPoints = liveLassoPoints
        let canvasPoints = liveLassoCanvasPoints
        liveLassoPoints = []
        liveLassoCanvasPoints = []
        guard selectedTool == .lasso, screenPoints.count > 2 else { return }
        let committedPolygon = canvasPoints.count == screenPoints.count ? canvasPoints : screenPoints
        commitLassoSelection(polygon: committedPolygon)
    }

    func cancelLiveLasso() {
        liveLassoPoints = []
        liveLassoCanvasPoints = []
    }

    /// Called when the user lifts the pencil. `polygon` is expected to be in
    /// canvas/block-overlay space, matching `CanvasElement.positionX/Y`.
    func commitLassoSelection(polygon: [CGPoint]) {
        guard polygon.count > 2 else {
            print("[Lasso] Polygon too small (\(polygon.count) points) — skipping")
            return
        }

        let canvasPolygon = polygon
        let polyBBox = polygonBoundingBox(canvasPolygon)
        print("[Lasso] Polygon canvas bbox: \(polyBBox.debugDescription)")
        print("[Lasso] canvasOffset=\(canvasOffset) canvasScale=\(canvasScale)")
        
        let hitElements = currentPage.elements.filter { el in
            let hit = elementIntersectsLasso(el, polygon: canvasPolygon, polygonBounds: polyBBox)
            print("[Lasso] Element '\(el.type)' pos=(\(el.positionX), \(el.positionY)) hit=\(hit)")
            return hit
        }

        // Hit-test PencilKit strokes (these are the actual ink strokes on screen)
        let pkStrokes = currentDrawing.strokes
        print("[Lasso] PKDrawing has \(pkStrokes.count) strokes to test")

        let strokeCoverageThreshold: Double = hitElements.isEmpty ? 0.2 : 0.25
        var hitPKStrokeIndices: [Int] = []
        for (i, stroke) in pkStrokes.enumerated() {
            let hit = strokeIntersectsLassoPrecisely(
                stroke,
                polygon: canvasPolygon,
                polygonBounds: polyBBox,
                minimumCoverage: strokeCoverageThreshold
            )
            print("[Lasso] Stroke \(i) renderBounds=\(stroke.renderBounds.debugDescription) hit=\(hit)")
            if hit { hitPKStrokeIndices.append(i) }
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
        
        let contentBounds = selectedContentBounds(
            strokeIndices: Set(hitPKStrokeIndices),
            elementIDs: Set(hitElements.map(\.id)),
            drawing: currentDrawing,
            elements: currentPage.elements
        )
        updateLassoBounds(contentBounds: contentBounds)
        if let lassoSelectionBox {
            print("[Lasso] Selection box set: \(lassoSelectionBox.debugDescription)")
        }
    }
    
    func clearLassoSelection() {
        clearFloatingLassoPreviewState()
        selectedStrokes = []
        selectedPKStrokeIndices = []
        selectedElementIds = []
        lassoContentBounds = nil
        lassoSelectionBox = nil
        isLassoSelectionActive = false
    }

    private func polygonBoundingBox(_ polygon: [CGPoint]) -> CGRect {
        let xs = polygon.map(\.x)
        let ys = polygon.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    private func sampledPoints(in rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY)
        ]
    }

    private func lineSegments(of polygon: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard polygon.count > 1 else { return [] }
        return polygon.indices.map { index in
            let next = (index + 1) % polygon.count
            return (polygon[index], polygon[next])
        }
    }

    private func ccw(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
    }

    private func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d)
    }

    private func polygonIntersectsRect(_ polygon: [CGPoint], rect: CGRect, polygonBounds: CGRect) -> Bool {
        guard rect.intersects(polygonBounds) else { return false }

        if sampledPoints(in: rect).contains(where: { pointInPolygon($0, polygon: polygon) }) {
            return true
        }

        if polygon.contains(where: { rect.contains($0) }) {
            return true
        }

        let rectCorners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let rectEdges = [
            (rectCorners[0], rectCorners[1]),
            (rectCorners[1], rectCorners[2]),
            (rectCorners[2], rectCorners[3]),
            (rectCorners[3], rectCorners[0])
        ]

        for (p0, p1) in lineSegments(of: polygon) {
            for (r0, r1) in rectEdges where segmentsIntersect(p0, p1, r0, r1) {
                return true
            }
        }

        return false
    }

    private func strokeIntersectsLassoPrecisely(
        _ stroke: PKStroke,
        polygon: [CGPoint],
        polygonBounds: CGRect,
        minimumCoverage: Double
    ) -> Bool {
        let strokeRect = stroke.renderBounds.insetBy(dx: -3, dy: -3)
        guard strokeRect.intersects(polygonBounds) else { return false }

        let transformedPoints = stroke.path.map { point in
            point.location.applying(stroke.transform)
        }
        guard !transformedPoints.isEmpty else { return false }

        let insideCount = transformedPoints.reduce(into: 0) { count, point in
            if pointInPolygon(point, polygon: polygon) {
                count += 1
            }
        }

        let fractionInside = Double(insideCount) / Double(transformedPoints.count)
        let centroid = CGPoint(
            x: transformedPoints.map(\.x).reduce(0, +) / CGFloat(transformedPoints.count),
            y: transformedPoints.map(\.y).reduce(0, +) / CGFloat(transformedPoints.count)
        )

        if pointInPolygon(centroid, polygon: polygon) {
            return true
        }

        return fractionInside >= minimumCoverage
    }

    private func elementIntersectsLasso(_ element: CanvasElement, polygon: [CGPoint], polygonBounds: CGRect) -> Bool {
        let rect = elementBounds(element)
        return polygonIntersectsRect(polygon, rect: rect, polygonBounds: polygonBounds)
    }

    private func elementBounds(_ element: CanvasElement) -> CGRect {
        // Lasso bounds should hug what the user actually sees, not the invisible
        // editing frame that text blocks keep around for insertion/caret behavior.
        if element.type == "text" {
            let contentRect = textContentBounds(for: element)
            return contentRect.insetBy(dx: -6, dy: -4)
        }

        return CGRect(
            x: element.positionX,
            y: element.positionY,
            width: max(60, CGFloat(element.width ?? 200)),
            height: max(60, CGFloat(element.height ?? 200))
        )
    }

    private func textContentBounds(for element: CanvasElement) -> CGRect {
        let rawText = (element.content ?? "").replacingOccurrences(of: "\u{200B}", with: "")
        let text = rawText.isEmpty ? " " : rawText
        let fontSize = CGFloat(element.style?.fontSize ?? 16)

        let baseFont: UIFont = {
            if let name = element.style?.fontName, let named = UIFont(name: name, size: fontSize) {
                return named
            }
            return .systemFont(ofSize: fontSize)
        }()

        var traits: UIFontDescriptor.SymbolicTraits = []
        if element.style?.isBold ?? false { traits.insert(.traitBold) }
        if element.style?.isItalic ?? false { traits.insert(.traitItalic) }
        let resolvedFont: UIFont = {
            guard !traits.isEmpty,
                  let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else { return baseFont }
            return UIFont(descriptor: descriptor, size: fontSize)
        }()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(element.style?.lineSpacing ?? 0)
        paragraphStyle.lineBreakMode = (element.userResized && (element.width ?? 0) > 0)
            ? .byCharWrapping
            : .byClipping
        switch element.style?.textAlignment {
        case "center": paragraphStyle.alignment = .center
        case "right": paragraphStyle.alignment = .right
        case "justified": paragraphStyle.alignment = .justified
        default: paragraphStyle.alignment = .left
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: resolvedFont,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let constrainedWidth = element.userResized
            ? max(1, CGFloat(element.width ?? 200) - TextElementMetrics.editorInsets.left - TextElementMetrics.editorInsets.right)
            : CGFloat.greatestFiniteMagnitude

        let measured = attributed.boundingRect(
            with: CGSize(width: constrainedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral

        let measuredWidth = max(1, min(measured.width, constrainedWidth.isFinite ? constrainedWidth : measured.width))
        let measuredHeight = max(resolvedFont.lineHeight, measured.height)

        return CGRect(
            x: element.positionX + TextElementMetrics.editorInsets.left,
            y: element.positionY + TextElementMetrics.editorInsets.top,
            width: measuredWidth,
            height: measuredHeight
        )
    }

    private func selectedContentBounds(
        strokeIndices: Set<Int>? = nil,
        elementIDs: Set<UUID>? = nil,
        drawing: PKDrawing? = nil,
        elements: [CanvasElement]? = nil
    ) -> CGRect? {
        let resolvedDrawing = drawing ?? currentDrawing
        let resolvedElements = elements ?? currentPage.elements
        let strokeSet = strokeIndices ?? selectedPKStrokeIndices
        let elementSet = elementIDs ?? selectedElementIds

        var rects: [CGRect] = []
        rects += strokeSet.compactMap { index in
            guard index >= 0, index < resolvedDrawing.strokes.count else { return nil }
            return resolvedDrawing.strokes[index].renderBounds
        }
        rects += resolvedElements
            .filter { elementSet.contains($0.id) }
            .map(elementBounds)

        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private func updateLassoBounds(contentBounds: CGRect?) {
        lassoContentBounds = contentBounds
        if let contentBounds {
            lassoSelectionBox = contentBounds.insetBy(dx: -lassoSelectionPadding, dy: -lassoSelectionPadding)
            isLassoSelectionActive = true
        } else {
            lassoSelectionBox = nil
            isLassoSelectionActive = false
        }
    }

    private func refreshLassoBoundsFromSelection(drawing: PKDrawing? = nil, elements: [CanvasElement]? = nil) {
        updateLassoBounds(
            contentBounds: selectedContentBounds(
                drawing: drawing,
                elements: elements
            )
        )
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
        setCurrentPageDrawingSerialized(
            newDrawing,
            forceViewUpdate: true,
            captureHistory: true
        )
        objectWillChange.send()
        print("[Lasso] Color changed on \(selectedPKStrokeIndices.count) strokes")
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Scale all selected strokes and elements from the bounding box top-left anchor.
    func applyLassoResize(scale: CGFloat) {
        guard let contentBounds = lassoContentBounds, scale > 0 else { return }
        let origin = contentBounds.origin
        let t = CGAffineTransform.identity
            .translatedBy(x: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -origin.x, y: -origin.y)

        // Scale PK strokes via their transform
        let updatedDrawing: PKDrawing?
        if !selectedPKStrokeIndices.isEmpty {
            var allStrokes = currentDrawing.strokes
            for i in selectedPKStrokeIndices where i < allStrokes.count {
                let old = allStrokes[i]
                allStrokes[i] = PKStroke(ink: old.ink, path: old.path,
                                         transform: old.transform.concatenating(t),
                                         mask: old.mask)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            updatedDrawing = newDrawing
        } else {
            updatedDrawing = nil
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

        if let updatedDrawing {
            setCurrentPageDrawingSerialized(
                updatedDrawing,
                forceViewUpdate: true,
                captureHistory: true
            )
        }
        refreshLassoBoundsFromSelection(drawing: updatedDrawing, elements: currentPage.elements)
        objectWillChange.send()
        scheduleElementSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Move all selected strokes and elements by the given translation in canvas space.
    func applyLassoMove(translation: CGSize) {
        beginLassoMoveIfNeeded()
        previewLassoMove(translation: translation)
    }

    func beginLassoMoveIfNeeded() {
        guard !isPreviewingLassoMove && !isPreviewingLassoResize else { return }
        guard beginFloatingLassoPreviewIfNeeded() else { return }
        isPreviewingLassoMove = true
        isPreviewingLassoResize = false
        lassoMoveTranslation = .zero
    }

    func beginLassoResizeIfNeeded() {
        guard !isPreviewingLassoResize && !isPreviewingLassoMove else { return }
        guard beginFloatingLassoPreviewIfNeeded() else { return }
        isPreviewingLassoResize = true
        isPreviewingLassoMove = false
        lassoResizeScale = 1.0
    }

    private func beginFloatingLassoPreviewIfNeeded() -> Bool {
        if lassoFloatingImage != nil || lassoRemainingDrawing != nil || isPreviewingLassoMove || isPreviewingLassoResize {
            return true
        }
        guard let selectionRect = lassoSelectionCanvasRect(), selectionRect.width > 0, selectionRect.height > 0 else { return false }

        let allStrokes = currentDrawing.strokes
        let sortedStrokeIndices = selectedPKStrokeIndices.sorted()
        let selectedSet = Set(sortedStrokeIndices)
        let selectedStrokes = sortedStrokeIndices.compactMap { $0 < allStrokes.count ? allStrokes[$0] : nil }
        let remainingStrokes = allStrokes.enumerated()
            .filter { !selectedSet.contains($0.offset) }
            .map(\.element)

        let selectedElements = currentPage.elements.filter { selectedElementIds.contains($0.id) }
        let snapshotRequest = CanvasCompositeRenderer.RenderRequest(
            drawing: PKDrawing(strokes: selectedStrokes),
            elements: selectedElements,
            canvasRect: selectionRect,
            backgroundPattern: currentPage.backgroundPattern,
            backgroundColor: .clear,
            includeBackgroundPattern: false,
            scale: UIScreen.main.scale,
            padding: 0
        )

        lassoFloatingImage = CanvasCompositeRenderer.renderImage(snapshotRequest)
        lassoFloatingCanvasRect = selectionRect
        lassoFloatedStrokes = selectedStrokes
        lassoMoveTranslation = .zero
        lassoResizeScale = 1.0
        lassoRemainingDrawing = PKDrawing(strokes: remainingStrokes)

        if !selectedStrokes.isEmpty {
            setCurrentPageDrawingSerialized(
                PKDrawing(strokes: remainingStrokes),
                forceViewUpdate: true,
                schedulePersistence: false
            )
        }
        objectWillChange.send()
        return true
    }

    func previewLassoMove(translation: CGSize) {
        guard isPreviewingLassoMove else { return }
        lassoMoveTranslation = translation
    }

    func previewLassoResize(scale: CGFloat) {
        guard isPreviewingLassoResize else { return }
        lassoResizeScale = max(0.1, scale)
    }

    func finalizeLassoMove() {
        defer { clearFloatingLassoPreviewState() }

        guard isPreviewingLassoMove else { return }

        let translation = lassoMoveTranslation
        let t = CGAffineTransform(translationX: translation.width, y: translation.height)
        let movedStrokes = lassoFloatedStrokes.map {
            PKStroke(
                ink: $0.ink,
                path: $0.path,
                transform: $0.transform.concatenating(t),
                mask: $0.mask
            )
        }

        let baseStrokes = lassoRemainingDrawing?.strokes ?? currentDrawing.strokes
        let finalDrawing = PKDrawing(strokes: baseStrokes + movedStrokes)
        if !lassoFloatedStrokes.isEmpty {
            setCurrentPageDrawingSerialized(
                finalDrawing,
                forceViewUpdate: true,
                captureHistory: true
            )
            let finalCount = finalDrawing.strokes.count
            selectedPKStrokeIndices = Set((finalCount - movedStrokes.count)..<finalCount)
        }

        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            pages[currentPageIndex].elements[i].positionX += translation.width
            pages[currentPageIndex].elements[i].positionY += translation.height
        }

        refreshLassoBoundsFromSelection(drawing: finalDrawing, elements: pages[currentPageIndex].elements)

        objectWillChange.send()
        scheduleElementSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    func finalizeLassoResize() {
        defer { clearFloatingLassoPreviewState() }

        guard isPreviewingLassoResize,
              let contentBounds = lassoContentBounds else { return }

        let scale = lassoResizeScale
        let origin = contentBounds.origin
        let t = CGAffineTransform.identity
            .translatedBy(x: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -origin.x, y: -origin.y)

        let movedStrokes = lassoFloatedStrokes.map {
            PKStroke(
                ink: $0.ink,
                path: $0.path,
                transform: $0.transform.concatenating(t),
                mask: $0.mask
            )
        }

        let baseStrokes = lassoRemainingDrawing?.strokes ?? currentDrawing.strokes
        let finalDrawing = PKDrawing(strokes: baseStrokes + movedStrokes)
        if !lassoFloatedStrokes.isEmpty {
            setCurrentPageDrawingSerialized(
                finalDrawing,
                forceViewUpdate: true,
                captureHistory: true
            )
            let finalCount = finalDrawing.strokes.count
            selectedPKStrokeIndices = Set((finalCount - movedStrokes.count)..<finalCount)
        }

        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            let el = pages[currentPageIndex].elements[i]
            pages[currentPageIndex].elements[i].positionX = origin.x + (el.positionX - origin.x) * scale
            pages[currentPageIndex].elements[i].positionY = origin.y + (el.positionY - origin.y) * scale
            pages[currentPageIndex].elements[i].width = max(40, (el.width ?? 200) * scale)
            pages[currentPageIndex].elements[i].height = max(40, (el.height ?? 200) * scale)
        }

        refreshLassoBoundsFromSelection(drawing: finalDrawing, elements: pages[currentPageIndex].elements)

        objectWillChange.send()
        scheduleElementSave()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    private func clearFloatingLassoPreviewState() {
        lassoFloatingImage = nil
        lassoFloatingCanvasRect = nil
        lassoFloatedStrokes = []
        lassoRemainingDrawing = nil
        lassoMoveTranslation = .zero
        lassoResizeScale = 1.0
        isPreviewingLassoMove = false
        isPreviewingLassoResize = false
    }

    func moveSelection(dx: CGFloat, dy: CGFloat) {
        let t = CGAffineTransform(translationX: dx, y: dy)
        var updatedDrawing: PKDrawing? = nil
        if !selectedPKStrokeIndices.isEmpty {
            var allStrokes = currentDrawing.strokes
            for i in selectedPKStrokeIndices where i < allStrokes.count {
                let old = allStrokes[i]
                allStrokes[i] = PKStroke(ink: old.ink, path: old.path,
                                         transform: old.transform.concatenating(t),
                                         mask: old.mask)
            }
            let newDrawing = PKDrawing(strokes: allStrokes)
            setCurrentPageDrawingSerialized(newDrawing, captureHistory: true)
            updatedDrawing = newDrawing
        }
        for i in pages[currentPageIndex].elements.indices {
            guard selectedElementIds.contains(pages[currentPageIndex].elements[i].id) else { continue }
            pages[currentPageIndex].elements[i].positionX += dx
            pages[currentPageIndex].elements[i].positionY += dy
        }
        refreshLassoBoundsFromSelection(drawing: updatedDrawing, elements: pages[currentPageIndex].elements)
        objectWillChange.send()
        scheduleElementSave()
        if updatedDrawing == nil {
            captureHistoryNow(for: currentPage.id)
        }
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    private struct LassoClipboardCopyResult {
        var copiedStrokes = false
        var copiedElements = false

        var copiedAnything: Bool { copiedStrokes || copiedElements }
    }

    private struct ElementClipboardPayload: Codable {
        var elements: [CanvasElement]
    }

    private func copySelectionInternal() -> LassoClipboardCopyResult {
        var result = LassoClipboardCopyResult()

        if !selectedPKStrokeIndices.isEmpty {
            let allStrokes = currentDrawing.strokes
            let selected = selectedPKStrokeIndices.sorted().compactMap {
                $0 < allStrokes.count ? allStrokes[$0] : nil
            }
            let drawing = PKDrawing(strokes: selected)
            let data = PencilKitBridge.serialize(drawing)
            UIPasteboard.general.setData(data, forPasteboardType: inkPasteboardType)
            result.copiedStrokes = !selected.isEmpty
            print("[Lasso] Copied \(selected.count) strokes to pasteboard")
        }

        let selectedElements = currentPage.elements
            .filter { selectedElementIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.zIndex < rhs.zIndex
            }
        if !selectedElements.isEmpty {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(ElementClipboardPayload(elements: selectedElements))
                UIPasteboard.general.setData(data, forPasteboardType: elementPasteboardType)
                result.copiedElements = true
            } catch {
                print("[Lasso] Failed to copy selected elements: \(error)")
            }
        }

        return result
    }

    /// Cut: copy to pasteboard then delete only what was actually copied.
    func cutSelection() {
        let result = copySelectionInternal()
        guard result.copiedAnything else { return }
        deleteSelectedLassoContent(
            deleteStrokes: result.copiedStrokes,
            deleteElements: result.copiedElements
        )
    }

    /// Copy selected PK strokes and canvas elements to UIPasteboard.
    func copySelection() {
        _ = copySelectionInternal()
    }

    /// Paste PKDrawing and canvas elements from UIPasteboard, offset slightly so it's visible.
    func pasteSelection() {
        let offset = CGAffineTransform(translationX: 24, y: 24)
        var pastedAnything = false
        var updatedDrawing = currentDrawing
        var drawingChanged = false
        var pastedStrokeIndices: Set<Int> = []
        var pastedElementIDs: Set<UUID> = []

        if let data = UIPasteboard.general.data(forPasteboardType: inkPasteboardType),
           let drawing = PencilKitBridge.deserialize(data) {
            let offsetStrokes = drawing.strokes.map { stroke in
                PKStroke(
                    ink: stroke.ink,
                    path: stroke.path,
                    transform: stroke.transform.concatenating(offset),
                    mask: stroke.mask
                )
            }
            var allStrokes = updatedDrawing.strokes
            let startIndex = allStrokes.count
            allStrokes.append(contentsOf: offsetStrokes)
            updatedDrawing = PKDrawing(strokes: allStrokes)
            pastedStrokeIndices = Set(startIndex..<allStrokes.count)
            drawingChanged = !offsetStrokes.isEmpty
            pastedAnything = pastedAnything || !offsetStrokes.isEmpty
        }

        if let data = UIPasteboard.general.data(forPasteboardType: elementPasteboardType) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let payload = try decoder.decode(ElementClipboardPayload.self, from: data)
                if !payload.elements.isEmpty {
                    let nextZIndex = (currentPage.elements.map(\.zIndex).max() ?? -1) + 1
                    let duplicatedElements = payload.elements.enumerated().map { index, element in
                        CanvasElement(
                            pageId: currentPage.id,
                            userId: userId ?? element.userId,
                            type: element.type,
                            content: element.content,
                            positionX: element.positionX + 24,
                            positionY: element.positionY + 24,
                            width: element.width,
                            height: element.height,
                            rotation: element.rotation,
                            zIndex: nextZIndex + index,
                            style: element.style,
                            userResized: element.userResized
                        )
                    }
                    pages[currentPageIndex].elements.append(contentsOf: duplicatedElements)
                    pastedElementIDs = Set(duplicatedElements.map(\.id))
                    scheduleElementSave()
                    pastedAnything = true
                }
            } catch {
                print("[Lasso] Failed to paste selected elements: \(error)")
            }
        }

        guard pastedAnything else { return }

        selectedPKStrokeIndices = pastedStrokeIndices
        selectedElementIds = pastedElementIDs
        if drawingChanged {
            setCurrentPageDrawingSerialized(updatedDrawing, captureHistory: true)
        } else {
            captureHistoryNow(for: currentPage.id)
        }
        refreshLassoBoundsFromSelection(drawing: updatedDrawing, elements: currentPage.elements)
        objectWillChange.send()
        NotificationCenter.default.post(name: .lassoDrawingMutated, object: nil)
    }

    /// Duplicate: paste a copy of the current selection in place (offset 24pt).
    func duplicateSelection() {
        let result = copySelectionInternal()
        guard result.copiedAnything else { return }
        pasteSelection()
    }

    /// Delete all selected strokes and elements, then clear the selection.
    func deleteSelectedLassoContent(deleteStrokes: Bool = true, deleteElements: Bool = true) {
        // Delete PK strokes by rebuilding drawing without selected indices
        var updatedDrawing: PKDrawing?
        if deleteStrokes, !selectedPKStrokeIndices.isEmpty {
            let allStrokes = currentDrawing.strokes
            let remaining = allStrokes.indices
                .filter { !selectedPKStrokeIndices.contains($0) }
                .map { allStrokes[$0] }
            let newDrawing = PKDrawing(strokes: remaining)
            updatedDrawing = newDrawing
        }
        
        if deleteElements {
            pages[currentPageIndex].elements.removeAll { selectedElementIds.contains($0.id) }
        }
        if let updatedDrawing {
            setCurrentPageDrawingSerialized(
                updatedDrawing,
                forceViewUpdate: true,
                captureHistory: true
            )
        } else {
            captureHistoryNow(for: currentPage.id)
        }
        clearLassoSelection()
        objectWillChange.send()
        scheduleElementSave()
    }
    
    private func lassoSelectionCanvasRect() -> CGRect? {
        if let lassoContentBounds, lassoContentBounds.width > 0, lassoContentBounds.height > 0 {
            return lassoContentBounds
        }
        return selectedContentBounds()
    }

    /// Render the selected strokes as a UIImage cropped to the lasso bounding box.
    /// Returns nil if nothing is selected or the bounding box is empty.
    func screenshotSelection() -> UIImage? {
        guard let selectionRect = lassoSelectionCanvasRect() else { return nil }

        let allStrokes = currentDrawing.strokes
        let selectedStrokes = selectedPKStrokeIndices.sorted().compactMap {
            $0 < allStrokes.count ? allStrokes[$0] : nil
        }
        let selectionDrawing = PKDrawing(strokes: selectedStrokes)

        let selectedElements = currentPage.elements
            .filter { selectedElementIds.contains($0.id) }

        let request = CanvasCompositeRenderer.RenderRequest(
            drawing: selectionDrawing,
            elements: selectedElements,
            canvasRect: selectionRect,
            backgroundPattern: currentPage.backgroundPattern,
            backgroundColor: .gBackground,
            scale: 2.0,
            padding: 24
        )
        return CanvasCompositeRenderer.renderImage(request)
    }
    
    private var elementSaveTask: Task<Void, Never>?
    
    func addElement(_ element: CanvasElement) {
        pages[currentPageIndex].elements.append(element)
        // Explicitly trigger an update since it's a nested array
        objectWillChange.send()
        scheduleElementSave()
        captureHistoryNow(for: currentPage.id)
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

    var shouldShowPhotoSettingsPrompt: Bool {
        photoAccessStatus == .denied || photoAccessStatus == .restricted
    }

    func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func localImageURL(for fileName: String) -> URL {
        NotebookTransferSupport.localImageURL(for: fileName)
    }

    private func canWriteToCloud(showLocalOnlyNotice: Bool = false) async -> Bool {
        guard Configuration.cloudSyncEnabled else { return false }
        let status = await quotaService.status(for: userId)
        if !status.canSyncToCloud, showLocalOnlyNotice {
            presentQuotaNotice(CloudStorageQuotaStatus.localOnlyWriteMessage)
        }
        return status.canSyncToCloud
    }

    private func presentQuotaNotice(_ message: String) {
        DispatchQueue.main.async {
            self.quotaNoticeMessage = message
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if self.quotaNoticeMessage == message {
                    self.quotaNoticeMessage = nil
                }
            }
        }
    }

    private func remoteImageAssetPath(for fileName: String) -> String? {
        guard Configuration.cloudSyncEnabled else { return nil }
        guard let userId, let notebookId else { return nil }
        return "\(userId.uuidString)/\(notebookId.uuidString)/\(fileName)"
    }

    func resolveImage(for element: CanvasElement) async -> UIImage? {
        guard element.type == "image", let fileName = element.content, !fileName.isEmpty else { return nil }

        let fileURL = localImageURL(for: fileName)
        if let localImage = await Task.detached(priority: .userInitiated, operation: {
            UIImage(contentsOfFile: fileURL.path)
        }).value {
            return localImage
        }

        guard Configuration.cloudSyncEnabled, let remotePath = element.style?.imageAssetPath else { return nil }

        do {
            let data = try await service.downloadCanvasImage(path: remotePath)
            try data.write(to: fileURL, options: .atomic)
            return UIImage(data: data)
        } catch {
            print("Failed to download remote image asset: \(error)")
            return nil
        }
    }

    private func uploadImageAssetIfNeeded(data: Data, remotePath: String?) {
        guard Configuration.cloudSyncEnabled, let remotePath else { return }
        Task(priority: .utility) {
            guard await self.canWriteToCloud(showLocalOnlyNotice: true) else { return }
            do {
                try await SupabaseService.shared.uploadCanvasImage(data: data, path: remotePath)
            } catch {
                print("Failed to upload canvas image asset: \(error)")
            }
        }
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
            let fileURL = self.localImageURL(for: fileName)
            
            do {
                try data.write(to: fileURL)
            } catch {
                print("Failed to save image locally: \(error)")
                return
            }

            ImageCache.shared.store(image, for: fileName)
            
            Task { @MainActor in
                self.insertResolvedImage(image, fileName: fileName, imageData: data, at: self.pendingImageInsertionPoint)
            }
        }
    }

    func insertImage(_ image: UIImage, at canvasPoint: CGPoint? = nil) {
        let fileName = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileURL = localImageURL(for: fileName)

        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to save image locally: \(error)")
            return
        }

        ImageCache.shared.store(image, for: fileName)
        insertResolvedImage(image, fileName: fileName, imageData: data, at: canvasPoint)
    }

    private func insertResolvedImage(_ image: UIImage, fileName: String, imageData: Data, at canvasPoint: CGPoint?) {
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
        let remoteAssetPath = remoteImageAssetPath(for: fileName)

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
            zIndex: currentPage.elements.count,
            style: ElementStyle(imageAssetPath: remoteAssetPath)
        )

        currentPage.elements.append(newElement)
        selectedElementIds = [newElement.id]
        objectWillChange.send()
        scheduleElementSave()
        uploadImageAssetIfNeeded(data: imageData, remotePath: remoteAssetPath)
        completePendingImageInsertion()
    }

    func updateElement(_ element: CanvasElement) {
        print("[VM] updateElement id=\(element.id) userResized=\(element.userResized) w=\(element.width ?? 0) h=\(element.height ?? 0)")
        if let index = pages[currentPageIndex].elements.firstIndex(where: { $0.id == element.id }) {
            pages[currentPageIndex].elements[index] = element
            objectWillChange.send()
            scheduleElementSave()
            captureHistoryNow(for: currentPage.id)
        }
    }
    
    func removeElement(id: UUID) {
        pages[currentPageIndex].elements.removeAll { $0.id == id }
        selectedElementIds.remove(id)
        objectWillChange.send()
        scheduleElementSave()
        captureHistoryNow(for: currentPage.id)
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
        await Task(priority: .utility) {
            do {
                try await LocalDatabase.shared.saveCanvasElements(elements, forPageId: pageId)
            } catch {
                print("Local element save error: \(error)")
            }
            guard Configuration.cloudSyncEnabled, await self.canWriteToCloud() else { return }
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

    private func normalizePaletteHex(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Consolidates legacy storage into a single ordered palette and removes duplicates.
    /// We still *seed* new tools with the default 5 colors, but users can delete down to 1.
    private func normalizeCustomizationIfNeeded(_ existing: ToolCustomization, for tool: DrawingTool) -> ToolCustomization {
        let defaults = ToolCustomization.defaults(for: tool)

        var seen = Set<String>()
        var palette: [String] = []

        func uniqueAppend(_ hex: String) {
            let h = normalizePaletteHex(hex)
            guard !h.isEmpty, !seen.contains(h) else { return }
            seen.insert(h)
            palette.append(h)
        }

        // Preserve order: presets first, then extras.
        for raw in existing.presetColorHexes { uniqueAppend(raw) }
        for raw in existing.extraColorHexes { uniqueAppend(raw) }

        if palette.isEmpty {
            palette = defaults.presetColorHexes.map(normalizePaletteHex)
        }

        // Ensure width presets remain valid.
        let widths = existing.widthPresets.isEmpty ? defaults.widthPresets : existing.widthPresets

        // Store everything in one place; we treat the palette as fully user-editable (min 1).
        return ToolCustomization(
            presetColorHexes: palette,
            extraColorHexes: [],
            widthPresets: widths
        )
    }

    @discardableResult
    func ensureToolCustomization(for tool: DrawingTool) -> ToolCustomization {
        if let existing = toolCustomizations[tool] {
            let normalized = normalizeCustomizationIfNeeded(existing, for: tool)
            if normalized.presetColorHexes != existing.presetColorHexes ||
                normalized.extraColorHexes != existing.extraColorHexes ||
                normalized.widthPresets != existing.widthPresets {
                toolCustomizations[tool] = normalized
                return normalized
            }
            return normalized
        }
        let created = ToolCustomization.defaults(for: tool)
        toolCustomizations[tool] = created
        return created
    }

    func presetColors(for tool: DrawingTool) -> [Color] {
        paletteColorHexes(for: tool).map { Color(hex: $0) }
    }

    func extraColors(for tool: DrawingTool) -> [Color] {
        []
    }

    func paletteColorHexes(for tool: DrawingTool) -> [String] {
        let c = ensureToolCustomization(for: tool)
        var seen = Set<String>()
        return (c.presetColorHexes + c.extraColorHexes).compactMap { raw in
            let hex = normalizePaletteHex(raw)
            guard !seen.contains(hex) else { return nil }
            seen.insert(hex)
            return hex
        }
    }

    func paletteColors(for tool: DrawingTool) -> [Color] {
        paletteColorHexes(for: tool).map { Color(hex: $0) }
    }

    func addExtraColor(_ color: Color, for tool: DrawingTool) {
        let hex = normalizePaletteHex(color.hexString)
        var palette = paletteColorHexes(for: tool)
        guard !palette.contains(hex) else { return }
        palette.append(hex)
        setPaletteColorHexes(palette, for: tool)
    }

    func movePaletteColor(for tool: DrawingTool, from sourceHex: String, to targetHex: String) {
        let fromHex = normalizePaletteHex(sourceHex)
        let toHex = normalizePaletteHex(targetHex)
        guard fromHex != toHex else { return }

        var palette = paletteColorHexes(for: tool)
        guard let from = palette.firstIndex(of: fromHex),
              let to = palette.firstIndex(of: toHex) else { return }

        let item = palette.remove(at: from)
        palette.insert(item, at: to)
        setPaletteColorHexes(palette, for: tool)
    }

    func removeSelectedCustomColor(for tool: DrawingTool, color: Color? = nil) {
        let hex = normalizePaletteHex((color ?? strokeColor).hexString)
        var palette = paletteColorHexes(for: tool)
        // Minimum palette size is 1.
        guard palette.count > 1 else { return }
        let before = palette.count
        palette.removeAll { $0 == hex }
        guard palette.count != before else { return }

        setPaletteColorHexes(palette, for: tool)

        if var memory = toolMemory[tool], memory.colorHex.uppercased() == hex {
            memory.colorHex = palette.first
                ?? Color.strokePresets.first?.hexString
                ?? "#FFFFFE"
            toolMemory[tool] = memory
        }

        if selectedTool == tool, strokeColor.hexString.uppercased() == hex {
            let fallback = paletteColors(for: tool).first
                ?? Color.strokePresets.first
                ?? Color(hex: "#FFFFFE")
            strokeColor = fallback
        }
    }

    func removeExtraColor(at index: Int, for tool: DrawingTool) {
        var palette = paletteColorHexes(for: tool)
        guard palette.count > 1 else { return }
        guard palette.indices.contains(index) else { return }
        let hex = palette[index]
        removeSelectedCustomColor(for: tool, color: Color(hex: hex))
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
        let hex = normalizePaletteHex(strokeColor.hexString)
        let palette = paletteColorHexes(for: tool)
        return palette.count > 1 && palette.contains(hex)
    }

    private func setPaletteColorHexes(_ hexes: [String], for tool: DrawingTool) {
        var c = ensureToolCustomization(for: tool)
        c.presetColorHexes = hexes.map(normalizePaletteHex)
        c.extraColorHexes = []
        toolCustomizations[tool] = c
    }

    func removeSelectedCustomColorFromColorTools(color: Color? = nil) {
        removeSelectedCustomColor(for: selectedTool, color: color)
    }

    private var colorCustomizableTools: [DrawingTool] {
        [.pen, .pencil, .marker]
    }

    func lassoRecolorPalette() -> [Color] {
        var orderedHexes: [String] = []
        var seen = Set<String>()

        for tool in colorCustomizableTools {
            for hex in paletteColorHexes(for: tool) {
                let normalized = hex.uppercased()
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                orderedHexes.append(normalized)
            }
        }

        return orderedHexes.map { Color(hex: $0) }
    }

    // MARK: - Drawing Changed Callback

    /// Called by PKCanvasRepresentable when the drawing changes.
    /// `fromPencil` indicates whether the change came from Apple Pencil (true) or finger (false).
    func drawingDidChange(_ drawing: PKDrawing, fromPencil: Bool = true) {
        guard !isApplyingHistorySnapshot else { return }
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
                let shouldSnap = recognition.confidence >= 0.9 || (heldToSnap && recognition.confidence >= 0.45)
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
              let strokes = liveDrawingCache[pageId]?.strokes,
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
                self.serializeDrawingSnapshot(
                    for: pageId,
                    drawing: snapped,
                    delayNanoseconds: 0,
                    captureHistory: true,
                    saveImmediately: false
                )
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
        guard pages.indices.contains(pageIndex) else { return }
        let page = pages[pageIndex]
        let pageId = page.id
        if let drawing = liveDrawingCache[pageId] {
            guard !drawing.strokes.isEmpty else {
                pageThumbnails[pageId] = nil
                return
            }
            Task.detached(priority: .utility) { [weak self] in
                let bounds = drawing.bounds.isEmpty
                    ? CGRect(origin: .zero, size: CGSize(width: 56, height: 74))
                    : drawing.bounds
                let renderScale = PencilKitBridge.boundedRenderScale(
                    for: bounds.size,
                    maxPixelDimension: 400
                )
                let image = drawing.image(from: bounds, scale: renderScale)
                await MainActor.run { [weak self] in
                    self?.pageThumbnails[pageId] = image
                }
            }
            return
        }

        guard let drawingData = pendingSerializedDrawingData[pageId] ?? page.drawingData else {
            pageThumbnails[pageId] = nil
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let drawing = PencilKitBridge.deserialize(drawingData),
                  !drawing.strokes.isEmpty else {
                await MainActor.run { [weak self] in
                    self?.pageThumbnails[pageId] = nil
                }
                return
            }
            let bounds = drawing.bounds.isEmpty
                ? CGRect(origin: .zero, size: CGSize(width: 56, height: 74))
                : drawing.bounds
            let renderScale = PencilKitBridge.boundedRenderScale(
                for: bounds.size,
                maxPixelDimension: 400
            )
            let image = drawing.image(from: bounds, scale: renderScale)
            await MainActor.run { [weak self] in
                    self?.cacheDrawing(drawing, for: pageId)
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
        let s = liveCanvasScale
        let ox = liveCanvasOffset.width
        let oy = liveCanvasOffset.height
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

        var newOffsetY = liveCanvasOffset.height

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

        autoSaveTasks.removeValue(forKey: resolvedPageId)?.cancel()
        autoSaveTasks[resolvedPageId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.performAutoSave(pageId: resolvedPageId, drawingData: resolvedData)
        }
    }
    
    /// Forces an immediate save of the current drawing data, cancelling any pending debounced save.
    func flushSave() async {
        for task in autoSaveTasks.values {
            task.cancel()
        }
        autoSaveTasks.removeAll()

        for task in drawingSerializationTasks.values {
            task.cancel()
        }
        drawingSerializationTasks.removeAll()

        for pageIndex in pages.indices {
            let pageId = pages[pageIndex].id
            if let cachedDrawing = liveDrawingCache[pageId] {
                let serialized = await Task.detached(priority: .utility) {
                    PencilKitBridge.serialize(cachedDrawing)
                }.value
                pendingSerializedDrawingData[pageId] = serialized
                pages[pageIndex].drawingData = serialized
                await performAutoSave(pageId: pageId, drawingData: serialized)
            } else if let drawingData = pendingSerializedDrawingData[pageId] ?? pages[pageIndex].drawingData {
                await performAutoSave(pageId: pageId, drawingData: drawingData)
            }
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
        autoSaveTasks[pageId] = nil
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
        photoAccessStatus = status
        switch status {
        case .authorized, .limited:
            hasPhotoAccess = true
            fetchRecentPhotos()
        case .notDetermined:
            Task {
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    self.photoAccessStatus = newStatus
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

}

// MARK: - Per-Tool Settings

struct ToolSettings: Codable {
    var colorHex: String
    var width: CGFloat
    var opacity: Double
}

struct ToolCustomization: Codable {
    /// Ordered palette colors (user-editable, minimum 1).
    var presetColorHexes: [String]
    /// Legacy bucket (kept for backwards compatibility; new builds consolidate into `presetColorHexes`).
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
