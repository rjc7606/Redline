// Platform-independent path description. The app turns these into CGPath /
// SwiftUI Path; tests can inspect them directly.

import Foundation

public enum PathOp: Sendable, Equatable {
    case move(Point)
    case line(Point)
    case quad(control: Point, end: Point)
    case cubic(c1: Point, c2: Point, end: Point)
    case close
}

public struct PathData: Sendable, Equatable {
    public var ops: [PathOp]
    public init(_ ops: [PathOp] = []) { self.ops = ops }

    public var isEmpty: Bool { ops.isEmpty }

    public mutating func move(to p: Point) { ops.append(.move(p)) }
    public mutating func line(to p: Point) { ops.append(.line(p)) }
    public mutating func quad(to p: Point, control c: Point) { ops.append(.quad(control: c, end: p)) }
    public mutating func cubic(to p: Point, c1: Point, c2: Point) { ops.append(.cubic(c1: c1, c2: c2, end: p)) }
    public mutating func close() { ops.append(.close) }

    public mutating func polyline(_ pts: [Point], closed: Bool = false) {
        guard let f = pts.first else { return }
        move(to: f)
        if pts.count == 1 { line(to: Point(f.x + 0.1, f.y)) }
        for p in pts.dropFirst() { line(to: p) }
        if closed { close() }
    }

    /// Smooth polyline (Catmull-Rom → cubic) — used for pens so ink looks less jagged.
    public mutating func smoothPolyline(_ pts: [Point]) {
        guard pts.count > 2 else { polyline(pts); return }
        move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            let c1 = Point(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6)
            let c2 = Point(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6)
            cubic(to: p2, c1: c1, c2: c2)
        }
    }

    public mutating func rect(_ r: Rect) {
        move(to: Point(r.minX, r.minY)); line(to: Point(r.maxX, r.minY))
        line(to: Point(r.maxX, r.maxY)); line(to: Point(r.minX, r.maxY)); close()
    }

    public mutating func ellipse(in r: Rect) {
        let k = 0.5522847498
        let cx = r.center.x, cy = r.center.y, rx = r.w / 2, ry = r.h / 2
        move(to: Point(cx + rx, cy))
        cubic(to: Point(cx, cy + ry), c1: Point(cx + rx, cy + ry * k), c2: Point(cx + rx * k, cy + ry))
        cubic(to: Point(cx - rx, cy), c1: Point(cx - rx * k, cy + ry), c2: Point(cx - rx, cy + ry * k))
        cubic(to: Point(cx, cy - ry), c1: Point(cx - rx, cy - ry * k), c2: Point(cx - rx * k, cy - ry))
        cubic(to: Point(cx + rx, cy), c1: Point(cx + rx * k, cy - ry), c2: Point(cx + rx, cy - ry * k))
        close()
    }

    /// Circular arc from the current point to `end` with radius `r` (SVG-style flags), as cubics.
    public mutating func arc(from start: Point, to end: Point, rx rxIn: Double, ry ryIn: Double, rotation: Double, largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || start == end { line(to: end); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { lambda = lambda.squareRoot(); rx *= lambda; ry *= lambda }
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : (num / den).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / Double(segments)
        let t = 4 / 3 * tan(delta / 4)
        var th = theta1
        for _ in 0..<segments {
            let cos1 = cos(th), sin1 = sin(th)
            let th2 = th + delta
            let cos2 = cos(th2), sin2 = sin(th2)
            func pt(_ c: Double, _ s: Double) -> Point {
                Point(cx + rx * cosPhi * c - ry * sinPhi * s, cy + rx * sinPhi * c + ry * cosPhi * s)
            }
            let p1 = pt(cos1, sin1), p2 = pt(cos2, sin2)
            let d1 = Point(-rx * cosPhi * sin1 - ry * sinPhi * cos1, -rx * sinPhi * sin1 + ry * cosPhi * cos1)
            let d2 = Point(-rx * cosPhi * sin2 - ry * sinPhi * cos2, -rx * sinPhi * sin2 + ry * cosPhi * cos2)
            cubic(to: p2, c1: Point(p1.x + t * d1.x, p1.y + t * d1.y), c2: Point(p2.x - t * d2.x, p2.y - t * d2.y))
            th = th2
        }
    }

    /// Bounding box of all points referenced by the ops (control points included).
    public var bounds: Rect {
        var pts: [Point] = []
        for op in ops {
            switch op {
            case .move(let p), .line(let p): pts.append(p)
            case .quad(let c, let e): pts.append(c); pts.append(e)
            case .cubic(let c1, let c2, let e): pts.append(c1); pts.append(c2); pts.append(e)
            case .close: break
            }
        }
        return Rect.bounding(pts)
    }
}
