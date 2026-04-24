import Foundation
import Combine
import SwiftUI
import PencilKit
import Realtime
import Photos

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
    @Published var canvasViewSize: CGSize = UIScreen.main.bounds.size
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
                        order: tuple.page.pageIndex,
                        elements: tuple.page.settings?.elements ?? []
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

    // MARK: - Lasso Selection State
    
    /// IDs of CanvasElements currently inside the lasso selection
    @Published var selectedElementIds: Set<UUID> = []
    
    /// The PKDrawing strokes selected by PencilKit's native lasso (read from canvasView.drawing after lasso)
    /// These are identified by index into pkDrawing.strokes
    @Published var selectedStrokeIndices: Set<Int> = []
    
    /// The frozen combined bounding box of ALL selected content (strokes + elements) in canvas space.
    /// Computed once when selection is committed. Used as the resize origin.
    @Published var selectionBoundingBox: CGRect? = nil
    
    /// Current scale factor applied to the selection during an active resize gesture.
    /// Drive UI live from this value.
    @Published var selectionScale: CGFloat = 1.0
    
    /// Whether a resize is actively in progress (drives handle visibility)
    @Published var isResizing: Bool = false
    
    /// The rect drawn by the user for lasso selection (in canvas space)
    @Published var pendingLassoRect: CGRect? = nil
    
    private var elementSaveTask: Task<Void, Never>?
    
    func addElement(_ element: CanvasElement) {
        pages[currentPageIndex].elements.append(element)
        // Explicitly trigger an update since it's a nested array
        objectWillChange.send()
        scheduleElementSave()
    }
    
    func insertImage(_ asset: PHAsset) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { [weak self] image, info in
            guard let self = self, let image = image else { return }
            
            // Generate a unique filename and save to local Documents directory
            let fileName = UUID().uuidString + ".jpg"
            guard let data = image.jpegData(compressionQuality: 0.8) else { return }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
            } catch {
                print("Failed to save image locally: \(error)")
                return
            }

            ImageCache.shared.store(image, for: fileName)
            
            Task { @MainActor in
                // Calculate center of the visible canvas based on offset and scale
                let viewSize = self.canvasViewSize
                let center = CGPoint(
                    x: (viewSize.width / 2 + self.canvasOffset.width) / self.canvasScale,
                    y: (viewSize.height / 2 + self.canvasOffset.height) / self.canvasScale
                )
                
                // Initial block size
                let blockWidth: Double = min(300, Double(viewSize.width) * 0.6 / self.canvasScale)
                let aspectRatio = image.size.width > 0
                    ? Double(image.size.height / image.size.width) : 1.0
                let blockHeight: Double = blockWidth * aspectRatio
                
                let newElement = CanvasElement(
                    pageId: self.currentPage.id,
                    userId: self.userId ?? UUID(),
                    type: "image",
                    content: fileName, // Store the local file name instead of base64
                    positionX: Double(center.x),
                    positionY: Double(center.y),
                    width: blockWidth,
                    height: blockHeight,
                    rotation: 0,
                    zIndex: self.currentPage.elements.count
                )
                
                self.currentPage.elements.append(newElement)
                self.selectedElementIds = [newElement.id]
                self.objectWillChange.send()
                self.scheduleElementSave()
                self.selectTool(.pen)
            }
        }
    }

    func updateElement(_ element: CanvasElement) {
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
    
    func computeSelectionBoundingBox() {
        var rects: [CGRect] = []

        // Bounding boxes from selected CanvasElements
        for el in currentPage.elements where selectedElementIds.contains(el.id) {
            let w = el.width ?? 200
            let h = el.height ?? 200
            rects.append(CGRect(
                x: el.positionX - w / 2,
                y: el.positionY - h / 2,
                width: w,
                height: h
            ))
        }

        // Bounding boxes from selected PencilKit strokes
        let drawing = currentPage.pkDrawing
        for (i, stroke) in drawing.strokes.enumerated() where selectedStrokeIndices.contains(i) {
            rects.append(stroke.renderBounds)
        }

        guard !rects.isEmpty else {
            selectionBoundingBox = nil
            return
        }

        // Union all rects into one combined bounding box
        let combined = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        selectionBoundingBox = combined
        selectionScale = 1.0
    }

    func applySelectionResize(scale: CGFloat) {
        guard let bbox = selectionBoundingBox, scale > 0 else { return }
        let origin = bbox.origin  // top-left of combined bounding box — the fixed resize anchor

        // 1. Resize CanvasElements
        for i in pages[currentPageIndex].elements.indices {
            let el = pages[currentPageIndex].elements[i]
            guard selectedElementIds.contains(el.id) else { continue }

            // Translate position relative to bbox origin, scale, translate back
            let newX = origin.x + (el.positionX - origin.x) * scale
            let newY = origin.y + (el.positionY - origin.y) * scale
            let newW = (el.width  ?? 200) * scale
            let newH = (el.height ?? 200) * scale

            pages[currentPageIndex].elements[i].positionX = newX
            pages[currentPageIndex].elements[i].positionY = newY
            pages[currentPageIndex].elements[i].width  = max(40, newW)
            pages[currentPageIndex].elements[i].height = max(40, newH)
            pages[currentPageIndex].elements[i].updatedAt = Date()
        }

        // 2. Resize PencilKit strokes
        let drawing = currentPage.pkDrawing
        var newStrokes = drawing.strokes

        for i in selectedStrokeIndices.sorted() where i < newStrokes.count {
            let stroke = newStrokes[i]

            // Build a CGAffineTransform: translate to origin, scale, translate back
            let transform = CGAffineTransform(translationX: -origin.x, y: -origin.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: origin.x / scale, y: origin.y / scale)

            // Reconstruct the PKStroke path using transformed points
            var newPoints: [PKStrokePoint] = []
            for point in stroke.path {
                let newLocation = point.location.applying(transform)
                let newPoint = PKStrokePoint(
                    location: newLocation,
                    timeOffset: point.timeOffset,
                    size: CGSize(width: point.size.width * scale, height: point.size.height * scale),
                    opacity: point.opacity,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude
                )
                newPoints.append(newPoint)
            }
            let newPath = PKStrokePath(controlPoints: newPoints, creationDate: stroke.path.creationDate)
            newStrokes[i] = PKStroke(ink: stroke.ink, path: newPath)
        }

        let newDrawing = PKDrawing(strokes: newStrokes)
        pages[currentPageIndex].drawingData = PencilKitBridge.serialize(newDrawing)

        // 3. Update frozen bounding box to the new scaled size (for subsequent resizes)
        selectionBoundingBox = CGRect(
            x: origin.x,
            y: origin.y,
            width: bbox.width  * scale,
            height: bbox.height * scale
        )
        selectionScale = 1.0  // reset — next gesture starts from 1.0 again

        // 4. Notify PencilKit to redraw and save
        forceDrawingUpdate = true
        objectWillChange.send()
        scheduleElementSave()
        scheduleAutoSave()
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
        selectedElementIds = []
        selectedTool = tool

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
        if selectedTool != .eraser && selectedTool != .lasso && selectedTool != .selection {
            toolMemory[selectedTool] = ToolSettings(colorHex: strokeColor.hexString, width: strokeWidth, opacity: strokeOpacity)
        }
    }

    // MARK: - Drawing Changed Callback

    /// Called by PKCanvasRepresentable when the drawing changes.
    /// `fromPencil` indicates whether the change came from Apple Pencil (true) or finger (false).
    func drawingDidChange(_ drawing: PKDrawing, fromPencil: Bool = true) {
        var modifiedDrawing = drawing
        
        // Shape snapping logic (post-processing method)
        if isShapeSnappingEnabled, let lastStroke = modifiedDrawing.strokes.last {
            let currentStrokes = pages[currentPageIndex].pkDrawing.strokes
            // Only process if a new stroke was just added
            if modifiedDrawing.strokes.count > currentStrokes.count {
                let pts = lastStroke.path.compactMap { $0.location }
                if let shape = ShapeSnapper.recognizeShape(from: pts) {
                    let snappedShape = ShapeSnapper.straightenShape(shape)
                    let newStroke = ShapeSnapper.createStroke(from: snappedShape, originalStroke: lastStroke)
                    
                    var newStrokes = modifiedDrawing.strokes
                    newStrokes[newStrokes.count - 1] = newStroke
                    modifiedDrawing = PKDrawing(strokes: newStrokes)
                    
                    // Trigger a view update so the canvas redrawns with the snapped stroke
                    self.forceDrawingUpdate = true
                }
            }
        }

        let data = PencilKitBridge.serialize(modifiedDrawing)
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
