import SwiftUI
import RedlineCore

/// Everything a page render needs, captured as a value in `body` so Observation
/// tracks the reads (the Canvas closure itself runs outside body).
struct PageRenderInput: Equatable {
    var page: Page
    var docType: DocumentType
    var canvas: Size
    var transform: CGAffineTransform
    var zoom: Double
    var activeLayer: ID?
    var live: Stroke?
    var selection: Set<ID>
    var eraseHits: Set<ID>
    var highlightComment: ID?
    var selectedField: ID?
    var showFieldTags: Bool
    var lasso: [Point]?
    var marquee: Rect?
    var blueprint: Bool
    var pdfImage: UIImage?
    var drawingPaper: Paper
    var accentHex: String
    var showSelection: Bool = true

    static func == (a: PageRenderInput, b: PageRenderInput) -> Bool {
        a.page == b.page && a.docType == b.docType && a.transform == b.transform && a.zoom == b.zoom && a.activeLayer == b.activeLayer
            && a.live == b.live && a.selection == b.selection && a.eraseHits == b.eraseHits && a.highlightComment == b.highlightComment
            && a.selectedField == b.selectedField && a.showFieldTags == b.showFieldTags && a.lasso == b.lasso && a.marquee == b.marquee
            && a.blueprint == b.blueprint && a.pdfImage === b.pdfImage && a.drawingPaper == b.drawingPaper && a.accentHex == b.accentHex
            && a.showSelection == b.showSelection
    }
}

enum PageRenderer {
    static let plainInk = "#22405f"
    static let blueprintPaper = "#16395f"
    static let blueprintInk = "#d4e4f5"

    static func paperHex(_ input: PageRenderInput) -> String {
        switch input.docType {
        case .markup: input.blueprint ? blueprintPaper : "#ffffff"
        case .drawing: input.drawingPaper.hex
        case .journal: input.page.paper.hex
        }
    }

    /// Draws a whole page into a context whose size is the scaled frame.
    static func draw(_ input: PageRenderInput, in context: GraphicsContext, size: CGSize) {
        var ctx = context
        ctx.scaleBy(x: input.zoom, y: input.zoom)
        ctx.concatenate(input.transform)
        let W = input.canvas.w, H = input.canvas.h
        let pageRect = CGRect(x: 0, y: 0, width: W, height: H)
        let paper = paperHex(input)
        ctx.fill(Path(pageRect), with: .color(Color(hex: paper)))

        // Template / artwork
        switch input.docType {
        case .journal:
            drawTemplate(input.page.template, paperDark: input.page.paper.isDark, in: ctx, W: W, H: H)
        case .markup:
            if let img = input.pdfImage {
                ctx.draw(Image(uiImage: img), in: pageRect)
            } else {
                SheetArtwork.draw(kind: input.page.artwork, in: ctx, ink: Color(hex: input.blueprint ? blueprintInk : plainInk))
            }
        case .drawing:
            break
        }

        let accent = Color(hex: input.accentHex)

        // Strokes (layers for drawings)
        if input.docType == .drawing {
            for layer in input.page.layers where layer.visible {
                if layer.isTrace, layer.opacity > 0 {
                    ctx.fill(Path(pageRect), with: .color(Color.white.opacity(layer.opacity)))
                }
                for s in layer.strokes {
                    drawStroke(s, in: ctx, dim: input.eraseHits.contains(s.id), glow: false, accent: accent)
                }
                if layer.id == (input.activeLayer ?? input.page.layers.last?.id), let live = input.live {
                    drawStroke(live, in: ctx, dim: false, glow: false, accent: accent)
                }
            }
        } else {
            for s in input.page.strokes {
                drawStroke(s, in: ctx, dim: input.eraseHits.contains(s.id), glow: input.highlightComment != nil && s.commentID == input.highlightComment, accent: accent)
            }
            if let live = input.live { drawStroke(live, in: ctx, dim: false, glow: false, accent: accent) }
        }

        // Form fields
        for f in input.page.fields {
            drawField(f, selected: f.id == input.selectedField, showTag: input.showFieldTags || f.id == input.selectedField, in: ctx, accent: accent)
        }

        // Selection rings
        if input.showSelection {
            let strokes = input.docType == .drawing ? (input.page.layers.first { $0.id == input.activeLayer } ?? input.page.layers.last)?.strokes ?? [] : input.page.strokes
            for s in strokes where input.selection.contains(s.id) {
                let b = StrokeGeometry.bounds(of: s).insetBy(-3)
                let r = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(accent), style: StrokeStyle(lineWidth: 2 / input.zoom))
            }
        }
        if let l = input.lasso, l.count > 1 {
            var p = PathData(); p.polyline(l, closed: true)
            ctx.fill(p.path(), with: .color(accent.opacity(0.08)))
            ctx.stroke(p.path(), with: .color(accent), style: StrokeStyle(lineWidth: 1.5 / input.zoom, dash: [6, 4]))
        }
        if let m = input.marquee {
            let r = CGRect(x: m.x, y: m.y, width: m.w, height: m.h)
            ctx.fill(Path(r), with: .color(accent.opacity(0.08)))
            ctx.stroke(Path(r), with: .color(accent), style: StrokeStyle(lineWidth: 1.5 / input.zoom, dash: [6, 4]))
        }
    }

    // MARK: templates

    static func drawTemplate(_ t: PageTemplate, paperDark: Bool, in ctx: GraphicsContext, W: Double, H: Double) {
        guard t != .blank else { return }
        let ink = (paperDark ? Color.white : Color.black).opacity(t.alpha)
        let s = t.spacing
        switch t {
        case .dot:
            var p = Path()
            var y = s
            while y < H { var x = s; while x < W { p.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += s }; y += s }
            ctx.fill(p, with: .color(ink))
        case .grid:
            var p = Path()
            var x = s
            while x < W { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: H)); x += s }
            var y = s
            while y < H { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: W, y: y)); y += s }
            ctx.stroke(p, with: .color(ink), lineWidth: 1)
        case .lined:
            var p = Path()
            var y = s
            while y < H { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: W, y: y)); y += s }
            ctx.stroke(p, with: .color(ink), lineWidth: 1)
        case .blank:
            break
        }
    }

    // MARK: strokes

    static func drawStroke(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        if let r = StrokeGeometry.render(s) {
            let path = r.path.path()
            ctx.drawLayer { layer in
                if dim { layer.opacity = 0.15 }
                if glow {
                    layer.stroke(path, with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: r.strokeWidth + 8, lineCap: .round, lineJoin: .round))
                }
                if r.multiply { layer.blendMode = .multiply }
                if let f = r.fillColor {
                    fill(path, hex: f, opacity: r.fillOpacity, pattern: r.fillPattern, in: layer)
                }
                if let sc = r.strokeColor, r.strokeWidth > 0 {
                    layer.stroke(path, with: .color(Color(hex: sc, alpha: r.strokeOpacity)),
                                 style: StrokeStyle(lineWidth: r.strokeWidth, lineCap: r.roundCap ? .round : .butt, lineJoin: .round, dash: r.dash.map { CGFloat($0) }))
                }
            }
            return
        }
        switch s.tool.kind {
        case .text: drawTextBox(s, in: ctx, dim: dim, glow: glow, accent: accent)
        case .stampGallery, .stampPreset: drawStamp(s, in: ctx, dim: dim, glow: glow, accent: accent)
        case .place where s.tool == .note: drawNote(s, in: ctx, dim: dim, glow: glow, accent: accent)
        default: break
        }
    }

    static func fill(_ path: Path, hex: String, opacity: Double, pattern: FillPattern, in ctx: GraphicsContext) {
        let color = Color(hex: hex, alpha: opacity)
        switch pattern {
        case .none: return
        case .solid: ctx.fill(path, with: .color(color))
        case .hatch, .cross, .dots:
            ctx.drawLayer { layer in
                layer.clip(to: path)
                let b = path.boundingRect.insetBy(dx: -10, dy: -10)
                var p = Path()
                let step = 7.0
                if pattern == .dots {
                    var y = b.minY
                    while y < b.maxY { var x = b.minX; while x < b.maxX { p.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)); x += step }; y += step }
                    layer.fill(p, with: .color(color))
                    return
                }
                var d = b.minX - b.height
                while d < b.maxX {
                    p.move(to: CGPoint(x: d, y: b.maxY)); p.addLine(to: CGPoint(x: d + b.height, y: b.minY))
                    if pattern == .cross { p.move(to: CGPoint(x: d, y: b.minY)); p.addLine(to: CGPoint(x: d + b.height, y: b.maxY)) }
                    d += step
                }
                layer.stroke(p, with: .color(color), lineWidth: 1.5)
            }
        }
    }

    static func drawTextBox(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        let fs = 10 + (s.width ?? 6)
        let text = Text(s.text ?? "").font(.system(size: fs, weight: .semibold)).foregroundStyle(Color(hex: s.color, alpha: s.opacity ?? 1))
        let resolved = ctx.resolve(text)
        let size = resolved.measure(in: CGSize(width: 600, height: 400))
        let a = s.anchor
        let box = CGRect(x: a.x - 6, y: a.y - fs - 3, width: size.width + 12, height: size.height + 6)
        ctx.drawLayer { layer in
            if dim { layer.opacity = 0.15 }
            if glow { layer.stroke(Path(roundedRect: box.insetBy(dx: -3, dy: -3), cornerRadius: 6), with: .color(accent.opacity(0.5)), lineWidth: 4) }
            if let bg = s.background, (s.backgroundOpacity ?? 0) > 0 {
                layer.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(hex: bg, alpha: s.backgroundOpacity ?? 1)))
            }
            if let bw = s.borderWidth, bw > 0 {
                layer.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(hex: s.borderColor ?? s.color, alpha: s.borderOpacity ?? 1)), lineWidth: bw)
            }
            layer.draw(resolved, at: CGPoint(x: a.x, y: a.y - fs), anchor: .topLeading)
        }
    }

    static func drawStamp(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        let c = Color(hex: s.color)
        let text = Text(s.text ?? "").font(.system(size: 17 * s.scale, weight: .heavy)).tracking(2 * s.scale).foregroundStyle(c)
        let resolved = ctx.resolve(text)
        let size = resolved.measure(in: CGSize(width: 800, height: 200))
        let box = CGRect(x: -size.width / 2 - 14 * s.scale, y: -size.height / 2 - 5 * s.scale, width: size.width + 28 * s.scale, height: size.height + 10 * s.scale)
        let a = s.anchor
        ctx.drawLayer { layer in
            if dim { layer.opacity = 0.15 }
            layer.translateBy(x: a.x, y: a.y)
            layer.rotate(by: .degrees(-5))
            if glow { layer.stroke(Path(roundedRect: box.insetBy(dx: -4, dy: -4), cornerRadius: 7), with: .color(accent.opacity(0.5)), lineWidth: 4) }
            layer.fill(Path(roundedRect: box, cornerRadius: 5 * s.scale), with: .color(Color.white.opacity(0.85)))
            layer.stroke(Path(roundedRect: box, cornerRadius: 5 * s.scale), with: .color(c), lineWidth: 3 * s.scale)
            layer.draw(resolved, at: .zero, anchor: .center)
        }
    }

    static func drawNote(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        let a = s.anchor
        let sz = 30 * s.scale
        let r = CGRect(x: a.x - sz / 2, y: a.y - sz / 2, width: sz, height: sz)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - sz * 0.4))
        p.addQuadCurve(to: CGPoint(x: r.maxX - sz * 0.4, y: r.maxY), control: CGPoint(x: r.maxX - sz * 0.05, y: r.maxY - sz * 0.05))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        ctx.drawLayer { layer in
            if dim { layer.opacity = 0.15 }
            if glow { layer.stroke(p, with: .color(accent.opacity(0.5)), lineWidth: 4) }
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 3, y: 2))
            layer.fill(p, with: .color(Color(hex: s.color, alpha: s.opacity ?? 1)))
        }
    }

    static func drawField(_ f: FormField, selected: Bool, showTag: Bool, in ctx: GraphicsContext, accent: Color) {
        let r = CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
        let shape = Path(roundedRect: r, cornerRadius: f.type.cornerRadius)
        ctx.fill(shape, with: .color(accent.opacity(0.1)))
        ctx.stroke(shape, with: .color(selected ? accent : accent.opacity(0.45)), lineWidth: 1.5)
        let ink = Color(hex: "#1c1c1e")
        switch f.type {
        case .check, .radio, .toggle:
            if f.isOn {
                let mark = Text(f.type == .radio ? "●" : "✓").font(.system(size: 16, weight: .heavy)).foregroundStyle(accent)
                ctx.draw(mark, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            }
        case .sig:
            let t = Text("✗ " + f.name).font(.system(size: 12).italic()).foregroundStyle(Color(hex: "#6d6d72"))
            ctx.draw(t, at: CGPoint(x: r.minX + 8, y: r.midY), anchor: .leading)
        default:
            let v = f.value.isEmpty ? f.defaultValue : f.value
            let t = Text(v.isEmpty ? f.name : v).font(.system(size: 13)).foregroundStyle(v.isEmpty ? Color(hex: "#8e8e93") : ink)
            ctx.draw(t, at: CGPoint(x: r.minX + 8, y: r.midY), anchor: .leading)
        }
        if showTag {
            let tag = Text("\(f.name)\(f.required ? " *" : "") · tab \(f.tab)").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
            ctx.draw(tag, at: CGPoint(x: r.minX, y: r.minY - 3), anchor: .bottomLeading)
        }
    }
}
