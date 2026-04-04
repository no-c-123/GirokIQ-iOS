import Foundation
import Combine
import SwiftUI
import PencilKit
import Realtime

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
    @Published var showProperties: Bool = true
    @Published var isLassoActive: Bool = false
    @Published var selectedStrokes: Set<UUID> = []
    @Published var isSaving: Bool = false
    @Published var palmRejectionEnabled: Bool = true
    @Published var isToolbarVisible: Bool = true
    @Published var isShapeSnappingEnabled: Bool = false
    @Published var forceDrawingUpdate: Bool = false
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

    var notebookId: UUID?
    var userId: UUID?

    // Web presence: tracks whether this notebook is also open on the web app
    @Published var webPresence: [PresenceEntry] = []
    var isOpenOnWeb: Bool { !webPresence.isEmpty }
    private var presenceChannel: RealtimeChannelV2?

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

    var currentPage: DrawingPage {
        get { pages[currentPageIndex] }
        set { pages[currentPageIndex] = newValue }
    }

    // MARK: - Loading

    func loadNotebook(notebookId: UUID, userId: UUID) async {
        self.notebookId = notebookId
        self.userId = userId
        
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
            } else {
                // Load existing pages
                self.pages = fetchedPages.map { tuple in
                    let bgPattern = BackgroundPattern(rawValue: tuple.page.settings?.backgroundPattern ?? "grid") ?? .grid
                    return DrawingPage(
                        id: tuple.page.id,
                        title: tuple.page.title,
                        drawingData: tuple.drawingData,
                        backgroundPattern: bgPattern,
                        order: tuple.page.pageIndex
                    )
                }
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

    // MARK: - Undo / Redo (forwarded to PKCanvasView)

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
    
    // We send standard UIResponder actions which PKCanvasView will catch if it has a lasso selection
    func performLassoAction(_ action: Selector) {
        UIApplication.shared.sendAction(action, to: nil, from: nil, for: nil)
    }

    func clearPage() {
        pages[currentPageIndex].drawingData = nil
        pages[currentPageIndex].strokes.removeAll()
    }

    func addPage() {
        guard let notebookId = self.notebookId, let userId = self.userId else { return }
        
        let newPageId = UUID()
        let newOrder = pages.count
        let newPage = DrawingPage(id: newPageId, title: "Page \(newOrder + 1)", backgroundPattern: backgroundPattern, order: newOrder)
        pages.append(newPage)
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

    // MARK: - Tool Selection (with per-tool memory)

    func selectTool(_ tool: DrawingTool) {
        isChangingTool = true
        defer { isChangingTool = false }

        // Save current tool settings before switching
        updateCurrentToolMemory()

        if tool == .lasso {
            isLassoActive = true
        } else {
            isLassoActive = false
            selectedStrokes.removeAll()
        }
        selectedTool = tool

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
        if selectedTool != .eraser && selectedTool != .lasso && selectedTool != .selection {
            toolMemory[selectedTool] = ToolSettings(colorHex: strokeColor.hexString, width: strokeWidth, opacity: strokeOpacity)
        }
    }

    // MARK: - Drawing Changed Callback

    /// Called by PKCanvasRepresentable when the drawing changes.
    /// `fromPencil` indicates whether the change came from Apple Pencil (true) or finger (false).
    func drawingDidChange(_ drawing: PKDrawing, fromPencil: Bool = true) {
        let data = PencilKitBridge.serialize(drawing)
        pages[currentPageIndex].drawingData = data
        refreshUndoState()
        scheduleAutoSave()

        // Regenerate cached thumbnail for the page strip (async, non-blocking)
        regenerateThumbnail(for: currentPageIndex)

        // Only auto-hide toolbar when drawing with Apple Pencil.
        // Finger interactions should keep the toolbar visible.
        if fromPencil {
            startToolbarHideTimer()
        }
    }

    // MARK: - Thumbnail Cache

    /// Regenerate the thumbnail for the current page on a background thread.
    /// Called after drawing changes are committed (debounced via auto-save).
    func regenerateThumbnail(for pageIndex: Int) {
        let page = pages[pageIndex]
        let pageId = page.id
        guard let data = page.drawingData,
              let drawing = PencilKitBridge.deserialize(data) else {
            pageThumbnails[pageId] = nil
            return
        }
        // Generate thumbnail off the main thread to avoid blocking scroll/animation
        Task.detached(priority: .utility) { [weak self] in
            let bounds = drawing.bounds.isEmpty
                ? CGRect(origin: .zero, size: CGSize(width: 56, height: 74))
                : drawing.bounds
            let image = drawing.image(from: bounds, scale: 1.0)
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

    /// Shows toolbar temporarily then hides again (for programmatic reveals).
    func showToolbarTemporarily() {
        animateMotionSafe(GAnimation.springFast) { [self] in isToolbarVisible = true }
        startToolbarHideTimer()
    }

    // MARK: - Auto-Save (1.5s debounce)

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.performAutoSave()
        }
    }
    
    /// Forces an immediate save of the current drawing data, cancelling any pending debounced save.
    func flushSave() async {
        autoSaveTask?.cancel()
        await performAutoSave()
    }

    private func performAutoSave() async {
        guard let drawingData = pages[currentPageIndex].drawingData else { return }
        let pageId = pages[currentPageIndex].id
        isSaving = true
        // Save to local database on a background thread — never blocks the UI
        await Task.detached(priority: .utility) {
            do {
                try await LocalDatabase.shared.saveDrawingData(drawingData, forPageId: pageId)
            } catch {
                print("Auto-save error: \(error)")
            }
        }.value
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
        URL(string: "https://app.girokiq.com/notebook/\(notebookId.uuidString)")
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
