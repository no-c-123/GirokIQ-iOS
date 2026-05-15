import SwiftUI
import UIKit

struct CustomLassoGestureView: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    func makeUIView(context: Context) -> LassoDrawingView {
        let v = LassoDrawingView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        v.isMultipleTouchEnabled = true
        v.viewModel = viewModel
        return v
    }

    func updateUIView(_ uiView: LassoDrawingView, context: Context) {
        uiView.isUserInteractionEnabled = viewModel.selectedTool == .lasso
        // Clear the drawn path if the tool changed away from lasso
        if viewModel.selectedTool != .lasso {
            uiView.clearPath()
        }
    }
}

final class LassoDrawingView: UIView {
    weak var viewModel: CanvasViewModel?

    private var path: UIBezierPath = UIBezierPath()
    private var points: [CGPoint] = []
    private var fadeTask: DispatchWorkItem?
    private var activeTouch: UITouch?
    private var touchCount: Int = 0

    func clearPath() {
        fadeTask?.cancel()
        path = UIBezierPath()
        points = []
        activeTouch = nil
        touchCount = 0
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If toolbar is hidden and selection is not active, a quick tap should restore it.
        // We detect this by checking if isLassoSelectionActive is false AND it's a single touch.
        // We still proceed with lasso path — the toolbar shows as a side effect.
        if touches.count == 1 {
            Task { @MainActor [weak self] in
                self?.viewModel?.showToolbar()
            }
        }

        touchCount = (event?.allTouches?.count ?? touches.count)
        
        // If two or more fingers — pass through to PKCanvasView for pan/zoom
        if touchCount >= 2 {
            // Cancel any in-progress lasso draw
            if activeTouch != nil { clearPath() }
            super.touchesBegan(touches, with: event)
            return
        }
        
        let requiresPencil = viewModel?.palmRejectionEnabled ?? true

        if activeTouch == nil {
            for touch in touches {
                if requiresPencil && touch.type != .pencil { continue }
                activeTouch = touch
                break
            }
        }

        guard let touch = activeTouch, touches.contains(touch) else {
            super.touchesBegan(touches, with: event)
            return
        }

        fadeTask?.cancel()

        viewModel?.clearLassoSelection()

        path = UIBezierPath()
        points = []

        let pt = touch.location(in: self)
        path.move(to: pt)
        points.append(pt)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Update touch count — if user adds a second finger, abort lasso
        let current = event?.allTouches?.count ?? touches.count
        if current >= 2 {
            if activeTouch != nil { clearPath() }
            super.touchesMoved(touches, with: event)
            return
        }
        
        guard let touch = activeTouch, touches.contains(touch) else {
            super.touchesMoved(touches, with: event)
            return
        }
        
        let pt = touch.location(in: self)
        path.addLine(to: pt)
        points.append(pt)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            super.touchesEnded(touches, with: event)
            return
        }
        activeTouch = nil
        touchCount = 0
        
        path.close()
        setNeedsDisplay()

        if !points.isEmpty {
            let xs = points.map { $0.x }, ys = points.map { $0.y }
            print("[Lasso] Screen polygon: \(points.count) pts bbox=(\(xs.min()!),\(ys.min()!),\(xs.max()!-xs.min()!),\(ys.max()!-ys.min()!))")
        }

        viewModel?.commitLassoSelection(polygon: points)

        let task = DispatchWorkItem { [weak self] in
            self?.path = UIBezierPath()
            self?.points = []
            self?.setNeedsDisplay()
        }
        fadeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            super.touchesCancelled(touches, with: event)
            return
        }
        activeTouch = nil
        touchCount = 0
        clearPath()
    }

    override func draw(_ rect: CGRect) {
        guard !path.isEmpty else { return }

        let gold = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 0.9)
        
        UIColor.clear.setFill()
        path.fill()

        gold.setStroke()
        path.lineWidth = 2.0
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard viewModel?.selectedTool == .lasso else { return nil }
        
        // Allow two-finger events to pass through for pan/zoom
        if let touches = event?.allTouches, touches.count >= 2 { return nil }
        
        return super.hitTest(point, with: event)
    }
}