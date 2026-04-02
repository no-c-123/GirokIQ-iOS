import Foundation
import Combine
import SwiftUI
import PencilKit

// MARK: - Canvas ViewModel

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published var pages: [DrawingPage] = [DrawingPage(title: "Page 1")]
    @Published var currentPageIndex: Int = 0
    @Published var selectedTool: DrawingTool = .pen
    @Published var strokeColor: Color = .white
    @Published var strokeWidth: CGFloat = 2.0
    @Published var strokeOpacity: Double = 1.0
    @Published var strokeStyle: StrokeStyle = .solid
    @Published var backgroundPattern: BackgroundPattern = .grid
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var showProperties: Bool = true
    @Published var isLassoActive: Bool = false
    @Published var selectedStrokes: Set<UUID> = []
    @Published var isSaving: Bool = false
    @Published var palmRejectionEnabled: Bool = true
    @Published var isToolbarVisible: Bool = true

    // Per-tool memory: remember last-used color + width per tool
    @Published var toolMemory: [DrawingTool: ToolSettings] = [:]

    // UndoManager forwarded from PKCanvasView
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    /// Reference to the PKCanvasView's undoManager, set by PKCanvasRepresentable
    weak var pkUndoManager: UndoManager?

    private let service = SupabaseService.shared
    private var autoSaveTask: Task<Void, Never>?
    private var toolbarHideTask: Task<Void, Never>?

    var currentPage: DrawingPage {
        get { pages[currentPageIndex] }
        set { pages[currentPageIndex] = newValue }
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

    func clearPage() {
        pages[currentPageIndex].drawingData = nil
        pages[currentPageIndex].strokes.removeAll()
    }

    func addPage() {
        let newPage = DrawingPage(title: "Page \(pages.count + 1)", backgroundPattern: backgroundPattern)
        pages.append(newPage)
        currentPageIndex = pages.count - 1
    }

    // MARK: - Tool Selection (with per-tool memory)

    func selectTool(_ tool: DrawingTool) {
        // Save current tool settings before switching
        if selectedTool != .eraser && selectedTool != .lasso && selectedTool != .selection {
            toolMemory[selectedTool] = ToolSettings(color: strokeColor, width: strokeWidth, opacity: strokeOpacity)
        }

        if tool == .lasso {
            isLassoActive = true
        } else {
            isLassoActive = false
            selectedStrokes.removeAll()
        }
        selectedTool = tool

        // Restore saved settings or use tool defaults
        if let saved = toolMemory[tool] {
            strokeColor = saved.color
            strokeWidth = saved.width
            strokeOpacity = saved.opacity
        } else {
            strokeWidth = tool.defaultWidth
            strokeOpacity = tool.defaultOpacity
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

        // Only auto-hide toolbar when drawing with Apple Pencil.
        // Finger interactions should keep the toolbar visible.
        if fromPencil {
            startToolbarHideTimer()
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

    private func performAutoSave() async {
        guard let drawingData = pages[currentPageIndex].drawingData else { return }
        isSaving = true
        // Save to local database (GRDB) — sync engine will push to Supabase
        do {
            try await LocalDatabase.shared.saveDrawingData(drawingData, forPageId: pages[currentPageIndex].id)
        } catch {
            print("Auto-save error: \(error)")
        }
        isSaving = false
    }

    // MARK: - Sync

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
        do {
            try await service.upsertStrokes(remoteStrokes)
        } catch {
            print("Sync error: \(error)")
        }
        isSaving = false
    }
}

// MARK: - Per-Tool Settings

struct ToolSettings {
    var color: Color
    var width: CGFloat
    var opacity: Double
}
