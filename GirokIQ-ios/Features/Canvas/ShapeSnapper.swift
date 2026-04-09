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
        
        if let rect = recognizeRect(points) {
            return .rect(corners: rect)
        } else if let circle = recognizeCircle(points) {
            return .circle(center: circle.center, radius: circle.radius)
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
        guard let f = p.first, let l = p.last else { return nil }
        
        // For a closed shape like a rectangle, the start and end points should be relatively close
        let startEndDist = hypot(l.x - f.x, l.y - f.y)
        
        let xs = p.map { $0.x }, ys = p.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        guard w > 30, h > 30 else { return nil }
        
        // The start and end points must be closer together than the overall size of the shape
        guard startEndDist < max(w, h) * 0.4 else { return nil }
        
        let corners = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                       CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
        
        // Count how many points lie roughly along the 4 edges of the bounding box
        let edgeTolerance = max(w, h) * 0.15
        var pointsOnEdge = 0
        
        for pt in p {
            let onTop = abs(pt.y - minY) < edgeTolerance
            let onBottom = abs(pt.y - maxY) < edgeTolerance
            let onLeft = abs(pt.x - minX) < edgeTolerance
            let onRight = abs(pt.x - maxX) < edgeTolerance
            
            if onTop || onBottom || onLeft || onRight {
                pointsOnEdge += 1
            }
        }
        
        // If a high percentage of the drawn points are near the bounding box edges, it's a rectangle
        let edgeDensity = CGFloat(pointsOnEdge) / CGFloat(p.count)
        
        if edgeDensity > 0.85 {
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
    
    // MARK: - Shape Straightening
    
    /// Straightens lines (perfectly horizontal or vertical) and passes through perfectly recognized circles/rectangles.
    static func straightenShape(_ shape: ShapeType) -> ShapeType {
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
                s.y = avgY
                e.y = avgY
            } 
            // Snap to vertical (close to 90 degrees)
            else if abs(angle - 90) < 15 {
                let avgX = (s.x + e.x) / 2
                s.x = avgX
                e.x = avgX
            }
            // Diagonal lines remain unchanged (perfectly straight between start and end)
            
            return .line(start: s, end: e)
            
        case .rect(let corners):
            return shape // recognizeRect already generates a perfect axis-aligned rectangle
            
        case .circle(let center, let radius):
            return shape // recognizeCircle already generates a perfect circle
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
