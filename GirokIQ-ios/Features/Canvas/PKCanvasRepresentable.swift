import SwiftUI
import PencilKit

final class GirokCanvasView: PKCanvasView {
    var onSelectionChanged: ((CGRect?) -> Void)?

    override func addInteraction(_ interaction: UIInteraction) {
        // Prevent PencilKit from adding its own edit menu interaction
        // This allows us to use a completely custom SwiftUI overlay instead.
        if interaction is UIEditMenuInteraction {
            return
        }
        super.addInteraction(interaction)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let actionName = NSStringFromSelector(action)
        // Disable "Insert Space" since we don't support it in our custom menu
        if actionName.contains("insertSpace") || actionName.contains("_insertSpace") {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Strip UIEditMenuInteraction from any internal selection views to kill Apple's menu
        stripEditMenu(from: self)
        
        let selectionRect = findSelectionViewFrame()
        onSelectionChanged?(selectionRect)
    }

    private func stripEditMenu(from view: UIView) {
        if view.interactions.contains(where: { $0 is UIEditMenuInteraction }) {
            view.interactions.removeAll { $0 is UIEditMenuInteraction }
        }
        for subview in view.subviews {
            stripEditMenu(from: subview)
        }
    }

    private func findSelectionViewFrame() -> CGRect? {
        func search(_ view: UIView) -> UIView? {
            let name = String(describing: type(of: view))
            if name.contains("Selection") && !name.contains("EditMenu") {
                return view
            }
            for sub in view.subviews {
                if let found = search(sub) { return found }
            }
            return nil
        }
        guard let selView = search(self) else { return nil }
        // Convert to GirokCanvasView coordinates
        return selView.convert(selView.bounds, to: self)
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
    private let canvasContentSize: CGSize
    private var viewModel: CanvasViewModel?
    private var didSetInitialZoom = false

    // MARK: - Init

    init(frame: CGRect = .zero, viewModel: CanvasViewModel? = nil) {
        self.viewModel = viewModel
        
        let size: CGSize
        if let nb = viewModel?.notebook, nb.canvasType == "fixed", let dims = nb.pageDimensions {
            size = CGSize(width: dims.widthPt, height: dims.heightPt)
        } else {
            size = CGSize(width: 50_000, height: 50_000)
        }
        self.canvasContentSize = size
        
        backgroundPatternView = BackgroundPatternView(
            frame: CGRect(origin: .zero, size: size)
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
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel, canvasView: canvasView))
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

        // Configure fixed canvas aesthetics
        if viewModel?.notebook?.canvasType == "fixed" {
            self.backgroundColor = UIColor.systemGray5
            backgroundPatternView.layer.shadowColor = UIColor.black.cgColor
            backgroundPatternView.layer.shadowOpacity = 0.15
            backgroundPatternView.layer.shadowRadius = 8
            backgroundPatternView.layer.shadowOffset = CGSize(width: 0, height: 4)
            backgroundPatternView.layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: canvasContentSize)).cgPath
            backgroundPatternView.clipsToBounds = false
        } else {
            self.backgroundColor = .clear
        }

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
        updateCenteringInsets()
    }

    // MARK: - UIScrollViewDelegate (for backgroundScrollView only)

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // Return the background pattern view so zoomScale assignment works
        return backgroundPatternView
    }

    // MARK: - Sync

    /// Mirrors PKCanvasView's scroll position and zoom to the background scroll view.
    /// Two property assignments — no frame changes, no tile invalidation.
    func syncBackground(isZooming: Bool = false) {
        if backgroundScrollView.contentOffset != canvasView.contentOffset {
            backgroundScrollView.contentOffset = canvasView.contentOffset
        }
        if backgroundScrollView.zoomScale != canvasView.zoomScale {
            backgroundScrollView.zoomScale = canvasView.zoomScale
        }
        
        if isZooming {
            updateCenteringInsets()
        }
    }
    
    private func updateCenteringInsets() {
        if viewModel?.notebook?.canvasType == "fixed" {
            let offsetX = max(0, (bounds.width - canvasContentSize.width * canvasView.zoomScale) / 2)
            let offsetY = max(0, (bounds.height - canvasContentSize.height * canvasView.zoomScale) / 2)
            let insets = UIEdgeInsets(top: offsetY + 40, left: offsetX + 40, bottom: 40, right: 40)
            canvasView.contentInset = insets
            backgroundScrollView.contentInset = insets
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

// MARK: - PKCanvasRepresentable

/// PencilKit-backed canvas view wrapped for SwiftUI.
/// Uses CanvasHostView to layer a CATiledLayer background behind the transparent
/// PKCanvasView, completely outside PencilKit's internal view hierarchy.
struct PKCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel
    let pageIndex: Int

    /// Whether finger drawing is allowed (false = Apple Pencil only)
    var allowsFingerDrawing: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, pageIndex: pageIndex)
    }

    func makeUIView(context: Context) -> CanvasHostView {
        // Use the specific page from the viewModel
        let page = viewModel.pages[pageIndex]
        let hostView = CanvasHostView(viewModel: viewModel)
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

    func updateUIView(_ hostView: CanvasHostView, context: Context) {
        let isCurrentPage = viewModel.currentPageIndex == pageIndex
        let page = viewModel.pages[pageIndex]

        // Sync SwiftUI colorScheme into UIKit trait collection so dynamic UIColors resolve correctly
        let targetStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if hostView.backgroundPatternView.overrideUserInterfaceStyle != targetStyle {
            hostView.backgroundPatternView.overrideUserInterfaceStyle = targetStyle
            hostView.backgroundPatternView.layer.setNeedsDisplay()
        }

        let canvasView = hostView.canvasView
        
        // PERFORMANCE: Only update canvasViewSize if it actually changed and it's the current page
        if isCurrentPage {
            let newSize = hostView.bounds.size
            if viewModel.canvasViewSize != newSize && newSize != .zero {
                DispatchQueue.main.async {
                    viewModel.canvasViewSize = newSize
                }
            }
        }

        // Only rebuild PKTool when tool-related properties actually changed
        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .text || viewModel.selectedTool == .image
        if isBlockTool {
            if canvasView.isUserInteractionEnabled {
                canvasView.isUserInteractionEnabled = false
            }
        } else {
            if !canvasView.isUserInteractionEnabled {
                canvasView.isUserInteractionEnabled = true
                canvasView.drawingGestureRecognizer.isEnabled = true
            }
            let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
        }

        // Sync background pattern when it changes for THIS page
        if hostView.backgroundPatternView.pattern != page.backgroundPattern {
            hostView.backgroundPatternView.pattern = page.backgroundPattern
        }
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = Self.resolveBackgroundColor(hex: hex)
            if hostView.backgroundPatternView.pageBackgroundColor != color {
                hostView.backgroundPatternView.pageBackgroundColor = color
            }
        }

        // Handle programmatic drawing updates (e.g. from undo/redo or shape snapping)
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
        let pageIndex: Int
        weak var canvasView: PKCanvasView?
        weak var hostView: CanvasHostView?
        var currentPageIndex: Int = 0
        var currentPageId: UUID?

        /// Tracks whether we are currently performing a programmatic drawing update
        private var isUpdatingDrawing = false

        /// Tracks whether the current/most-recent stroke came from Apple Pencil
        private var lastStrokeFromPencil = true
        
        init(viewModel: CanvasViewModel, pageIndex: Int) {
            self.viewModel = viewModel
            self.pageIndex = pageIndex
            self.currentPageIndex = pageIndex
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

            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, pageIndex: self.pageIndex, fromPencil: fromPencil)
            }
        }
        
        // MARK: UIScrollViewDelegate (via PKCanvasViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            hostView?.syncBackground(isZooming: false)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.syncBackground(isZooming: true)
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
                    self.viewModel.drawingDidChange(drawing, pageIndex: self.pageIndex, fromPencil: self.lastStrokeFromPencil)
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
