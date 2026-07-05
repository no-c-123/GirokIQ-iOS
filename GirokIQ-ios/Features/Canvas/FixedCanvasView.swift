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
        hostView.backgroundPatternView.pageBackgroundColor = .gBackground

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

        // Defer published-state writes until after UIKit finishes this update cycle.
        DispatchQueue.main.async {
            viewModel.pkUndoManager = canvasView.undoManager
            viewModel.refreshUndoState()
            viewModel.setViewportScrollView(hostView.scrollView)
        }

        return hostView
    }

    func updateUIView(_ hostView: FixedCanvasHostView, context: Context) {
        let canvasView = hostView.canvasView
        viewModel.setCanvasViewSizeIfNeeded(hostView.bounds.size)

        if context.coordinator.lastViewportRestoreToken != viewModel.viewportRestoreToken {
            context.coordinator.lastViewportRestoreToken = viewModel.viewportRestoreToken
            hostView.resetViewportRestoreState()
        }

        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .image || viewModel.selectedTool == .text
        let isLassoTool = viewModel.selectedTool == .lasso

        // Let the pencil draw/erase over blocks: disable overlay hit-testing for ink tools.
        hostView.blockOverlayHostView?.view.isUserInteractionEnabled = !viewModel.selectedTool.isInkOrEraser
        // Pencil-only lasso capture lives on the host; enable it for the lasso tool.
        hostView.setLassoActive(isLassoTool)

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
        if hostView.backgroundPatternView.pageBackgroundColor != .gBackground {
            hostView.backgroundPatternView.pageBackgroundColor = .gBackground
        }

        // Sync drawing data when page changes
        if context.coordinator.currentPageIndex != viewModel.currentPageIndex || context.coordinator.currentPageId != viewModel.currentPage.id || viewModel.forceDrawingUpdate {
            context.coordinator.currentPageIndex = viewModel.currentPageIndex
            context.coordinator.currentPageId = viewModel.currentPage.id
            let pageDrawing = viewModel.currentDrawing
            
            if viewModel.forceDrawingUpdate {
                if !viewModel.isPreviewingLassoMove, let undoManager = canvasView.undoManager {
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
            
            DispatchQueue.main.async {
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
        if let aEraser = a as? PKEraserTool, let bEraser = b as? PKEraserTool {
            return aEraser.eraserType == bEraser.eraserType &&
                   abs(aEraser.width - bEraser.width) < 0.01
        }
        if a is PKLassoTool && b is PKLassoTool { return true }
        return false
    }

    private func currentPKTool() -> PKTool {
        let uiColor = UIColor(viewModel.strokeColor)
        return PencilKitBridge.pkTool(
            for: viewModel.selectedTool,
            color: uiColor.withAlphaComponent(viewModel.strokeOpacity),
            width: viewModel.selectedTool == .eraser ? viewModel.eraserWidth : viewModel.strokeWidth,
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
        var lastViewportRestoreToken: UUID?

        private var isUpdatingDrawing = false
        private var lastStrokeFromPencil = true
        
        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            self.currentPageIndex = viewModel.currentPageIndex
            self.lastViewportRestoreToken = viewModel.viewportRestoreToken
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
    private var pendingRestoredViewport: CanvasViewportState?

    func resetViewportRestoreState() {
        didSetInitialZoom = false
        pendingRestoredViewport = nil
        setNeedsLayout()
    }
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
    /// Apple Pencil–only lasso capture. Lives on the host so finger touches still
    /// reach the scroll view and pan/zoom the page while the lasso tool is active.
    private lazy var lassoPanRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleLassoPan(_:)))
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        recognizer.isEnabled = false
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
        scrollView.minimumZoomScale = 0.15
        scrollView.maximumZoomScale = 7.0
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
            viewModel.setCanvasCoordinateViews(hostView: self, contentView: blockHost.view)
        }

        // Lasso capture sits on the host (above the page). The scroll view's pan must
        // wait for it to fail: a pencil drag draws the lasso (and the pan fails); a
        // finger drag fails the pencil-only lasso instantly, so the page pans normally.
        addGestureRecognizer(lassoPanRecognizer)
        scrollView.panGestureRecognizer.require(toFail: lassoPanRecognizer)
    }

    /// Enables the pencil-only lasso recognizer for the lasso tool.
    func setLassoActive(_ active: Bool) {
        if lassoPanRecognizer.isEnabled != active {
            lassoPanRecognizer.isEnabled = active
        }
    }

    @objc private func handleLassoPan(_ recognizer: UIPanGestureRecognizer) {
        guard let viewModel, viewModel.selectedTool == .lasso, !viewModel.isRegionCaptureMode else { return }
        let screenPoint = recognizer.location(in: self)
        let canvasPoint = blockOverlayHostView?.view.map { self.convert(screenPoint, to: $0) } ?? screenPoint
        switch recognizer.state {
        case .began:    viewModel.beginLiveLasso(at: screenPoint, canvasPoint: canvasPoint)
        case .changed:  viewModel.appendLiveLasso(screenPoint, canvasPoint: canvasPoint)
        case .ended:    viewModel.endLiveLasso()
        case .cancelled, .failed: viewModel.cancelLiveLasso()
        default: break
        }
    }

    // MARK: - Hosting Controller Containment

    /// Attach the block-overlay `UIHostingController` to the owning view controller.
    /// Without this containment, SwiftUI presentations inside it (color picker, sheets,
    /// edit/context menus) reparent their effect views into the hosting controller's
    /// own view — the source of the "_UIReparentingView / _UIGravityWellEffectAnchorView
    /// … not supported" console warnings.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let blockHost = blockOverlayHostView else { return }
        if window != nil {
            if blockHost.parent == nil, let parentVC = parentViewController {
                parentVC.addChild(blockHost)
                blockHost.didMove(toParent: parentVC)
            }
        } else if blockHost.parent != nil {
            blockHost.willMove(toParent: nil)
            blockHost.removeFromParent()
        }
    }

    private var parentViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didSetInitialZoom, bounds.width > 0 else {
            return
        }
        if let state = viewModel?.restoredViewport {
            let restoredScale = max(scrollView.minimumZoomScale, min(state.scale, scrollView.maximumZoomScale))
            pendingRestoredViewport = CanvasViewportState(
                offsetX: state.offsetX,
                offsetY: state.offsetY,
                scale: restoredScale
            )
            scrollView.zoomScale = restoredScale
            centerPage()
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingRestoredViewportIfNeeded()
            }
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

    private func applyPendingRestoredViewportIfNeeded() {
        guard let state = pendingRestoredViewport else { return }
        scrollView.setContentOffset(CGPoint(x: state.offsetX, y: state.offsetY), animated: false)
        viewModel?.finalizeViewport(
            offset: CGSize(width: state.offsetX, height: state.offsetY),
            scale: state.scale
        )
        pendingRestoredViewport = nil
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
        // While an ink or eraser tool is active the pencil must be able to draw or
        // erase over image and text blocks. The overlay's interaction is disabled in
        // updateUIView for these tools (so super.hitTest skips it), but we also bail
        // here so the custom forwarding never claims the touch.
        if viewModel?.selectedTool.isInkOrEraser == true {
            return super.hitTest(point, with: event)
        }
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

        // The system edit menu (UIEditMenuInteraction on iOS 16+) is already
        // suppressed via canPerformAction(_:withSender:) and interaction stripping,
        // so no explicit menu dismissal is needed here before showing our own menu.

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
