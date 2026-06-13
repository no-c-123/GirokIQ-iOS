import SwiftUI
import PencilKit

struct FixedCanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let pageSize: CGSize

    var body: some View {
        FixedCanvasRepresentable(viewModel: viewModel, pageSize: pageSize)
            .ignoresSafeArea()
    }
}

// MARK: - FixedCanvasRepresentable

struct FixedCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel
    let pageSize: CGSize
    
    var allowsFingerDrawing: Bool {
        !viewModel.palmRejectionEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> FixedCanvasHostView {
        let hostView = FixedCanvasHostView(pageSize: pageSize, viewModel: viewModel)
        let canvasView = hostView.canvasView

        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Configure background pattern
        hostView.backgroundPatternView.pattern = viewModel.backgroundPattern
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = hex.uppercased() == "#0F0F0E" ? .gBackground : UIColor(hex: hex)
            hostView.backgroundPatternView.pageBackgroundColor = color
        }

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

        // Install Menu Blocker to stop "Select All / Insert Space" on empty canvas
        let menuBlocker = MenuBlockerGestureRecognizer(canvas: canvasView)
        canvasView.addGestureRecognizer(menuBlocker)

        // Forward UndoManager to viewModel
        Task { @MainActor in
            viewModel.pkUndoManager = canvasView.undoManager
            viewModel.refreshUndoState()
        }

        // Used by #5: allow the view model to scroll the viewport when the keyboard covers text.
        Task { @MainActor in
            viewModel.setViewportScrollView(hostView.scrollView)
        }

        return hostView
    }

    func updateUIView(_ hostView: FixedCanvasHostView, context: Context) {
        let canvasView = hostView.canvasView
        viewModel.setCanvasViewSizeIfNeeded(hostView.bounds.size)

        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .image || viewModel.selectedTool == .text
        let isLassoTool = viewModel.selectedTool == .lasso
        if isBlockTool {
            // Never disable isUserInteractionEnabled for PKCanvasView during drawing.
            // Use drawingGestureRecognizer.isEnabled to toggle PencilKit input.
            canvasView.drawingGestureRecognizer.isEnabled = false
            // Force pencil-only so finger taps don't trigger PencilKit's edit menu.
            if canvasView.drawingPolicy != .pencilOnly {
                canvasView.drawingPolicy = .pencilOnly
            }
            // Allow one-finger drag for moving/resizing blocks; pan the page with two fingers.
            hostView.scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        } else if isLassoTool {
            // Lasso is Apple Pencil only (handled by CustomLassoGestureView). Disable drawing so Pencil doesn't ink.
            canvasView.drawingGestureRecognizer.isEnabled = false
            hostView.scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        } else {
            canvasView.drawingGestureRecognizer.isEnabled = true
            let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
            hostView.scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        }

        // Sync background pattern
        if hostView.backgroundPatternView.pattern != viewModel.backgroundPattern {
            hostView.backgroundPatternView.pattern = viewModel.backgroundPattern
        }
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = hex.uppercased() == "#0F0F0E" ? .gBackground : UIColor(hex: hex)
            if hostView.backgroundPatternView.pageBackgroundColor != color {
                hostView.backgroundPatternView.pageBackgroundColor = color
            }
        }

        // Sync drawing data when page changes
        if context.coordinator.currentPageIndex != viewModel.currentPageIndex || context.coordinator.currentPageId != viewModel.currentPage.id || viewModel.forceDrawingUpdate {
            context.coordinator.currentPageIndex = viewModel.currentPageIndex
            context.coordinator.currentPageId = viewModel.currentPage.id
            let pageDrawing = viewModel.currentDrawing
            
            if viewModel.forceDrawingUpdate {
                if let undoManager = canvasView.undoManager {
                    let oldDrawing = canvasView.drawing
                    undoManager.registerUndo(withTarget: context.coordinator) { coordinator in
                        coordinator.setDrawing(oldDrawing, on: canvasView)
                    }
                }
                context.coordinator.setDrawing(pageDrawing, on: canvasView)
                
                DispatchQueue.main.async {
                    viewModel.forceDrawingUpdate = false
                }
            } else {
                context.coordinator.setDrawing(pageDrawing, on: canvasView)
            }
            
            Task { @MainActor in
                viewModel.pkUndoManager = canvasView.undoManager
                viewModel.refreshUndoState()
            }
        }
    }

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

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var viewModel: CanvasViewModel
        weak var canvasView: GirokCanvasView?
        weak var hostView: FixedCanvasHostView?
        var currentPageIndex: Int = 0
        var currentPageId: UUID?

        private var isUpdatingDrawing = false
        private var lastStrokeFromPencil = true
        
        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            self.currentPageIndex = viewModel.currentPageIndex
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if canvasView.drawingPolicy == .pencilOnly {
                lastStrokeFromPencil = true
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingDrawing else { return }

            let fromPencil = lastStrokeFromPencil
            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, fromPencil: fromPencil)
            }
        }
        
        func fingerTouchDetected() {
            lastStrokeFromPencil = false
            Task { @MainActor in
                self.viewModel.showToolbar()
            }
        }

        func pencilTouchDetected() {
            lastStrokeFromPencil = true
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            Task { @MainActor in
                let newTool: DrawingTool = self.viewModel.selectedTool == .eraser ? .pen : .eraser
                self.viewModel.selectTool(newTool)
                HapticEngine.light()
            }
        }

        func setDrawing(_ drawing: PKDrawing, on canvasView: PKCanvasView? = nil) {
            let target = canvasView ?? self.canvasView
            guard let canvas = target else { return }
            
            if let undoManager = canvas.undoManager, undoManager.isUndoing || undoManager.isRedoing {
                let currentDrawing = canvas.drawing
                undoManager.registerUndo(withTarget: self) { coordinator in
                    coordinator.setDrawing(currentDrawing, on: canvas)
                }
            }
            
            isUpdatingDrawing = true
            canvas.drawing = drawing
            isUpdatingDrawing = false
            
            if let undoManager = canvas.undoManager, undoManager.isUndoing || undoManager.isRedoing {
                Task { @MainActor in
                    self.viewModel.drawingDidChange(drawing, fromPencil: self.lastStrokeFromPencil)
                }
            }
        }
    }

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

// MARK: - FixedCanvasHostView

final class FixedCanvasHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let pageContainerView = UIView()
    let pageBackgroundView = UIView()
    let backgroundPatternView: BackgroundPatternView
    let canvasView = GirokCanvasView()

    var blockOverlayHostView: UIHostingController<BlockOverlayView>?

    private let pageSize: CGSize
    private var viewModel: CanvasViewModel?
    private var didSetInitialZoom = false
    private lazy var textTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleCanvasTap(_:)))
        // Do NOT swallow touches: the UITextView inside text blocks must receive
        // finger taps for caret placement and standard editing.
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var canvasLongPressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleCanvasLongPress(_:)))
        recognizer.minimumPressDuration = 0.45
        // Cancel touches so the system doesn't show the iPadOS edit menu under our custom menu.
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    init(pageSize: CGSize, viewModel: CanvasViewModel?) {
        self.pageSize = pageSize
        self.viewModel = viewModel
        self.backgroundPatternView = BackgroundPatternView(frame: CGRect(origin: .zero, size: pageSize))
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .gBackground

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.contentSize = pageSize
        scrollView.minimumZoomScale = 0.3
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addGestureRecognizer(textTapRecognizer)
        scrollView.addGestureRecognizer(canvasLongPressRecognizer)
        addSubview(scrollView)

        pageContainerView.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.addSubview(pageContainerView)

        pageBackgroundView.frame = CGRect(origin: .zero, size: pageSize)
        pageBackgroundView.backgroundColor = .white
        pageBackgroundView.layer.shadowColor = UIColor.black.cgColor
        pageBackgroundView.layer.shadowOpacity = 0.18
        pageBackgroundView.layer.shadowRadius = 12
        pageBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)
        pageContainerView.addSubview(pageBackgroundView)

        backgroundPatternView.clipsToBounds = true
        pageBackgroundView.addSubview(backgroundPatternView)

        canvasView.frame = CGRect(origin: .zero, size: pageSize)
        canvasView.contentSize = pageSize
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        if let contentView = canvasView.subviews.first {
            contentView.backgroundColor = .clear
            contentView.isOpaque = false
        }
        
        // PKCanvasView is itself a UIScrollView. Disable its own scrolling/zooming
        // so that pinch and pan gestures reach the outer scrollView (which handles
        // zoom and panning for the whole page). Without this, PKCanvasView swallows
        // all pinch gestures and the page appears completely locked.
        canvasView.isScrollEnabled = false
        canvasView.bounces = false
        canvasView.bouncesZoom = false
        canvasView.pinchGestureRecognizer?.isEnabled = false
        canvasView.panGestureRecognizer.isEnabled = false

        pageContainerView.addSubview(canvasView)

        if let viewModel = viewModel {
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel))
            blockHost.view.backgroundColor = .clear
            blockHost.view.isUserInteractionEnabled = true
            blockHost.view.frame = CGRect(origin: .zero, size: pageSize)
            blockHost.view.clipsToBounds = false
            pageContainerView.addSubview(blockHost.view)
            self.blockOverlayHostView = blockHost
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didSetInitialZoom, bounds.width > 0 else {
            return
        }
        if let state = viewModel?.restoredViewport {
            let restoredScale = max(scrollView.minimumZoomScale, min(state.scale, scrollView.maximumZoomScale))
            scrollView.zoomScale = restoredScale
            centerPage()
            scrollView.contentOffset = CGPoint(x: state.offsetX, y: state.offsetY)
            viewModel?.finalizeViewport(
                offset: CGSize(width: state.offsetX, height: state.offsetY),
                scale: restoredScale
            )
        } else {
            let fitZoom = (bounds.width - 80) / pageSize.width
            scrollView.zoomScale = max(scrollView.minimumZoomScale, min(fitZoom, scrollView.maximumZoomScale))
            centerPage()
            viewModel?.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }
        didSetInitialZoom = true
    }

    private func centerPage() {
        let offsetX = max(0, (scrollView.bounds.width - pageSize.width * scrollView.zoomScale) / 2)
        let offsetY = max(0, (scrollView.bounds.height - pageSize.height * scrollView.zoomScale) / 2)
        scrollView.contentInset = UIEdgeInsets(top: offsetY + 40, left: offsetX + 40, bottom: 40, right: 40)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return pageContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPage()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        Task { @MainActor in
            self.viewModel?.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        Task { @MainActor in
            self.viewModel?.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        centerPage()
        Task { @MainActor in
            self.viewModel?.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scale
            )
        }
    }

    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let blockView = blockOverlayHostView?.view {
            let blockPoint = self.convert(point, to: blockView)
            if let hit = blockView.hitTest(blockPoint, with: event) {
                // Forward only real overlay subviews (text blocks, handles, editor).
                // Let empty-space touches fall through so the scroll view can pan/zoom.
                if hit !== blockView {
                    return hit
                }
            }
        }
        return super.hitTest(point, with: event)
    }

    @objc private func handleCanvasTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let viewModel else { return }
        guard viewModel.selectedTool == .text || viewModel.selectedTool == .image else { return }

        let location = recognizer.location(in: pageContainerView)
        guard CGRect(origin: .zero, size: pageSize).contains(location) else { return }
        if viewModel.selectedTool == .text {
            viewModel.handleTextToolCanvasTap(at: location)
        } else {
            viewModel.beginImageInsertion(at: location)
        }
    }

    @objc private func handleCanvasLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let viewModel else { return }
        guard !viewModel.isLassoSelectionActive, !viewModel.isRegionCaptureMode else { return }

        if #available(iOS 13.0, *) {
            UIMenuController.shared.hideMenu(from: self)
        } else {
            UIMenuController.shared.setMenuVisible(false, animated: false)
        }

        let location = recognizer.location(in: pageContainerView)
        guard CGRect(origin: .zero, size: pageSize).contains(location) else { return }
        viewModel.showCanvasContextMenu(at: location)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === textTapRecognizer || gestureRecognizer === canvasLongPressRecognizer else {
            return true
        }
        guard let blockView = blockOverlayHostView?.view else { return true }

        let pointInBlock = touch.location(in: blockView)
        if let hit = blockView.hitTest(pointInBlock, with: nil), hit !== blockView {
            // Touch landed on a real overlay subview (textbox, editor, handle, etc).
            // Let that view own the interaction; canvas gestures should ignore it.
            return false
        }
        return true
    }
}
