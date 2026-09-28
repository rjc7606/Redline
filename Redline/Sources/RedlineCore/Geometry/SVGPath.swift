// Minimal SVG path-data parser (M L H V C S Q T A Z, absolute and relative).
// Used for the custom tool glyphs, which are authored on a 24×24 grid.

import Foundation

public enum SVGPath {
    public static func parse(_ d: String) -> PathData {
        var path = PathData()
        var tokens = tokenize(d)
        var i = 0
        var cmd: Character = "M"
        var cur = Point.zero, start = Point.zero
        var lastCubicControl: Point? = nil
        var lastQuadControl: Point? = nil

        func num() -> Double? {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return nil }
            i += 1
            return v
        }
        func pt(relative: Bool) -> Point? {
            guard let x = num(), let y = num() else { return nil }
            return relative ? Point(cur.x + x, cur.y + y) : Point(x, y)
        }

        while i < tokens.count {
            if case .command(let c) = tokens[i] { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            let upper = Character(cmd.uppercased())
            switch upper {
            case "M":
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                path.move(to: p); cur = p; start = p
                cmd = rel ? "l" : "L"
                lastCubicControl = nil; lastQuadControl = nil
            case "L":
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                path.line(to: p); cur = p
                lastCubicControl = nil; lastQuadControl = nil
            case "H":
                guard let x = num() else { i = tokens.count; break }
                let p = Point(rel ? cur.x + x : x, cur.y)
                path.line(to: p); cur = p
                lastCubicControl = nil; lastQuadControl = nil
            case "V":
                guard let y = num() else { i = tokens.count; break }
                let p = Point(cur.x, rel ? cur.y + y : y)
                path.line(to: p); cur = p
                lastCubicControl = nil; lastQuadControl = nil
            case "C":
                guard let c1 = pt(relative: rel), let c2 = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                path.cubic(to: p, c1: c1, c2: c2); cur = p
                lastCubicControl = c2; lastQuadControl = nil
            case "S":
                guard let c2 = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                let c1 = lastCubicControl.map { Point(2 * cur.x - $0.x, 2 * cur.y - $0.y) } ?? cur
                path.cubic(to: p, c1: c1, c2: c2); cur = p
                lastCubicControl = c2; lastQuadControl = nil
            case "Q":
                guard let c = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                path.quad(to: p, control: c); cur = p
                lastQuadControl = c; lastCubicControl = nil
            case "T":
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                let c = lastQuadControl.map { Point(2 * cur.x - $0.x, 2 * cur.y - $0.y) } ?? cur
                path.quad(to: p, control: c); cur = p
                lastQuadControl = c; lastCubicControl = nil
            case "A":
                guard let rx = num(), let ry = num(), let rot = num(), let la = num(), let sw = num(), let p = pt(relative: rel) else { i = tokens.count; break }
                path.arc(from: cur, to: p, rx: rx, ry: ry, rotation: rot, largeArc: la != 0, sweep: sw != 0); cur = p
                lastCubicControl = nil; lastQuadControl = nil
            case "Z":
                path.close(); cur = start
                lastCubicControl = nil; lastQuadControl = nil
                // Z takes no numbers; guard against infinite loop if followed by numbers.
                if i < tokens.count, case .number = tokens[i] { cmd = rel ? "l" : "L" }
            default:
                i = tokens.count
            }
        }
        _ = tokens.count
        tokens.removeAll()
        return path
    }

    enum Token { case command(Character), number(Double) }

    static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var numBuf = ""
        func flush() {
            if !numBuf.isEmpty { if let v = Double(numBuf) { out.append(.number(v)) }; numBuf = "" }
        }
        var prevWasExp = false
        for ch in d {
            if ch.isLetter && !(prevWasExp && (ch == "e" || ch == "E")) {
                if ch == "e" || ch == "E" { numBuf.append(ch); prevWasExp = true; continue }
                flush(); out.append(.command(ch)); prevWasExp = false
            } else if ch == "-" || ch == "+" {
                if prevWasExp { numBuf.append(ch) } else { flush(); numBuf.append(ch) }
                prevWasExp = false
            } else if ch == "." {
                if numBuf.contains(".") { flush() }
                numBuf.append(ch); prevWasExp = false
            } else if ch.isNumber {
                numBuf.append(ch); prevWasExp = false
            } else {
                flush(); prevWasExp = false
            }
        }
        flush()
        return out
    }
}
