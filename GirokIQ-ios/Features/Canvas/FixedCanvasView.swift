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

        // Tap gesture for text and image placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleCanvasTap(_:)))
        canvasView.addGestureRecognizer(tapGesture)

        return hostView
    }

    func updateUIView(_ hostView: FixedCanvasHostView, context: Context) {
        let canvasView = hostView.canvasView
        DispatchQueue.main.async {
            viewModel.canvasViewSize = hostView.bounds.size
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
            let pageDrawing = viewModel.currentPage.pkDrawing
            
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
        pageContainerView.addSubview(canvasView)

        if let viewModel = viewModel {
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel))
            blockHost.view.backgroundColor = .clear
            blockHost.view.isUserInteractionEnabled = true
            blockHost.view.frame = bounds
            blockHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(blockHost.view)
            self.blockOverlayHostView = blockHost
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didSetInitialZoom, bounds.width > 0 else {
            return
        }
        let fitZoom = (bounds.width - 80) / pageSize.width
        scrollView.zoomScale = max(scrollView.minimumZoomScale, min(fitZoom, scrollView.maximumZoomScale))
        centerPage()
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
