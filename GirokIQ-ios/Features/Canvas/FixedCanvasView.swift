import SwiftUI
import PencilKit

struct FixedCanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let pageIndex: Int
    let pageSize: CGSize

    var body: some View {
        FixedCanvasRepresentable(viewModel: viewModel, pageIndex: pageIndex, pageSize: pageSize)
            .ignoresSafeArea(edges: [.horizontal, .bottom])
    }
}

// MARK: - FixedCanvasRepresentable

struct FixedCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel
    let pageIndex: Int
    let pageSize: CGSize
    
    var allowsFingerDrawing: Bool {
        !viewModel.palmRejectionEnabled
    }
    
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, pageIndex: pageIndex)
    }

    func makeUIView(context: Context) -> FixedCanvasHostView {
        let page = viewModel.pages[pageIndex]
        let hostView = FixedCanvasHostView(pageSize: pageSize, viewModel: viewModel)
        let canvasView = hostView.canvasView

        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Configure background pattern
        hostView.backgroundPatternView.pattern = page.backgroundPattern
        if let hex = viewModel.notebook?.backgroundColorHex {
            hostView.backgroundPatternView.pageBackgroundColor = Self.resolveBackgroundColor(hex: hex)
        }
        
        hostView.backgroundPatternView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        context.coordinator.hostView = hostView
        context.coordinator.canvasView = canvasView

        hostView.canvasView.onSelectionChanged = { [weak viewModel, weak hostView] viewRect in
            guard let vm = viewModel, let host = hostView, vm.currentPageIndex == pageIndex else { return }
            Task { @MainActor in
                if let rect = viewRect, rect.width > 4, rect.height > 4 {
                    // Anchor the menu above the selection bounding box center
                    let anchor = CGPoint(x: rect.midX, y: rect.minY - 16)
                    vm.presentEditMenu(at: anchor)
                    
                    // Convert view rect to canvas rect to populate selectionBoundingBox
                    let scale = host.canvasView.zoomScale
                    let offset = host.canvasView.contentOffset
                    let canvasRect = CGRect(
                        x: (rect.minX + offset.x) / scale,
                        y: (rect.minY + offset.y) / scale,
                        width: rect.width / scale,
                        height: rect.height / scale
                    )
                    vm.selectionBoundingBox = canvasRect
                    
                    // Populate selectedStrokeIndices by finding strokes inside the rect
                    let drawing = host.canvasView.drawing
                    let selected = drawing.strokes.indices.filter { i in
                        drawing.strokes[i].renderBounds.intersects(canvasRect)
                    }
                    vm.selectedStrokeIndices = Set(selected)
                } else {
                    if !vm.selectedStrokeIndices.isEmpty {
                        vm.dismissEditMenu()
                        vm.selectionBoundingBox = nil
                        vm.selectedStrokeIndices = []
                    }
                }
            }
        }

        // Load existing drawing data from the current page
        context.coordinator.currentPageId = page.id
        if let data = page.drawingData,
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

        // Remove any pre-existing UIEditMenuInteractions just in case
        canvasView.interactions.removeAll(where: { $0 is UIEditMenuInteraction })

        // Forward UndoManager to viewModel if this is the active page
        if viewModel.currentPageIndex == pageIndex {
            Task { @MainActor in
                viewModel.pkUndoManager = canvasView.undoManager
                viewModel.refreshUndoState()
            }
        }

        // Tap gesture for text and image placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleCanvasTap(_:)))
        canvasView.addGestureRecognizer(tapGesture)

        return hostView
    }

    func updateUIView(_ hostView: FixedCanvasHostView, context: Context) {
        let isCurrentPage = viewModel.currentPageIndex == pageIndex
        let page = viewModel.pages[pageIndex]

        // Sync SwiftUI colorScheme into UIKit trait collection so dynamic UIColors resolve correctly
        let targetStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if hostView.backgroundPatternView.overrideUserInterfaceStyle != targetStyle {
            hostView.backgroundPatternView.overrideUserInterfaceStyle = targetStyle
            hostView.backgroundPatternView.layer.setNeedsDisplay()
        }

        let canvasView = hostView.canvasView
        
        if isCurrentPage {
            DispatchQueue.main.async {
                viewModel.canvasViewSize = hostView.bounds.size
            }
        }

        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .text || viewModel.selectedTool == .image
        if isBlockTool {
            // Never disable isUserInteractionEnabled for PKCanvasView during drawing.
            // Use drawingGestureRecognizer.isEnabled to toggle PencilKit input.
            canvasView.drawingGestureRecognizer.isEnabled = false
        } else {
            canvasView.drawingGestureRecognizer.isEnabled = true
            let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
        }

        // Sync background pattern
        if hostView.backgroundPatternView.pattern != page.backgroundPattern {
            hostView.backgroundPatternView.pattern = page.backgroundPattern
        }
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = Self.resolveBackgroundColor(hex: hex)
            if hostView.backgroundPatternView.pageBackgroundColor != color {
                hostView.backgroundPatternView.pageBackgroundColor = color
                hostView.pageBackgroundView.backgroundColor = color
            }
        }

        // Handle programmatic drawing updates
        if isCurrentPage && viewModel.forceDrawingUpdate {
            let pageDrawing = page.pkDrawing
            
            // If it's a programmatic shape update, inject it using the UndoManager to preserve undo/redo stack
            if let undoManager = canvasView.undoManager, !viewModel.isLiveResizing {
                let oldDrawing = viewModel.undoDrawing ?? canvasView.drawing
                undoManager.registerUndo(withTarget: context.coordinator) { coordinator in
                    coordinator.setDrawing(oldDrawing, on: canvasView)
                }
                DispatchQueue.main.async {
                    viewModel.undoDrawing = nil
                }
            }
            context.coordinator.setDrawing(pageDrawing, on: canvasView)
            
            DispatchQueue.main.async {
                viewModel.forceDrawingUpdate = false
            }
        }
        
        // Always sync UndoManager to viewModel when this page becomes active
        if isCurrentPage && viewModel.pkUndoManager !== canvasView.undoManager {
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

    /// Maps a stored hex to a UIColor, using adaptive tokens for "Default"-class colors.
    /// "#0F0F0E" is the legacy default (dark), and "#F8F8FA" is the light-mode gBackground value.
    /// Both should resolve to the adaptive .gBackground token so they respond to dark/light mode.
    private static func resolveBackgroundColor(hex: String) -> UIColor {
        let normalized = hex.uppercased()
        switch normalized {
        case "#0F0F0E", "#F8F8FA":
            return .gBackground   // adaptive: off-white in light, near-black in dark
        default:
            return UIColor(hex: hex)  // user-chosen static color — keep as-is
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var viewModel: CanvasViewModel
        let pageIndex: Int
        weak var canvasView: GirokCanvasView?
        weak var hostView: FixedCanvasHostView?
        var currentPageIndex: Int = 0
        var currentPageId: UUID?

        private var isUpdatingDrawing = false
        private var lastStrokeFromPencil = true
        
        init(viewModel: CanvasViewModel, pageIndex: Int) {
            self.viewModel = viewModel
            self.pageIndex = pageIndex
            self.currentPageIndex = pageIndex
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
                self.viewModel.drawingDidChange(canvasView.drawing, pageIndex: self.pageIndex, fromPencil: fromPencil)
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

        @objc func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
            guard let canvas = canvasView,
                  viewModel.selectedTool == .text else { return }

            let location = gesture.location(in: canvas)
            let tapPoint = location

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
                    self.viewModel.drawingDidChange(drawing, pageIndex: self.pageIndex, fromPencil: self.lastStrokeFromPencil)
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

final class FixedCanvasHostView: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let pageContainerView = UIView()
    let pageBackgroundView = UIView()
    let backgroundPatternView: BackgroundPatternView
    let canvasView = GirokCanvasView()

    var blockOverlayHostView: UIHostingController<BlockOverlayView>?

    private let pageSize: CGSize
    private var viewModel: CanvasViewModel?
    private var didSetInitialZoom = false

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
        addSubview(scrollView)

        pageContainerView.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.addSubview(pageContainerView)

        pageBackgroundView.frame = CGRect(origin: .zero, size: pageSize)
        pageBackgroundView.backgroundColor = .gBackground
        pageBackgroundView.layer.shadowColor = UIColor.black.cgColor
        pageBackgroundView.layer.shadowOpacity = 0.18
        pageBackgroundView.layer.shadowRadius = 12
        pageBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)
        pageContainerView.addSubview(pageBackgroundView)

        backgroundPatternView.clipsToBounds = true
        pageBackgroundView.addSubview(backgroundPatternView)

        if let viewModel = viewModel {
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel, canvasView: scrollView))
            blockHost.view.backgroundColor = .clear
            blockHost.view.isUserInteractionEnabled = true
            blockHost.view.frame = CGRect(origin: .zero, size: pageSize)
            pageContainerView.addSubview(blockHost.view)
            self.blockOverlayHostView = blockHost
        }

        canvasView.frame = CGRect(origin: .zero, size: pageSize)
        canvasView.contentSize = pageSize
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        // Fixed Canvas drawing quality improvement:
        // Set contentScaleFactor explicitly to prevent pixelation when zoomed.
        canvasView.contentScaleFactor = UIScreen.main.scale
        if let contentView = canvasView.subviews.first {
            contentView.backgroundColor = .clear
            contentView.isOpaque = false
            contentView.contentScaleFactor = UIScreen.main.scale
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
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didSetInitialZoom, bounds.width > 0 else {
            return
        }
        let fitZoom = (bounds.width - 80) / pageSize.width
        scrollView.zoomScale = max(scrollView.minimumZoomScale, min(fitZoom, scrollView.maximumZoomScale))
        centerPage()
        
        let newScale = UIScreen.main.scale * scrollView.zoomScale
        canvasView.contentScaleFactor = newScale
        if let contentView = canvasView.subviews.first {
            contentView.contentScaleFactor = newScale
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
        Task { @MainActor in
            self.viewModel?.canvasScale = scrollView.zoomScale
        }
        
        // Dynamically update the internal contentScaleFactor of the PKCanvasView to match the zoom scale.
        // This forces PencilKit to re-rasterize the vector strokes at the correct resolution instead of 
        // blowing up a low-res bitmap, fixing the blurry strokes on the fixed canvas.
        let newScale = UIScreen.main.scale * scrollView.zoomScale
        canvasView.contentScaleFactor = newScale
        if let contentView = canvasView.subviews.first {
            contentView.contentScaleFactor = newScale
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        Task { @MainActor in
            self.viewModel?.canvasOffset = CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y)
        }
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
