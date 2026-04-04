import Foundation
import CoreGraphics
import PencilKit

final class ShapeSnapper {
    
    enum ShapeType {
        case line(start: CGPoint, end: CGPoint)
        case rect(corners: [CGPoint])
        case circle(center: CGPoint, radius: CGFloat)
    }
    
    /// Analyzes a set of points and returns the recognized shape, if any.
    static func recognizeShape(from points: [CGPoint]) -> ShapeType? {
        guard points.count > 2 else { return nil }
        
        if let circle = recognizeCircle(points) {
            return .circle(center: circle.center, radius: circle.radius)
        } else if let rect = recognizeRect(points) {
            return .rect(corners: rect)
        } else if let line = recognizeLine(points) {
            return .line(start: line.start, end: line.end)
        }
        
        return nil
    }
    
    // MARK: - Recognition Algorithms
    
    private static func recognizeLine(_ p: [CGPoint]) -> (start: CGPoint, end: CGPoint)? {
        guard let f = p.first, let l = p.last else { return nil }
        let direct = hypot(l.x - f.x, l.y - f.y)
        let path = zip(p, p.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        if direct > 20 && path / direct < 1.25 {
            return (f, l)
        }
        return nil
    }
    
    private static func recognizeRect(_ p: [CGPoint]) -> [CGPoint]? {
        let xs = p.map { $0.x }, ys = p.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        guard w > 30, h > 30 else { return nil }
        
        let corners = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                       CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
        
        let matchedCorners = corners.filter { c in
            p.contains { hypot($0.x - c.x, $0.y - c.y) < max(w, h) * 0.25 }
        }
        
        if matchedCorners.count >= 3 {
            return corners
        }
        return nil
    }
    
    private static func recognizeCircle(_ p: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        let cx = p.map { $0.x }.reduce(0, +) / CGFloat(p.count)
        let cy = p.map { $0.y }.reduce(0, +) / CGFloat(p.count)
        let radii = p.map { hypot($0.x - cx, $0.y - cy) }
        let avg = radii.reduce(0, +) / CGFloat(radii.count)
        let variance = radii.map { pow($0 - avg, 2) }.reduce(0, +) / CGFloat(radii.count)
        
        if variance < (avg * avg * 0.15) && avg > 15 {
            return (CGPoint(x: cx, y: cy), avg)
        }
        return nil
    }
    
    // MARK: - Grid Snapping
    
    static func snapToGrid(shape: ShapeType, gridSize: CGFloat = 28.0) -> ShapeType {
        switch shape {
        case .line(let start, let end):
            var s = start
            var e = end
            
            // Check for horizontal/vertical snapping first
            let dx = abs(e.x - s.x)
            let dy = abs(e.y - s.y)
            let angle = atan2(dy, dx) * 180 / .pi
            
            // Snap to horizontal (close to 0 or 180 degrees)
            if angle < 15 || angle > 165 {
                let avgY = (s.y + e.y) / 2
                let snappedY = round(avgY / gridSize) * gridSize
                s.y = snappedY
                e.y = snappedY
                s.x = round(s.x / gridSize) * gridSize
                e.x = round(e.x / gridSize) * gridSize
            } 
            // Snap to vertical (close to 90 degrees)
            else if abs(angle - 90) < 15 {
                let avgX = (s.x + e.x) / 2
                let snappedX = round(avgX / gridSize) * gridSize
                s.x = snappedX
                e.x = snappedX
                s.y = round(s.y / gridSize) * gridSize
                e.y = round(e.y / gridSize) * gridSize
            } 
            // Diagonal, snap start and end points to grid
            else {
                s.x = round(s.x / gridSize) * gridSize
                s.y = round(s.y / gridSize) * gridSize
                e.x = round(e.x / gridSize) * gridSize
                e.y = round(e.y / gridSize) * gridSize
            }
            
            return .line(start: s, end: e)
            
        case .rect(let corners):
            guard corners.count == 4 else { return shape }
            let minX = round(corners[0].x / gridSize) * gridSize
            let minY = round(corners[0].y / gridSize) * gridSize
            let maxX = round(corners[2].x / gridSize) * gridSize
            let maxY = round(corners[2].y / gridSize) * gridSize
            
            return .rect(corners: [
                CGPoint(x: minX, y: minY),
                CGPoint(x: maxX, y: minY),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: minX, y: maxY)
            ])
            
        case .circle(let center, let radius):
            let snappedCx = round(center.x / gridSize) * gridSize
            let snappedCy = round(center.y / gridSize) * gridSize
            let snappedR = max(gridSize, round(radius / gridSize) * gridSize)
            return .circle(center: CGPoint(x: snappedCx, y: snappedCy), radius: snappedR)
        }
    }
    
    // MARK: - PKStroke Generation
    
    static func createStroke(from shape: ShapeType, originalStroke: PKStroke) -> PKStroke {
        var points: [PKStrokePoint] = []
        let creationDate = Date()
        
        let baseInk = originalStroke.ink
        let baseSize = originalStroke.path.first?.size ?? CGSize(width: 4, height: 4)
        
        let makePoint = { (pt: CGPoint) -> PKStrokePoint in
            PKStrokePoint(location: pt, timeOffset: 0, size: baseSize, opacity: 1.0, force: 1.0, azimuth: 0, altitude: .pi / 2)
        }
        
        switch shape {
        case .line(let start, let end):
            // Generate multiple points along the line for a smooth stroke path
            let steps = 10
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let pt = CGPoint(x: start.x + (end.x - start.x) * t,
                                 y: start.y + (end.y - start.y) * t)
                points.append(makePoint(pt))
            }
            
        case .rect(let corners):
            let allCorners = corners + [corners[0]] // close the loop
            for i in 0..<corners.count {
                let start = allCorners[i]
                let end = allCorners[i+1]
                let steps = 10
                for j in 0...steps {
                    let t = CGFloat(j) / CGFloat(steps)
                    let pt = CGPoint(x: start.x + (end.x - start.x) * t,
                                     y: start.y + (end.y - start.y) * t)
                    points.append(makePoint(pt))
                }
            }
            
        case .circle(let center, let radius):
            let steps = 60
            for i in 0...steps {
                let angle = CGFloat(i) / CGFloat(steps) * .pi * 2
                let pt = CGPoint(x: center.x + radius * cos(angle),
                                 y: center.y + radius * sin(angle))
                points.append(makePoint(pt))
            }
        }
        
        let path = PKStrokePath(controlPoints: points, creationDate: creationDate)
        return PKStroke(ink: baseInk, path: path)
    }
}
