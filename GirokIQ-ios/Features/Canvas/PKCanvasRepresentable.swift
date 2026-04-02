import SwiftUI
import PencilKit

/// PencilKit-backed canvas view wrapped for SwiftUI.
/// Uses Apple's native inking engine for high-fidelity Apple Pencil support
/// including pressure, tilt, and low-latency rendering.
struct PKCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    /// Whether finger drawing is allowed (false = Apple Pencil only)
    var allowsFingerDrawing: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.minimumZoomScale = 0.25
        canvasView.maximumZoomScale = 5.0
        canvasView.alwaysBounceVertical = true
        canvasView.alwaysBounceHorizontal = true

        // Set large content size for infinite-canvas feel
        canvasView.contentSize = CGSize(width: 4096, height: 4096)

        // Load existing drawing data from the current page
        if let data = viewModel.currentPage.drawingData,
           let drawing = PencilKitBridge.deserialize(data) {
            context.coordinator.setDrawing(drawing, on: canvasView)
        }

        // Set initial tool
        canvasView.tool = currentPKTool()

        // Apple Pencil double-tap interaction
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)

        context.coordinator.canvasView = canvasView

        // Install touch-type recognizer to distinguish pencil from finger
        let touchRecognizer = TouchTypeRecognizer()
        touchRecognizer.coordinator = context.coordinator
        touchRecognizer.cancelsTouchesInView = false
        touchRecognizer.delaysTouchesEnded = false
        touchRecognizer.delaysTouchesBegan = false
        canvasView.addGestureRecognizer(touchRecognizer)

        // Forward UndoManager to viewModel
        Task { @MainActor in
            viewModel.pkUndoManager = canvasView.undoManager
            viewModel.refreshUndoState()
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        // Update tool — always sync color/width even if same tool type
        canvasView.tool = currentPKTool()

        // Update drawing policy
        canvasView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Sync drawing data when page changes (detect by comparing data)
        if context.coordinator.currentPageIndex != viewModel.currentPageIndex {
            context.coordinator.currentPageIndex = viewModel.currentPageIndex
            let pageDrawing = viewModel.currentPage.pkDrawing
            context.coordinator.setDrawing(pageDrawing, on: canvasView)
            Task { @MainActor in
                viewModel.pkUndoManager = canvasView.undoManager
                viewModel.refreshUndoState()
            }
        }
    }

    // MARK: - Helpers

    private func currentPKTool() -> PKTool {
        let uiColor = UIColor(viewModel.strokeColor)
        return PencilKitBridge.pkTool(
            for: viewModel.selectedTool,
            color: uiColor.withAlphaComponent(viewModel.strokeOpacity),
            width: viewModel.strokeWidth
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var viewModel: CanvasViewModel
        weak var canvasView: PKCanvasView?
        var currentPageIndex: Int = 0

        /// Tracks whether we are currently performing a programmatic drawing update
        private var isUpdatingDrawing = false

        /// Tracks whether the current/most-recent stroke came from Apple Pencil
        private var lastStrokeFromPencil = true

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            self.currentPageIndex = viewModel.currentPageIndex
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Detect the active input: Apple Pencil strokes use .pencil type touches.
            // If the canvas policy is pencilOnly, all strokes are from pencil.
            if canvasView.drawingPolicy == .pencilOnly {
                lastStrokeFromPencil = true
            }
            // Otherwise we check in canvasViewDidEndUsingTool via the drawing's stroke data
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // After each tool use, check the last stroke's ink type to heuristically
            // determine the input source. PKStroke doesn't expose touch type directly,
            // but if drawingPolicy is .pencilOnly we already know.
            // For anyInput, we use a gesture recognizer fallback (see makeUIView).
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingDrawing else { return }

            let fromPencil = lastStrokeFromPencil
            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, fromPencil: fromPencil)
            }
        }

        /// Called by the finger-touch gesture recognizer installed on the canvas
        func fingerTouchDetected() {
            lastStrokeFromPencil = false
            Task { @MainActor in
                self.viewModel.showToolbar()
            }
        }

        /// Called by the pencil-touch gesture recognizer installed on the canvas
        func pencilTouchDetected() {
            lastStrokeFromPencil = true
        }

        // MARK: UIPencilInteractionDelegate

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            Task { @MainActor in
                // Toggle between pen and eraser on Apple Pencil double-tap
                let newTool: DrawingTool = self.viewModel.selectedTool == .eraser ? .pen : .eraser
                self.viewModel.selectTool(newTool)
                HapticEngine.light()
            }
        }

        // MARK: - Page Switching Support

        /// Call this before programmatically changing the drawing to prevent feedback loop
        func setDrawing(_ drawing: PKDrawing, on canvasView: PKCanvasView? = nil) {
            isUpdatingDrawing = true
            let target = canvasView ?? self.canvasView
            target?.drawing = drawing
            isUpdatingDrawing = false
        }
    }

    // MARK: - Touch Type Gesture Recognizer

    /// A gesture recognizer that distinguishes Apple Pencil from finger touches
    /// and notifies the coordinator, without interfering with PencilKit's drawing.
    final class TouchTypeRecognizer: UIGestureRecognizer {
        weak var coordinator: Coordinator?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            if touch.type == .pencil {
                coordinator?.pencilTouchDetected()
            } else {
                coordinator?.fingerTouchDetected()
            }
            // Always fail so we don't consume the touch — PencilKit handles drawing.
            state = .failed
        }
    }
}
