import Foundation

// A small PDF object model, parser and incremental-update writer. Enough to locate annotation
// dictionaries in a saved file, import appearance-stream form objects (with their embedded fonts)
// and append an incremental update that attaches them. Supports classic xref tables, xref streams,
// object streams and FlateDecode (with PNG predictors).

indirect enum PDFObj: Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case string(Data)
    case name(String)
    case array([PDFObj])
    case dictionary([String: PDFObj])
    case stream(dict: [String: PDFObj], raw: Data)
    case reference(Int, Int)

    var intValue: Int? {
        switch self { case .integer(let i): return i; case .real(let d): return Int(d); default: return nil }
    }
    var doubleValue: Double? {
        switch self { case .integer(let i): return Double(i); case .real(let d): return d; default: return nil }
    }
    var nameValue: String? { if case .name(let n) = self { return n }; return nil }
    var stringValue: String? { if case .string(let d) = self { return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) }; return nil }
    var arrayValue: [PDFObj]? { if case .array(let a) = self { return a }; return nil }
    var dictValue: [String: PDFObj]? {
        switch self { case .dictionary(let d): return d; case .stream(let d, _): return d; default: return nil }
    }
}

struct PDFRef: Hashable { let num: Int; let gen: Int }

// MARK: - Lexer

struct PDFLexer {
    let bytes: [UInt8]
    var pos: Int

    init(_ data: Data, at offset: Int = 0) { bytes = [UInt8](data); pos = offset }
    init(bytes: [UInt8], at offset: Int = 0) { self.bytes = bytes; pos = offset }

    enum Token: Equatable {
        case number(String)
        case name(String)
        case string(Data)
        case dictOpen, dictClose, arrayOpen, arrayClose, braceOpen, braceClose
        case keyword(String)
        case eof
    }

    static func isWhite(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 || b == 0x0C || b == 0x00 }
    static func isDelim(_ b: UInt8) -> Bool { [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(b) }
    static func isRegular(_ b: UInt8) -> Bool { !isWhite(b) && !isDelim(b) }

    mutating func skipWhitespace() {
        while pos < bytes.count {
            let b = bytes[pos]
            if PDFLexer.isWhite(b) { pos += 1 }
            else if b == 0x25 { while pos < bytes.count && bytes[pos] != 0x0A && bytes[pos] != 0x0D { pos += 1 } }
            else { break }
        }
    }

    mutating func next() -> Token {
        skipWhitespace()
        guard pos < bytes.count else { return .eof }
        let b = bytes[pos]
        switch b {
        case 0x5B: pos += 1; return .arrayOpen
        case 0x5D: pos += 1; return .arrayClose
        case 0x7B: pos += 1; return .braceOpen
        case 0x7D: pos += 1; return .braceClose
        case 0x3C:
            if pos + 1 < bytes.count && bytes[pos + 1] == 0x3C { pos += 2; return .dictOpen }
            return .string(hexString())
        case 0x3E:
            if pos + 1 < bytes.count && bytes[pos + 1] == 0x3E { pos += 2; return .dictClose }
            pos += 1; return next()
        case 0x28: return .string(literalString())
        case 0x2F:
            pos += 1
            var s = ""
            while pos < bytes.count, PDFLexer.isRegular(bytes[pos]) {
                if bytes[pos] == 0x23, pos + 2 < bytes.count, let v = UInt8(String(bytes: bytes[(pos + 1)...(pos + 2)], encoding: .ascii) ?? "", radix: 16) {
                    s.append(Character(UnicodeScalar(v))); pos += 3
                } else { s.append(Character(UnicodeScalar(bytes[pos]))); pos += 1 }
            }
            return .name(s)
        default:
            var s = ""
            while pos < bytes.count, PDFLexer.isRegular(bytes[pos]) { s.append(Character(UnicodeScalar(bytes[pos]))); pos += 1 }
            if s.isEmpty { pos += 1; return next() }
            if let f = s.first, f == "-" || f == "+" || f == "." || f.isNumber { return .number(s) }
            return .keyword(s)
        }
    }

    mutating func hexString() -> Data {
        pos += 1
        var out = Data(); var hi: UInt8? = nil
        while pos < bytes.count, bytes[pos] != 0x3E {
            let c = bytes[pos]; pos += 1
            guard let v = hexVal(c) else { continue }
            if let h = hi { out.append(h << 4 | v); hi = nil } else { hi = v }
        }
        if let h = hi { out.append(h << 4) }
        pos += 1
        return out
    }
    private func hexVal(_ c: UInt8) -> UInt8? {
        switch c { case 0x30...0x39: return c - 0x30; case 0x41...0x46: return c - 0x41 + 10; case 0x61...0x66: return c - 0x61 + 10; default: return nil }
    }

    mutating func literalString() -> Data {
        pos += 1
        var out = Data(); var depth = 1
        while pos < bytes.count {
            let c = bytes[pos]; pos += 1
            if c == 0x5C {
                guard pos < bytes.count else { break }
                let e = bytes[pos]; pos += 1
                switch e {
                case 0x6E: out.append(0x0A); case 0x72: out.append(0x0D); case 0x74: out.append(0x09); case 0x62: out.append(0x08); case 0x66: out.append(0x0C)
                case 0x0A: break
                case 0x0D: if pos < bytes.count && bytes[pos] == 0x0A { pos += 1 }
                case 0x30...0x37:
                    var v = Int(e - 0x30); var n = 1
                    while n < 3, pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x37 { v = v * 8 + Int(bytes[pos] - 0x30); pos += 1; n += 1 }
                    out.append(UInt8(v & 0xFF))
                default: out.append(e)
                }
            } else if c == 0x28 { depth += 1; out.append(c) }
            else if c == 0x29 { depth -= 1; if depth == 0 { break }; out.append(c) }
            else { out.append(c) }
        }
        return out
    }
}

// MARK: - Parser

struct PDFParser {
    var lexer: PDFLexer
    /// Resolves indirect /Length values while reading streams.
    var lengthResolver: ((PDFRef) -> Int?)? = nil

    init(_ data: Data, at offset: Int = 0) { lexer = PDFLexer(data, at: offset) }
    init(bytes: [UInt8], at offset: Int = 0) { lexer = PDFLexer(bytes: bytes, at: offset) }

    var position: Int { get { lexer.pos } set { lexer.pos = newValue } }

    /// Parses one object; handles `n g R` references and `stream` bodies after dictionaries.
    mutating func parseObject(token first: PDFLexer.Token? = nil) -> PDFObj? {
        let t = first ?? lexer.next()
        switch t {
        case .eof: return nil
        case .number(let s):
            // Possible reference: int int R
            let save = lexer.pos
            if let i = Int(s) {
                let t2 = lexer.next()
                if case .number(let g) = t2, let gi = Int(g) {
                    let save2 = lexer.pos
                    if case .keyword("R") = lexer.next() { return .reference(i, gi) }
                    lexer.pos = save2
                    lexer.pos = save
                    return .integer(i)
                }
                lexer.pos = save
                return .integer(i)
            }
            return .real(Double(s) ?? 0)
        case .name(let n): return .name(n)
        case .string(let d): return .string(d)
        case .arrayOpen:
            var arr: [PDFObj] = []
            while true {
                let nt = lexer.next()
                if nt == .arrayClose || nt == .eof { break }
                if let o = parseObject(token: nt) { arr.append(o) } else { break }
            }
            return .array(arr)
        case .dictOpen:
            var dict: [String: PDFObj] = [:]
            while true {
                let nt = lexer.next()
                if nt == .dictClose || nt == .eof { break }
                guard case .name(let key) = nt else { _ = parseObject(token: nt); continue }
                guard let v = parseObject() else { break }
                dict[key] = v
            }
            // stream?
            let save = lexer.pos
            if case .keyword("stream") = lexer.next() {
                var p = lexer.pos
                if p < lexer.bytes.count && lexer.bytes[p] == 0x0D { p += 1 }
                if p < lexer.bytes.count && lexer.bytes[p] == 0x0A { p += 1 }
                var length: Int? = nil
                if let l = dict["Length"] {
                    if let i = l.intValue { length = i } else if case .reference(let n, let g) = l { length = lengthResolver?(PDFRef(num: n, gen: g)) }
                }
                var end: Int
                if let l = length, p + l <= lexer.bytes.count, PDFParser.hasEndstream(lexer.bytes, near: p + l) {
                    end = p + l
                } else {
                    end = PDFParser.find("endstream", in: lexer.bytes, from: p) ?? lexer.bytes.count
                    while end > p && (lexer.bytes[end - 1] == 0x0A || lexer.bytes[end - 1] == 0x0D) { end -= 1 }
                }
                let raw = Data(lexer.bytes[p..<end])
                lexer.pos = PDFParser.find("endstream", in: lexer.bytes, from: end).map { $0 + 9 } ?? lexer.bytes.count
                return .stream(dict: dict, raw: raw)
            }
            lexer.pos = save
            return .dictionary(dict)
        case .keyword(let k):
            switch k { case "true": return .bool(true); case "false": return .bool(false); case "null": return .null; default: return .null }
        case .arrayClose, .dictClose, .braceOpen, .braceClose: return .null
        }
    }

    static func hasEndstream(_ bytes: [UInt8], near p: Int) -> Bool {
        var i = p; var n = 0
        while i < bytes.count && n < 4 && PDFLexer.isWhite(bytes[i]) { i += 1; n += 1 }
        return find("endstream", in: bytes, from: i, limit: i + 9) == i
    }

    static func find(_ s: String, in bytes: [UInt8], from: Int, limit: Int? = nil) -> Int? {
        let pat = [UInt8](s.utf8)
        let end = min(bytes.count - pat.count, limit ?? (bytes.count - pat.count))
        guard from <= end else { return nil }
        var i = from
        while i <= end {
            if bytes[i] == pat[0] {
                var ok = true
                for k in 1..<pat.count where bytes[i + k] != pat[k] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    static func findLast(_ s: String, in bytes: [UInt8]) -> Int? {
        let pat = [UInt8](s.utf8)
        var i = bytes.count - pat.count
        while i >= 0 {
            if bytes[i] == pat[0] {
                var ok = true
                for k in 1..<pat.count where bytes[i + k] != pat[k] { ok = false; break }
                if ok { return i }
            }
            i -= 1
        }
        return nil
    }
}

// MARK: - Filters

enum PDFFilters {
    static func decode(_ stream: PDFObj, resolve: (PDFObj) -> PDFObj) -> Data? {
        guard case .stream(let dict, let raw) = stream else { return nil }
        var filters: [String] = []
        if let f = dict["Filter"].map(resolve) {
            if let n = f.nameValue { filters = [n] } else if let a = f.arrayValue { filters = a.compactMap { resolve($0).nameValue } }
        }
        var parms: [[String: PDFObj]?] = []
        if let p = dict["DecodeParms"].map(resolve) {
            if let d = p.dictValue { parms = [d] } else if let a = p.arrayValue { parms = a.map { resolve($0).dictValue } }
        }
        var data = raw
        for (i, f) in filters.enumerated() {
            switch f {
            case "FlateDecode", "Fl":
                guard let d = inflate(data) else { return nil }
                data = d
                if i < parms.count, let pm = parms[i], let pred = pm["Predictor"].map(resolve)?.intValue, pred >= 10 {
                    let cols = pm["Columns"].map(resolve)?.intValue ?? 1
                    let colors = pm["Colors"].map(resolve)?.intValue ?? 1
                    let bpc = pm["BitsPerComponent"].map(resolve)?.intValue ?? 8
                    data = unpredictPNG(data, columns: cols, colors: colors, bpc: bpc)
                }
            default:
                return nil // unsupported filter
            }
        }
        return data
    }

    /// zlib-wrapped deflate → raw bytes.
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        let body = data.subdata(in: 2..<data.count) // strip the 2-byte zlib header
        return (try? (body as NSData).decompressed(using: .zlib)) as Data?
    }

    /// raw bytes → zlib-wrapped deflate (header + adler32).
    static func deflate(_ data: Data) -> Data {
        var out = Data([0x78, 0x9C])
        let compressed = (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
        out.append(compressed)
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        out.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
        return out
    }

    static func unpredictPNG(_ data: Data, columns: Int, colors: Int, bpc: Int) -> Data {
        let bpp = max(1, colors * bpc / 8)
        let rowLen = (columns * colors * bpc + 7) / 8
        let bytes = [UInt8](data)
        var out = [UInt8](); out.reserveCapacity(bytes.count)
        var prev = [UInt8](repeating: 0, count: rowLen)
        var i = 0
        while i + 1 <= bytes.count {
            let ft = bytes[i]; i += 1
            var row = Array(bytes[i..<min(bytes.count, i + rowLen)]); i += rowLen
            if row.count < rowLen { row += [UInt8](repeating: 0, count: rowLen - row.count) }
            for x in 0..<rowLen {
                let a = x >= bpp ? row[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0
                switch ft {
                case 1: row[x] = row[x] &+ a
                case 2: row[x] = row[x] &+ b
                case 3: row[x] = row[x] &+ UInt8((Int(a) + Int(b)) / 2)
                case 4:
                    let p = Int(a) + Int(b) - Int(c)
                    let pa = abs(p - Int(a)), pb = abs(p - Int(b)), pc = abs(p - Int(c))
                    row[x] = row[x] &+ (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))
                default: break
                }
            }
            out += row
            prev = row
        }
        return Data(out)
    }
}

// MARK: - Document

/// Read-only view of a PDF file's object graph plus what we need to write an incremental update.
final class PDFFile {
    let bytes: [UInt8]
    private(set) var xref: [Int: XrefEntry] = [:]
    private(set) var trailer: [String: PDFObj] = [:]
    private(set) var startXref: Int = 0
    private(set) var usesXrefStream = false
    private var cache: [Int: PDFObj] = [:]
    private var objectStreams: [Int: [Int: PDFObj]] = [:]

    enum XrefEntry { case offset(Int, gen: Int), inStream(stream: Int, index: Int), free }

    var maxObjectNumber: Int { max(trailer["Size"]?.intValue ?? 0, (xref.keys.max() ?? 0) + 1) }

    init?(data: Data) {
        bytes = [UInt8](data)
        guard let sx = PDFParser.findLast("startxref", in: bytes) else { return nil }
        var lx = PDFLexer(bytes: bytes, at: sx + 9)
        guard case .number(let s) = lx.next(), let off = Int(s) else { return nil }
        startXref = off
        var seen: Set<Int> = []
        var next: Int? = off
        var first = true
        while let o = next, !seen.contains(o), o < bytes.count {
            seen.insert(o)
            next = parseXrefSection(at: o, isFirst: first)
            first = false
        }
        if xref.isEmpty { return nil }
    }

    /// Parses one xref section (table or stream); returns /Prev.
    private func parseXrefSection(at offset: Int, isFirst: Bool) -> Int? {
        var lx = PDFLexer(bytes: bytes, at: offset)
        lx.skipWhitespace()
        if PDFParser.find("xref", in: bytes, from: lx.pos, limit: lx.pos + 4) == lx.pos {
            lx.pos += 4
            // subsections
            while true {
                lx.skipWhitespace()
                if PDFParser.find("trailer", in: bytes, from: lx.pos, limit: lx.pos + 7) == lx.pos { lx.pos += 7; break }
                guard case .number(let s) = lx.next(), let start = Int(s), case .number(let c) = lx.next(), let count = Int(c) else { break }
                for k in 0..<count {
                    guard case .number(let o) = lx.next(), case .number(let g) = lx.next(), case .keyword(let ty) = lx.next() else { break }
                    let num = start + k
                    if xref[num] == nil {
                        xref[num] = ty == "n" ? .offset(Int(o) ?? 0, gen: Int(g) ?? 0) : .free
                    }
                }
            }
            var p = PDFParser(bytes: bytes, at: lx.pos)
            guard let t = p.parseObject(), let d = t.dictValue else { return nil }
            if isFirst { trailer = d } else { for (k, v) in d where trailer[k] == nil { trailer[k] = v } }
            if let xs = d["XRefStm"]?.intValue { _ = parseXrefSection(at: xs, isFirst: false) }
            return d["Prev"]?.intValue
        }
        // xref stream: "n g obj <<...>> stream"
        var p = PDFParser(bytes: bytes, at: lx.pos)
        _ = p.lexer.next(); _ = p.lexer.next(); _ = p.lexer.next() // n g obj
        guard let obj = p.parseObject(), case .stream(let d, _) = obj, let data = PDFFilters.decode(obj, resolve: { $0 }) else { return nil }
        if isFirst { usesXrefStream = true; trailer = d } else { for (k, v) in d where trailer[k] == nil { trailer[k] = v } }
        let w = (d["W"]?.arrayValue ?? []).compactMap(\.intValue)
        guard w.count >= 3 else { return d["Prev"]?.intValue }
        let size = d["Size"]?.intValue ?? 0
        var index = (d["Index"]?.arrayValue ?? []).compactMap(\.intValue)
        if index.isEmpty { index = [0, size] }
        let rowLen = w.reduce(0, +)
        var pos = 0
        let bytesArr = [UInt8](data)
        var i = 0
        while i + 1 < index.count {
            let start = index[i], count = index[i + 1]; i += 2
            for k in 0..<count {
                guard pos + rowLen <= bytesArr.count else { break }
                var fields: [Int] = []
                var q = pos
                for width in w {
                    var v = 0
                    for _ in 0..<width { v = (v << 8) | Int(bytesArr[q]); q += 1 }
                    fields.append(v)
                }
                pos += rowLen
                let type = w[0] == 0 ? 1 : fields[0]
                let num = start + k
                if xref[num] == nil {
                    switch type {
                    case 1: xref[num] = .offset(fields[1], gen: fields[2])
                    case 2: xref[num] = .inStream(stream: fields[1], index: fields[2])
                    default: xref[num] = .free
                    }
                }
            }
        }
        return d["Prev"]?.intValue
    }

    func object(_ num: Int) -> PDFObj {
        if let c = cache[num] { return c }
        guard let e = xref[num] else { return .null }
        var result: PDFObj = .null
        switch e {
        case .free: break
        case .offset(let off, _):
            guard off >= 0, off < bytes.count else { break }
            var p = PDFParser(bytes: bytes, at: off)
            p.lengthResolver = { [weak self] r in self?.object(r.num).intValue }
            _ = p.lexer.next(); _ = p.lexer.next()
            if case .keyword("obj") = p.lexer.next(), let o = p.parseObject() { result = o }
        case .inStream(let sn, let idx):
            result = objectFromStream(sn, index: idx, number: num)
        }
        cache[num] = result
        return result
    }

    private func objectFromStream(_ sn: Int, index: Int, number: Int) -> PDFObj {
        if objectStreams[sn] == nil {
            var table: [Int: PDFObj] = [:]
            let so = object(sn)
            if case .stream(let d, _) = so, let data = PDFFilters.decode(so, resolve: resolve) {
                let n = d["N"]?.intValue ?? 0
                let first = d["First"]?.intValue ?? 0
                var hdr = PDFLexer(data, at: 0)
                var pairs: [(Int, Int)] = []
                for _ in 0..<n {
                    guard case .number(let a) = hdr.next(), case .number(let b) = hdr.next(), let an = Int(a), let bo = Int(b) else { break }
                    pairs.append((an, bo))
                }
                let arr = [UInt8](data)
                for (onum, off) in pairs {
                    var p = PDFParser(bytes: arr, at: first + off)
                    if let o = p.parseObject() { table[onum] = o }
                }
            }
            objectStreams[sn] = table
        }
        return objectStreams[sn]?[number] ?? .null
    }

    func resolve(_ o: PDFObj) -> PDFObj {
        if case .reference(let n, _) = o { return object(n) }
        return o
    }

    func dict(_ o: PDFObj?) -> [String: PDFObj]? { o.map(resolve)?.dictValue }

    /// Page dictionaries in document order, as (object number, dict).
    func pages() -> [(num: Int, dict: [String: PDFObj])] {
        guard let root = dict(trailer["Root"]), case .reference(let pn, _)? = root["Pages"] else { return [] }
        var out: [(Int, [String: PDFObj])] = []
        var seen: Set<Int> = []
        func walk(_ n: Int) {
            guard !seen.contains(n), let d = object(n).dictValue else { return }
            seen.insert(n)
            let type = d["Type"]?.nameValue
            if type == "Page" || (type == nil && d["Kids"] == nil && d["Contents"] != nil) { out.append((n, d)); return }
            for k in resolve(d["Kids"] ?? .null).arrayValue ?? [] { if case .reference(let kn, _) = k { walk(kn) } }
        }
        walk(pn)
        return out
    }

    /// Annotation (object number, dict) pairs for a page dict.
    func annotations(of page: [String: PDFObj]) -> [(num: Int, dict: [String: PDFObj])] {
        (resolve(page["Annots"] ?? .null).arrayValue ?? []).compactMap { a in
            if case .reference(let n, _) = a, let d = object(n).dictValue { return (n, d) }
            return nil
        }
    }

    // MARK: - Writing

    static func serialize(_ o: PDFObj) -> Data {
        var out = Data()
        write(o, into: &out)
        return out
    }

    private static func write(_ o: PDFObj, into out: inout Data) {
        switch o {
        case .null: out.append(contentsOf: "null".utf8)
        case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case .integer(let i): out.append(contentsOf: String(i).utf8)
        case .real(let d):
            var s = String(format: "%.4f", d)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            out.append(contentsOf: s.utf8)
        case .string(let d):
            out.append(0x3C); out.append(contentsOf: d.map { String(format: "%02X", $0) }.joined().utf8); out.append(0x3E)
        case .name(let n):
            out.append(0x2F)
            for u in n.utf8 {
                if PDFLexer.isRegular(u) && u != 0x23 && u > 0x20 && u < 0x7F { out.append(u) } else { out.append(contentsOf: String(format: "#%02X", u).utf8) }
            }
        case .array(let a):
            out.append(0x5B)
            for (i, e) in a.enumerated() { if i > 0 { out.append(0x20) }; write(e, into: &out) }
            out.append(0x5D)
        case .dictionary(let d):
            out.append(contentsOf: "<<".utf8)
            for (k, v) in d.sorted(by: { $0.key < $1.key }) { write(.name(k), into: &out); out.append(0x20); write(v, into: &out); out.append(0x0A) }
            out.append(contentsOf: ">>".utf8)
        case .stream(var d, let raw):
            d["Length"] = .integer(raw.count)
            write(.dictionary(d), into: &out)
            out.append(contentsOf: "\nstream\n".utf8); out.append(raw); out.append(contentsOf: "\nendstream".utf8)
        case .reference(let n, let g): out.append(contentsOf: "\(n) \(g) R".utf8)
        }
    }

    /// Appends an incremental update with the given (number → object) additions/replacements.
    func incrementalUpdate(objects: [Int: PDFObj]) -> Data {
        var out = Data(bytes)
        if out.last != 0x0A { out.append(0x0A) }
        var offsets: [Int: Int] = [:]
        for (num, obj) in objects.sorted(by: { $0.key < $1.key }) {
            offsets[num] = out.count
            out.append(contentsOf: "\(num) 0 obj\n".utf8)
            out.append(PDFFile.serialize(obj))
            out.append(contentsOf: "\nendobj\n".utf8)
        }
        let newSize = max(maxObjectNumber, (objects.keys.max() ?? 0) + 1)
        var trailerDict: [String: PDFObj] = ["Size": .integer(newSize), "Prev": .integer(startXref)]
        for key in ["Root", "Info", "ID"] where trailer[key] != nil { trailerDict[key] = trailer[key] }
        let xrefOffset = out.count
        if usesXrefStream {
            // Cross-reference stream (required when the previous section was one).
            let xnum = newSize
            var rows = Data()
            var index: [PDFObj] = []
            let all = (Array(offsets.keys) + [xnum]).sorted()
            var runs: [[Int]] = []
            for n in all { if let last = runs.last?.last, last + 1 == n { runs[runs.count - 1].append(n) } else { runs.append([n]) } }
            for run in runs {
                index.append(.integer(run[0])); index.append(.integer(run.count))
                for n in run {
                    let off = n == xnum ? xrefOffset : (offsets[n] ?? 0)
                    rows.append(1)
                    rows.append(contentsOf: [UInt8(off >> 24 & 0xFF), UInt8(off >> 16 & 0xFF), UInt8(off >> 8 & 0xFF), UInt8(off & 0xFF)])
                    rows.append(contentsOf: [0, 0])
                }
            }
            var xd = trailerDict
            xd["Type"] = .name("XRef"); xd["W"] = .array([.integer(1), .integer(4), .integer(2)]); xd["Index"] = .array(index)
            xd["Size"] = .integer(newSize + 1)
            xd["Filter"] = nil; xd["DecodeParms"] = nil
            out.append(contentsOf: "\(xnum) 0 obj\n".utf8)
            out.append(PDFFile.serialize(.stream(dict: xd, raw: rows)))
            out.append(contentsOf: "\nendobj\n".utf8)
        } else {
            out.append(contentsOf: "xref\n".utf8)
            let all = offsets.keys.sorted()
            var runs: [[Int]] = []
            for n in all { if let last = runs.last?.last, last + 1 == n { runs[runs.count - 1].append(n) } else { runs.append([n]) } }
            for run in runs {
                out.append(contentsOf: "\(run[0]) \(run.count)\n".utf8)
                for n in run { out.append(contentsOf: String(format: "%010d 00000 n \n", offsets[n] ?? 0).utf8) }
            }
            out.append(contentsOf: "trailer\n".utf8)
            out.append(PDFFile.serialize(.dictionary(trailerDict)))
            out.append(0x0A)
        }
        out.append(contentsOf: "startxref\n\(xrefOffset)\n%%EOF\n".utf8)
        return out
    }
}

// MARK: - Copying an object graph between files

/// Deep-copies objects (with their referenced sub-objects) from one PDFFile into new object numbers.
final class PDFObjectImporter {
    let source: PDFFile
    private(set) var objects: [Int: PDFObj] = [:]
    private var map: [Int: Int] = [:]
    private var nextNumber: Int

    init(source: PDFFile, firstFreeNumber: Int) { self.source = source; nextNumber = firstFreeNumber }

    var nextFree: Int { nextNumber }

    func allocate() -> Int { defer { nextNumber += 1 }; return nextNumber }

    /// Copies `obj` (which may contain references) and returns the rewritten object.
    func copy(_ obj: PDFObj) -> PDFObj {
        switch obj {
        case .reference(let n, _):
            if let m = map[n] { return .reference(m, 0) }
            let m = allocate()
            map[n] = m
            objects[m] = copy(source.object(n))
            return .reference(m, 0)
        case .array(let a): return .array(a.map(copy))
        case .dictionary(let d): return .dictionary(d.mapValues(copy))
        case .stream(let d, let raw): return .stream(dict: d.mapValues(copy), raw: raw)
        default: return obj
        }
    }
}
