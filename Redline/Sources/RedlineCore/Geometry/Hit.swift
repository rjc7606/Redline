// Hit testing, lasso containment and polyline simplification.

import Foundation

public enum Hit {
    /// Distance from `p` to segment ab.
    public static func distance(_ p: Point, toSegment a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return p.distance(to: Point(a.x + t * dx, a.y + t * dy))
    }

    /// Whether the eraser at `p` (radius `r`) touches the stroke.
    public static func strokeTouches(_ s: Stroke, point p: Point, radius r: Double) -> Bool {
        let info = s.tool.info
        if info.isPathBased {
            let pts = s.points.map(\.point)
            if s.tool.kind == .shape || s.tool.kind == .highlight || s.tool.kind == .textMarkup {
                // Shapes: test the outline of the rendered path segments (control points approximation) and the box.
                let b = StrokeGeometry.bounds(of: s)
                if !b.insetBy(-r).contains(p) { return false }
                if s.tool == .rect || s.tool == .ellipse || s.tool == .cloud || s.tool == .redact || s.tool == .polygon {
                    return true
                }
                if pts.count == 1 { return true }
                for i in 0..<(pts.count - 1) where distance(p, toSegment: pts[i], pts[i + 1]) <= r + StrokeGeometry.width(of: s) / 2 { return true }
                return false
            }
            let tol = r + StrokeGeometry.width(of: s) / 2
            if pts.count == 1 { return pts[0].distance(to: p) <= tol }
            for i in 0..<(pts.count - 1) where distance(p, toSegment: pts[i], pts[i + 1]) <= tol { return true }
            return false
        }
        return StrokeGeometry.bounds(of: s).insetBy(-r).contains(p)
    }

    /// Point-in-polygon (even-odd).
    public static func polygon(_ poly: [Point], contains p: Point) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Ramer–Douglas–Peucker simplification (used to turn a freehand drag into a polyline).
    public static func simplify(_ pts: [Point], tolerance: Double) -> [Point] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (s, e) = stack.popLast() {
            var maxD = 0.0, idx = -1
            if e - s > 1 {
                for i in (s + 1)..<e {
                    let d = distance(pts[i], toSegment: pts[s], pts[e])
                    if d > maxD { maxD = d; idx = i }
                }
            }
            if idx >= 0 && maxD > tolerance {
                keep[idx] = true
                stack.append((s, idx)); stack.append((idx, e))
            }
        }
        return pts.enumerated().filter { keep[$0.offset] }.map(\.element)
    }
}
