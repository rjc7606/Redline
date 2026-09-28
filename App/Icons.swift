import SwiftUI
import RedlineCore

extension PathData {
    /// SwiftUI path, optionally scaled by a uniform factor.
    func path(scale: Double = 1) -> Path {
        var p = Path()
        func pt(_ q: Point) -> CGPoint { CGPoint(x: q.x * scale, y: q.y * scale) }
        for op in ops {
            switch op {
            case .move(let q): p.move(to: pt(q))
            case .line(let q): p.addLine(to: pt(q))
            case .quad(let c, let e): p.addQuadCurve(to: pt(e), control: pt(c))
            case .cubic(let c1, let c2, let e): p.addCurve(to: pt(e), control1: pt(c1), control2: pt(c2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
}

/// A tool glyph: SF Symbol when mapped, otherwise the custom 24-grid outline glyph.
struct ToolIcon: View {
    var tool: Tool
    var size: Double = 20
    var color: Color = .primary
    /// Optional fill shown through closed custom glyphs (shape fill / text-box background).
    var glyphFill: Color? = nil
    var glyphStroke: Color? = nil

    var body: some View {
        let info = tool.info
        if let s = info.symbol {
            Image(systemName: s)
                .font(.system(size: size * 0.92, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size + 4, height: size + 4)
        } else if let g = info.glyph {
            GlyphView(d: g, d2: info.glyph2, fill: info.glyphFill, size: size, color: color, primaryFill: glyphFill, primaryStroke: glyphStroke)
        } else {
            Image(systemName: "questionmark").foregroundStyle(color).frame(width: size + 4, height: size + 4)
        }
    }
}

struct GlyphView: View {
    var d: String
    var d2: String? = nil
    var fill: String? = nil
    var size: Double = 20
    var color: Color = .primary
    var primaryFill: Color? = nil
    var primaryStroke: Color? = nil

    var body: some View {
        let k = size / 24
        let style = StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)
        ZStack {
            let p1 = SVGPath.parse(d).path(scale: k)
            if let f = primaryFill { p1.fill(f) }
            p1.stroke(primaryStroke ?? color, style: style)
            if let d2 { SVGPath.parse(d2).path(scale: k).stroke(color, style: style) }
            if let fill { SVGPath.parse(fill).path(scale: k).fill(color) }
        }
        .frame(width: size, height: size)
        .padding(2)
    }
}

/// Symbol for a comment kind (tool raw value).
func commentSymbol(for kind: String) -> String {
    if let t = Tool(rawValue: kind) {
        if let s = t.info.symbol { return s }
        switch t {
        case .pen, .fineliner, .felt, .marker: return "pencil.line"
        case .rect: return "rectangle"
        case .ellipse: return "oval"
        case .cloud: return "cloud"
        case .textbox: return "textformat"
        case .fill: return "drop.fill"
        case .line, .dblarrow, .polyline, .polygon: return "line.diagonal"
        default: return "pencil"
        }
    }
    return "pencil"
}
