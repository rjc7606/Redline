// Hex colour helpers shared by the core (readability rules) and the app (Color init).

import Foundation

public struct RGB: Sendable, Equatable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

public enum HexColor {
    /// Parses "#RGB", "#RRGGBB" or "#RRGGBBAA" (alpha ignored). Returns components 0…1.
    public static func parse(_ hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s.prefix(6), radix: 16) else { return nil }
        return RGB(Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }

    /// Canonical "#RRGGBB" upper-case form, or nil if unparsable.
    public static func normalize(_ hex: String) -> String? {
        guard let c = parse(hex) else { return nil }
        return format(c)
    }

    public static func format(_ c: RGB) -> String {
        func h(_ v: Double) -> String {
            let n = Int((min(1, max(0, v)) * 255).rounded())
            return String(format: "%02X", n)
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    /// Relative luminance (0 dark … 1 light), perceptual weights as in the prototype.
    public static func luminance(_ hex: String) -> Double {
        guard let c = parse(hex) else { return 1 }
        return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
    }

    /// README: a tool tint is unreadable when luminance > .9 in light mode or < .22 in dark mode.
    public static func isUnreadable(_ hex: String, dark: Bool) -> Bool {
        let l = luminance(hex)
        return dark ? l < 0.22 : l > 0.9
    }

    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return normalize(a) == normalize(b)
    }

    /// HSL → hex, h in degrees, s/l in percent.
    public static func hsl(_ h: Double, _ s: Double, _ l: Double) -> String {
        let H = h / 360, S = s / 100, L = l / 100
        func f(_ n: Double) -> Double {
            let k = (n + H * 12).truncatingRemainder(dividingBy: 12)
            let a = S * min(L, 1 - L)
            return L - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return format(RGB(f(0), f(8), f(4)))
    }
}
