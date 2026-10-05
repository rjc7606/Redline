import UIKit
import PDFKit
import RedlineCore

// Our own appearance for text boxes / callouts / stamps: drawn on screen by a PDFAnnotation subclass and
// written into the PDF as an appearance stream (/AP /N form XObject with the font embedded) so every
// reader shows exactly the same thing — rounded corners, any font, a real border colour.

extension PDFAnnotationKey {
    static let redlineID = PDFAnnotationKey(rawValue: "/RedlineID")
    static let redlineBorder = PDFAnnotationKey(rawValue: "/RedlineBorder")
    static let redlineRadius = PDFAnnotationKey(rawValue: "/RedlineRadius")
    /// Set once the user dragged a text box's corner: the width is theirs, only the height follows the text.
    static let redlineSized = PDFAnnotationKey(rawValue: "/RedlineSized")
    /// Tilt in degrees (stamps sit at -2°, like their preview).
    static let redlineRotation = PDFAnnotationKey(rawValue: "/RedlineRotation")
    static let redlineFlipH = PDFAnnotationKey(rawValue: "/RedlineFlipH")
    static let redlineFlipV = PDFAnnotationKey(rawValue: "/RedlineFlipV")
    /// Callout leader: the side of the box the user put the elbow on (L R T B); absent = face the tip.
    static let redlineSide = PDFAnnotationKey(rawValue: "/RedlineSide")
    /// Standard PDF polygon vertices (x y x y …, page space).
    static let vertices = PDFAnnotationKey(rawValue: "/Vertices")
}

/// Tabler outline glyphs (24-grid, 2 pt stroke) drawn on the page.
enum Glyphs {
    /// `ti ti-sticker-2`
    static let sticker = "M6 4h12a2 2 0 0 1 2 2v7h-5a2 2 0 0 0 -2 2v5h-7a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z"
    static let stickerFold = "M20 13v.172a2 2 0 0 1 -.586 1.414l-4.828 4.828a2 2 0 0 1 -1.414 .586h-.172"
    /// `ti ti-bubble-text`
    static let bubble = "M12.4 3a5.34 5.34 0 0 1 4.906 3.239a5.333 5.333 0 0 1 -1.195 10.6a4.26 4.26 0 0 1 -5.28 1.863l-3.831 2.298v-3.134a2.668 2.668 0 0 1 -1.795 -3.773a4.8 4.8 0 0 1 2.908 -8.933a5.33 5.33 0 0 1 4.287 -2.16"
    static let bubbleLines = "M8 10h8M8 14h5"

    static func cgPath(_ d: String, scale k: CGFloat) -> CGPath { SVGPath.parse(d).path(scale: Double(k)).cgPath }
}

/// Everything needed to draw a text box.
struct TextBoxLook {
    var fill: UIColor
    var textColor: UIColor
    var border: UIColor
    var borderWidth: CGFloat
    var radius: CGFloat
    var font: UIFont
    var text: String
    var centered: Bool
    var rotation: CGFloat = 0
    static let padding = CGSize(width: 8, height: 5)
}

extension PDFAnnotation {
    var redlineID: String? { value(forAnnotationKey: .redlineID) as? String }

    var borderColorHex: String? {
        get { value(forAnnotationKey: .redlineBorder) as? String }
        set { if let v = newValue { setValue(NSString(string: v), forAnnotationKey: .redlineBorder) } else { removeValue(forAnnotationKey: .redlineBorder) } }
    }
    var cornerRadius: CGFloat {
        get { CGFloat((value(forAnnotationKey: .redlineRadius) as? NSNumber)?.doubleValue ?? 6) }
        set { setValue(NSNumber(value: Double(newValue)), forAnnotationKey: .redlineRadius) }
    }

    var rotationDegrees: CGFloat {
        get { CGFloat((value(forAnnotationKey: .redlineRotation) as? NSNumber)?.doubleValue ?? 0) }
        set { if newValue == 0 { removeValue(forAnnotationKey: .redlineRotation) } else { setValue(NSNumber(value: Double(newValue)), forAnnotationKey: .redlineRotation) } }
    }
    /// Image stamps: mirrored horizontally / vertically.
    var flipH: Bool {
        get { (value(forAnnotationKey: .redlineFlipH) as? NSNumber)?.boolValue ?? false }
        set { if newValue { setValue(NSNumber(value: true), forAnnotationKey: .redlineFlipH) } else { removeValue(forAnnotationKey: .redlineFlipH) } }
    }
    var flipV: Bool {
        get { (value(forAnnotationKey: .redlineFlipV) as? NSNumber)?.boolValue ?? false }
        set { if newValue { setValue(NSNumber(value: true), forAnnotationKey: .redlineFlipV) } else { removeValue(forAnnotationKey: .redlineFlipV) } }
    }
    /// The PDF /F "Locked" flag (bit 8): other readers honour it too.
    var annotationFlags: Int { (value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 4 }
    var isLockedFlag: Bool {
        get { annotationFlags & 128 != 0 }
        set {
            var f = annotationFlags
            if newValue { f |= 128 } else { f &= ~128 }
            setValue(NSNumber(value: f), forAnnotationKey: .flags)
        }
    }

    var isRedlineTextBox: Bool { subtype == "FreeText" && redlineID != nil }
    var isRedlineNote: Bool { subtype == "Text" && redlineID != nil }
    /// A bucket fill: a /Polygon with an interior colour, grouped under the outline it fills.
    var isRedlinePolygon: Bool { subtype == "Polygon" && redlineID != nil }
    /// A line / arrow drawn with Redline's rounded look.
    var isRedlineLine: Bool { subtype == "Line" && redlineID != nil }
    /// A form field drawn with Redline's look.
    var isRedlineWidget: Bool { subtype == "Widget" && redlineID != nil }
    /// A rectangle / ellipse drawn by Redline.
    var isRedlineShape: Bool { (subtype == "Square" || subtype == "Circle") && redlineID != nil }
    /// An image stamp placed by Redline (its pixels live in the appearance stream; in-session also in ImageStore).
    var isRedlineImage: Bool { subtype == "Stamp" && redlineID != nil }
    /// A reply or review-state note Redline made: gets a blank appearance so no reader draws it.
    var isRedlineHiddenNote: Bool { (isReply || isStateAnnotation) && redlineID != nil }
    /// Pen / marker ink drawn by Redline (PDFKit ignores an Ink annotation's opacity and doubles overlaps).
    var isRedlineInk: Bool { subtype == "Ink" && redlineID != nil }
    /// Highlight / underline / strikeout / squiggly drawn by Redline (PDFKit ignores their opacity).
    var isRedlineMarkup: Bool { ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(subtype) && redlineID != nil }

    /// Polygon vertices in page space.
    var polygonVertices: [CGPoint] {
        get {
            guard let nums = value(forAnnotationKey: .vertices) as? [NSNumber], nums.count >= 4 else { return [] }
            return stride(from: 0, to: nums.count - 1, by: 2).map { CGPoint(x: CGFloat(nums[$0].doubleValue), y: CGFloat(nums[$0 + 1].doubleValue)) }
        }
        set { setValue(newValue.flatMap { [NSNumber(value: Double($0.x)), NSNumber(value: Double($0.y))] } as NSArray, forAnnotationKey: .vertices) }
    }
    /// A text box whose width the user set by dragging its corner.
    var isManuallySized: Bool {
        get { (value(forAnnotationKey: .redlineSized) as? NSNumber)?.boolValue ?? false }
        set { if newValue { setValue(NSNumber(value: true), forAnnotationKey: .redlineSized) } else { removeValue(forAnnotationKey: .redlineSized) } }
    }

    var textBoxLook: TextBoxLook {
        let borderHex = borderColorHex ?? PDFColors.hex(fontColor ?? .black)
        return TextBoxLook(fill: color, textColor: fontColor ?? .black, border: PDFColors.uiColor(borderHex),
                           borderWidth: border?.lineWidth ?? 1, radius: cornerRadius,
                           font: font ?? RedlineFonts.page(size: 16, weight: nil), text: contents ?? "",
                           centered: alignment == .center, rotation: rotationDegrees)
    }
}

/// FreeText drawn with our look on screen (PDFKit calls `draw` instead of using the default appearance).
final class RedlineFreeText: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let look = textBoxLook
        context.saveGState()
        // PDFKit hands us page space (y up); flip into a top-left, y-down box for UIKit text drawing.
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        TextBoxRenderer.draw(look, size: bounds.size, in: context)
        UIGraphicsPopContext()
        context.restoreGState()
    }
}

/// Sticky note drawn as the Tabler `sticker-2` glyph in the note's colour.
final class RedlineNote: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        NoteRenderer.draw(color: color, size: bounds.size, in: context)
        context.restoreGState()
    }
}

/// Ink drawn with the annotation's opacity applied once to the whole annotation (all its strokes in one
/// transparency layer, so overlapping strokes and joins never go darker), multiply blend for markers.
final class RedlineInk: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        InkRenderer.draw(self, origin: .zero, in: context)   // page space on screen
    }
}

enum InkRenderer {
    static func draw(_ a: PDFAnnotation, origin: CGPoint, in cg: CGContext) {
        let paths = AnnotationFactory.inkPaths(a)
        guard !paths.isEmpty else { return }
        let w = max(0.3, a.border?.lineWidth ?? 2)
        let marker = a.redlineTool == .marker || a.redlineTool == .highlighter
        cg.saveGState()
        if marker { cg.setBlendMode(.multiply) }
        cg.setAlpha(CGFloat(a.opacityValue))
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        cg.setStrokeColor(a.color.cgColor)
        cg.setLineWidth(w)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        if let d = AnnotationFactory.dashLengths(of: a) { cg.setLineDash(phase: 0, lengths: d) }
        for path in paths {
            guard let f = path.first else { continue }
            cg.move(to: CGPoint(x: f.x - origin.x, y: f.y - origin.y))
            if path.count == 1 { cg.addLine(to: CGPoint(x: f.x - origin.x + 0.1, y: f.y - origin.y)) }
            for p in path.dropFirst() { cg.addLine(to: CGPoint(x: p.x - origin.x, y: p.y - origin.y)) }
        }
        cg.strokePath()
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let origin = a.bounds.origin
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(a, origin: origin, in: cg)
        }
    }
}

/// Text markup (highlight, underline, strikeout, squiggly) drawn at its real opacity; PDFKit's default draws
/// highlights fully opaque whatever /CA says.
final class RedlineMarkup: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        MarkupRenderer.draw(self, origin: .zero, in: context)   // page space on screen
    }
}

enum MarkupRenderer {
    /// Quads as (upper-left, upper-right, lower-left, lower-right) in page space.
    static func quads(of a: PDFAnnotation) -> [[CGPoint]] {
        let pts = (a.quadrilateralPoints as? [NSValue])?.map { $0.cgPointValue } ?? []
        var out: [[CGPoint]] = []
        var i = 0
        while i + 3 < pts.count {
            out.append((0..<4).map { CGPoint(x: pts[i + $0].x + a.bounds.minX, y: pts[i + $0].y + a.bounds.minY) })
            i += 4
        }
        return out
    }

    /// Draws into a context whose origin is `origin` (page space, y up).
    static func draw(_ a: PDFAnnotation, origin: CGPoint, in cg: CGContext) {
        let qs = quads(of: a)
        guard !qs.isEmpty else { return }
        cg.saveGState()
        cg.setAlpha(CGFloat(a.opacityValue))
        cg.setFillColor(a.color.cgColor); cg.setStrokeColor(a.color.cgColor)
        cg.setLineCap(.round)
        for q in qs {
            let ul = q[0], ur = q[1], ll = q[2]
            let x0 = min(ul.x, ll.x) - origin.x, x1 = max(ur.x, q[3].x) - origin.x
            let top = max(ul.y, ur.y) - origin.y, bottom = min(ll.y, q[3].y) - origin.y
            let h = max(1, top - bottom)
            switch a.subtype {
            case "Highlight":
                cg.setBlendMode(.multiply)
                cg.fill(CGRect(x: x0, y: bottom, width: x1 - x0, height: h))
            case "Underline":
                cg.setLineWidth(max(1, h * 0.07))
                cg.move(to: CGPoint(x: x0, y: bottom + h * 0.08)); cg.addLine(to: CGPoint(x: x1, y: bottom + h * 0.08)); cg.strokePath()
            case "StrikeOut":
                cg.setLineWidth(max(1, h * 0.08))
                cg.move(to: CGPoint(x: x0, y: bottom + h * 0.5)); cg.addLine(to: CGPoint(x: x1, y: bottom + h * 0.5)); cg.strokePath()
            default: // Squiggly
                cg.setLineWidth(max(0.8, h * 0.06))
                let amp = max(1, h * 0.09), step = amp * 2
                var x = x0, up = false
                cg.move(to: CGPoint(x: x, y: bottom))
                while x < x1 { x = min(x1, x + step); cg.addLine(to: CGPoint(x: x, y: bottom + (up ? 0 : amp))); up.toggle() }
                cg.strokePath()
            }
        }
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let origin = a.bounds.origin
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(a, origin: origin, in: cg)
        }
    }
}

/// Form field drawn with Redline's look (rounded tinted box, real check / radio / switch glyphs, placeholder names).
final class RedlineWidget: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        WidgetRenderer.draw(self, size: bounds.size, in: context)
        UIGraphicsPopContext()
        context.restoreGState()
    }
}

enum WidgetRenderer {
    static let accent = UIColor(hex: "#2F6FE4")
    static let fill = UIColor(hex: "#EEF3FD")
    static let border = UIColor(hex: "#7FA3EA")
    static let ink = UIColor(hex: "#2a2622")
    static let muted = UIColor(hex: "#968e84")

    /// Draws a field into a y-down context whose origin is its top-left corner.
    static func draw(_ a: PDFAnnotation, size: CGSize, in cg: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        let value = a.widgetStringValue ?? ""
        let tool = a.redlineTool
        switch a.widgetFieldType {
        case .button:
            let on = !value.isEmpty && value != "Off"
            if tool == .ftoggle { drawSwitch(on: on, rect, cg) }
            else if a.widgetControlType == .radioButtonControl { drawRadio(on: on, rect, cg) }
            else { drawCheck(on: on, rect, cg) }
        case .signature:
            drawSignature(value: value, rect, cg)
        default:
            drawField(value: value, name: a.fieldName ?? "", rect, cg, area: tool == .farea, date: tool == .fdate, choice: a.widgetFieldType == .choice)
        }
    }

    private static func box(_ rect: CGRect, radius: CGFloat, _ cg: CGContext) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), cornerRadius: radius).cgPath
        cg.setFillColor(fill.cgColor); cg.addPath(path); cg.fillPath()
        cg.setStrokeColor(border.cgColor); cg.setLineWidth(1.2); cg.addPath(path); cg.strokePath()
    }

    private static func text(_ s: String, in r: CGRect, size: CGFloat, color: UIColor, italic: Bool = false, top: Bool = false) {
        let font = italic ? UIFont.italicSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size, weight: .medium)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        var draw = r
        if !top { draw.origin.y = r.midY - font.lineHeight / 2; draw.size.height = font.lineHeight }
        str.draw(with: draw, options: [.usesLineFragmentOrigin], context: nil)
    }

    private static func drawField(value: String, name: String, _ rect: CGRect, _ cg: CGContext, area: Bool, date: Bool, choice: Bool) {
        box(rect, radius: 4, cg)
        let fs = max(8, min(12, rect.height * (area ? 0.22 : 0.5)))
        var inner = rect.insetBy(dx: 6, dy: 3)
        if choice || date { inner.size.width -= 16 }
        if value.isEmpty {
            let placeholder = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces).capitalized
            text(placeholder.isEmpty ? (date ? "Date" : "Text") : placeholder, in: inner, size: fs, color: muted, italic: true, top: area)
        } else {
            text(value, in: inner, size: fs, color: ink, top: area)
        }
        cg.setStrokeColor(border.cgColor); cg.setLineWidth(1.5); cg.setLineCap(.round); cg.setLineJoin(.round)
        if choice {
            let c = CGPoint(x: rect.maxX - 11, y: rect.midY)
            cg.move(to: CGPoint(x: c.x - 4, y: c.y - 2)); cg.addLine(to: c.applying(.init(translationX: 0, y: 2))); cg.addLine(to: CGPoint(x: c.x + 4, y: c.y - 2)); cg.strokePath()
        } else if date {
            let s: CGFloat = 10
            let r = CGRect(x: rect.maxX - 6 - s, y: rect.midY - s / 2, width: s, height: s)
            cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: 2).cgPath); cg.strokePath()
            cg.move(to: CGPoint(x: r.minX, y: r.minY + 3)); cg.addLine(to: CGPoint(x: r.maxX, y: r.minY + 3)); cg.strokePath()
        }
    }

    private static func drawCheck(on: Bool, _ rect: CGRect, _ cg: CGContext) {
        let s = min(rect.width, rect.height)
        let r = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s).insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: r, cornerRadius: s * 0.22).cgPath
        cg.setFillColor((on ? accent : fill).cgColor); cg.addPath(path); cg.fillPath()
        cg.setStrokeColor((on ? accent : border).cgColor); cg.setLineWidth(1.2); cg.addPath(path); cg.strokePath()
        if on {
            cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(max(1.5, s * 0.12)); cg.setLineCap(.round); cg.setLineJoin(.round)
            cg.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.midY))
            cg.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.7))
            cg.addLine(to: CGPoint(x: r.minX + r.width * 0.77, y: r.minY + r.height * 0.3))
            cg.strokePath()
        }
    }

    private static func drawRadio(on: Bool, _ rect: CGRect, _ cg: CGContext) {
        let s = min(rect.width, rect.height)
        let r = CGRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s).insetBy(dx: 1, dy: 1)
        cg.setFillColor(fill.cgColor); cg.fillEllipse(in: r)
        cg.setStrokeColor((on ? accent : border).cgColor); cg.setLineWidth(on ? 1.6 : 1.2); cg.strokeEllipse(in: r)
        if on { cg.setFillColor(accent.cgColor); cg.fillEllipse(in: r.insetBy(dx: r.width * 0.28, dy: r.height * 0.28)) }
    }

    private static func drawSwitch(on: Bool, _ rect: CGRect, _ cg: CGContext) {
        let h = min(rect.height, rect.width / 1.7)
        let w = h * 1.7
        let track = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        cg.setFillColor((on ? accent : UIColor(hex: "#cfc9be")).cgColor)
        cg.addPath(UIBezierPath(roundedRect: track, cornerRadius: h / 2).cgPath); cg.fillPath()
        let k = h - 4
        let knob = CGRect(x: on ? track.maxX - 2 - k : track.minX + 2, y: track.minY + 2, width: k, height: k)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: knob)
        cg.restoreGState()
    }

    private static func drawSignature(value: String, _ rect: CGRect, _ cg: CGContext) {
        box(rect, radius: 4, cg)
        let base = rect.minY + rect.height * 0.74
        cg.setStrokeColor(border.cgColor); cg.setLineWidth(1)
        cg.move(to: CGPoint(x: rect.minX + 8, y: base)); cg.addLine(to: CGPoint(x: rect.maxX - 8, y: base)); cg.strokePath()
        text("×", in: CGRect(x: rect.minX + 6, y: base - 14, width: 12, height: 14), size: 11, color: muted)
        if value.isEmpty {
            text("Sign here", in: CGRect(x: rect.minX + 20, y: base - 14, width: rect.width - 28, height: 14), size: max(8, min(10, rect.height * 0.3)), color: muted, italic: true)
        } else {
            text(value, in: CGRect(x: rect.minX + 20, y: rect.minY + 2, width: rect.width - 28, height: base - rect.minY - 2), size: max(10, min(16, rect.height * 0.45)), color: ink, italic: true)
        }
    }

    /// Text-like fields get an appearance stream; check / radio / switch states are left to the reader (they need
    /// per-state streams), so only their /MK colours travel.
    static func wantsAppearance(_ a: PDFAnnotation) -> Bool { a.isRedlineWidget && a.widgetFieldType != .button }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            draw(a, size: size, in: c.cgContext)
        }
    }
}

/// Images placed this session, by Redline id (after a reload the appearance stream carries the pixels).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    private var images: [String: UIImage] = [:]
    func image(for id: String?) -> UIImage? { id.flatMap { images[$0] } }
    func set(_ img: UIImage, for id: String) { images[id] = img }

    /// Pixels for an image stamp: the session image, or — after a reload — its saved appearance rasterised. The
    /// saved look already contains any rotation or flip, so those keys are reset to match the baked image.
    @MainActor
    func resolve(_ a: RedlineImage) -> UIImage? {
        if let img = image(for: a.redlineID) { return img }
        guard let id = a.redlineID, a.bounds.width > 1, a.bounds.height > 1 else { return nil }
        let size = a.bounds.size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
            cg.translateBy(x: -a.bounds.minX, y: -a.bounds.minY)
            a.drawStored(in: cg)
        }
        a.rotationDegrees = 0; a.flipH = false; a.flipV = false
        images[id] = img
        return img
    }
}

/// Image stamp: drawn from the in-session image when there is one, else from its appearance stream.
final class RedlineImage: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let img = ImageStore.shared.image(for: redlineID), let cg = img.cgImage else { super.draw(with: box, in: context); return }
        ImageStampRenderer.draw(cg, bounds: bounds, rotation: rotationDegrees, flipH: flipH, flipV: flipV, in: context)
    }
    /// The saved appearance stream, as any reader shows it.
    func drawStored(in cg: CGContext) { super.draw(with: .cropBox, in: cg) }
}

enum ImageStampRenderer {
    /// Draws the image inside `bounds` (page space, y up), tilted and mirrored about the centre.
    static func draw(_ img: CGImage, bounds: CGRect, rotation: CGFloat, flipH: Bool, flipV: Bool, in cg: CGContext) {
        let inner = TextBoxRenderer.innerSize(outer: bounds.size, rotation: rotation)
        cg.saveGState()
        cg.interpolationQuality = .high
        cg.translateBy(x: bounds.midX, y: bounds.midY)
        cg.rotate(by: -rotation * .pi / 180)   // positive = clockwise on screen
        cg.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
        cg.draw(img, in: CGRect(x: -inner.width / 2, y: -inner.height / 2, width: inner.width, height: inner.height))
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data? {
        guard let img = ImageStore.shared.image(for: a.redlineID), let cgImage = img.cgImage else { return nil }
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(cgImage, bounds: CGRect(origin: .zero, size: size), rotation: a.rotationDegrees, flipH: a.flipH, flipV: a.flipV, in: cg)
        }
    }
}

/// A blank appearance (a content stream that paints nothing) for notes that must stay invisible.
enum BlankRenderer {
    static func appearancePDF(for a: PDFAnnotation) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 1, height: 1)).pdfData { c in
            c.beginPage()
            c.cgContext.setAlpha(0)
            c.cgContext.fill(CGRect(x: 0, y: 0, width: 0.1, height: 0.1))   // ensures a content stream exists
        }
    }
}

/// Rectangle / ellipse drawn by Redline: real dotted borders, opacity, interior fill.
final class RedlineShape: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        ShapeRenderer.draw(self, origin: .zero, in: context)
    }
}

enum ShapeRenderer {
    static func draw(_ a: PDFAnnotation, origin: CGPoint, in cg: CGContext) {
        let w = max(0, a.border?.lineWidth ?? 1)
        let r = a.bounds.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: w / 2, dy: w / 2)
        let path = a.subtype == "Circle" ? UIBezierPath(ovalIn: r).cgPath : UIBezierPath(rect: r).cgPath
        cg.saveGState()
        cg.setAlpha(CGFloat(a.opacityValue))
        if let ic = a.interiorColor {
            var al: CGFloat = 1; ic.getWhite(nil, alpha: &al)
            cg.setFillColor(ic.cgColor)
            cg.addPath(path); cg.fillPath()
            _ = al
        }
        if w > 0.05 {
            cg.setStrokeColor(a.color.cgColor)
            cg.setLineWidth(w); cg.setLineCap(.round); cg.setLineJoin(.round)
            if let d = AnnotationFactory.dashLengths(of: a) { cg.setLineDash(phase: 0, lengths: d) }
            cg.addPath(path); cg.strokePath()
        }
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let origin = a.bounds.origin
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(a, origin: origin, in: cg)
        }
    }
}

/// Line / arrow drawn with round caps and joins (PDFKit's default draws them square).
final class RedlineLine: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        LineRenderer.draw(self, origin: .zero, in: context)   // page space on screen
    }
}

enum LineRenderer {
    /// Draws the shaft and open arrow heads in a context whose origin is `origin` (page space, y up).
    static func draw(_ a: PDFAnnotation, origin: CGPoint, in cg: CGContext) {
        let w = max(0.5, a.border?.lineWidth ?? 1)
        // startPoint / endPoint are relative to the annotation's bounds.
        let p0 = CGPoint(x: a.bounds.minX + a.startPoint.x - origin.x, y: a.bounds.minY + a.startPoint.y - origin.y)
        let p1 = CGPoint(x: a.bounds.minX + a.endPoint.x - origin.x, y: a.bounds.minY + a.endPoint.y - origin.y)
        cg.saveGState()
        cg.setAlpha(CGFloat(a.opacityValue))
        cg.setStrokeColor(a.color.cgColor)
        cg.setLineWidth(w)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        if let d = AnnotationFactory.dashLengths(of: a) { cg.setLineDash(phase: 0, lengths: d) }
        cg.move(to: p0); cg.addLine(to: p1); cg.strokePath()
        cg.setLineDash(phase: 0, lengths: [])
        cg.setFillColor(a.color.cgColor)
        ending(a.endLineStyle, at: p1, from: p0, width: w, in: cg)
        ending(a.startLineStyle, at: p0, from: p1, width: w, in: cg)
        if a.redlineTool == .distance || a.redlineTool == .calibrate {
            // Dimension ticks: short hashes across both ends, like a drawing.
            let t = max(5, w * 3)
            let ang = atan2(p1.y - p0.y, p1.x - p0.x)
            for e in [p0, p1] {
                cg.move(to: CGPoint(x: e.x - t * sin(ang), y: e.y + t * cos(ang)))
                cg.addLine(to: CGPoint(x: e.x + t * sin(ang), y: e.y - t * cos(ang)))
            }
            cg.strokePath()
        }
        cg.restoreGState()
    }

    /// One line ending at `tip`, pointing away from `from`. Stroke and fill colours are already set.
    static func ending(_ style: PDFLineStyle, at tip: CGPoint, from: CGPoint, width w: CGFloat, in cg: CGContext) {
        let size = max(10, w * 4)
        let ang = atan2(tip.y - from.y, tip.x - from.x)
        let l = CGPoint(x: tip.x - size * cos(ang - 0.45), y: tip.y - size * sin(ang - 0.45))
        let r = CGPoint(x: tip.x - size * cos(ang + 0.45), y: tip.y - size * sin(ang + 0.45))
        switch style {
        case .openArrow:
            cg.move(to: l); cg.addLine(to: tip); cg.addLine(to: r); cg.strokePath()
        case .closedArrow:
            cg.move(to: l); cg.addLine(to: tip); cg.addLine(to: r); cg.closePath(); cg.drawPath(using: .fillStroke)
        case .circle:
            let rad = max(3, w * 1.8)
            cg.fillEllipse(in: CGRect(x: tip.x - rad, y: tip.y - rad, width: rad * 2, height: rad * 2))
        case .square, .diamond:
            let rad = max(3, w * 1.6)
            cg.saveGState(); cg.translateBy(x: tip.x, y: tip.y); cg.rotate(by: ang)
            cg.fill(CGRect(x: -rad, y: -rad, width: rad * 2, height: rad * 2)); cg.restoreGState()
        default: break
        }
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let origin = a.bounds.origin
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(a, origin: origin, in: cg)
        }
    }
}

/// Bucket fill drawn as a filled polygon (readers that know /Polygon /IC show it too; the appearance stream covers the rest).
final class RedlinePolygon: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        PolygonRenderer.draw(self, origin: .zero, in: context)   // page space on screen
    }
}

enum PolygonRenderer {
    /// Fills the polygon in a context whose origin is `origin` (page space, y up).
    static func draw(_ a: PDFAnnotation, origin: CGPoint, in cg: CGContext) {
        let pts = a.polygonVertices
        guard pts.count >= 3, let fill = a.interiorColor else { return }
        cg.saveGState()
        cg.setAlpha(CGFloat(a.opacityValue))
        cg.setFillColor(fill.cgColor)
        cg.move(to: CGPoint(x: pts[0].x - origin.x, y: pts[0].y - origin.y))
        for p in pts.dropFirst() { cg.addLine(to: CGPoint(x: p.x - origin.x, y: p.y - origin.y)) }
        cg.closePath()
        cg.fillPath()
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let origin = a.bounds.origin
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            // UIKit's PDF context is y-down; flip so page-space vertices land where readers expect.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(a, origin: origin, in: cg)
        }
    }
}

enum NoteRenderer {
    /// Draws the sticker glyph into a y-down context whose origin is the note's top-left corner.
    static func draw(color: UIColor, size: CGSize, in cg: CGContext) {
        let k = min(size.width, size.height) / 24
        cg.saveGState()
        cg.translateBy(x: (size.width - 24 * k) / 2, y: (size.height - 24 * k) / 2)
        let body = Glyphs.cgPath(Glyphs.sticker, scale: k)
        cg.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        cg.addPath(body); cg.fillPath()
        cg.setFillColor(color.withAlphaComponent(0.22).cgColor)
        cg.addPath(body); cg.fillPath()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(2 * k); cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.addPath(body); cg.strokePath()
        cg.addPath(Glyphs.cgPath(Glyphs.stickerFold, scale: k)); cg.strokePath()
        cg.restoreGState()
    }

    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let color = a.color
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            draw(color: color, size: size, in: c.cgContext)
        }
    }
}

enum TextBoxRenderer {
    /// Draws a text box into a y-down context whose origin is the box's top-left corner. A tilted box (stamp)
    /// is the un-tilted box rotated about the centre of its (larger) bounds.
    static func draw(_ look: TextBoxLook, size: CGSize, in cg: CGContext) {
        guard look.rotation != 0 else { drawBox(look, size: size, in: cg); return }
        let inner = innerSize(outer: size, rotation: look.rotation)
        cg.saveGState()
        cg.translateBy(x: size.width / 2, y: size.height / 2)
        cg.rotate(by: look.rotation * .pi / 180)
        cg.translateBy(x: -inner.width / 2, y: -inner.height / 2)
        drawBox(look, size: inner, in: cg)
        cg.restoreGState()
    }

    /// Bounds a box needs once tilted.
    static func outerSize(inner: CGSize, rotation: CGFloat) -> CGSize {
        let r = abs(rotation) * .pi / 180, c = cos(r), s = sin(r)
        return CGSize(width: ceil(inner.width * c + inner.height * s), height: ceil(inner.width * s + inner.height * c))
    }
    /// The un-tilted box inside tilted bounds.
    static func innerSize(outer: CGSize, rotation: CGFloat) -> CGSize {
        let r = abs(rotation) * .pi / 180, c = cos(r), s = sin(r)
        let det = c * c - s * s
        guard det > 0.05 else { return outer }
        return CGSize(width: max(1, (outer.width * c - outer.height * s) / det), height: max(1, (outer.height * c - outer.width * s) / det))
    }

    private static func drawBox(_ look: TextBoxLook, size: CGSize, in cg: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        let inset = look.borderWidth / 2
        let boxPath = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: max(0, look.radius - inset))
        var alpha: CGFloat = 1
        look.fill.getWhite(nil, alpha: &alpha)
        if alpha > 0.005 {
            cg.setFillColor(look.fill.cgColor)
            cg.addPath(boxPath.cgPath)
            cg.fillPath()
        }
        if look.borderWidth > 0.05 {
            cg.setStrokeColor(look.border.cgColor)
            cg.setLineWidth(look.borderWidth)
            cg.addPath(boxPath.cgPath)
            cg.strokePath()
        }
        let para = NSMutableParagraphStyle()
        para.alignment = look.centered ? .center : .left
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: look.font, .foregroundColor: look.textColor, .paragraphStyle: para]
        let textRect = rect.insetBy(dx: TextBoxLook.padding.width, dy: TextBoxLook.padding.height)
        let str = NSAttributedString(string: look.text.isEmpty ? " " : look.text, attributes: attrs)
        let needed = str.boundingRect(with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        var drawRect = textRect
        if look.centered { drawRect.origin.y += max(0, (textRect.height - needed.height) / 2) }
        str.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)
    }

    /// Size a box needs for its text (used when text is committed).
    static func fittingSize(text: String, font: UIFont, maxWidth: CGFloat = 480) -> CGSize {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let s = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font, .paragraphStyle: para])
        let r = s.boundingRect(with: CGSize(width: maxWidth - TextBoxLook.padding.width * 2, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        return CGSize(width: ceil(r.width) + TextBoxLook.padding.width * 2 + 2, height: ceil(r.height) + TextBoxLook.padding.height * 2 + 2)
    }

    /// A one-page PDF of the box (Core Graphics embeds a subset of the font).
    static func appearancePDF(for a: PDFAnnotation) -> Data {
        let size = CGSize(width: max(1, a.bounds.width), height: max(1, a.bounds.height))
        let look = a.textBoxLook
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            draw(look, size: size, in: c.cgContext)
        }
    }
}

/// After PDFKit saves the file, attaches appearance streams for our text boxes via an incremental update.
@MainActor
enum AppearancePatcher {
    @discardableResult
    static func patch(fileURL: URL, annotations: [PDFAnnotation]) -> Bool {
        let ours = annotations.filter { $0.isRedlineTextBox || $0.isRedlineNote || $0.isRedlinePolygon || $0.isRedlineLine || $0.isRedlineMarkup || $0.isRedlineInk || $0.isRedlineShape || $0.isRedlineHiddenNote || WidgetRenderer.wantsAppearance($0) || ($0.isRedlineImage && ImageStore.shared.image(for: $0.redlineID) != nil) }
        guard !ours.isEmpty, let data = try? Data(contentsOf: fileURL), let file = PDFFile(data: data) else { return ours.isEmpty }
        var byID: [String: (num: Int, dict: [String: PDFObj])] = [:]
        for page in file.pages() {
            for (n, d) in file.annotations(of: page.dict) {
                if let id = d["RedlineID"]?.stringValue { byID[id] = (n, d) }
            }
        }
        var newObjects: [Int: PDFObj] = [:]
        var next = file.maxObjectNumber
        for a in ours {
            guard let id = a.redlineID, let entry = byID[id] else { continue }
            let helperData: Data
            if a.isRedlineNote { helperData = NoteRenderer.appearancePDF(for: a) }
            else if a.isRedlinePolygon { helperData = PolygonRenderer.appearancePDF(for: a) }
            else if a.isRedlineLine { helperData = LineRenderer.appearancePDF(for: a) }
            else if a.isRedlineWidget { helperData = WidgetRenderer.appearancePDF(for: a) }
            else if a.isRedlineMarkup { helperData = MarkupRenderer.appearancePDF(for: a) }
            else if a.isRedlineInk { helperData = InkRenderer.appearancePDF(for: a) }
            else if a.isRedlineShape { helperData = ShapeRenderer.appearancePDF(for: a) }
            else if a.isRedlineHiddenNote { helperData = BlankRenderer.appearancePDF(for: a) }
            else if a.isRedlineImage { guard let d = ImageStampRenderer.appearancePDF(for: a) else { continue }; helperData = d }
            else { helperData = TextBoxRenderer.appearancePDF(for: a) }
            guard let helper = PDFFile(data: helperData), let page = helper.pages().first else { continue }
            let importer = PDFObjectImporter(source: helper, firstFreeNumber: next)
            // Content stream(s) of the helper page become the form's content.
            let contents = helper.resolve(page.dict["Contents"] ?? .null)
            var raw = Data()
            var streamDict: [String: PDFObj] = [:]
            if case .stream(let d, let r) = contents {
                raw = r
                streamDict = d
            } else if let arr = contents.arrayValue {
                var joined = Data()
                for part in arr {
                    let s = helper.resolve(part)
                    if let dec = PDFFilters.decode(s, resolve: helper.resolve) { joined.append(dec); joined.append(0x0A) }
                }
                raw = PDFFilters.deflate(joined)
                streamDict = ["Filter": .name("FlateDecode")]
            } else { continue }
            var form = streamDict
            form["Length"] = nil
            form["Type"] = .name("XObject")
            form["Subtype"] = .name("Form")
            form["FormType"] = .integer(1)
            let w = Double(max(1, a.bounds.width)), h = Double(max(1, a.bounds.height))
            form["BBox"] = .array([.integer(0), .integer(0), .real(w), .real(h)])
            form["Matrix"] = .array([.integer(1), .integer(0), .integer(0), .integer(1), .integer(0), .integer(0)])
            if let res = page.dict["Resources"] { form["Resources"] = importer.copy(res) }
            let formNum = importer.allocate()
            for (n, o) in importer.objects { newObjects[n] = o }
            newObjects[formNum] = .stream(dict: form, raw: raw)
            next = importer.nextFree
            var annot = entry.dict
            annot["AP"] = .dictionary(["N": .reference(formNum, 0)])
            annot["AS"] = nil
            newObjects[entry.num] = .dictionary(annot)
        }
        guard !newObjects.isEmpty else { return true }
        let out = file.incrementalUpdate(objects: newObjects)
        do { try out.write(to: fileURL, options: .atomic); return true } catch { return false }
    }

    /// Nothing is touched when a document loads: every annotation renders from the appearance stream the file
    /// carries. A Redline-made annotation is promoted to its drawing subclass only when the user selects it, and
    /// its appearance stream is kept until an edit replaces it.
    static func needsPromotion(_ a: PDFAnnotation) -> Bool {
        (a.isRedlineTextBox && !(a is RedlineFreeText)) || (a.isRedlineNote && !(a is RedlineNote))
            || (a.isRedlinePolygon && !(a is RedlinePolygon)) || (a.isRedlineLine && !(a is RedlineLine))
            || (a.isRedlineWidget && !(a is RedlineWidget)) || (a.isRedlineMarkup && !(a is RedlineMarkup))
            || (a.isRedlineInk && !(a is RedlineInk)) || (a.isRedlineShape && !(a is RedlineShape))
            || (a.isRedlineImage && !(a is RedlineImage))
    }

    /// Promotes a group of annotations in place: same page order, same keys (including /AP), replies re-pointed.
    static func promote(_ group: [PDFAnnotation], on page: PDFPage) -> [PDFAnnotation] {
        guard group.contains(where: needsPromotion) else { return group }
        let ordered = page.annotations.filter { a in group.contains { $0 === a } }
        var map: [ObjectIdentifier: PDFAnnotation] = [:]
        for a in ordered { page.removeAnnotation(a) }
        for a in ordered {
            let r: PDFAnnotation
            if !needsPromotion(a) { r = a }
            else if a.isRedlineNote { r = RedlineNote(bounds: a.bounds, forType: .text, withProperties: a.annotationKeyValues) }
            else if a.isRedlinePolygon { r = RedlinePolygon(bounds: a.bounds, forType: PDFAnnotationSubtype(rawValue: "/Polygon"), withProperties: a.annotationKeyValues) }
            else if a.isRedlineLine { r = RedlineLine(bounds: a.bounds, forType: .line, withProperties: a.annotationKeyValues) }
            else if a.isRedlineWidget { r = RedlineWidget(bounds: a.bounds, forType: .widget, withProperties: a.annotationKeyValues) }
            else if a.isRedlineMarkup { r = RedlineMarkup(bounds: a.bounds, forType: PDFAnnotationSubtype(rawValue: "/" + a.subtype), withProperties: a.annotationKeyValues) }
            else if a.isRedlineInk { r = RedlineInk(bounds: a.bounds, forType: .ink, withProperties: a.annotationKeyValues) }
            else if a.isRedlineShape { r = RedlineShape(bounds: a.bounds, forType: a.subtype == "Circle" ? .circle : .square, withProperties: a.annotationKeyValues) }
            else if a.isRedlineImage { r = RedlineImage(bounds: a.bounds, forType: .stamp, withProperties: a.annotationKeyValues) }
            else { r = RedlineFreeText(bounds: a.bounds, forType: .freeText, withProperties: a.annotationKeyValues) }
            map[ObjectIdentifier(a)] = r
            page.addAnnotation(r)
        }
        for other in page.annotations {
            if let irt = other.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation, let r = map[ObjectIdentifier(irt)], r !== irt {
                other.setValue(r, forAnnotationKey: .inReplyTo)
            }
        }
        return group.map { map[ObjectIdentifier($0)] ?? $0 }
    }
}
