import SwiftUI
import PencilKit

// MARK: - CanvasHostView

/// Hosts the background pattern scroll view and PKCanvasView as siblings.
/// The background is completely outside PencilKit's layer tree, preventing
/// interference from the low-latency Apple Pencil hover/inking Metal pipeline.
///
/// Architecture:
/// ```
/// CanvasHostView (UIView)
/// ├── backgroundScrollView (UIScrollView)     ← index 0, behind
/// │   └── backgroundPatternView               ← CATiledLayer, frame set ONCE
/// └── canvasView (PKCanvasView)               ← index 1, on top, transparent
/// ```
final class CanvasHostView: UIView, UIScrollViewDelegate {

    // MARK: - Public

    let canvasView = PKCanvasView()
    let backgroundPatternView: BackgroundPatternView

    // MARK: - Private

    private let backgroundScrollView = UIScrollView()
    private let canvasContentSize = CGSize(width: 50_000, height: 50_000)

    // MARK: - Init

    override init(frame: CGRect) {
        backgroundPatternView = BackgroundPatternView(
            frame: CGRect(origin: .zero, size: CGSize(width: 50_000, height: 50_000))
        )
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupViews() {
        // --- Background scroll view ---
        backgroundScrollView.frame = bounds
        backgroundScrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundScrollView.contentSize = canvasContentSize
        backgroundScrollView.minimumZoomScale = 0.25
        backgroundScrollView.maximumZoomScale = 5.0
        backgroundScrollView.isScrollEnabled = false
        backgroundScrollView.isUserInteractionEnabled = false
        backgroundScrollView.showsVerticalScrollIndicator = false
        backgroundScrollView.showsHorizontalScrollIndicator = false
        backgroundScrollView.backgroundColor = .clear
        backgroundScrollView.isOpaque = false
        backgroundScrollView.delegate = self  // for viewForZooming(in:)
        backgroundScrollView.addSubview(backgroundPatternView)

        addSubview(backgroundScrollView)

        // --- PKCanvasView ---
        canvasView.frame = bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.contentSize = canvasContentSize
        canvasView.minimumZoomScale = 0.25
        canvasView.maximumZoomScale = 5.0
        canvasView.alwaysBounceVertical = true
        canvasView.alwaysBounceHorizontal = true
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false

        // Make PencilKit's internal content view transparent so background shows through
        if let contentView = canvasView.subviews.first {
            contentView.backgroundColor = .clear
            contentView.isOpaque = false
        }

        addSubview(canvasView)

        // Center initial viewport
        let initialOffset = CGPoint(
            x: (canvasContentSize.width  - bounds.width)  / 2,
            y: (canvasContentSize.height - bounds.height) / 2
        )
        canvasView.contentOffset = initialOffset
        backgroundScrollView.contentOffset = initialOffset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-center if this is the first real layout (bounds were zero during init)
        if backgroundScrollView.contentOffset == .zero && bounds.width > 0 {
            let initialOffset = CGPoint(
                x: (canvasContentSize.width  - bounds.width)  / 2,
                y: (canvasContentSize.height - bounds.height) / 2
            )
            canvasView.contentOffset = initialOffset
            backgroundScrollView.contentOffset = initialOffset
        }
    }

    // MARK: - UIScrollViewDelegate (for backgroundScrollView only)

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // Return the background pattern view so zoomScale assignment works
        return backgroundPatternView
    }

    // MARK: - Sync

    /// Mirrors PKCanvasView's scroll position and zoom to the background scroll view.
    /// Two property assignments — no frame changes, no tile invalidation.
    func syncBackground() {
        backgroundScrollView.contentOffset = canvasView.contentOffset
        backgroundScrollView.zoomScale = canvasView.zoomScale
    }
}

// MARK: - PKCanvasRepresentable

/// PencilKit-backed canvas view wrapped for SwiftUI.
/// Uses CanvasHostView to layer a CATiledLayer background behind the transparent
/// PKCanvasView, completely outside PencilKit's internal view hierarchy.
struct PKCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    /// Whether finger drawing is allowed (false = Apple Pencil only)
    var allowsFingerDrawing: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> CanvasHostView {
        let hostView = CanvasHostView()
        let canvasView = hostView.canvasView

        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Configure background pattern
        hostView.backgroundPatternView.pattern = viewModel.backgroundPattern

        context.coordinator.hostView = hostView
        context.coordinator.canvasView = canvasView

        // Load existing drawing data from the current page
        context.coordinator.currentPageId = viewModel.currentPage.id
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

        // Install touch-type recognizer to distinguish pencil from finger
        let touchRecognizer = TouchTypeRecognizer()
        touchRecognizer.coordinator = context.coordinator
        touchRecognizer.cancelsTouchesInView = false
        touchRecognizer.delaysTouchesEnded = false
        touchRecognizer.delaysTouchesBegan = false
        canvasView.addGestureRecognizer(touchRecognizer)

        // Install shape snap gesture recognizer
        let shapeSnapRecognizer = ShapeSnapGestureRecognizer(target: nil, action: nil)
        shapeSnapRecognizer.canvasView = canvasView
        shapeSnapRecognizer.onShapeRecognized = { shape, stroke in
            return context.coordinator.handleShapeRecognized(shape: shape, stroke: stroke)
        }
        shapeSnapRecognizer.onShapeUpdated = { shape in
            context.coordinator.handleShapeUpdated(shape: shape)
        }
        shapeSnapRecognizer.onShapeCommitted = {
            context.coordinator.handleShapeCommitted()
        }
        canvasView.addGestureRecognizer(shapeSnapRecognizer)

        // Forward UndoManager to viewModel
        Task { @MainActor in
            viewModel.pkUndoManager = canvasView.undoManager
            viewModel.refreshUndoState()
        }

        return hostView
    }

    func updateUIView(_ hostView: CanvasHostView, context: Context) {
        let canvasView = hostView.canvasView

        // Only rebuild PKTool when tool-related properties actually changed
        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        // Update drawing policy only when changed
        let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        if canvasView.drawingPolicy != newPolicy {
            canvasView.drawingPolicy = newPolicy
        }

        // Sync background pattern when it changes
        if hostView.backgroundPatternView.pattern != viewModel.backgroundPattern {
            hostView.backgroundPatternView.pattern = viewModel.backgroundPattern
        }

        // Sync drawing data when page changes (detect by comparing index or ID)
        if context.coordinator.currentPageIndex != viewModel.currentPageIndex || context.coordinator.currentPageId != viewModel.currentPage.id || viewModel.forceDrawingUpdate {
            context.coordinator.currentPageIndex = viewModel.currentPageIndex
            context.coordinator.currentPageId = viewModel.currentPage.id
            let pageDrawing = viewModel.currentPage.pkDrawing
            context.coordinator.setDrawing(pageDrawing, on: canvasView)
            
            if viewModel.forceDrawingUpdate {
                DispatchQueue.main.async {
                    viewModel.forceDrawingUpdate = false
                }
            }
            
            Task { @MainActor in
                viewModel.pkUndoManager = canvasView.undoManager
                viewModel.refreshUndoState()
            }
        }
    }

    /// Compare PKTools to avoid redundant assignments that reset internal PencilKit state.
    private func toolsEqual(_ a: PKTool, _ b: PKTool) -> Bool {
        if let aInk = a as? PKInkingTool, let bInk = b as? PKInkingTool {
            return aInk.inkType == bInk.inkType &&
                   aInk.color == bInk.color &&
                   aInk.width == bInk.width
        }
        if a is PKEraserTool && b is PKEraserTool { return true }
        if a is PKLassoTool && b is PKLassoTool { return true }
        return false
    }

    // MARK: - Helpers

    private func currentPKTool() -> PKTool {
        let uiColor = UIColor(viewModel.strokeColor)
        return PencilKitBridge.pkTool(
            for: viewModel.selectedTool,
            color: uiColor.withAlphaComponent(viewModel.strokeOpacity),
            width: viewModel.strokeWidth,
            penStyle: viewModel.penStyle,
            eraserType: viewModel.eraserType
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var viewModel: CanvasViewModel
        weak var canvasView: PKCanvasView?
        weak var hostView: CanvasHostView?
        var currentPageIndex: Int = 0
        var currentPageId: UUID?

        /// Tracks whether we are currently performing a programmatic drawing update
        private var isUpdatingDrawing = false

        /// Tracks whether the current/most-recent stroke came from Apple Pencil
        private var lastStrokeFromPencil = true
        
        /// Shape snapping state
        private var liveShapeOverlay: CAShapeLayer?
        private var liveShapeType: ShapeSnapper.ShapeType?
        private var liveShapeOriginalStroke: PKStroke?

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            self.currentPageIndex = viewModel.currentPageIndex
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if canvasView.drawingPolicy == .pencilOnly {
                lastStrokeFromPencil = true
            }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // For anyInput, input type is determined by the TouchTypeRecognizer.
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingDrawing else { return }

            let fromPencil = lastStrokeFromPencil
            
            // If the gesture recognizer is actively showing an overlay, don't save the live stroke.
            if liveShapeOverlay != nil {
                // We swapped the tool to force PencilKit to commit the messy stroke.
                // We need to silently remove that messy stroke so it doesn't stay behind our overlay.
                isUpdatingDrawing = true
                var strokes = canvasView.drawing.strokes
                if !strokes.isEmpty {
                    strokes.removeLast()
                    canvasView.drawing = PKDrawing(strokes: strokes)
                }
                isUpdatingDrawing = false
                return
            }

            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, fromPencil: fromPencil)
            }
        }
        
        // MARK: - Shape Snapping Callbacks
        
        func handleShapeRecognized(shape: ShapeSnapper.ShapeType, stroke: PKStroke) -> Bool {
            guard viewModel.isShapeSnappingEnabled, let canvas = canvasView else { return false }
            liveShapeType = shape
            liveShapeOriginalStroke = stroke
            
            // Create and show overlay layer
            let overlay = CAShapeLayer()
            overlay.fillColor = UIColor.clear.cgColor
            overlay.strokeColor = stroke.ink.color.cgColor
            let width = stroke.path.first?.size.width ?? 4.0
            overlay.lineWidth = width * canvas.zoomScale
            overlay.lineCap = .round
            overlay.lineJoin = .round
            
            canvas.layer.addSublayer(overlay)
            liveShapeOverlay = overlay
            
            updateOverlayPath()
            HapticEngine.rigid()
            return true
        }
        
        func handleShapeUpdated(shape: ShapeSnapper.ShapeType) {
            guard viewModel.isShapeSnappingEnabled else { return }
            liveShapeType = shape
            updateOverlayPath()
        }
        
        func handleShapeCommitted() {
            guard viewModel.isShapeSnappingEnabled,
                  let canvas = canvasView,
                  let shape = liveShapeType,
                  let originalStroke = liveShapeOriginalStroke else {
                removeOverlay()
                return
            }
            
            let snappedShape = ShapeSnapper.snapToGrid(shape: shape, gridSize: 28.0)
            let newStroke = ShapeSnapper.createStroke(from: snappedShape, originalStroke: originalStroke)
            
            // Insert into canvas view
            isUpdatingDrawing = true
            var strokes = canvas.drawing.strokes
            strokes.append(newStroke)
            canvas.drawing = PKDrawing(strokes: strokes)
            isUpdatingDrawing = false
            
            // Force save
            Task { @MainActor in
                viewModel.drawingDidChange(canvas.drawing, fromPencil: lastStrokeFromPencil)
            }
            
            removeOverlay()
        }
        
        private func removeOverlay() {
            liveShapeOverlay?.removeFromSuperlayer()
            liveShapeOverlay = nil
            liveShapeType = nil
            liveShapeOriginalStroke = nil
        }
        
        private func updateOverlayPath() {
            guard let overlay = liveShapeOverlay, let shape = liveShapeType, let canvas = canvasView else { return }
            
            // Convert canvas coordinates to view coordinates considering scroll and zoom
            let scale = canvas.zoomScale
            let offset = canvas.contentOffset
            
            let transformPoint = { (pt: CGPoint) -> CGPoint in
                CGPoint(x: pt.x * scale - offset.x, y: pt.y * scale - offset.y)
            }
            
            let path = UIBezierPath()
            switch shape {
            case .line(let start, let end):
                path.move(to: transformPoint(start))
                path.addLine(to: transformPoint(end))
            case .rect(let corners):
                if corners.count == 4 {
                    path.move(to: transformPoint(corners[0]))
                    path.addLine(to: transformPoint(corners[1]))
                    path.addLine(to: transformPoint(corners[2]))
                    path.addLine(to: transformPoint(corners[3]))
                    path.close()
                }
            case .circle(let center, let radius):
                let tc = transformPoint(center)
                let tr = radius * scale
                path.addArc(withCenter: tc, radius: tr, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.path = path.cgPath
            if let originalStroke = liveShapeOriginalStroke {
                let width = originalStroke.path.first?.size.width ?? 4.0
                overlay.lineWidth = width * scale
            }
            CATransaction.commit()
        }

        // MARK: UIScrollViewDelegate (via PKCanvasViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
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
                let newTool: DrawingTool = self.viewModel.selectedTool == .eraser ? .pen : .eraser
                self.viewModel.selectTool(newTool)
                HapticEngine.light()
            }
        }

        // MARK: - Page Switching Support

        func setDrawing(_ drawing: PKDrawing, on canvasView: PKCanvasView? = nil) {
            isUpdatingDrawing = true
            let target = canvasView ?? self.canvasView
            target?.drawing = drawing
            isUpdatingDrawing = false
        }
    }

    // MARK: - Touch Type Gesture Recognizer

    final class TouchTypeRecognizer: UIGestureRecognizer {
        weak var coordinator: Coordinator?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            if touch.type == .pencil {
                coordinator?.pencilTouchDetected()
            } else {
                coordinator?.fingerTouchDetected()
            }
            state = .failed
        }
    }
}
