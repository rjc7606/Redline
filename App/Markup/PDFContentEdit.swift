import Foundation
import UIKit
import PDFKit

// Edits what a page actually draws, not just what sits on top of it.
//
// A page's content stream is walked operator by operator with the same state a reader keeps (CTM, text matrix,
// font, size, spacing), so every glyph's box on the page is known. Glyphs under a rectangle are dropped from the
// text operators — the glyphs after them are shifted back into place with a TJ adjustment, so the rest of the
// line does not move — images fully under a rectangle lose their Do, and form XObjects are rewritten the same
// way. Everything else is copied through byte for byte. The result goes into the file as an incremental update
// (a new content stream and page dictionary), so the original bytes of the removed text are no longer part of
// what the page draws; a PDFKit save afterwards rewrites the file without the orphaned objects.

/// What one edit found out about the text it removed, so replacement text can take its place.
struct RemovedTextInfo {
    var origin: CGPoint          // baseline start of the first removed glyph, page space
    var angle: CGFloat           // text direction, radians
    var size: CGFloat            // effective font size on the page
    var fillOps: String          // the colour operators in force (e.g. "0 0 1 rg")
    var fontResource: String?    // a page font that can be reused for new text (non-embedded simple font)
    var baseFont: String
}

enum PDFContentEditor {
    enum Failure: Error { case noPage, unsupportedStream, nothingRemoved, writeFailed }

    /// Removes everything under `rects` on page `pageIndex` and paints the areas black.
    static func redact(fileURL: URL, pageIndex: Int, rects: [CGRect]) throws {
        _ = try edit(fileURL: fileURL, pageIndex: pageIndex, remove: rects, paintBlack: true, insert: nil)
    }

    /// Replaces the text under `lineRect` with `text` (same place, size and colour as the first removed glyph).
    static func replaceText(fileURL: URL, pageIndex: Int, lineRect: CGRect, text: String) throws {
        _ = try edit(fileURL: fileURL, pageIndex: pageIndex, remove: [lineRect], paintBlack: false, insert: text)
    }

    @discardableResult
    private static func edit(fileURL: URL, pageIndex: Int, remove rects: [CGRect], paintBlack: Bool, insert: String?) throws -> RemovedTextInfo? {
        guard let data = try? Data(contentsOf: fileURL), let file = PDFFile(data: data) else { throw Failure.noPage }
        let pages = file.pages()
        guard pages.indices.contains(pageIndex) else { throw Failure.noPage }
        let (pageNum, pageDict) = pages[pageIndex]
        let resources = inheritedResources(of: pageDict, in: file)

        // Content: one stream or an array of streams, joined.
        let contentsObj = file.resolve(pageDict["Contents"] ?? .null)
        var content = Data()
        if case .stream = contentsObj {
            guard let d = PDFFilters.decode(contentsObj, resolve: file.resolve) ?? rawIfUnfiltered(contentsObj) else { throw Failure.unsupportedStream }
            content = d
        } else if let arr = contentsObj.arrayValue {
            for part in arr {
                let s = file.resolve(part)
                guard let d = PDFFilters.decode(s, resolve: file.resolve) ?? rawIfUnfiltered(s) else { throw Failure.unsupportedStream }
                content.append(d); content.append(0x0A)
            }
        } else {
            content = Data()
        }

        let engine = ContentRewriter(file: file, rects: rects)
        var out = engine.rewrite(content, resources: resources, ctm: .identity)
        guard engine.removedAny || paintBlack else { throw Failure.nothingRemoved }

        var newObjects: [Int: PDFObj] = engine.formObjects
        var next = max(file.maxObjectNumber, (newObjects.keys.max() ?? 0) + 1)
        var newPage = pageDict

        // Black boxes over the redacted areas (vector art or partly covered pictures underneath stay hidden).
        var tail = Data()
        if paintBlack {
            tail.append(contentsOf: "\nq 0 g 0 G\n".utf8)
            for r in rects { tail.append(contentsOf: String(format: "%.3f %.3f %.3f %.3f re f\n", r.minX, r.minY, r.width, r.height).utf8) }
            tail.append(contentsOf: "Q\n".utf8)
        }
        // Replacement text where the old text was.
        if let text = insert, let info = engine.firstRemoved {
            var fontName = info.fontResource
            if fontName == nil {
                // Add a standard font the page can use (every reader has it).
                let base = standardFont(matching: info.baseFont)
                let fontObj: PDFObj = .dictionary(["Type": .name("Font"), "Subtype": .name("Type1"), "BaseFont": .name(base), "Encoding": .name("WinAnsiEncoding")])
                let fontNum = next; next += 1
                newObjects[fontNum] = fontObj
                var res = resources
                var fonts = file.dict(res["Font"]) ?? [:]
                var name = "RLF1"; var k = 1
                while fonts[name] != nil { k += 1; name = "RLF\(k)" }
                fonts[name] = .reference(fontNum, 0)
                res["Font"] = .dictionary(fonts)
                let resNum = next; next += 1
                newObjects[resNum] = .dictionary(res)
                newPage["Resources"] = .reference(resNum, 0)
                fontName = name
            }
            let c = cos(info.angle), s = sin(info.angle)
            tail.append(contentsOf: "\nq BT\n".utf8)
            if !info.fillOps.isEmpty { tail.append(contentsOf: (info.fillOps + "\n").utf8) }
            tail.append(contentsOf: String(format: "/%@ %.3f Tf %.4f %.4f %.4f %.4f %.3f %.3f Tm ", fontName!, info.size, c, s, -s, c, info.origin.x, info.origin.y).utf8)
            tail.append(contentsOf: "<".utf8)
            tail.append(contentsOf: winAnsi(text).map { String(format: "%02X", $0) }.joined().utf8)
            tail.append(contentsOf: "> Tj\nET Q\n".utf8)
        }
        if !tail.isEmpty {
            var wrapped = Data("q\n".utf8); wrapped.append(out); wrapped.append(contentsOf: "\nQ\n".utf8); wrapped.append(tail)
            out = wrapped
        }

        let contentNum = next; next += 1
        newObjects[contentNum] = .stream(dict: ["Filter": .name("FlateDecode")], raw: PDFFilters.deflate(out))
        newPage["Contents"] = .reference(contentNum, 0)
        newObjects[pageNum] = .dictionary(newPage)
        let updated = file.incrementalUpdate(objects: newObjects)
        do { try updated.write(to: fileURL, options: .atomic) } catch { throw Failure.writeFailed }
        return engine.firstRemoved
    }

    private static func rawIfUnfiltered(_ o: PDFObj) -> Data? {
        if case .stream(let d, let raw) = o, d["Filter"] == nil { return raw }
        return nil
    }

    /// Page resources, inherited through the Pages tree when the page has none.
    static func inheritedResources(of page: [String: PDFObj], in file: PDFFile) -> [String: PDFObj] {
        var d: [String: PDFObj]? = page
        var hops = 0
        while let cur = d, hops < 64 {
            if let r = file.dict(cur["Resources"]) { return r }
            d = file.dict(cur["Parent"]); hops += 1
        }
        return [:]
    }

    static func standardFont(matching base: String) -> String {
        let n = base.lowercased()
        let bold = n.contains("bold") || n.contains("black") || n.contains("heavy") || n.contains("semibold")
        let italic = n.contains("italic") || n.contains("oblique")
        if n.contains("courier") || n.contains("mono") {
            return bold ? (italic ? "Courier-BoldOblique" : "Courier-Bold") : (italic ? "Courier-Oblique" : "Courier")
        }
        if n.contains("times") || n.contains("georgia") || n.contains("garamond") || n.contains("serif") || n.contains("book") || n.contains("roman") || n.contains("cambria") || n.contains("minion") {
            return bold ? (italic ? "Times-BoldItalic" : "Times-Bold") : (italic ? "Times-Italic" : "Times-Roman")
        }
        return bold ? (italic ? "Helvetica-BoldOblique" : "Helvetica-Bold") : (italic ? "Helvetica-Oblique" : "Helvetica")
    }

    static func winAnsi(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for ch in s {
            if let d = String(ch).data(using: .windowsCP1252), d.count == 1 { out.append(d[0]) }
            else if let d = String(ch).data(using: .windowsCP1252) { out.append(contentsOf: d) }
            else { out.append(0x3F) }
        }
        return out
    }
}

// MARK: - Fonts

/// Enough of a font to place its glyphs: how codes are split from the string bytes and how wide each is.
final class FontInfo {
    var widths: [Int: Double] = [:]      // code → width in text space (already /1000)
    var defaultWidth: Double = 0.5
    var codeLengths: [Int] = [1]          // byte lengths tried in order (CMap codespaces)
    var ascent: CGFloat = 0.78
    var descent: CGFloat = -0.22
    var baseFont = ""
    var reusable = false                  // non-embedded simple font with a standard encoding: new text can use it

    func codes(in bytes: Data) -> [(code: Int, bytes: Int)] {
        var out: [(Int, Int)] = []
        let b = [UInt8](bytes)
        var i = 0
        while i < b.count {
            let len = codeLengths.first { i + $0 <= b.count } ?? 1
            var c = 0
            for k in 0..<len { c = c << 8 | Int(b[i + k]) }
            out.append((c, len))
            i += len
        }
        return out
    }
    func width(_ code: Int) -> Double { widths[code] ?? defaultWidth }

    static func load(_ obj: PDFObj, in file: PDFFile) -> FontInfo {
        let f = FontInfo()
        guard let d = file.dict(obj) else { return f }
        f.baseFont = d["BaseFont"].map(file.resolve)?.nameValue ?? ""
        let subtype = d["Subtype"].map(file.resolve)?.nameValue ?? ""
        var descriptor = file.dict(d["FontDescriptor"])
        if subtype == "Type0" {
            f.codeLengths = [2]
            if let enc = d["Encoding"].map(file.resolve) {
                if case .stream = enc, let cmap = PDFFilters.decode(enc, resolve: file.resolve) { f.codeLengths = FontInfo.codespaceLengths(cmap) }
                else if let n = enc.nameValue, n.hasPrefix("Identity") { f.codeLengths = [2] }
            }
            if let desc = file.resolve(d["DescendantFonts"] ?? .null).arrayValue?.first, let cid = file.dict(desc) {
                descriptor = file.dict(cid["FontDescriptor"])
                f.defaultWidth = (cid["DW"].map(file.resolve)?.doubleValue ?? 1000) / 1000
                if let w = file.resolve(cid["W"] ?? .null).arrayValue {
                    var i = 0
                    while i < w.count {
                        guard let first = file.resolve(w[i]).intValue else { break }
                        if i + 1 < w.count, let arr = file.resolve(w[i + 1]).arrayValue {
                            for (k, v) in arr.enumerated() { if let x = file.resolve(v).doubleValue { f.widths[first + k] = x / 1000 } }
                            i += 2
                        } else if i + 2 < w.count, let last = file.resolve(w[i + 1]).intValue, let x = file.resolve(w[i + 2]).doubleValue {
                            if last >= first, last - first < 65536 { for c in first...last { f.widths[c] = x / 1000 } }
                            i += 3
                        } else { break }
                    }
                }
            }
        } else {
            let first = d["FirstChar"].map(file.resolve)?.intValue ?? 0
            var scale = 1.0 / 1000
            if subtype == "Type3", let m = file.resolve(d["FontMatrix"] ?? .null).arrayValue, m.count >= 1, let a = file.resolve(m[0]).doubleValue { scale = abs(a) }
            if let w = file.resolve(d["Widths"] ?? .null).arrayValue, !w.isEmpty {
                for (k, v) in w.enumerated() { if let x = file.resolve(v).doubleValue { f.widths[first + k] = x * scale } }
                f.defaultWidth = (descriptor?["MissingWidth"].map(file.resolve)?.doubleValue ?? 0) * scale
            } else {
                FontInfo.standardWidths(for: f.baseFont, into: f)
            }
            let embedded = descriptor.map { $0["FontFile"] != nil || $0["FontFile2"] != nil || $0["FontFile3"] != nil } ?? false
            var stdEncoding = true
            if let enc = d["Encoding"].map(file.resolve) {
                if let ed = enc.dictValue { stdEncoding = ed["Differences"] == nil }
                else if let n = enc.nameValue { stdEncoding = n == "WinAnsiEncoding" || n == "StandardEncoding" }
            }
            f.reusable = !embedded && subtype != "Type3" && stdEncoding
        }
        if let desc = descriptor {
            if let a = desc["Ascent"].map(file.resolve)?.doubleValue, a > 100 { f.ascent = min(1.1, CGFloat(a) / 1000) }
            if let de = desc["Descent"].map(file.resolve)?.doubleValue, de < -20 { f.descent = max(-0.4, CGFloat(de) / 1000) }
        }
        return f
    }

    /// Byte lengths from a CMap's codespace ranges (shortest first).
    static func codespaceLengths(_ cmap: Data) -> [Int] {
        var lens: Set<Int> = []
        var lx = PDFLexer(cmap)
        var inRange = false
        loop: while true {
            let t = lx.next()
            switch t {
            case .eof: break loop
            case .keyword("begincodespacerange"): inRange = true
            case .keyword("endcodespacerange"): inRange = false
            case .string(let d): if inRange, d.count >= 1, d.count <= 4 { lens.insert(d.count) }
            default: break
            }
        }
        return lens.isEmpty ? [2] : lens.sorted()
    }

    /// Metrics of the standard 14 fonts (Helvetica, Times, Courier families; others fall back to Helvetica).
    static func standardWidths(for base: String, into f: FontInfo) {
        let n = base.lowercased()
        if n.contains("courier") || n.contains("mono") { f.defaultWidth = 0.6; return }
        let table: [Int] = (n.contains("times") || n.contains("serif") || n.contains("roman") || n.contains("georgia")) ? timesWidths : helveticaWidths
        for (i, w) in table.enumerated() { f.widths[32 + i] = Double(w) / 1000 }
        f.defaultWidth = (n.contains("times")) ? 0.5 : 0.556
    }

    // ASCII 32…126
    static let helveticaWidths: [Int] = [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584]
    static let timesWidths: [Int] = [250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500, 333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500, 500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541]
}

// MARK: - Rewriter

/// One pass over a content stream. Untouched operators are copied byte for byte.
final class ContentRewriter {
    let file: PDFFile
    let rects: [CGRect]
    private(set) var removedAny = false
    private(set) var firstRemoved: RemovedTextInfo? = nil
    /// Form XObjects rewritten along the way (object number → new stream).
    private(set) var formObjects: [Int: PDFObj] = [:]
    private var formsDone: Set<Int> = []
    private var fontCache: [Int: FontInfo] = [:]

    init(file: PDFFile, rects: [CGRect]) { self.file = file; self.rects = rects }

    private struct GState {
        var ctm: CGAffineTransform
        var font: FontInfo? = nil
        var size: CGFloat = 0
        var charSp: CGFloat = 0
        var wordSp: CGFloat = 0
        var hscale: CGFloat = 1
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        var fillOps = ""
    }

    private enum Operand {
        case number(Double)
        case name(String)
        case string(Data)
        case array([Operand])
        case other
    }

    func rewrite(_ content: Data, resources: [String: PDFObj], ctm base: CGAffineTransform) -> Data {
        let bytes = [UInt8](content)
        var lx = PDFLexer(bytes: bytes)
        var out = Data()
        out.reserveCapacity(bytes.count + 256)
        var gs = GState(ctm: base)
        var stack: [GState] = []
        var tm = CGAffineTransform.identity, tlm = CGAffineTransform.identity
        var operands: [Operand] = []
        var segStart = 0
        let fonts = file.dict(resources["Font"]) ?? [:]
        let xobjects = file.dict(resources["XObject"]) ?? [:]

        var currentFontName = ""
        var changedText = false
        func num(_ i: Int) -> Double { if i < operands.count, case .number(let d) = operands[i] { return d }; return 0 }
        func copyThrough() { out.append(contentsOf: bytes[segStart..<lx.pos]); segStart = lx.pos }
        func drop() { segStart = lx.pos }
        func replace(with s: String) { out.append(contentsOf: s.utf8); segStart = lx.pos }
        func operandText() -> String { String(decoding: bytes[segStart..<lx.pos], as: UTF8.self) }

        func glyphAdvance(_ code: Int, len: Int, font: FontInfo) -> CGFloat {
            var tx = CGFloat(font.width(code)) * gs.size + gs.charSp
            if len == 1 && code == 32 { tx += gs.wordSp }
            return tx * gs.hscale
        }

        /// Shows a string: returns the kept pieces (strings / adjustments) and advances tm.
        func show(_ data: Data, pieces: inout [String]) {
            guard let font = gs.font else {
                pieces.append("<" + data.map { String(format: "%02X", $0) }.joined() + ">")
                return
            }
            var kept = Data()
            var pendingAdjust: CGFloat = 0   // text-space advance of removed glyphs, to put back as a TJ number
            let codes = font.codes(in: data)
            var byteIndex = 0
            for (code, len) in codes {
                let trm = CGAffineTransform(a: gs.size * gs.hscale, b: 0, c: 0, d: gs.size, tx: 0, ty: gs.rise).concatenating(tm).concatenating(gs.ctm)
                let w0 = CGFloat(font.width(code))
                let box = CGRect(x: 0, y: font.descent, width: max(0.01, w0), height: font.ascent - font.descent)
                let pageBox = box.applying(trm)
                let advance = glyphAdvance(code, len: len, font: font)
                let hit = ContentRewriter.covered(pageBox, by: rects)
                if hit {
                    if firstRemoved == nil {
                        let a = atan2(trm.b, trm.a)
                        firstRemoved = RemovedTextInfo(origin: CGPoint(x: trm.tx, y: trm.ty), angle: a, size: hypot(trm.a, trm.b) / max(0.01, gs.hscale),
                                                       fillOps: gs.fillOps, fontResource: (font.reusable && formDepth == 0) ? currentFontName : nil, baseFont: font.baseFont)
                    }
                    removedAny = true
                    countRemoved += 1
                    if !kept.isEmpty { pieces.append("<" + kept.map { String(format: "%02X", $0) }.joined() + ">"); kept = Data() }
                    pendingAdjust += advance
                } else {
                    if pendingAdjust != 0 {
                        let denom = gs.size * gs.hscale
                        if denom != 0 { pieces.append(String(format: "%.2f", -pendingAdjust * 1000 / denom)) }
                        pendingAdjust = 0
                    }
                    kept.append(contentsOf: data[byteIndex..<min(data.count, byteIndex + len)])
                }
                byteIndex += len
                tm = CGAffineTransform(translationX: advance, y: 0).concatenating(tm)
            }
            if !kept.isEmpty { pieces.append("<" + kept.map { String(format: "%02X", $0) }.joined() + ">") }
            if pendingAdjust != 0 {
                let denom = gs.size * gs.hscale
                if denom != 0 { pieces.append(String(format: "%.2f", -pendingAdjust * 1000 / denom)) }
            }
        }

        func emitTJ(_ pieces: [String]) { replace(with: "[" + pieces.joined(separator: " ") + "] TJ\n") }

        loop: while true {
            let tok = lx.next()
            switch tok {
            case .eof: break loop
            case .number(let s): operands.append(.number(Double(s) ?? 0)); continue
            case .name(let n): operands.append(.name(n)); continue
            case .string(let d): operands.append(.string(d)); continue
            case .arrayOpen:
                operands.append(.array(parseArray(&lx))); continue
            case .dictOpen:
                var depth = 1
                while depth > 0 { let t = lx.next(); if t == .dictOpen { depth += 1 } else if t == .dictClose { depth -= 1 } else if t == .eof { break } }
                operands.append(.other); continue
            case .arrayClose, .dictClose, .braceOpen, .braceClose: continue
            case .keyword(let op):
                defer { operands.removeAll() }
                switch op {
                case "q": stack.append(gs); copyThrough()
                case "Q": if let g = stack.popLast() { gs = g }; copyThrough()
                case "cm":
                    if operands.count >= 6 {
                        let m = CGAffineTransform(a: num(0), b: num(1), c: num(2), d: num(3), tx: num(4), ty: num(5))
                        gs.ctm = m.concatenating(gs.ctm)
                    }
                    copyThrough()
                case "BT": tm = .identity; tlm = .identity; copyThrough()
                case "ET": copyThrough()
                case "Tf":
                    if operands.count >= 2, case .name(let n) = operands[0] {
                        currentFontName = n
                        gs.size = CGFloat(num(1))
                        if let ref = fonts[n] {
                            if case .reference(let on, _) = ref {
                                if let c = fontCache[on] { gs.font = c } else { let f = FontInfo.load(ref, in: file); fontCache[on] = f; gs.font = f }
                            } else { gs.font = FontInfo.load(ref, in: file) }
                        } else { gs.font = nil }
                    }
                    copyThrough()
                case "Td": tlm = CGAffineTransform(translationX: num(0), y: num(1)).concatenating(tlm); tm = tlm; copyThrough()
                case "TD": gs.leading = -num(1); tlm = CGAffineTransform(translationX: num(0), y: num(1)).concatenating(tlm); tm = tlm; copyThrough()
                case "Tm":
                    if operands.count >= 6 { tlm = CGAffineTransform(a: num(0), b: num(1), c: num(2), d: num(3), tx: num(4), ty: num(5)); tm = tlm }
                    copyThrough()
                case "T*": tlm = CGAffineTransform(translationX: 0, y: -gs.leading).concatenating(tlm); tm = tlm; copyThrough()
                case "TL": gs.leading = num(0); copyThrough()
                case "Tc": gs.charSp = num(0); copyThrough()
                case "Tw": gs.wordSp = num(0); copyThrough()
                case "Tz": gs.hscale = num(0) / 100; copyThrough()
                case "Ts": gs.rise = num(0); copyThrough()
                case "g", "rg", "k", "sc", "scn", "cs":
                    gs.fillOps = operandText().trimmingCharacters(in: .whitespacesAndNewlines)
                    copyThrough()
                case "Tj", "'", "\"":
                    var prefix = ""
                    var strIndex = 0
                    if op == "'" {
                        tlm = CGAffineTransform(translationX: 0, y: -gs.leading).concatenating(tlm); tm = tlm; prefix = "T* "
                    } else if op == "\"" {
                        gs.wordSp = num(0); gs.charSp = num(1); strIndex = 2
                        tlm = CGAffineTransform(translationX: 0, y: -gs.leading).concatenating(tlm); tm = tlm
                        prefix = String(format: "%.3f Tw %.3f Tc T* ", gs.wordSp, gs.charSp)
                    }
                    guard strIndex < operands.count, case .string(let d) = operands[strIndex] else { copyThrough(); continue }
                    var pieces: [String] = []
                    let removedBefore = countRemoved
                    show(d, pieces: &pieces)
                    changedText = countRemoved != removedBefore
                    if changedText { replace(with: prefix); emitTJ(pieces) } else { copyThrough() }
                case "TJ":
                    guard let first = operands.first, case .array(let arr) = first, gs.font != nil else { copyThrough(); continue }
                    var pieces: [String] = []
                    let removedBefore = countRemoved
                    for el in arr {
                        switch el {
                        case .string(let d): show(d, pieces: &pieces)
                        case .number(let n):
                            pieces.append(String(format: "%.2f", n))
                            tm = CGAffineTransform(translationX: CGFloat(-n / 1000) * gs.size * gs.hscale, y: 0).concatenating(tm)
                        default: break
                        }
                    }
                    if countRemoved != removedBefore { emitTJ(pieces) } else { copyThrough() }
                case "Do":
                    guard case .name(let n)? = operands.first, let xref = xobjects[n], let xd = file.dict(xref) else { copyThrough(); continue }
                    let sub = xd["Subtype"].map(file.resolve)?.nameValue ?? ""
                    if sub == "Image" {
                        let box = CGRect(x: 0, y: 0, width: 1, height: 1).applying(gs.ctm)
                        if ContentRewriter.fullyCovered(box, by: rects) { removedAny = true; countRemoved += 1; drop() } else { copyThrough() }
                    } else if sub == "Form", case .reference(let on, _) = xref {
                        rewriteForm(on, dict: xd, ctm: gs.ctm, parentResources: resources)
                        copyThrough()
                    } else { copyThrough() }
                case "BI":
                    // Inline image: key/value pairs up to ID, then binary data up to EI.
                    var t = lx.next()
                    while t != .keyword("ID") && t != .eof { t = lx.next() }
                    var p = lx.pos + 1
                    let b = lx.bytes
                    while p + 1 < b.count {
                        if b[p] == 0x45, b[p + 1] == 0x49, p > 0, PDFLexer.isWhite(b[p - 1]), (p + 2 >= b.count || PDFLexer.isWhite(b[p + 2]) || PDFLexer.isDelim(b[p + 2])) { break }
                        p += 1
                    }
                    lx.pos = min(b.count, p + 2)
                    let box = CGRect(x: 0, y: 0, width: 1, height: 1).applying(gs.ctm)
                    if ContentRewriter.fullyCovered(box, by: rects) { removedAny = true; countRemoved += 1; drop() } else { copyThrough() }
                default:
                    copyThrough()
                }
            }
        }
        if segStart < bytes.count { out.append(contentsOf: bytes[segStart..<bytes.count]) }
        return out
    }

    private var countRemoved = 0
    private var formDepth = 0

    private func parseArray(_ lx: inout PDFLexer) -> [Operand] {
        var items: [Operand] = []
        while true {
            let t = lx.next()
            switch t {
            case .eof, .arrayClose: return items
            case .number(let s): items.append(.number(Double(s) ?? 0))
            case .name(let n): items.append(.name(n))
            case .string(let d): items.append(.string(d))
            case .arrayOpen: items.append(.array(parseArray(&lx)))
            default: items.append(.other)
            }
        }
    }

    private func rewriteForm(_ num: Int, dict: [String: PDFObj], ctm: CGAffineTransform, parentResources: [String: PDFObj]) {
        guard !formsDone.contains(num) else { return }
        formsDone.insert(num)
        let obj = file.object(num)
        guard case .stream(let sd, let raw) = obj else { return }
        var decoded = PDFFilters.decode(obj, resolve: file.resolve)
        if decoded == nil, sd["Filter"] == nil { decoded = raw }
        guard let data = decoded else { return }
        var m = CGAffineTransform.identity
        if let arr = file.resolve(dict["Matrix"] ?? .null).arrayValue, arr.count >= 6 {
            let v = arr.map { file.resolve($0).doubleValue ?? 0 }
            m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }
        let res = file.dict(dict["Resources"]) ?? parentResources
        let before = countRemoved
        formDepth += 1
        let out = rewrite(data, resources: res, ctm: m.concatenating(ctm))
        formDepth -= 1
        guard countRemoved != before else { return }
        var nd = sd
        nd["Length"] = nil; nd["DecodeParms"] = nil
        nd["Filter"] = .name("FlateDecode")
        formObjects[num] = .stream(dict: nd, raw: PDFFilters.deflate(out))
    }

    /// A glyph is removed when most of it lies under a rectangle.
    static func covered(_ box: CGRect, by rects: [CGRect]) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let area = box.width * box.height
        for r in rects {
            let i = box.intersection(r)
            if i.isNull { continue }
            if i.width * i.height >= area * 0.5 { return true }
            if r.contains(CGPoint(x: box.midX, y: box.midY)) { return true }
        }
        return false
    }
    static func fullyCovered(_ box: CGRect, by rects: [CGRect]) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let area = box.width * box.height
        for r in rects {
            let i = box.intersection(r)
            if !i.isNull, i.width * i.height >= area * 0.95 { return true }
        }
        return false
    }
}
