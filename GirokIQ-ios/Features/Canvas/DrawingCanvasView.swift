import SwiftUI
import UIKit

// MARK: - SwiftUI Bridge

struct DrawingCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> CanvasUIView {
        let view = CanvasUIView()
        view.coordinator = context.coordinator
        view.viewModel = viewModel
        context.coordinator.canvasView = view

        // Apple Pencil double-tap
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        view.addInteraction(pencilInteraction)

        // Two-finger pan
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        // Pinch to zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        uiView.backgroundPattern = viewModel.backgroundPattern
        uiView.setNeedsDisplay()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var viewModel: CanvasViewModel
        weak var canvasView: CanvasUIView?

        var currentStroke: Stroke?
        var lassoPoints: [CGPoint] = []
        var lastPanTranslation: CGPoint = .zero
        var pinchStartScale: CGFloat = 1.0
        var snapTimer: Timer?
        var strokeForSnap: Stroke?

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        // MARK: Apple Pencil Double Tap

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            Task { @MainActor in
                self.viewModel.selectTool(self.viewModel.selectedTool == .eraser ? .pen : .eraser)
                HapticEngine.light()
            }
        }

        // MARK: Gestures

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = canvasView else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                lastPanTranslation = .zero
            case .changed:
                let delta = CGSize(
                    width: translation.x - lastPanTranslation.x,
                    height: translation.y - lastPanTranslation.y
                )
                Task { @MainActor in
                    self.viewModel.canvasOffset = CGSize(
                        width: self.viewModel.canvasOffset.width + delta.width,
                        height: self.viewModel.canvasOffset.height + delta.height
                    )
                }
                lastPanTranslation = translation
                view.setNeedsDisplay()
            default: break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = canvasView else { return }
            switch gesture.state {
            case .began:
                pinchStartScale = viewModel.canvasScale
            case .changed:
                let newScale = (pinchStartScale * gesture.scale).clamped(to: 0.2...5.0)
                Task { @MainActor in self.viewModel.canvasScale = newScale }
                view.setNeedsDisplay()
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touch.type != .pencil
        }

        // MARK: Coordinate conversion

        func canvasPoint(from touch: UITouch, in view: UIView) -> CGPoint {
            let raw = touch.location(in: view)
            return CGPoint(
                x: (raw.x - viewModel.canvasOffset.width) / viewModel.canvasScale,
                y: (raw.y - viewModel.canvasOffset.height) / viewModel.canvasScale
            )
        }

        // MARK: Touch Handling

        func handleBegan(_ touch: UITouch, in view: UIView) {
            if viewModel.palmRejectionEnabled, touch.type != .pencil { return }
            let pt = canvasPoint(from: touch, in: view)

            switch viewModel.selectedTool {
            case .lasso:
                lassoPoints = [pt]
            case .eraser:
                eraseAt(pt)
            default:
                let stroke = Stroke(
                    color: viewModel.strokeColor,
                    width: viewModel.strokeWidth,
                    opacity: viewModel.strokeOpacity,
                    style: viewModel.strokeStyle,
                    tool: viewModel.selectedTool
                )
                stroke.points.append(makePoint(touch, at: pt))
                currentStroke = stroke
                strokeForSnap = stroke

                // Hold-to-snap: 1 second still hold triggers shape snap
                snapTimer?.invalidate()
                snapTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    guard let self, let s = self.strokeForSnap, s.points.count > 3 else { return }
                    self.applyShapeSnapping(to: s)
                    HapticEngine.medium()
                    Task { @MainActor in self.canvasView?.setNeedsDisplay() }
                }
            }
        }

        func handleMoved(_ touch: UITouch, in view: UIView) {
            if viewModel.palmRejectionEnabled, touch.type != .pencil { return }
            let pt = canvasPoint(from: touch, in: view)

            switch viewModel.selectedTool {
            case .lasso:
                lassoPoints.append(pt)
                canvasView?.setNeedsDisplay()
            case .eraser:
                eraseAt(pt)
            default:
                guard let stroke = currentStroke else { return }
                // If user keeps moving after 8 points, cancel snap (they're drawing, not holding)
                if stroke.points.count == 8 {
                    snapTimer?.invalidate()
                    snapTimer = nil
                    strokeForSnap = nil
                }
                stroke.points.append(makePoint(touch, at: pt))
                canvasView?.setNeedsDisplay()
            }
        }

        func handleEnded(_ touch: UITouch, in view: UIView) {
            snapTimer?.invalidate()
            snapTimer = nil
            strokeForSnap = nil

            if viewModel.selectedTool == .lasso {
                selectStrokesInLasso()
                lassoPoints = []
                canvasView?.setNeedsDisplay()
                return
            }

            guard let stroke = currentStroke, !stroke.points.isEmpty else { return }
            Task { @MainActor in
                self.viewModel.pages[self.viewModel.currentPageIndex].strokes.append(stroke)
            }
            currentStroke = nil
            canvasView?.setNeedsDisplay()
        }

        // MARK: Helpers

        private func makePoint(_ touch: UITouch, at pt: CGPoint) -> StrokePoint {
            let force: CGFloat = touch.type == .pencil && touch.maximumPossibleForce > 0
                ? touch.force / touch.maximumPossibleForce
                : 0.5
            return StrokePoint(location: pt, force: force,
                               azimuth: touch.type == .pencil ? touch.azimuthAngle(in: touch.view) : 0,
                               altitude: touch.altitudeAngle, timestamp: touch.timestamp)
        }

        private func eraseAt(_ pt: CGPoint) {
            let radius = viewModel.strokeWidth * 4
            Task { @MainActor in
                self.viewModel.currentPage.strokes.removeAll {
                    $0.points.contains { hypot($0.location.x - pt.x, $0.location.y - pt.y) < radius }
                }
            }
            canvasView?.setNeedsDisplay()
        }

        private func selectStrokesInLasso() {
            guard lassoPoints.count > 2 else { return }
            let polygonCopy = lassoPoints
            Task { @MainActor in
                self.viewModel.selectedStrokes = Set(self.viewModel.currentPage.strokes.compactMap { stroke in
                    let c = CGPoint(x: stroke.boundingRect.midX, y: stroke.boundingRect.midY)
                    return self.pointInPolygon(c, polygon: polygonCopy) ? stroke.id : nil
                })
            }
        }

        private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
            var inside = false
            var j = polygon.count - 1
            for i in 0..<polygon.count {
                let xi = polygon[i].x, yi = polygon[i].y
                let xj = polygon[j].x, yj = polygon[j].y
                if ((yi > point.y) != (yj > point.y)) &&
                    (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) { inside = !inside }
                j = i
            }
            return inside
        }

        // MARK: Shape Snapping

        func applyShapeSnapping(to stroke: Stroke) {
            let pts = stroke.points.map { $0.location }
            guard pts.count > 4 else { return }
            if isCircle(pts)      { snapToCircle(stroke) }
            else if isRect(pts)   { snapToRect(stroke) }
            else if isLine(pts)   { snapToLine(stroke) }
        }

        private func isLine(_ p: [CGPoint]) -> Bool {
            guard let f = p.first, let l = p.last else { return false }
            let direct = hypot(l.x - f.x, l.y - f.y)
            let path = zip(p, p.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            return direct > 20 && path / direct < 1.2
        }

        private func isRect(_ p: [CGPoint]) -> Bool {
            let xs = p.map { $0.x }, ys = p.map { $0.y }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return false }
            let w = maxX - minX, h = maxY - minY
            guard w > 30, h > 30 else { return false }
            let corners = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                           CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
            return corners.filter { c in p.contains { hypot($0.x - c.x, $0.y - c.y) < 50 } }.count >= 3
        }

        private func isCircle(_ p: [CGPoint]) -> Bool {
            let cx = p.map { $0.x }.reduce(0, +) / CGFloat(p.count)
            let cy = p.map { $0.y }.reduce(0, +) / CGFloat(p.count)
            let radii = p.map { hypot($0.x - cx, $0.y - cy) }
            let avg = radii.reduce(0, +) / CGFloat(radii.count)
            let variance = radii.map { pow($0 - avg, 2) }.reduce(0, +) / CGFloat(radii.count)
            return variance < 600 && avg > 15
        }

        private func snapToLine(_ stroke: Stroke) {
            guard let f = stroke.points.first, let l = stroke.points.last else { return }
            stroke.points = [f, l]
        }

        private func snapToRect(_ stroke: Stroke) {
            let xs = stroke.points.map { $0.location.x }, ys = stroke.points.map { $0.location.y }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let corners = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                           CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY),
                           CGPoint(x: minX, y: minY)]
            let ts = Date().timeIntervalSince1970
            stroke.points = corners.map {
                StrokePoint(location: $0, force: 1, azimuth: 0, altitude: 0, timestamp: ts)
            }
        }

        private func snapToCircle(_ stroke: Stroke) {
            let cx = stroke.points.map { $0.location.x }.reduce(0, +) / CGFloat(stroke.points.count)
            let cy = stroke.points.map { $0.location.y }.reduce(0, +) / CGFloat(stroke.points.count)
            let r  = stroke.points.map { hypot($0.location.x - cx, $0.location.y - cy) }.reduce(0, +) / CGFloat(stroke.points.count)
            stroke.points = (0...72).map { i in
                let a = CGFloat(i) / 72 * .pi * 2
                return StrokePoint(location: CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)),
                                   force: 1, azimuth: 0, altitude: 0, timestamp: Date().timeIntervalSince1970)
            }
        }
    }
}

// MARK: - CanvasUIView

final class CanvasUIView: UIView {
    weak var coordinator: DrawingCanvasView.Coordinator?
    var viewModel: CanvasViewModel?
    var backgroundPattern: BackgroundPattern = .dots { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .gBackground
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let vm = viewModel else { return }

        drawBackground(ctx: ctx, bounds: rect)

        ctx.saveGState()
        ctx.translateBy(x: vm.canvasOffset.width, y: vm.canvasOffset.height)
        ctx.scaleBy(x: vm.canvasScale, y: vm.canvasScale)

        for stroke in vm.currentPage.strokes where !stroke.isErased {
            render(stroke, ctx: ctx, selected: vm.selectedStrokes.contains(stroke.id), scale: vm.canvasScale)
        }
        if let live = coordinator?.currentStroke {
            render(live, ctx: ctx, selected: false, scale: vm.canvasScale)
        }

        ctx.restoreGState()

        if let lasso = coordinator?.lassoPoints, lasso.count > 1 {
            let screen = lasso.map { CGPoint(x: $0.x * vm.canvasScale + vm.canvasOffset.width,
                                             y: $0.y * vm.canvasScale + vm.canvasOffset.height) }
            drawLasso(screen, ctx: ctx)
        }
    }

    // MARK: Background

    private func drawBackground(ctx: CGContext, bounds: CGRect) {
        ctx.setFillColor(UIColor.gBackground.cgColor)
        ctx.fill(bounds)
        let spacing: CGFloat = 28
        ctx.setStrokeColor(UIColor.gGridLine.cgColor)
        ctx.setLineWidth(0.5)
        switch backgroundPattern {
        case .blank: break
        case .grid:
            var x: CGFloat = 0
            while x <= bounds.width { ctx.move(to: .init(x: x, y: 0)); ctx.addLine(to: .init(x: x, y: bounds.height)); x += spacing }
            var y: CGFloat = 0
            while y <= bounds.height { ctx.move(to: .init(x: 0, y: y)); ctx.addLine(to: .init(x: bounds.width, y: y)); y += spacing }
            ctx.strokePath()
        case .dots:
            ctx.setFillColor(UIColor.gDot.cgColor)
            var x: CGFloat = spacing
            while x < bounds.width {
                var y: CGFloat = spacing
                while y < bounds.height { ctx.fillEllipse(in: .init(x: x-1.2, y: y-1.2, width: 2.4, height: 2.4)); y += spacing }
                x += spacing
            }
        case .lines:
            var y: CGFloat = 0
            while y <= bounds.height { ctx.move(to: .init(x: 0, y: y)); ctx.addLine(to: .init(x: bounds.width, y: y)); y += spacing }
            ctx.strokePath()
        case .isometric:
            let h = spacing * 0.866
            var y: CGFloat = -bounds.height
            while y <= bounds.height * 2 {
                ctx.move(to: .init(x: 0, y: y)); ctx.addLine(to: .init(x: bounds.width, y: y + bounds.width * 0.577))
                ctx.move(to: .init(x: 0, y: y)); ctx.addLine(to: .init(x: bounds.width, y: y - bounds.width * 0.577))
                y += h
            }
            ctx.strokePath()
        }
    }

    // MARK: Stroke Rendering

    private func render(_ stroke: Stroke, ctx: CGContext, selected: Bool, scale: CGFloat) {
        guard !stroke.points.isEmpty else { return }
        let color = UIColor(stroke.color)

        if selected {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor.gSelectionHalo.cgColor)
            ctx.setLineWidth((stroke.width + 8) / scale)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            buildPath(stroke.points.map { $0.location }, ctx: ctx)
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        switch stroke.tool {
        case .marker:
            ctx.setAlpha(0.45)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(stroke.width / scale)
            ctx.setLineCap(.square); ctx.setLineJoin(.round)
            buildPath(stroke.points.map { $0.location }, ctx: ctx)
            ctx.strokePath()

        case .pencil:
            ctx.setAlpha(stroke.opacity * 0.75)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(0.8, stroke.width * 0.6) / scale)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            buildPath(stroke.points.map { $0.location }, ctx: ctx)
            ctx.strokePath()

        default:
            // Ball pen — pressure-varying width, smooth quad curves
            ctx.setAlpha(stroke.opacity)
            let pts = stroke.points
            if pts.count == 1 {
                let r = stroke.width / 2 / scale
                let p = pts[0].location
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            } else {
                for i in 1..<pts.count {
                    let from = pts[i - 1], to = pts[i]
                    let pressure = (from.force + to.force) / 2
                    // Subtle pressure: 0.75x–1.25x base width
                    let w = max(0.5, stroke.width * (0.75 + pressure * 0.5)) / scale
                    ctx.setLineWidth(w)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.setStrokeColor(color.cgColor)
                    ctx.beginPath()
                    ctx.move(to: from.location)
                    if i < pts.count - 1 {
                        let next = pts[i + 1]
                        let mid = CGPoint(x: (to.location.x + next.location.x) / 2,
                                          y: (to.location.y + next.location.y) / 2)
                        ctx.addQuadCurve(to: mid, control: to.location)
                    } else {
                        ctx.addLine(to: to.location)
                    }
                    ctx.strokePath()
                }
            }
        }
        ctx.restoreGState()
    }

    private func buildPath(_ pts: [CGPoint], ctx: CGContext) {
        guard pts.count > 0 else { return }
        ctx.beginPath()
        ctx.move(to: pts[0])
        guard pts.count > 1 else { return }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i+1].x) / 2, y: (pts[i].y + pts[i+1].y) / 2)
            ctx.addQuadCurve(to: mid, control: pts[i])
        }
        ctx.addLine(to: pts[pts.count - 1])
    }

    private func drawLasso(_ pts: [CGPoint], ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.gLasso.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setAlpha(0.85)
        ctx.beginPath()
        ctx.move(to: pts[0])
        pts.dropFirst().forEach { ctx.addLine(to: $0) }
        if pts.count > 2 { ctx.closePath() }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Touch Events

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        coordinator?.handleBegan(t, in: self); setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        (event?.coalescedTouches(for: t) ?? [t]).forEach { coordinator?.handleMoved($0, in: self) }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        coordinator?.handleEnded(t, in: self); setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.currentStroke = nil
        coordinator?.snapTimer?.invalidate()
        setNeedsDisplay()
    }
}


