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
        if let L = StrokeGeometry.leader(s) {
            if L.box.insetBy(-r).contains(p) { return true }
            return distance(p, toSegment: L.attach, L.elbow) <= r + 4 || distance(p, toSegment: L.elbow, L.tip) <= r + 4
        }
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

    /// Erases the part of an ink stroke within `r` of `p`. Returns nil when the stroke is untouched,
    /// otherwise the remaining pieces (possibly empty). The eraser only affects ink; every other
    /// annotation type is left alone.
    public static func erase(_ s: Stroke, at p: Point, radius r: Double) -> [Stroke]? {
        guard s.tool.kind == .ink else { return nil }
        let tol = r + StrokeGeometry.width(of: s) / 2
        // Resample so cuts follow the finger rather than jumping to the nearest vertex.
        let pts = resample(s.points, maxStep: max(2, r / 2))
        let inside = pts.map { $0.point.distance(to: p) <= tol }
        guard inside.contains(true) else { return nil }
        var pieces: [Stroke] = []
        var run: [StrokePoint] = []
        func flush() {
            if run.count >= 2 {
                var piece = s
                piece.id = IDGen.make()
                piece.points = run
                pieces.append(piece)
            }
            run.removeAll()
        }
        for (i, q) in pts.enumerated() {
            if inside[i] { flush() } else { run.append(q) }
        }
        flush()
        // Keep the original id on the first piece so selection / comments stay linked.
        if !pieces.isEmpty { pieces[0].id = s.id }
        return pieces
    }

    /// Inserts intermediate points so no segment is longer than `maxStep`.
    public static func resample(_ pts: [StrokePoint], maxStep: Double) -> [StrokePoint] {
        guard pts.count > 1, maxStep > 0 else { return pts }
        var out: [StrokePoint] = [pts[0]]
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let d = a.point.distance(to: b.point)
            let n = Int(ceil(d / maxStep))
            if n > 1 {
                for k in 1..<n {
                    let t = Double(k) / Double(n)
                    out.append(StrokePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.p + (b.p - a.p) * t))
                }
            }
            out.append(b)
        }
        return out
    }

    /// Whether an ink stroke roughly closes on itself (so it can be bucket-filled).
    public static func isClosedInk(_ s: Stroke) -> Bool {
        guard s.tool.kind == .ink, s.points.count >= 4, let a = s.points.first, let b = s.points.last else { return false }
        let bb = s.bounds
        let diag = (bb.w * bb.w + bb.h * bb.h).squareRoot()
        guard diag > 20 else { return false }
        return a.point.distance(to: b.point) <= max(24, diag * 0.15)
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
