import UIKit
import PencilKit

/// A gesture recognizer that runs concurrently with PKCanvasView to detect
/// when the user holds their pencil/finger still at the end of a stroke.
final class ShapeSnapGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var canvasView: PKCanvasView?
    var onShapeRecognized: ((ShapeSnapper.ShapeType, PKStroke) -> Bool)?
    var onShapeUpdated: ((ShapeSnapper.ShapeType) -> Void)?
    var onShapeCommitted: (() -> Void)?
    
    private var touchPoints: [CGPoint] = []
    private var snapTimer: Timer?
    private var isSnapped = false
    private var baseInk: PKInk?
    private var baseSize: CGSize = .zero
    private var activeTouch: UITouch?
    private var currentShape: ShapeSnapper.ShapeType?
    private var initialSnapPoint: CGPoint?
    private var timerStartLocation: CGPoint?
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        self.delegate = self
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let canvas = canvasView else { return }
        
        activeTouch = touch
        touchPoints = [touch.location(in: canvas)]
        isSnapped = false
        currentShape = nil
        initialSnapPoint = nil
        
        // Capture ink properties from current tool
        if let inkingTool = canvas.tool as? PKInkingTool {
            baseInk = PKInk(inkingTool.inkType, color: inkingTool.color)
            baseSize = CGSize(width: inkingTool.width, height: inkingTool.width)
        }
        
        startTimer(at: touchPoints[0])
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, touch == activeTouch, let canvas = canvasView else { return }
        
        let loc = touch.location(in: canvas)
        
        if isSnapped, let shape = currentShape, let initial = initialSnapPoint {
            // Update shape size/rotation based on drag
            let dx = loc.x - initial.x
            let dy = loc.y - initial.y
            
            let updatedShape = updateShape(shape, dx: dx, dy: dy, currentLoc: loc)
            currentShape = updatedShape
            onShapeUpdated?(updatedShape)
            return
        }
        
        touchPoints.append(loc)
        
        // Restart timer if moved significantly from where the timer was last started
        if let startLoc = timerStartLocation {
            let dist = hypot(loc.x - startLoc.x, loc.y - startLoc.y)
            if dist > 8.0 { // Allow 8 points of jitter without cancelling the hold
                startTimer(at: loc)
            }
        } else {
            startTimer(at: loc)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        cancelTimer()
        if isSnapped {
            onShapeCommitted?()
        }
        resetState()
        state = .failed
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        cancelTimer()
        if isSnapped {
            onShapeCommitted?()
        }
        resetState()
        state = .failed
    }
    
    private func startTimer(at loc: CGPoint) {
        cancelTimer()
        timerStartLocation = loc
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.evaluateSnap()
        }
    }
    
    private func cancelTimer() {
        snapTimer?.invalidate()
        snapTimer = nil
    }
    
    private func resetState() {
        touchPoints.removeAll()
        activeTouch = nil
        isSnapped = false
        currentShape = nil
        initialSnapPoint = nil
    }
    
    private func evaluateSnap() {
        guard !isSnapped, touchPoints.count > 3 else { return }
        
        if let shape = ShapeSnapper.recognizeShape(from: touchPoints) {
            isSnapped = true
            currentShape = shape
            initialSnapPoint = touchPoints.last
            
            // Create a dummy PKStroke to hold the ink info
            let dummyPoint = PKStrokePoint(location: .zero, timeOffset: 0, size: baseSize, opacity: 1, force: 1, azimuth: 0, altitude: 0)
            let dummyPath = PKStrokePath(controlPoints: [dummyPoint], creationDate: Date())
            let stroke = PKStroke(ink: baseInk ?? PKInk(.pen, color: .black), path: dummyPath)
            
            let handled = onShapeRecognized?(shape, stroke) ?? false
            if handled {
                // Cancel PKCanvasView's live stroke by temporarily swapping tools.
                // This safely forces PencilKit to commit the messy stroke without crashing its internal gesture states.
                if let canvas = canvasView {
                    let currentTool = canvas.tool
                    canvas.tool = PKEraserTool(.vector)
                    canvas.tool = currentTool
                }
            } else {
                isSnapped = false
                currentShape = nil
                initialSnapPoint = nil
            }
        } else {
            // If the shape wasn't recognized, but the user is still holding still,
            // try evaluating again shortly in case they added more points
            snapTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                self?.evaluateSnap()
            }
        }
    }
    
    private func updateShape(_ shape: ShapeSnapper.ShapeType, dx: CGFloat, dy: CGFloat, currentLoc: CGPoint) -> ShapeSnapper.ShapeType {
        switch shape {
        case .line(let start, _):
            return .line(start: start, end: currentLoc)
        case .circle(let center, let radius):
            let newRadius = hypot(currentLoc.x - center.x, currentLoc.y - center.y)
            return .circle(center: center, radius: newRadius)
        case .rect(let corners):
            // Simple resize: adjust the bottom-right corner and recompute
            let minX = min(corners[0].x, currentLoc.x)
            let minY = min(corners[0].y, currentLoc.y)
            let maxX = max(corners[0].x, currentLoc.x)
            let maxY = max(corners[0].y, currentLoc.y)
            
            return .rect(corners: [
                CGPoint(x: minX, y: minY),
                CGPoint(x: maxX, y: minY),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: minX, y: maxY)
            ])
        }
    }
}
