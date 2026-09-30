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
    /// The page image is still rendering in the background.
    var pdfLoading: Bool = false
    var drawingPaper: Paper
    var accentHex: String
    var showSelection: Bool = true
    /// Stroke ids that carry the "has a comment" badge (first mark of each commented annotation).
    var commentBadges: Set<ID> = []
    /// Notebook cover: the title drawn on the page (nil for every other page).
    var coverTitle: String? = nil
    /// Notebook cover colour (with `coverTitle`).
    var coverHex: String? = nil

    static func == (a: PageRenderInput, b: PageRenderInput) -> Bool {
        a.page == b.page && a.docType == b.docType && a.transform == b.transform && a.zoom == b.zoom && a.activeLayer == b.activeLayer
            && a.live == b.live && a.selection == b.selection && a.eraseHits == b.eraseHits && a.highlightComment == b.highlightComment
            && a.selectedField == b.selectedField && a.showFieldTags == b.showFieldTags && a.lasso == b.lasso && a.marquee == b.marquee
            && a.blueprint == b.blueprint && a.pdfImage === b.pdfImage && a.pdfLoading == b.pdfLoading && a.drawingPaper == b.drawingPaper && a.accentHex == b.accentHex
            && a.showSelection == b.showSelection && a.commentBadges == b.commentBadges
    }
}

enum PageRenderer {
    static let plainInk = "#22405f"
    static let blueprintPaper = "#16395f"
    static let blueprintInk = "#d4e4f5"

    static func paperHex(_ input: PageRenderInput) -> String {
        switch input.docType {
        case .markup: input.pdfImage != nil ? "#ffffff" : (input.blueprint ? blueprintPaper : input.page.paper.hex)
        case .drawing: input.drawingPaper.hex
        case .journal: input.coverHex ?? input.page.paper.hex
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
            if let title = input.coverTitle { drawCover(title: title, hex: input.coverHex ?? input.page.paper.hex, in: ctx, W: W, H: H) }
            else { drawTemplate(input.page.template, paperDark: input.page.paper.isDark, in: ctx, W: W, H: H) }
        case .markup:
            if let img = input.pdfImage {
                ctx.draw(Image(uiImage: img), in: pageRect)
            } else if input.pdfLoading {
                drawLoadingPlaceholder(in: ctx, W: W, H: H)
            } else {
                drawTemplate(input.page.template, paperDark: input.blueprint, in: ctx, W: W, H: H)
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

        // "Has a comment" badges
        if !input.commentBadges.isEmpty {
            for s in input.page.strokes where input.commentBadges.contains(s.id) {
                let b = StrokeGeometry.bounds(of: s)
                drawCommentBadge(at: CGPoint(x: b.maxX, y: b.minY), scale: 1 / input.zoom, in: ctx, accent: accent)
            }
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

    /// Neutral page shown while the PDF renders in the background (marks still draw on top).
    static func drawLoadingPlaceholder(in ctx: GraphicsContext, W: Double, H: Double) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(Color(hex: "#f4f4f6")))
        var lines = Path()
        var y = 60.0
        while y < H - 40 { lines.addRoundedRect(in: CGRect(x: 56, y: y, width: (W - 112) * (y.truncatingRemainder(dividingBy: 90) == 0 ? 0.55 : 0.9), height: 10), cornerSize: CGSize(width: 5, height: 5)); y += 30 }
        ctx.fill(lines, with: .color(Color(hex: "#e2e2e6")))
        let t = Text("Loading page…").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: "#8e8e93"))
        ctx.draw(t, at: CGPoint(x: W / 2, y: H / 2), anchor: .center)
    }

    /// Small speech-bubble dot marking an annotation that has comment text or replies.
    static func drawCommentBadge(at c: CGPoint, scale k: Double, in ctx: GraphicsContext, accent: Color) {
        let r = 9 * k
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 2 * k, y: 1 * k))
            layer.fill(circle, with: .color(accent))
        }
        ctx.stroke(circle, with: .color(.white), lineWidth: 1.5 * k)
        var dots = Path()
        for dx in [-0.42, 0.0, 0.42] { dots.addEllipse(in: CGRect(x: c.x + dx * r - 0.15 * r, y: c.y - 0.15 * r, width: 0.3 * r, height: 0.3 * r)) }
        ctx.fill(dots, with: .color(.white))
    }

    // MARK: templates

    /// Composition-notebook cover: marbled speckle over the cover colour, a dark cloth spine, and a white label
    /// plate with the title. Ink is drawn on top like any page, so drawings show in the thumbnail.
    static func drawCover(title: String, hex: String, in ctx: GraphicsContext, W: Double, H: Double) {
        let page = CGRect(x: 0, y: 0, width: W, height: H)
        let dark = Covers.isDark(hex)
        // marbling (cached texture image, white speckles)
        ctx.draw(Image(uiImage: CoverTexture.shared.image), in: page)
        if dark { ctx.fill(Path(page), with: .color(Color.black.opacity(0.25))) }
        // spine
        let spineW = W * 0.075
        ctx.fill(Path(CGRect(x: 0, y: 0, width: spineW, height: H)), with: .color(Color.black.opacity(0.62)))
        ctx.fill(Path(CGRect(x: spineW, y: 0, width: W * 0.006, height: H)), with: .color(Color.white.opacity(0.35)))
        // label plate
        let plate = CGRect(x: W * 0.22, y: H * 0.2, width: W * 0.6, height: H * 0.19)
        let r = W * 0.012
        ctx.fill(Path(roundedRect: plate, cornerRadius: r), with: .color(Color.black.opacity(0.18)))
        ctx.fill(Path(roundedRect: plate.offsetBy(dx: 0, dy: -H * 0.003), cornerRadius: r), with: .color(.white))
        ctx.stroke(Path(roundedRect: plate.insetBy(dx: W * 0.012, dy: W * 0.012), cornerRadius: r * 0.6), with: .color(Color.black.opacity(0.22)), lineWidth: 1.5)
        let inner = plate.insetBy(dx: W * 0.035, dy: W * 0.03)
        for f in [0.62, 0.8] {
            let y = inner.minY + inner.height * f
            ctx.fill(Path(CGRect(x: inner.minX, y: y, width: inner.width, height: 1.2)), with: .color(Color.black.opacity(0.18)))
        }
        let label = Text(title).font(.system(size: W * 0.05, weight: .bold)).foregroundStyle(Color(hex: "#1c1c1e"))
        let resolved = ctx.resolve(label)
        let box = CGSize(width: inner.width, height: inner.height * 0.58)
        let sz = resolved.measure(in: box)
        let tw = min(sz.width, box.width), th = min(sz.height, box.height)
        ctx.draw(resolved, in: CGRect(x: inner.midX - tw / 2, y: inner.minY + (box.height - th) / 2, width: tw, height: th))
    }

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
        if s.tool == .callout { drawLeader(s, in: ctx, dim: dim, glow: glow, accent: accent); return }
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

    /// Leader: text box plus attach → elbow → arrow tip.
    static func drawLeader(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        let w = max(1.5, StrokeGeometry.width(of: s) * 0.35)
        let color = Color(hex: s.color, alpha: s.opacity ?? 1)
        if let L = StrokeGeometry.leader(s) {
            let path = StrokeGeometry.leaderPath(L, width: w).path()
            ctx.drawLayer { layer in
                if dim { layer.opacity = 0.15 }
                if glow { layer.stroke(path, with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: w + 8, lineCap: .round, lineJoin: .round)) }
                layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            var box = s
            box.tool = .textbox
            box.points = [StrokePoint(L.anchor.x, L.anchor.y)]
            drawTextBox(box, in: ctx, dim: dim, glow: glow, accent: accent)
        } else if s.points.count >= 2 {
            // Still being dragged: straight arrow from tip to the future box position.
            let a = s.points[0].point, b = s.points[1].point
            let L = StrokeGeometry.Leader(tip: a, elbow: b, attach: b, box: Rect(x: b.x, y: b.y, w: 0, h: 0), anchor: b)
            ctx.stroke(StrokeGeometry.leaderPath(L, width: w).path(), with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }

    static func drawTextBox(_ s: Stroke, in ctx: GraphicsContext, dim: Bool, glow: Bool, accent: Color) {
        let fs = 10 + (s.width ?? 6)
        let empty = (s.text ?? "").isEmpty
        let text = Text(empty ? "Text" : (s.text ?? "")).font(textFont(s.font, size: fs, weight: s.fontWeight))
            .foregroundStyle(empty ? Color(hex: "#8e8e93", alpha: 0.7) : Color(hex: s.color, alpha: s.opacity ?? 1))
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
        let text = Text(s.text ?? "").font(Font(RedlineFonts.page(size: 17 * s.scale, weight: .bold) as CTFont)).tracking(2 * s.scale).foregroundStyle(c)
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
                let mark = Text(f.type == .radio ? "●" : "✓").font(.system(size: 16, weight: .bold)).foregroundStyle(accent)
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


/// White speckle texture for notebook covers (drawn over the cover colour). Generated once, deterministic.
final class CoverTexture: @unchecked Sendable {
    static let shared = CoverTexture()
    let image: UIImage

    private init() {
        let W = Metrics.notesCanvas.w, H = Metrics.notesCanvas.h
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = false
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        image = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { c in
            let cg = c.cgContext
            // fine speckle
            for _ in 0..<5200 {
                let x = rnd() * W, y = rnd() * H
                let w = 1.2 + rnd() * 5.5, h = 1.0 + rnd() * 3.0
                cg.setFillColor(UIColor(white: 1, alpha: 0.55 + rnd() * 0.4).cgColor)
                cg.saveGState()
                cg.translateBy(x: x, y: y); cg.rotate(by: rnd() * .pi)
                cg.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                cg.restoreGState()
            }
            // larger patches
            for _ in 0..<420 {
                let x = rnd() * W, y = rnd() * H
                let w = 5 + rnd() * 16, h = 3 + rnd() * 9
                cg.setFillColor(UIColor(white: 1, alpha: 0.35 + rnd() * 0.4).cgColor)
                cg.saveGState()
                cg.translateBy(x: x, y: y); cg.rotate(by: rnd() * .pi)
                cg.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                cg.restoreGState()
            }
        }
    }
}
