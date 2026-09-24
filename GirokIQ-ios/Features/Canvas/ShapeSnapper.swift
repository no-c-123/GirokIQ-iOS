import Foundation
import CoreGraphics
import PencilKit

/// Recognises hand-drawn shapes and turns them into clean geometry.
///
/// The recogniser is confidence-based so casual handwriting is left untouched:
/// callers snap only when confidence is high, or when the user signals intent by
/// holding the pencil still at the end of the stroke (see `endHoldDuration`).
final class ShapeSnapper {

    enum ShapeType {
        case line(start: CGPoint, end: CGPoint)
        case triangle(corners: [CGPoint])
        case rect(corners: [CGPoint])
        case circle(center: CGPoint, radius: CGFloat)
        case ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat)

        var isClosed: Bool {
            if case .line = self { return false }
            return true
        }
    }

    struct Recognition {
        let shape: ShapeType
        /// 0...1 — how confidently the stroke matches the shape.
        let confidence: CGFloat
    }

    // MARK: - Public Recognition

    /// Analyses a set of points and returns the best matching shape with a
    /// confidence score, or `nil` if the stroke doesn't resemble a shape.
    static func recognize(from rawPoints: [CGPoint]) -> Recognition? {
        let points = dedupe(rawPoints, minSpacing: 1.0)
        guard points.count >= 4, let first = points.first, let last = points.last else { return nil }

        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        let maxDim = max(w, h)
        // Too small — almost certainly handwriting or a stray dot.
        guard maxDim > 24 else { return nil }

        let pathLen = polylineLength(points)
        guard pathLen > 1 else { return nil }
        let startEndDist = distance(first, last)

        var candidates: [Recognition] = []

        // Closed if the trace returns near its start relative to the overall size.
        let isClosed = startEndDist < maxDim * 0.28

        if !isClosed {
            // Open trace — only a straight line is plausible.
            let straightness = startEndDist / pathLen
            let conf = clamp((straightness - 0.85) / 0.13)
            if conf > 0 && startEndDist > 24 {
                candidates.append(Recognition(shape: .line(start: first, end: last), confidence: conf))
            }
        } else {
            let eps = max(6, maxDim * 0.06)
            var verts = rdp(points, epsilon: eps)
            // Drop the closing vertex when it lands on the start vertex.
            if verts.count > 1, distance(verts.first!, verts.last!) < eps * 1.6 {
                verts.removeLast()
            }
            let corners = verts.count

            let center = CGPoint(x: xs.reduce(0, +) / CGFloat(points.count),
                                 y: ys.reduce(0, +) / CGFloat(points.count))

            // Round shapes (smooth → many RDP vertices).
            if corners >= 5 {
                let elongation = maxDim > 0 ? abs(w - h) / maxDim : 0
                if elongation < 0.18 {
                    let radius = (w + h) / 4
                    let conf = circleFit(points, center: center, radius: radius)
                    if conf >= 0.55 {
                        candidates.append(Recognition(shape: .circle(center: center, radius: radius), confidence: conf))
                    }
                } else {
                    let bboxCenter = CGPoint(x: minX + w / 2, y: minY + h / 2)
                    let conf = ellipseFit(points, center: bboxCenter, rx: w / 2, ry: h / 2)
                    if conf >= 0.58 {
                        candidates.append(Recognition(shape: .ellipse(center: bboxCenter, rx: w / 2, ry: h / 2), confidence: conf))
                    }
                }
            }

            // Triangle.
            if corners == 3, w > 30, h > 30 {
                let tri = Array(verts.prefix(3))
                let conf = polygonFit(points, polygon: tri)
                if conf >= 0.7 {
                    candidates.append(Recognition(shape: .triangle(corners: tri), confidence: conf))
                }
            }

            // Rectangle (axis-aligned). Allow a spare vertex from imperfect tracing.
            if (corners == 4 || corners == 5), w > 30, h > 30 {
                let rectCorners = [
                    CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                    CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)
                ]
                let conf = rectFit(points, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
                if conf >= 0.78 {
                    candidates.append(Recognition(shape: .rect(corners: rectCorners), confidence: conf))
                }
            }
        }

        return candidates.max(by: { $0.confidence < $1.confidence })
    }

    /// Seconds the pencil was held roughly stationary at the end of the stroke.
    /// A deliberate "hold" is the GoodNotes-style signal that the user wants the
    /// stroke snapped immediately.
    static func endHoldDuration(of stroke: PKStroke) -> TimeInterval {
        let path = stroke.path
        guard path.count >= 2 else { return 0 }
        let endPoint = path[path.count - 1]
        let endLoc = endPoint.location
        let endTime = endPoint.timeOffset
        let holdRadius: CGFloat = 6
        var holdStart = endTime
        var i = path.count - 2
        while i >= 0 {
            let p = path[i]
            if distance(p.location, endLoc) <= holdRadius {
                holdStart = p.timeOffset
                i -= 1
            } else {
                break
            }
        }
        return max(0, endTime - holdStart)
    }

    // MARK: - Straightening

    /// Snaps near-horizontal/vertical lines flat. Closed shapes are already ideal.
    static func straightenShape(_ shape: ShapeType) -> ShapeType {
        switch shape {
        case .line(let start, let end):
            var s = start, e = end
            let dx = abs(e.x - s.x), dy = abs(e.y - s.y)
            let angle = atan2(dy, dx) * 180 / .pi
            if angle < 12 || angle > 168 {
                let avgY = (s.y + e.y) / 2
                s.y = avgY; e.y = avgY
            } else if abs(angle - 90) < 12 {
                let avgX = (s.x + e.x) / 2
                s.x = avgX; e.x = avgX
            }
            return .line(start: s, end: e)
        default:
            return shape
        }
    }

    // MARK: - Ideal outline (used for the snap animation & resampling)

    /// Returns `count` points sampled evenly along the ideal shape outline.
    static func outlinePoints(for shape: ShapeType, count: Int) -> [CGPoint] {
        switch shape {
        case .line(let start, let end):
            return (0..<count).map { i in
                let t = CGFloat(i) / CGFloat(max(count - 1, 1))
                return CGPoint(x: start.x + (end.x - start.x) * t,
                               y: start.y + (end.y - start.y) * t)
            }
        case .triangle(let corners):
            return sampleClosedPolygon(corners, count: count)
        case .rect(let corners):
            return sampleClosedPolygon(corners, count: count)
        case .circle(let center, let radius):
            return (0..<count).map { i in
                let a = CGFloat(i) / CGFloat(count) * .pi * 2
                return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            }
        case .ellipse(let center, let rx, let ry):
            return (0..<count).map { i in
                let a = CGFloat(i) / CGFloat(count) * .pi * 2
                return CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
            }
        }
    }

    /// Arc-length resample of an arbitrary polyline into exactly `count` points.
    static func resample(_ pts: [CGPoint], count: Int) -> [CGPoint] {
        guard pts.count > 1, count > 1 else {
            return Array(repeating: pts.first ?? .zero, count: count)
        }
        let total = polylineLength(pts)
        guard total > 0 else { return Array(repeating: pts[0], count: count) }
        let step = total / CGFloat(count - 1)
        var result: [CGPoint] = [pts[0]]
        var prev = pts[0]
        var idx = 1
        var accumulated: CGFloat = 0
        while result.count < count && idx < pts.count {
            let next = pts[idx]
            let segLen = distance(prev, next)
            if accumulated + segLen >= step, segLen > 0 {
                let t = (step - accumulated) / segLen
                let p = CGPoint(x: prev.x + (next.x - prev.x) * t,
                                y: prev.y + (next.y - prev.y) * t)
                result.append(p)
                prev = p
                accumulated = 0
            } else {
                accumulated += segLen
                prev = next
                idx += 1
            }
        }
        while result.count < count { result.append(pts[pts.count - 1]) }
        return result
    }

    // MARK: - PKStroke Generation

    static func createStroke(from shape: ShapeType, originalStroke: PKStroke) -> PKStroke {
        var points: [PKStrokePoint] = []
        let creationDate = Date()
        let baseInk = originalStroke.ink
        let originalPath = originalStroke.path
        let originalCount = max(originalPath.count, 1)

        let originalSample = { (normalizedT: CGFloat) -> PKStrokePoint? in
            guard originalPath.count > 0 else { return nil }
            let clamped = min(max(normalizedT, 0), 1)
            let index = min(Int(round(clamped * CGFloat(originalCount - 1))), originalCount - 1)
            return originalPath[index]
        }

        let makePoint = { (pt: CGPoint, normalizedT: CGFloat) -> PKStrokePoint in
            let originalPoint = originalSample(normalizedT) ?? originalPath.first
            return PKStrokePoint(
                location: pt,
                timeOffset: Double(normalizedT),
                size: originalPoint?.size ?? CGSize(width: 4, height: 4),
                opacity: originalPoint?.opacity ?? 1.0,
                force: originalPoint?.force ?? 1.0,
                azimuth: originalPoint?.azimuth ?? 0,
                altitude: originalPoint?.altitude ?? (.pi / 2)
            )
        }

        func appendSegment(_ start: CGPoint, _ end: CGPoint, steps: Int, segmentIndex: Int, segmentCount: Int) {
            for j in 0...steps {
                let t = CGFloat(j) / CGFloat(steps)
                let globalT = (CGFloat(segmentIndex) + t) / CGFloat(max(segmentCount, 1))
                points.append(
                    makePoint(
                        CGPoint(x: start.x + (end.x - start.x) * t,
                                y: start.y + (end.y - start.y) * t),
                        globalT
                    )
                )
            }
        }

        switch shape {
        case .line(let start, let end):
            appendSegment(start, end, steps: 10, segmentIndex: 0, segmentCount: 1)

        case .triangle(let corners), .rect(let corners):
            let loop = corners + [corners[0]]
            for i in 0..<corners.count {
                appendSegment(loop[i], loop[i + 1], steps: 10, segmentIndex: i, segmentCount: corners.count)
            }

        case .circle(let center, let radius):
            let steps = 60
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * .pi * 2
                points.append(
                    makePoint(
                        CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)),
                        CGFloat(i) / CGFloat(steps)
                    )
                )
            }

        case .ellipse(let center, let rx, let ry):
            let steps = 64
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * .pi * 2
                points.append(
                    makePoint(
                        CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a)),
                        CGFloat(i) / CGFloat(steps)
                    )
                )
            }
        }

        let path = PKStrokePath(controlPoints: points, creationDate: creationDate)
        return PKStroke(ink: baseInk, path: path, transform: originalStroke.transform, mask: originalStroke.mask)
    }

    // MARK: - Geometry Helpers

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat = 0, _ hi: CGFloat = 1) -> CGFloat {
        min(hi, max(lo, v))
    }

    private static func dedupe(_ pts: [CGPoint], minSpacing: CGFloat) -> [CGPoint] {
        guard let first = pts.first else { return [] }
        var result = [first]
        for p in pts.dropFirst() where distance(p, result[result.count - 1]) >= minSpacing {
            result.append(p)
        }
        return result
    }

    private static func sampleClosedPolygon(_ corners: [CGPoint], count: Int) -> [CGPoint] {
        guard corners.count >= 2 else { return Array(repeating: corners.first ?? .zero, count: count) }
        let loop = corners + [corners[0]]
        return resample(loop, count: count)
    }

    /// Perpendicular distance from a point to the line through `a`–`b`.
    private static func perpendicularDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        if len == 0 { return distance(p, a) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    /// Distance from a point to a segment `a`–`b`.
    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return distance(p, a) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = clamp(t)
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(p, proj)
    }

    private static func rdp(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let end = points.count - 1
        var index = 0
        var dmax: CGFloat = 0
        for i in 1..<end {
            let d = perpendicularDistance(points[i], points[0], points[end])
            if d > dmax { index = i; dmax = d }
        }
        if dmax > epsilon {
            let left = rdp(Array(points[0...index]), epsilon: epsilon)
            let right = rdp(Array(points[index...end]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [points[0], points[end]]
    }

    // MARK: - Confidence Scoring

    private static func circleFit(_ pts: [CGPoint], center: CGPoint, radius: CGFloat) -> CGFloat {
        guard radius > 12 else { return 0 }
        let radii = pts.map { distance($0, center) }
        let mean = radii.reduce(0, +) / CGFloat(radii.count)
        guard mean > 0 else { return 0 }
        let variance = radii.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / CGFloat(radii.count)
        let cv = sqrt(variance) / mean
        return clamp(1 - cv / 0.18)
    }

    private static func ellipseFit(_ pts: [CGPoint], center: CGPoint, rx: CGFloat, ry: CGFloat) -> CGFloat {
        guard rx > 10, ry > 10 else { return 0 }
        let err = pts.map { p -> CGFloat in
            let nx = (p.x - center.x) / rx
            let ny = (p.y - center.y) / ry
            return abs(nx * nx + ny * ny - 1)
        }.reduce(0, +) / CGFloat(pts.count)
        return clamp(1 - err / 0.55)
    }

    /// Fraction of points lying close to the polygon's edges.
    private static func polygonFit(_ pts: [CGPoint], polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        let span = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        let tol = max(8, span * 0.09)
        let loop = polygon + [polygon[0]]
        var onEdge = 0
        for p in pts {
            var best = CGFloat.greatestFiniteMagnitude
            for i in 0..<polygon.count {
                best = min(best, segmentDistance(p, loop[i], loop[i + 1]))
            }
            if best <= tol { onEdge += 1 }
        }
        return CGFloat(onEdge) / CGFloat(pts.count)
    }

    private static func rectFit(_ pts: [CGPoint], minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGFloat {
        let w = maxX - minX, h = maxY - minY
        let tol = max(w, h) * 0.12
        var onEdge = 0
        for p in pts {
            let near = abs(p.y - minY) < tol || abs(p.y - maxY) < tol ||
                       abs(p.x - minX) < tol || abs(p.x - maxX) < tol
            if near { onEdge += 1 }
        }
        return CGFloat(onEdge) / CGFloat(pts.count)
    }
}
