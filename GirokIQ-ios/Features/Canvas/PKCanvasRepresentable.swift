import SwiftUI
import PencilKit

final class GirokCanvasView: PKCanvasView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let actionName = NSStringFromSelector(action)
        // Disable "Select All" and "Insert Space" which appear when tapping empty canvas
        if actionName == "selectAll:" || actionName == "_insertSpace:" || actionName == "insertSpace:" {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

// MARK: - Menu Blocker Gesture Recognizer

final class MenuBlockerGestureRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    weak var canvas: PKCanvasView?
    
    init(canvas: PKCanvasView) {
        self.canvas = canvas
        super.init(target: nil, action: nil)
        self.addTarget(self, action: #selector(dummyAction))
        self.delegate = self
        self.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        self.cancelsTouchesInView = true
    }
    
    @objc private func dummyAction() {}
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only block finger taps if the drawing policy is pencil only.
        // (If finger drawing is enabled, PencilKit draws a dot instead of showing a menu).
        guard let canvas = canvas, canvas.drawingPolicy == .pencilOnly else { return false }
        
        // We only want to block the tap if there is NO active selection.
        // If there is an active selection (Lasso), we must let the tap pass through 
        // so the user can tap the selection to see the "Copy/Delete/Duplicate" menu.
        func hasSelectionView(_ view: UIView) -> Bool {
            let name = String(describing: type(of: view))
            if name.contains("Selection") || name.contains("EditMenu") { return true }
            for subview in view.subviews {
                if hasSelectionView(subview) { return true }
            }
            return false
        }
        
        // Return true to swallow the touch if there is NO selection
        return !hasSelectionView(canvas)
    }
}

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

    let canvasView = GirokCanvasView()
    let backgroundPatternView: BackgroundPatternView
    var blockOverlayHostView: UIHostingController<BlockOverlayView>?

    // MARK: - Private

    private let backgroundScrollView = UIScrollView()
    private let canvasContentSize = CGSize(width: 50_000, height: 50_000)
    private var viewModel: CanvasViewModel?

    // MARK: - Init

    init(frame: CGRect = .zero, viewModel: CanvasViewModel? = nil) {
        self.viewModel = viewModel
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

        // index 0 — tiled background
        addSubview(backgroundScrollView)

        // index 1 — block overlay (images, text blocks)
        if let viewModel = viewModel {
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel))
            blockHost.view.backgroundColor = .clear
            blockHost.view.isUserInteractionEnabled = true
            blockHost.view.frame = bounds
            blockHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(blockHost.view)
            self.blockOverlayHostView = blockHost
        }

        // index 2 — PKCanvasView (ink on top, transparent)
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

    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let blockView = blockOverlayHostView?.view {
            let blockPoint = self.convert(point, to: blockView)
            if let hit = blockView.hitTest(blockPoint, with: event),
               hit !== blockView {
                return hit
            }
        }
        return super.hitTest(point, with: event)
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
        let hostView = CanvasHostView(viewModel: viewModel)
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

        // Install Menu Blocker to stop "Select All / Insert Space" on empty canvas
        let menuBlocker = MenuBlockerGestureRecognizer(canvas: canvasView)
        canvasView.addGestureRecognizer(menuBlocker)
        
        // Custom Pan Gesture to track Lasso rectangle in canvas space
        let lassoTracker = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLassoPan(_:)))
        lassoTracker.delegate = context.coordinator
        lassoTracker.cancelsTouchesInView = false
        canvasView.addGestureRecognizer(lassoTracker)

        // Forward UndoManager to viewModel
        Task { @MainActor in
            viewModel.pkUndoManager = canvasView.undoManager
            viewModel.refreshUndoState()
        }

        // Tap gesture for text and image placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleCanvasTap(_:)))
        canvasView.addGestureRecognizer(tapGesture)

        return hostView
    }

    func updateUIView(_ hostView: CanvasHostView, context: Context) {
        let canvasView = hostView.canvasView
        DispatchQueue.main.async {
            viewModel.canvasViewSize = hostView.bounds.size
        }

        // Only rebuild PKTool when tool-related properties actually changed
        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .text || viewModel.selectedTool == .image
        if isBlockTool {
            canvasView.isUserInteractionEnabled = false
        } else {
            canvasView.isUserInteractionEnabled = true
            canvasView.drawingGestureRecognizer.isEnabled = true
            let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
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
            
            if viewModel.forceDrawingUpdate {
                // If it's a programmatic shape update, inject it using the UndoManager to preserve undo/redo stack
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
                // Regular page change, just set drawing normally
                context.coordinator.setDrawing(pageDrawing, on: canvasView)
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

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var viewModel: CanvasViewModel
        weak var canvasView: PKCanvasView?
        weak var hostView: CanvasHostView?
        var currentPageIndex: Int = 0
        var currentPageId: UUID?

        var lassoStartPoint: CGPoint? = nil

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
            if canvasView.drawingPolicy == .pencilOnly {
                lastStrokeFromPencil = true
            }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // For anyInput, input type is determined by the TouchTypeRecognizer.
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingDrawing else { return }

            // If lasso tool is active, try to determine which strokes are selected
            // by checking which strokes' renderBounds intersect the lasso region
            if viewModel.selectedTool == .lasso, let lassoRect = viewModel.pendingLassoRect {
                let drawing = canvasView.drawing
                let selected = drawing.strokes.indices.filter { i in
                    drawing.strokes[i].renderBounds.intersects(lassoRect)
                }
                Task { @MainActor in
                    self.viewModel.selectedStrokeIndices = Set(selected)
                    self.viewModel.computeSelectionBoundingBox()
                }
            }

            let fromPencil = lastStrokeFromPencil

            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, fromPencil: fromPencil)
            }
        }
        
        // MARK: UIScrollViewDelegate (via PKCanvasViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
            Task { @MainActor in
                self.viewModel.canvasOffset = CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y)
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
            Task { @MainActor in
                self.viewModel.canvasScale = scrollView.zoomScale
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
                let newTool: DrawingTool = self.viewModel.selectedTool == .eraser ? .pen : .eraser
                self.viewModel.selectTool(newTool)
                HapticEngine.light()
            }
        }

        // MARK: - Lasso Pan Gesture

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func handleLassoPan(_ gesture: UIPanGestureRecognizer) {
            guard viewModel.selectedTool == .lasso, let canvas = canvasView else { return }
            let screenLocation = gesture.location(in: canvas)
            
            // Convert screen location to canvas coordinate space
            let scale = viewModel.canvasScale
            let offset = viewModel.canvasOffset
            let canvasLocation = CGPoint(
                x: (screenLocation.x + offset.width) / scale,
                y: (screenLocation.y + offset.height) / scale
            )
            
            switch gesture.state {
            case .began:
                lassoStartPoint = canvasLocation
                viewModel.pendingLassoRect = nil
            case .changed:
                if let start = lassoStartPoint {
                    let rect = CGRect(
                        x: min(start.x, canvasLocation.x),
                        y: min(start.y, canvasLocation.y),
                        width: abs(canvasLocation.x - start.x),
                        height: abs(canvasLocation.y - start.y)
                    )
                    viewModel.pendingLassoRect = rect
                }
            case .ended, .cancelled:
                if let rect = viewModel.pendingLassoRect {
                    // Check intersection with elements and set them in viewModel
                    let hits = viewModel.currentPage.elements.filter { el in
                        let w = el.width ?? 200
                        let h = el.height ?? 200
                        let elRect = CGRect(
                            x: el.positionX - w / 2,
                            y: el.positionY - h / 2,
                            width: w,
                            height: h
                        )
                        return rect.intersects(elRect)
                    }
                    viewModel.selectedElementIds = Set(hits.map(\.id))
                    
                    // The drawingDidChange delegate will handle strokes.
                    // But if there are no strokes, drawingDidChange might NOT fire!
                    // We must manually trigger bounding box computation just in case.
                    viewModel.computeSelectionBoundingBox()
                }
                lassoStartPoint = nil
            default:
                break
            }
        }

        // MARK: - Tap Gesture for Blocks

        @objc func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
            guard let canvas = canvasView,
                  viewModel.selectedTool == .text else { return }

            let location = gesture.location(in: canvas)
            let scale = canvas.zoomScale
            let offset = canvas.contentOffset
            let canvasX = (location.x + offset.x) / scale
            let canvasY = (location.y + offset.y) / scale
            let tapPoint = CGPoint(x: canvasX, y: canvasY)

            for element in viewModel.currentPage.elements where element.type == "text" {
                let w = CGFloat(element.width ?? 200)
                let h = CGFloat(element.height ?? 50)
                let rect = CGRect(
                    x: CGFloat(element.positionX) - w / 2,
                    y: CGFloat(element.positionY) - h / 2,
                    width: w,
                    height: h
                )
                if rect.contains(tapPoint) { return }
            }

            Task { @MainActor in
                let newElement = CanvasElement(
                    pageId: self.viewModel.currentPage.id,
                    userId: self.viewModel.userId ?? UUID(),
                    type: "text",
                    content: "\u{200B}",
                    positionX: Double(tapPoint.x),
                    positionY: Double(tapPoint.y),
                    width: 200,
                    height: nil,
                    style: ElementStyle(fontSize: 24, textColor: "#FFFFFE")
                )
                self.viewModel.addElement(newElement)
                self.viewModel.selectTool(.pen)
                HapticEngine.medium()
            }
        }

        // MARK: - Page Switching & Programmatic Updates

        func setDrawing(_ drawing: PKDrawing, on canvasView: PKCanvasView? = nil) {
            let target = canvasView ?? self.canvasView
            guard let canvas = target else { return }
            
            // If this is called from an Undo/Redo block, we need to register the *reverse* action
            // so the user can keep undoing/redoing back and forth.
            if let undoManager = canvas.undoManager, undoManager.isUndoing || undoManager.isRedoing {
                let currentDrawing = canvas.drawing
                undoManager.registerUndo(withTarget: self) { coordinator in
                    coordinator.setDrawing(currentDrawing, on: canvas)
                }
            }
            
            isUpdatingDrawing = true
            canvas.drawing = drawing
            isUpdatingDrawing = false
            
            // Force a viewModel sync if this was triggered by an undo/redo
            if let undoManager = canvas.undoManager, undoManager.isUndoing || undoManager.isRedoing {
                Task { @MainActor in
                    self.viewModel.drawingDidChange(drawing, fromPencil: self.lastStrokeFromPencil)
                }
            }
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
