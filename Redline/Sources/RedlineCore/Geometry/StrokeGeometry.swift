// Turns a Stroke into drawable geometry. Everything the renderer needs
// (path, widths, fill mode, dash pattern) is computed here so the SwiftUI /
// Core Graphics renderer and the PDF exporter draw exactly the same thing.

import Foundation

public struct StrokeRender: Sendable, Equatable {
    public var path: PathData
    /// Stroke colour hex (nil → no outline).
    public var strokeColor: String?
    public var strokeWidth: Double
    public var strokeOpacity: Double
    /// Fill colour hex (nil → no fill). For pressure ink the whole path is a fill.
    public var fillColor: String?
    public var fillOpacity: Double
    public var fillPattern: FillPattern
    /// Dash pattern in points (empty → solid).
    public var dash: [Double]
    public var roundCap: Bool
    /// Multiply blend for translucent markers / highlighters.
    public var multiply: Bool
    public init(path: PathData, strokeColor: String?, strokeWidth: Double, strokeOpacity: Double, fillColor: String?,
                fillOpacity: Double, fillPattern: FillPattern, dash: [Double], roundCap: Bool, multiply: Bool) {
        self.path = path; self.strokeColor = strokeColor; self.strokeWidth = strokeWidth; self.strokeOpacity = strokeOpacity
        self.fillColor = fillColor; self.fillOpacity = fillOpacity; self.fillPattern = fillPattern; self.dash = dash
        self.roundCap = roundCap; self.multiply = multiply
    }
}

public enum StrokeGeometry {
    /// Effective outline width, applying the pressure mode to the average pressure.
    public static func width(of s: Stroke) -> Double {
        let base = s.width ?? ToolStyles.base(for: s.tool).width
        return base
    }

    public static func opacity(of s: Stroke) -> Double {
        s.opacity ?? ToolStyles.defaultOpacity(for: s.tool)
    }

    /// Fixed footprint of tap-placed glyphs (before `scale`).
    public static func placedSize(for tool: Tool) -> Size {
        switch tool {
        case .check: Size(110, 90)
        case .xmark: Size(90, 90)
        case .note: Size(30, 30)
        default: Size(60, 60)
        }
    }

    public static func render(_ s: Stroke) -> StrokeRender? {
        let w = width(of: s)
        let op = opacity(of: s)
        let pts = s.points.map(\.point)
        var path = PathData()
        var dash: [Double] = []
        if let ls = s.lineStyle {
            switch ls {
            case .solid: dash = []
            case .dash: dash = [w * 3, w * 2]
            case .dot: dash = [0.1, w * 2.2]
            }
        }
        if let rects = s.rects, !rects.isEmpty, s.tool.kind == .highlight || s.tool.kind == .textMarkup {
            return renderTextAnchored(s, rects: rects, width: w, opacity: op, dash: dash)
        }
        switch s.tool.kind {
        case .ink:
            // A pen-drawn shape that was bucket-filled: closed centreline with fill and outline.
            if let fp = s.fillPattern, fp != FillPattern.none {
                path.smoothPolyline(pts)
                path.close()
                return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(0.5, w), strokeOpacity: op, fillColor: s.fill ?? s.color,
                                    fillOpacity: s.fillOpacity ?? 0.5, fillPattern: fp, dash: dash, roundCap: true, multiply: false)
            }
            if s.weight == .pressure, s.points.count > 1 {
                let outline = pressureOutline(s.points, width: w * 1.6)
                path.polyline(outline, closed: true)
                return StrokeRender(path: path, strokeColor: nil, strokeWidth: 0, strokeOpacity: op, fillColor: s.color, fillOpacity: op,
                                    fillPattern: .solid, dash: [], roundCap: true, multiply: s.tool == .marker)
            }
            if s.tool == .marker || s.tool == .fineliner { path.polyline(pts) } else { path.smoothPolyline(pts) }
            return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(0.5, w), strokeOpacity: op, fillColor: nil,
                                fillOpacity: 0, fillPattern: .none, dash: dash, roundCap: s.tool != .marker, multiply: s.tool == .marker)
        case .highlight:
            guard let a = pts.first else { return nil }
            let b = pts.last ?? a
            path.polyline([a, Point(b.x, a.y)])
            return StrokeRender(path: path, strokeColor: s.color, strokeWidth: w, strokeOpacity: op, fillColor: nil, fillOpacity: 0,
                                fillPattern: .none, dash: [], roundCap: false, multiply: true)
        case .textMarkup:
            guard let a = pts.first else { return nil }
            let b = pts.last ?? a
            let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
            if s.tool == .squiggly {
                path.move(to: Point(x0, a.y))
                var x = x0
                var up = true
                while x < x1 {
                    let nx = min(x1, x + 8)
                    path.quad(to: Point(nx, a.y), control: Point((x + nx) / 2, a.y + (up ? -6 : 6)))
                    up.toggle(); x = nx
                }
            } else {
                path.polyline([Point(x0, a.y), Point(x1, a.y)])
            }
            return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(1.5, w * 0.6), strokeOpacity: op, fillColor: nil,
                                fillOpacity: 0, fillPattern: .none, dash: dash, roundCap: true, multiply: false)
        case .shape:
            guard let a = pts.first else { return nil }
            let b = pts.last ?? a
            let box = Rect.from(a, b)
            let fp = s.fillPattern ?? FillPattern.none
            let fillC: String? = fp == FillPattern.none ? nil : (s.fill ?? s.color)
            let fo = s.fillOpacity ?? 0.5
            switch s.tool {
            case .rect: path.rect(box)
            case .ellipse: path.ellipse(in: box)
            case .redact:
                path.rect(box)
                return StrokeRender(path: path, strokeColor: nil, strokeWidth: 0, strokeOpacity: 1, fillColor: "#1c1c1e",
                                    fillOpacity: 0.96, fillPattern: .solid, dash: [], roundCap: false, multiply: false)
            case .line: path.polyline([a, b])
            case .arrow:
                path.polyline([a, b]); arrowHead(&path, from: a, to: b, size: max(14, w * 4))
            case .dblarrow:
                path.polyline([a, b]); arrowHead(&path, from: a, to: b, size: max(14, w * 4)); arrowHead(&path, from: b, to: a, size: max(14, w * 4))
            case .polyline: path.polyline(pts)
            case .polygon: path.polyline(pts, closed: true)
            case .cloud: path = cloud(box, radius: max(8, min(box.w, box.h) / 8))
            case .callout:
                // Leader: drawn by the renderer (text box + leader line); see `leader(_:)`.
                return nil
            default: path.polyline(pts)
            }
            let closed = s.tool.isShape
            return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(0.5, w), strokeOpacity: op,
                                fillColor: closed ? fillC : nil, fillOpacity: fo, fillPattern: closed ? fp : .none,
                                dash: dash, roundCap: true, multiply: false)
        case .place:
            let c = s.anchor
            let f = s.scale
            switch s.tool {
            case .check:
                path.polyline([Point(c.x - 50 * f, c.y), Point(c.x - 12 * f, c.y + 38 * f), Point(c.x + 60 * f, c.y - 48 * f)])
            case .xmark:
                path.move(to: Point(c.x - 40 * f, c.y - 40 * f)); path.line(to: Point(c.x + 40 * f, c.y + 40 * f))
                path.move(to: Point(c.x + 40 * f, c.y - 40 * f)); path.line(to: Point(c.x - 40 * f, c.y + 40 * f))
            default: return nil
            }
            return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(1, w * 1.4 * f), strokeOpacity: op, fillColor: nil,
                                fillOpacity: 0, fillPattern: .none, dash: [], roundCap: true, multiply: false)
        default:
            return nil
        }
    }

    /// Highlight / underline / strike / squiggly snapped to PDF text-line rectangles.
    static func renderTextAnchored(_ s: Stroke, rects: [Rect], width w: Double, opacity op: Double, dash: [Double]) -> StrokeRender {
        var path = PathData()
        switch s.tool {
        case .highlighter:
            for r in rects { path.rect(r.insetBy(-1)) }
            return StrokeRender(path: path, strokeColor: nil, strokeWidth: 0, strokeOpacity: op, fillColor: s.color, fillOpacity: op,
                                fillPattern: .solid, dash: [], roundCap: false, multiply: true)
        case .underline:
            for r in rects { path.move(to: Point(r.minX, r.maxY - 1)); path.line(to: Point(r.maxX, r.maxY - 1)) }
        case .strike:
            for r in rects { path.move(to: Point(r.minX, r.center.y)); path.line(to: Point(r.maxX, r.center.y)) }
        case .squiggly:
            for r in rects {
                let y = r.maxY - 1
                path.move(to: Point(r.minX, y))
                var x = r.minX
                var up = true
                while x < r.maxX {
                    let nx = min(r.maxX, x + 6)
                    path.quad(to: Point(nx, y), control: Point((x + nx) / 2, y + (up ? -4 : 4)))
                    up.toggle(); x = nx
                }
            }
        default:
            for r in rects { path.rect(r) }
        }
        return StrokeRender(path: path, strokeColor: s.color, strokeWidth: max(1.2, min(w * 0.35, 3)), strokeOpacity: op, fillColor: nil,
                            fillOpacity: 0, fillPattern: .none, dash: dash, roundCap: true, multiply: false)
    }

    // MARK: Text boxes & leaders

    /// Text box rectangle for a text anchor (top-left of the text) — the same estimate the renderer uses.
    public static func textRect(anchor a: Point, text: String, width: Double?) -> Rect {
        let fs = 10 + (width ?? 6)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        return Rect(x: a.x - 6, y: a.y - fs - 3, w: Double(max(1, longest)) * fs * 0.58 + 12, h: fs * 1.45 * Double(max(1, lines.count)) + 6)
    }

    public struct Leader: Sendable, Equatable {
        public var tip: Point
        public var elbow: Point
        /// Where the shelf meets the text box.
        public var attach: Point
        public var box: Rect
        public var anchor: Point
        public init(tip: Point, elbow: Point, attach: Point, box: Rect, anchor: Point) {
            self.tip = tip; self.elbow = elbow; self.attach = attach; self.box = box; self.anchor = anchor
        }
    }

    /// Leader geometry: points[0] = arrow tip, points[1] = elbow, points[2] = text anchor.
    /// The shelf leaves the box side that faces the elbow, sliding along it.
    public static func leader(_ s: Stroke) -> Leader? {
        guard s.tool == .callout, s.points.count >= 3 else { return nil }
        let tip = s.points[0].point, elbow = s.points[1].point, anchor = s.points[2].point
        let box = textRect(anchor: anchor, text: s.text?.isEmpty == false ? s.text! : "Text", width: s.width)
        let attach: Point
        if elbow.x < box.minX { attach = Point(box.minX, min(box.maxY, max(box.minY, elbow.y))) }
        else if elbow.x > box.maxX { attach = Point(box.maxX, min(box.maxY, max(box.minY, elbow.y))) }
        else if elbow.y < box.minY { attach = Point(min(box.maxX, max(box.minX, elbow.x)), box.minY) }
        else if elbow.y > box.maxY { attach = Point(min(box.maxX, max(box.minX, elbow.x)), box.maxY) }
        else { attach = Point(box.minX, box.center.y) }
        return Leader(tip: tip, elbow: elbow, attach: attach, box: box, anchor: anchor)
    }

    /// Default elbow for a new leader: a horizontal shelf on the box side facing the tip.
    public static func defaultElbow(tip: Point, anchor: Point, text: String, width: Double?) -> Point {
        let box = textRect(anchor: anchor, text: text.isEmpty ? "Text" : text, width: width)
        let left = tip.x < box.center.x
        return Point(left ? box.minX - 28 : box.maxX + 28, box.center.y)
    }

    /// Leader line path (attach → elbow → tip) with an arrowhead at the tip.
    public static func leaderPath(_ L: Leader, width w: Double) -> PathData {
        var path = PathData()
        path.move(to: L.attach); path.line(to: L.elbow); path.line(to: L.tip)
        arrowHead(&path, from: L.elbow, to: L.tip, size: max(12, w * 4))
        return path
    }

    static func arrowHead(_ path: inout PathData, from a: Point, to b: Point, size: Double) {
        let ang = atan2(b.y - a.y, b.x - a.x)
        let spread = 0.45
        let p1 = Point(b.x - size * cos(ang - spread), b.y - size * sin(ang - spread))
        let p2 = Point(b.x - size * cos(ang + spread), b.y - size * sin(ang + spread))
        path.move(to: p1); path.line(to: b); path.line(to: p2)
    }

    /// Revision cloud: arcs bumping outward around a rectangle.
    public static func cloud(_ r: Rect, radius: Double) -> PathData {
        var path = PathData()
        guard r.w > 4, r.h > 4 else { path.rect(r); return path }
        let step = radius * 1.7
        var pts: [Point] = []
        var x = r.minX
        while x < r.maxX { pts.append(Point(x, r.minY)); x += step }
        var y = r.minY
        while y < r.maxY { pts.append(Point(r.maxX, y)); y += step }
        x = r.maxX
        while x > r.minX { pts.append(Point(x, r.maxY)); x -= step }
        y = r.maxY
        while y > r.minY { pts.append(Point(r.minX, y)); y -= step }
        guard let first = pts.first else { return path }
        path.move(to: first)
        var prev = first
        for p in pts.dropFirst() { path.arc(from: prev, to: p, rx: radius, ry: radius, rotation: 0, largeArc: false, sweep: true); prev = p }
        path.arc(from: prev, to: first, rx: radius, ry: radius, rotation: 0, largeArc: false, sweep: true)
        path.close()
        return path
    }

    /// Variable-width outline polygon for pressure-sensitive ink.
    public static func pressureOutline(_ pts: [StrokePoint], width w: Double) -> [Point] {
        guard pts.count > 1 else { return pts.map(\.point) }
        let n = pts.count - 1
        var left: [Point] = [], right: [Point] = []
        for (i, p) in pts.enumerated() {
            let t = Double(i) / Double(n)
            let a = pts[max(0, i - 1)], b = pts[min(n, i + 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let m = max(1e-6, (dx * dx + dy * dy).squareRoot())
            dx /= m; dy /= m
            let taper = min(1, t * 8 + 0.15, (1 - t) * 8 + 0.15)
            let pr = taper * min(1.6, p.p * 1.6)
            let hw = w * (0.18 + 0.82 * max(0, pr)) / 2
            left.append(Point(p.x - dy * hw, p.y + dx * hw))
            right.append(Point(p.x + dy * hw, p.y - dx * hw))
        }
        return left + right.reversed()
    }

    /// Bounding rectangle used for hit-testing / selection rings.
    public static func bounds(of s: Stroke) -> Rect {
        if let L = leader(s) {
            let pts = [L.tip, L.elbow, Point(L.box.minX, L.box.minY), Point(L.box.maxX, L.box.maxY)]
            return Rect.bounding(pts).insetBy(-6)
        }
        if let r = render(s) { return r.path.bounds.insetBy(-max(4, r.strokeWidth / 2)) }
        let c = s.anchor
        switch s.tool.kind {
        case .place:
            let sz = placedSize(for: s.tool)
            return Rect(x: c.x - sz.w * s.scale / 2, y: c.y - sz.h * s.scale / 2, w: sz.w * s.scale, h: sz.h * s.scale)
        case .text:
            return textRect(anchor: c, text: s.text ?? "", width: s.width)
        case .stampGallery, .stampPreset:
            let wdt = Double((s.text ?? "").count) * 11 * s.scale + 28 * s.scale
            return Rect(x: c.x - wdt / 2, y: c.y - 18 * s.scale, w: wdt, h: 36 * s.scale)
        default:
            return Rect(x: c.x - 20, y: c.y - 20, w: 40, h: 40)
        }
    }
}
