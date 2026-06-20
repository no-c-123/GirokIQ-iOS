import SwiftUI
import PencilKit
import UIKit

final class GirokCanvasView: PKCanvasView {
    private var didStripEditMenuInteractions = false

    // Block ALL edit-menu actions, not just three selectors.
    // Keep undo/redo so hardware keyboard Cmd+Z and Cmd+Shift+Z still work.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let name = NSStringFromSelector(action)
        if name == "undo:" || name == "redo:" {
            return super.canPerformAction(action, withSender: sender)
        }
        return false
    }

    // Remove PencilKit's internal edit-menu / handwriting-selection interactions,
    // which can present pills from internal subviews via UIEditMenuInteraction.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didStripEditMenuInteractions, window != nil else { return }
        didStripEditMenuInteractions = true
        Self.stripEditMenuInteractions(from: self)
    }

    private static func stripEditMenuInteractions(from view: UIView) {
        for interaction in view.interactions {
            let typeName = String(describing: type(of: interaction))
            if #available(iOS 16.0, *) {
                if interaction is UIEditMenuInteraction {
                    view.removeInteraction(interaction)
                    continue
                }
            }
            if typeName.contains("EditMenu") || typeName.contains("TextSelection") {
                view.removeInteraction(interaction)
            }
        }
        for sub in view.subviews {
            stripEditMenuInteractions(from: sub)
        }
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
final class CanvasHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - Public

    let canvasView = GirokCanvasView()
    let backgroundPatternView: BackgroundPatternView
    var blockOverlayHostView: UIHostingController<BlockOverlayView>?

    // MARK: - Private

    private let backgroundScrollView = UIScrollView()
    private let canvasContentView = UIView()
    private let canvasContentSize: CGSize
    private var viewModel: CanvasViewModel?
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
        // Cancel touches so the system doesn't show the PencilKit edit menu
        // (e.g. "Select All / Insert Space") underneath our custom menu.
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

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

        // canvasContentView is the single zoom target for backgroundScrollView.
        // viewForZooming returns this view, so both backgroundPatternView and
        // blockHost.view scale together as one unit when syncBackground() assigns
        // backgroundScrollView.zoomScale = canvasView.zoomScale.
        canvasContentView.frame = CGRect(origin: .zero, size: canvasContentSize)
        canvasContentView.backgroundColor = .clear
        canvasContentView.isUserInteractionEnabled = false
        canvasContentView.clipsToBounds = false

        canvasContentView.addSubview(backgroundPatternView)
        backgroundScrollView.addSubview(canvasContentView)

        // index 0 — tiled background
        addSubview(backgroundScrollView)

        // index 1 — block overlay inside canvasContentView so it zooms with the background.
        // Touches reach it via CanvasHostView.hitTest which converts and forwards
        // directly, bypassing backgroundScrollView.isUserInteractionEnabled=false.
        if let viewModel = viewModel {
            let blockHost = UIHostingController(rootView: BlockOverlayView(viewModel: viewModel))
            blockHost.view.backgroundColor = .clear
            blockHost.view.isUserInteractionEnabled = true
            blockHost.view.clipsToBounds = false
            blockHost.view.frame = CGRect(origin: .zero, size: canvasContentSize)
            canvasContentView.addSubview(blockHost.view)
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
        canvasView.addGestureRecognizer(textTapRecognizer)
        canvasView.addGestureRecognizer(canvasLongPressRecognizer)

        // Initial viewport is applied in layoutSubviews once real bounds exist.
    }

    // Tracks whether the viewport has been centered for the first time.
    // Cannot use contentOffset == .zero as the sentinel because setupViews()
    // already writes a non-zero value before the real bounds are known.
    private var didApplyInitialOffset = false

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-center once the view receives its real bounds for the first time.
        // setupViews() sets contentOffset based on zero bounds, so we must
        // recompute and reapply here — and keep the two scroll views in sync.
        if !didApplyInitialOffset && bounds.width > 0 {
            didApplyInitialOffset = true
            if let state = viewModel?.restoredViewport {
                let clampedScale = max(canvasView.minimumZoomScale, min(state.scale, canvasView.maximumZoomScale))
                canvasView.zoomScale = clampedScale
                let restoredOffset = CGPoint(x: state.offsetX, y: state.offsetY)
                canvasView.contentOffset = restoredOffset
                backgroundScrollView.zoomScale = clampedScale
                backgroundScrollView.contentOffset = restoredOffset
                viewModel?.finalizeViewport(
                    offset: CGSize(width: restoredOffset.x, height: restoredOffset.y),
                    scale: clampedScale
                )
            } else {
                let initialOffset = CGPoint(
                    x: (canvasContentSize.width  - bounds.width)  / 2,
                    y: (canvasContentSize.height - bounds.height) / 2
                )
                canvasView.contentOffset = initialOffset
                backgroundScrollView.contentOffset = initialOffset
                viewModel?.finalizeViewport(
                    offset: CGSize(width: initialOffset.x, height: initialOffset.y),
                    scale: canvasView.zoomScale
                )
            }
        }
        updateCenteringInsets()
    }

    // MARK: - UIScrollViewDelegate (for backgroundScrollView only)

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // Return canvasContentView so both backgroundPatternView and blockHost.view
        // zoom together as one unit when syncBackground() assigns zoomScale.
        return canvasContentView
    }

    // MARK: - Sync

    /// Mirrors PKCanvasView's scroll position and zoom to the background scroll view.
    /// Two property assignments — no frame changes, no tile invalidation.
    func syncBackground() {
        if backgroundScrollView.contentOffset != canvasView.contentOffset {
            backgroundScrollView.contentOffset = canvasView.contentOffset
        }
        if backgroundScrollView.zoomScale != canvasView.zoomScale {
            backgroundScrollView.zoomScale = canvasView.zoomScale
        }
        updateCenteringInsets()
        // No syncOverlay() — blockHost.view is inside backgroundScrollView
        // and moves automatically when contentOffset/zoomScale are synced.
    }
    
    private func updateCenteringInsets() {
        if viewModel?.notebook?.canvasType == "fixed" {
            let offsetX = max(0, (bounds.width - canvasContentSize.width * canvasView.zoomScale) / 2)
            let offsetY = max(0, (bounds.height - canvasContentSize.height * canvasView.zoomScale) / 2)
            let insets = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
            if canvasView.contentInset != insets {
                canvasView.contentInset = insets
            }
            if backgroundScrollView.contentInset != insets {
                backgroundScrollView.contentInset = insets
            }
        }
    }

    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let blockView = blockOverlayHostView?.view {
            let blockPoint = self.convert(point, to: blockView)
            if let hit = blockView.hitTest(blockPoint, with: event) {
                // Forward only real overlay subviews (text blocks, handles, editor).
                // Let empty-space touches fall through so the canvas can pan/zoom.
                if hit !== blockView {
                    return hit
                }
            }
            if isInteractiveOverlayPoint(blockPoint) {
                return blockView
            }
        }
        return super.hitTest(point, with: event)
    }

    @objc private func handleCanvasTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let viewModel else { return }
        guard viewModel.selectedTool == .text || viewModel.selectedTool == .image else { return }

        // Convert the tap to the block overlay's coordinate space.
        // This automatically accounts for scroll + zoom transforms and avoids
        // edge cases with contentInset/contentOffset math.
        let hostPoint = recognizer.location(in: self)
        if let blockView = blockOverlayHostView?.view {
            let canvasPoint = self.convert(hostPoint, to: blockView)
            if viewModel.selectedTool == .text {
                viewModel.handleTextToolCanvasTap(at: canvasPoint)
            } else {
                viewModel.beginImageInsertion(at: canvasPoint)
            }
        } else {
            // Fallback to canvas view space (should not happen in normal operation).
            let location = recognizer.location(in: canvasView)
            let canvasPoint = CGPoint(
                x: (location.x + canvasView.contentOffset.x) / canvasView.zoomScale,
                y: (location.y + canvasView.contentOffset.y) / canvasView.zoomScale
            )
            if viewModel.selectedTool == .text {
                viewModel.handleTextToolCanvasTap(at: canvasPoint)
            } else {
                viewModel.beginImageInsertion(at: canvasPoint)
            }
        }
    }

    @objc private func handleCanvasLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let viewModel else { return }
        // Do not interrupt lasso / region capture modes
        guard !viewModel.isLassoSelectionActive, !viewModel.isRegionCaptureMode else { return }

        // The system edit menu (UIEditMenuInteraction on iOS 16+) is already
        // suppressed via canPerformAction(_:withSender:) and interaction stripping,
        // so no explicit menu dismissal is needed here before showing our own menu.

        let hostPoint = recognizer.location(in: self)
        if let blockView = blockOverlayHostView?.view {
            let canvasPoint = self.convert(hostPoint, to: blockView)
            viewModel.showCanvasContextMenu(at: canvasPoint)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === textTapRecognizer || gestureRecognizer === canvasLongPressRecognizer else {
            return true
        }
        guard let blockView = blockOverlayHostView?.view else { return true }

        let pointInBlock = touch.location(in: blockView)
        if isInteractiveOverlayPoint(pointInBlock) {
            return false
        }
        if let hit = blockView.hitTest(pointInBlock, with: nil), hit !== blockView {
            // Touch landed on a real overlay subview (textbox, editor, handle, etc).
            // Let that view own the interaction; canvas gestures should ignore it.
            return false
        }
        return true
    }

    private func isInteractiveOverlayPoint(_ pointInBlock: CGPoint) -> Bool {
        guard let viewModel else { return false }
        for element in viewModel.currentPage.elements.reversed() {
            let width = CGFloat(element.width ?? 200)
            let height = CGFloat(element.height ?? 200)
            var rect = CGRect(x: element.positionX, y: element.positionY, width: width, height: height)

            if viewModel.selectedElementIds.contains(element.id) {
                if element.type == "text" {
                    rect = rect.insetBy(dx: -14, dy: -16)
                    rect.origin.y -= 58
                    rect.size.height += 74
                } else {
                    rect = rect.insetBy(dx: -18, dy: -18)
                    rect.origin.y -= 58
                    rect.size.height += 76
                }
            }

            if rect.contains(pointInBlock) {
                return true
            }
        }
        return false
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
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = UIColor(hex: hex)
            // If the saved hex is the default dark gray "#0F0F0E", map it to the adaptive gBackground token
            // so that it turns white in light mode. Otherwise use the specific color.
            hostView.backgroundPatternView.pageBackgroundColor = hex.uppercased() == "#0F0F0E" ? .gBackground : color
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
            viewModel.setViewportScrollView(canvasView)
        }

        return hostView
    }

    func updateUIView(_ hostView: CanvasHostView, context: Context) {
        let canvasView = hostView.canvasView
        viewModel.setCanvasViewSizeIfNeeded(hostView.bounds.size)

        // Only rebuild PKTool when tool-related properties actually changed
        let newTool = currentPKTool()
        if !toolsEqual(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }

        let isBlockTool = viewModel.selectedTool == .image || viewModel.selectedTool == .text
        let isLassoTool = viewModel.selectedTool == .lasso
        if isBlockTool {
            canvasView.isUserInteractionEnabled = true
            canvasView.drawingGestureRecognizer.isEnabled = false
            // Force pencil-only while block tools are active so finger taps don't
            // trigger PencilKit's edit menu. Pan/zoom still works via scrolling.
            if canvasView.drawingPolicy != .pencilOnly {
                canvasView.drawingPolicy = .pencilOnly
            }
            // Allow one-finger drag for moving/resizing blocks; pan the canvas with two fingers.
            canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
        } else if isLassoTool {
            // Lasso is Apple Pencil only (handled by CustomLassoGestureView). Disable drawing so Pencil doesn't ink.
            canvasView.isUserInteractionEnabled = true
            canvasView.drawingGestureRecognizer.isEnabled = false
            // Allow finger panning with one finger while lasso is selected.
            canvasView.panGestureRecognizer.minimumNumberOfTouches = 1
        } else {
            canvasView.isUserInteractionEnabled = true
            canvasView.drawingGestureRecognizer.isEnabled = true
            let newPolicy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
            if canvasView.drawingPolicy != newPolicy {
                canvasView.drawingPolicy = newPolicy
            }
            canvasView.panGestureRecognizer.minimumNumberOfTouches = 1
        }

        // Sync background pattern when it changes
        if hostView.backgroundPatternView.pattern != viewModel.backgroundPattern {
            hostView.backgroundPatternView.pattern = viewModel.backgroundPattern
        }
        if let hex = viewModel.notebook?.backgroundColorHex {
            let color = hex.uppercased() == "#0F0F0E" ? .gBackground : UIColor(hex: hex)
            if hostView.backgroundPatternView.pageBackgroundColor != color {
                hostView.backgroundPatternView.pageBackgroundColor = color
            }
        }

        // Sync drawing data when page changes (detect by comparing index or ID)
        if context.coordinator.currentPageIndex != viewModel.currentPageIndex ||
            context.coordinator.currentPageId != viewModel.currentPage.id ||
            viewModel.forceDrawingUpdate {
            context.coordinator.currentPageIndex = viewModel.currentPageIndex
            context.coordinator.currentPageId = viewModel.currentPage.id
            let pageDrawing = viewModel.currentDrawing
            
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

            let fromPencil = lastStrokeFromPencil

            Task { @MainActor in
                self.viewModel.drawingDidChange(canvasView.drawing, fromPencil: fromPencil)
            }
        }
        
        // MARK: UIScrollViewDelegate (via PKCanvasViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
            viewModel.updateViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            hostView?.syncBackground()
            viewModel.updateViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            viewModel.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            viewModel.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scrollView.zoomScale
            )
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            hostView?.syncBackground()
            viewModel.finalizeViewport(
                offset: CGSize(width: scrollView.contentOffset.x, height: scrollView.contentOffset.y),
                scale: scale
            )
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

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // MARK: - Programmatic Updates

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
            // Do not auto-dismiss the keyboard while using the text tool, otherwise
            // finger taps to select/edit text blocks will immediately close it.
            if coordinator?.viewModel.selectedTool != .text {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
            state = .failed
        }
    }
}
