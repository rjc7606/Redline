import UIKit
import PDFKit
import RedlineCore

// MARK: - Keys & helpers

extension PDFAnnotationKey {
    static let inReplyTo = PDFAnnotationKey(rawValue: "/IRT")
    static let replyType = PDFAnnotationKey(rawValue: "/RT")
    static let state = PDFAnnotationKey(rawValue: "/State")
    static let stateModel = PDFAnnotationKey(rawValue: "/StateModel")
    static let intent = PDFAnnotationKey(rawValue: "/IT")
    static let calloutLine = PDFAnnotationKey(rawValue: "/CL")
    static let creationDate = PDFAnnotationKey(rawValue: "/CreationDate")
    static let opacity = PDFAnnotationKey(rawValue: "/CA")
    static let redlineTool = PDFAnnotationKey(rawValue: "/RedlineTool")
    static let redlineGroup = PDFAnnotationKey(rawValue: "/RedlineGroup")
}

extension PDFAnnotation {
    /// Subtype without the leading slash ("Ink", "FreeText"…).
    var subtype: String { (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    /// The Redline tool that created it (stored in a private key) or a best guess from the subtype.
    var redlineTool: Tool {
        if let raw = value(forAnnotationKey: .redlineTool) as? String, let t = Tool(rawValue: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) { return t }
        switch subtype {
        case "Ink": return .pen
        case "Highlight": return .highlighter
        case "Underline": return .underline
        case "StrikeOut": return .strike
        case "Squiggly": return .squiggly
        case "Square": return .rect
        case "Circle": return .ellipse
        case "Line": return (endLineStyle == .closedArrow || endLineStyle == .openArrow) ? .arrow : .line
        case "FreeText": return .textbox
        case "Text": return .note
        case "Stamp": return .stamps
        case "Widget": return .ftext
        default: return .pen
        }
    }

    var isReply: Bool { value(forAnnotationKey: .inReplyTo) != nil && subtype == "Text" && value(forAnnotationKey: .state) == nil }
    var isStateAnnotation: Bool { value(forAnnotationKey: .state) != nil }
    var isPopup: Bool { subtype == "Popup" }
    var isWidget: Bool { subtype == "Widget" }
    var isLink: Bool { subtype == "Link" }
    /// Grouped child (e.g. a callout's leader line) — RT /Group.
    var isGroupChild: Bool { (value(forAnnotationKey: .replyType) as? String)?.contains("Group") == true }

    /// A comment-bearing, user-visible annotation (what the sidebar lists).
    var isPrimary: Bool { !isReply && !isStateAnnotation && !isPopup && !isLink && !isGroupChild }

    var stableID: String { ObjectIdentifier(self).debugDescription }

    var opacityValue: Double {
        get { (value(forAnnotationKey: .opacity) as? NSNumber)?.doubleValue ?? 1 }
        set { setValue(NSNumber(value: newValue), forAnnotationKey: .opacity) }
    }

    /// Forgets the stored appearance so PDFKit re-renders from the properties (used after an edit).
    func dropAppearance() { removeValue(forAnnotationKey: .appearanceStreams) }
}

enum PDFColors {
    static func uiColor(_ hex: String, alpha: Double = 1) -> UIColor { UIColor(hex: hex, alpha: alpha) }
    static func hex(_ c: UIColor?) -> String {
        guard let c else { return "#FF3B30" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if c.getRed(&r, green: &g, blue: &b, alpha: &a) { return HexColor.format(RGB(Double(r), Double(g), Double(b))) }
        var w: CGFloat = 0
        if c.getWhite(&w, alpha: &a) { return HexColor.format(RGB(Double(w), Double(w), Double(w))) }
        return "#FF3B30"
    }
}

// MARK: - Factories (page space, y up)

enum AnnotationFactory {
    private static func stamp(_ a: PDFAnnotation, tool: Tool, author: String, contents: String = "") {
        a.userName = author
        a.modificationDate = Date()
        a.setValue(NSString(string: "/" + tool.rawValue), forAnnotationKey: .redlineTool)
        if !contents.isEmpty { a.contents = contents }
    }

    /// Bounds enclosing points with a margin for the stroke width.
    static func bounds(for pts: [CGPoint], inset: CGFloat) -> CGRect {
        guard let f = pts.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for p in pts { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -inset, dy: -inset)
    }

    static func ink(paths: [[CGPoint]], tool: Tool, style: StylePreset, author: String) -> PDFAnnotation {
        let w = CGFloat(style.width)
        let all = paths.flatMap { $0 }
        let b = bounds(for: all, inset: w / 2 + 2)
        let a = PDFAnnotation(bounds: b, forType: .ink, withProperties: nil)
        a.color = PDFColors.uiColor(style.color)
        let border = PDFBorder()
        border.lineWidth = w
        border.style = style.lineStyle == .dash ? .dashed : .solid
        if style.lineStyle == .dash { border.dashPattern = [NSNumber(value: Double(w) * 3), NSNumber(value: Double(w) * 2)] }
        a.border = border
        for p in paths { a.add(bezier(for: p, in: b)) }
        if let op = style.opacity, op < 1 { a.opacityValue = op }
        stamp(a, tool: tool, author: author)
        return a
    }

    /// Appends a path to an existing Ink annotation (pen strokes chaining into one comment).
    static func append(path pts: [CGPoint], to a: PDFAnnotation) {
        let w = a.border?.lineWidth ?? 2
        let old = a.bounds
        let newBounds = old.union(bounds(for: pts, inset: w / 2 + 2))
        if newBounds != old {
            // Re-base existing paths on the enlarged bounds.
            let dx = old.minX - newBounds.minX, dy = old.minY - newBounds.minY
            let existing = a.paths ?? []
            for p in existing { a.remove(p) }
            a.bounds = newBounds
            for p in existing { p.apply(CGAffineTransform(translationX: dx, y: dy)); a.add(p) }
        }
        a.add(bezier(for: pts, in: a.bounds))
        a.modificationDate = Date()
        a.dropAppearance()
    }

    static func bezier(for pts: [CGPoint], in b: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        guard let f = pts.first else { return path }
        path.move(to: CGPoint(x: f.x - b.minX, y: f.y - b.minY))
        if pts.count == 1 { path.addLine(to: CGPoint(x: f.x - b.minX + 0.1, y: f.y - b.minY)) }
        for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x - b.minX, y: p.y - b.minY)) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    /// Points of every path of an Ink annotation in page space.
    static func inkPaths(_ a: PDFAnnotation) -> [[CGPoint]] {
        (a.paths ?? []).map { path in
            var pts: [CGPoint] = []
            path.cgPath.applyWithBlock { el in
                let e = el.pointee
                switch e.type {
                case .moveToPoint, .addLineToPoint: pts.append(e.points[0])
                case .addQuadCurveToPoint: pts.append(e.points[1])
                case .addCurveToPoint: pts.append(e.points[2])
                default: break
                }
            }
            return pts.map { CGPoint(x: $0.x + a.bounds.minX, y: $0.y + a.bounds.minY) }
        }
    }

    /// Replaces an Ink annotation's paths (partial erase / handle edits).
    static func setInkPaths(_ a: PDFAnnotation, _ paths: [[CGPoint]]) {
        let w = a.border?.lineWidth ?? 2
        for p in a.paths ?? [] { a.remove(p) }
        let b = bounds(for: paths.flatMap { $0 }, inset: w / 2 + 2)
        a.bounds = b
        for p in paths { a.add(bezier(for: p, in: b)) }
        a.modificationDate = Date()
        a.dropAppearance()
    }

    static func textMarkup(quads: [CGRect], tool: Tool, style: StylePreset, author: String) -> PDFAnnotation {
        let sub: PDFAnnotationSubtype = tool == .highlighter ? .highlight : (tool == .underline ? .underline : (tool == .strike ? .strikeOut : PDFAnnotationSubtype(rawValue: "/Squiggly")))
        var b = quads[0]
        for q in quads { b = b.union(q) }
        let a = PDFAnnotation(bounds: b, forType: sub, withProperties: nil)
        a.color = PDFColors.uiColor(style.color)
        var pts: [NSValue] = []
        for q in quads {
            // Quad order per PDF spec: upper-left, upper-right, lower-left, lower-right (relative to bounds origin).
            pts.append(NSValue(cgPoint: CGPoint(x: q.minX - b.minX, y: q.maxY - b.minY)))
            pts.append(NSValue(cgPoint: CGPoint(x: q.maxX - b.minX, y: q.maxY - b.minY)))
            pts.append(NSValue(cgPoint: CGPoint(x: q.minX - b.minX, y: q.minY - b.minY)))
            pts.append(NSValue(cgPoint: CGPoint(x: q.maxX - b.minX, y: q.minY - b.minY)))
        }
        a.quadrilateralPoints = pts
        if tool == .highlighter, let op = style.opacity, op < 1 { a.opacityValue = op }
        stamp(a, tool: tool, author: author)
        return a
    }

    static func shape(rect: CGRect, tool: Tool, style: StylePreset, author: String) -> PDFAnnotation {
        let w = CGFloat(style.width)
        let a = PDFAnnotation(bounds: rect.insetBy(dx: -w / 2, dy: -w / 2), forType: tool == .ellipse ? .circle : .square, withProperties: nil)
        a.color = PDFColors.uiColor(style.color)
        let border = PDFBorder()
        border.lineWidth = w
        border.style = style.lineStyle == .dash ? .dashed : .solid
        if style.lineStyle == .dash { border.dashPattern = [NSNumber(value: Double(w) * 3), NSNumber(value: Double(w) * 2)] }
        a.border = border
        if let fp = style.fillPattern, fp != FillPattern.none { a.interiorColor = PDFColors.uiColor(style.fill ?? style.color, alpha: style.fillOpacity ?? 0.5) }
        if let op = style.opacity, op < 1 { a.opacityValue = op }
        stamp(a, tool: tool, author: author)
        return a
    }

    static func redaction(rect: CGRect, author: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        a.color = .black
        a.interiorColor = .black
        let border = PDFBorder(); border.lineWidth = 0; a.border = border
        stamp(a, tool: .redact, author: author)
        return a
    }

    static func line(from p0: CGPoint, to p1: CGPoint, tool: Tool, style: StylePreset, author: String) -> PDFAnnotation {
        let w = CGFloat(style.width)
        let b = bounds(for: [p0, p1], inset: max(w, 12))
        let a = PDFAnnotation(bounds: b, forType: .line, withProperties: nil)
        a.color = PDFColors.uiColor(style.color)
        let border = PDFBorder()
        border.lineWidth = w
        border.style = style.lineStyle == .dash ? .dashed : .solid
        a.border = border
        a.startPoint = CGPoint(x: p0.x - b.minX, y: p0.y - b.minY)
        a.endPoint = CGPoint(x: p1.x - b.minX, y: p1.y - b.minY)
        if tool == .arrow || tool == .dblarrow { a.endLineStyle = .openArrow }
        if tool == .dblarrow { a.startLineStyle = .openArrow }
        if let op = style.opacity, op < 1 { a.opacityValue = op }
        stamp(a, tool: tool, author: author)
        return a
    }

    static func freeText(rect: CGRect, text: String, tool: Tool, style: StylePreset, author: String, fontSize: CGFloat? = nil) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        let size = fontSize ?? CGFloat(10 + style.width)
        a.font = fontFor(style, size: size)
        a.fontColor = PDFColors.uiColor(style.color)
        a.color = PDFColors.uiColor(style.borderColor ?? style.color, alpha: style.borderOpacity ?? 1)
        if let bg = style.background, (style.backgroundOpacity ?? 1) > 0 { a.interiorColor = PDFColors.uiColor(bg, alpha: style.backgroundOpacity ?? 1) }
        let border = PDFBorder(); border.lineWidth = CGFloat(style.borderWidth ?? 1); a.border = border
        a.contents = text
        a.alignment = .left
        stamp(a, tool: tool, author: author)
        return a
    }

    static func fontFor(_ style: StylePreset, size: CGFloat) -> UIFont {
        let weight: UIFont.Weight
        switch style.fontWeight { case .regular: weight = .regular; case .medium: weight = .medium; case .bold: weight = .bold; default: weight = .semibold }
        if let name = style.font, !name.isEmpty {
            let desc = UIFontDescriptor(fontAttributes: [.family: name])
            let traits: UIFontDescriptor.SymbolicTraits = (style.fontWeight == .bold || style.fontWeight == .semibold) ? .traitBold : []
            if let d = desc.withSymbolicTraits(traits), let f = UIFont(descriptor: d, size: size) as UIFont? { return f }
            return UIFont(descriptor: desc, size: size)
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// Stamp-like text (APPROVED, date, initials): bordered bold FreeText so every reader shows it.
    static func stampText(center: CGPoint, text: String, colorHex: String, author: String, tool: Tool) -> PDFAnnotation {
        let font = UIFont.systemFont(ofSize: 18, weight: .heavy)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let rect = CGRect(x: center.x - size.width / 2 - 12, y: center.y - size.height / 2 - 6, width: size.width + 24, height: size.height + 12)
        let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        a.font = font
        a.fontColor = PDFColors.uiColor(colorHex)
        a.color = PDFColors.uiColor(colorHex)
        a.interiorColor = UIColor.white.withAlphaComponent(0.85)
        let border = PDFBorder(); border.lineWidth = 3; a.border = border
        a.contents = text
        a.alignment = .center
        stamp(a, tool: tool, author: author)
        return a
    }

    static func note(at p: CGPoint, style: StylePreset, author: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24), forType: .text, withProperties: nil)
        a.color = PDFColors.uiColor(style.color)
        a.iconType = .comment
        stamp(a, tool: .note, author: author)
        return a
    }

    /// Callout = FreeText box + a grouped Line (tip → elbow → box) that every reader draws.
    static func callout(tip: CGPoint, elbow: CGPoint, attach: CGPoint, box: CGRect, text: String, style: StylePreset, author: String) -> (box: PDFAnnotation, leader: PDFAnnotation) {
        let boxA = freeText(rect: box, text: text, tool: .callout, style: style, author: author)
        let leader = inkLeader(tip: tip, elbow: elbow, attach: attach, style: style, author: author)
        let gid = IDGen.make()
        boxA.setValue(NSString(string: gid), forAnnotationKey: .redlineGroup)
        leader.setValue(NSString(string: gid), forAnnotationKey: .redlineGroup)
        leader.setValue(NSString(string: "/Group"), forAnnotationKey: .replyType)
        return (boxA, leader)
    }

    /// Leader as an Ink polyline with an arrowhead (Ink renders everywhere; the group key ties it to its box).
    static func inkLeader(tip: CGPoint, elbow: CGPoint, attach: CGPoint, style: StylePreset, author: String) -> PDFAnnotation {
        let w = max(1.5, CGFloat(style.width) * 0.35)
        var st = style; st.width = Double(w); st.fillPattern = nil
        let ang = atan2(tip.y - elbow.y, tip.x - elbow.x)
        let size = max(10, w * 4)
        let h1 = CGPoint(x: tip.x - size * cos(ang - 0.45), y: tip.y - size * sin(ang - 0.45))
        let h2 = CGPoint(x: tip.x - size * cos(ang + 0.45), y: tip.y - size * sin(ang + 0.45))
        let a = ink(paths: [[attach, elbow, tip], [h1, tip, h2]], tool: .callout, style: st, author: author)
        a.color = PDFColors.uiColor(style.borderColor ?? style.color)
        return a
    }

    static func widget(rect: CGRect, type: FieldType, name: String, author: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: rect, forType: .widget, withProperties: nil)
        switch type {
        case .check: a.widgetFieldType = .button; a.widgetControlType = .checkBoxControl
        case .radio: a.widgetFieldType = .button; a.widgetControlType = .radioButtonControl
        case .toggle: a.widgetFieldType = .button; a.widgetControlType = .checkBoxControl
        case .drop, .list: a.widgetFieldType = .choice; a.choices = ["Option A", "Option B"]
        case .sig: a.widgetFieldType = .signature
        default: a.widgetFieldType = .text
        }
        a.fieldName = name
        a.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        a.color = UIColor.systemBlue.withAlphaComponent(0.6)
        let border = PDFBorder(); border.lineWidth = 1; a.border = border
        stamp(a, tool: ToolCatalog.tool(for: type), author: author)
        return a
    }

    // MARK: replies & review state

    static func reply(to parent: PDFAnnotation, text: String, author: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: parent.bounds.minX, y: parent.bounds.maxY, width: 20, height: 20), forType: .text, withProperties: nil)
        a.contents = text
        a.userName = author
        a.modificationDate = Date()
        a.setValue(parent, forAnnotationKey: .inReplyTo)
        a.setValue(NSString(string: "/R"), forAnnotationKey: .replyType)
        a.shouldDisplay = false
        return a
    }

    static func stateAnnotation(for parent: PDFAnnotation, status: CommentStatus, author: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: parent.bounds.minX, y: parent.bounds.maxY, width: 20, height: 20), forType: .text, withProperties: nil)
        a.userName = author
        a.modificationDate = Date()
        a.setValue(parent, forAnnotationKey: .inReplyTo)
        a.setValue(NSString(string: "/R"), forAnnotationKey: .replyType)
        a.setValue(NSString(string: "/Review"), forAnnotationKey: .stateModel)
        a.setValue(NSString(string: "/" + stateName(status)), forAnnotationKey: .state)
        a.contents = status.rawValue
        a.shouldDisplay = false
        return a
    }

    static func stateName(_ s: CommentStatus) -> String {
        switch s { case .open: "None"; case .accepted: "Accepted"; case .rejected: "Rejected"; case .completed: "Completed" }
    }
    static func status(fromState raw: String?) -> CommentStatus? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch s { case "Accepted": return .accepted; case "Rejected": return .rejected; case "Completed": return .completed; case "None": return .open; default: return nil }
    }
}

// MARK: - Snapshots for undo

/// Copy of an annotation's editable properties (restored on undo).
struct AnnotationSnapshot {
    var bounds: CGRect
    var color: UIColor
    var interiorColor: UIColor?
    var fontColor: UIColor?
    var font: UIFont?
    var contents: String?
    var lineWidth: CGFloat?
    var dashPattern: [NSNumber]?
    var borderStyle: PDFBorderStyle?
    var opacity: Double
    var paths: [[CGPoint]]?
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var quads: [NSValue]?
    var iconType: PDFTextAnnotationIconType?

    @MainActor
    init(_ a: PDFAnnotation) {
        bounds = a.bounds; color = a.color; interiorColor = a.interiorColor; fontColor = a.fontColor; font = a.font; contents = a.contents
        lineWidth = a.border?.lineWidth; dashPattern = a.border?.dashPattern as? [NSNumber]; borderStyle = a.border?.style
        opacity = a.opacityValue
        paths = a.subtype == "Ink" ? AnnotationFactory.inkPaths(a) : nil
        startPoint = a.subtype == "Line" ? a.startPoint : nil
        endPoint = a.subtype == "Line" ? a.endPoint : nil
        quads = a.quadrilateralPoints as? [NSValue]
        iconType = a.subtype == "Text" ? a.iconType : nil
    }

    @MainActor
    func restore(to a: PDFAnnotation) {
        a.bounds = bounds
        a.color = color
        a.interiorColor = interiorColor
        a.fontColor = fontColor
        if let font { a.font = font }
        a.contents = contents
        if let lineWidth {
            let b = PDFBorder(); b.lineWidth = lineWidth; b.style = borderStyle ?? .solid
            if let dashPattern { b.dashPattern = dashPattern }
            a.border = b
        }
        a.opacityValue = opacity
        if let paths { AnnotationFactory.setInkPaths(a, paths) }
        if let startPoint { a.startPoint = startPoint }
        if let endPoint { a.endPoint = endPoint }
        if let quads { a.quadrilateralPoints = quads }
        if let iconType { a.iconType = iconType }
        a.dropAppearance()
    }
}

/// Reversible edit on the PDF.
enum PDFCommand {
    case add(page: PDFPage, annots: [PDFAnnotation])
    case remove(page: PDFPage, annots: [PDFAnnotation])
    case change(annots: [(PDFAnnotation, AnnotationSnapshot)])
}
