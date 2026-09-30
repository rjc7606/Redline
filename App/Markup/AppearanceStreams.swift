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

    var isRedlineTextBox: Bool { subtype == "FreeText" && redlineID != nil }

    var textBoxLook: TextBoxLook {
        let borderHex = borderColorHex ?? PDFColors.hex(fontColor ?? .black)
        return TextBoxLook(fill: color, textColor: fontColor ?? .black, border: PDFColors.uiColor(borderHex),
                           borderWidth: border?.lineWidth ?? 1, radius: cornerRadius,
                           font: font ?? UIFont.systemFont(ofSize: 16, weight: .semibold), text: contents ?? "",
                           centered: alignment == .center)
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

enum TextBoxRenderer {
    /// Draws a text box into a y-down context whose origin is the box's top-left corner.
    static func draw(_ look: TextBoxLook, size: CGSize, in cg: CGContext) {
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
        let ours = annotations.filter { $0.isRedlineTextBox }
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
            let helperData = TextBoxRenderer.appearancePDF(for: a)
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

    /// Swaps plain FreeText annotations created by Redline for our drawing subclass after a document loads.
    static func adoptTextBoxes(in doc: PDFDocument) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations where a.isRedlineTextBox && !(a is RedlineFreeText) {
                let replacement = RedlineFreeText(bounds: a.bounds, forType: .freeText, withProperties: a.annotationKeyValues)
                replacement.removeValue(forAnnotationKey: .appearanceDictionary)
                page.removeAnnotation(a)
                page.addAnnotation(replacement)
                for other in page.annotations where (other.value(forAnnotationKey: .inReplyTo) as? PDFAnnotation) === a {
                    other.setValue(replacement, forAnnotationKey: .inReplyTo)
                }
            }
        }
    }
}
