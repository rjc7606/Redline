import SwiftUI
import RedlineCore

extension Color {
    init(hex: String, alpha: Double = 1) {
        let c = HexColor.parse(hex) ?? RGB(0, 0, 0)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let c = HexColor.parse(hex) ?? RGB(0, 0, 0)
        self.init(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
}

/// Design tokens resolved to SwiftUI colours. See README "Design tokens".
struct Theme: Sendable {
    let tokens: ThemeTokens
    init(_ tokens: ThemeTokens) { self.tokens = tokens }

    var isDark: Bool { tokens.isDark }
    var accent: Color { Color(hex: tokens.accent) }
    var accentSoft: Color { Color(hex: tokens.accent, alpha: 0.14) }
    var bg: Color { Color(hex: tokens.bg) }
    var bg2: Color { Color(hex: tokens.bg2) }
    var bg3: Color { Color(hex: tokens.bg3) }
    var card: Color { Color(hex: tokens.card) }
    var bar: Color { Color(hex: tokens.bar, alpha: tokens.barAlpha) }
    var pop: Color { Color(hex: tokens.pop, alpha: tokens.popAlpha) }
    var popSolid: Color { Color(hex: tokens.pop) }
    var ink1: Color { Color(hex: tokens.ink1) }
    var ink2: Color { Color(hex: tokens.ink2) }
    var ink3: Color { Color(hex: tokens.ink3) }
    var ink4: Color { Color(hex: tokens.ink4) }
    var dis: Color { Color(hex: tokens.dis) }
    var line: Color { Color(hex: tokens.overlayBase, alpha: tokens.lineAlpha) }
    var line2: Color { Color(hex: tokens.overlayBase, alpha: tokens.line2Alpha) }
    var hov: Color { Color(hex: tokens.overlayBase, alpha: tokens.hovAlpha) }
    var hov2: Color { Color(hex: tokens.overlayBase, alpha: tokens.hov2Alpha) }
    var canvas: Color { Color(hex: tokens.canvas) }
    var danger: Color { Color(hex: "#FF3B30") }

    static func resolve(_ pref: ThemePreference, systemDark: Bool) -> Theme {
        switch pref {
        case .light: Theme(.light)
        case .dark: Theme(.dark)
        case .system: Theme(systemDark ? .dark : .light)
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(.light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// System font at a point size (README type scale).
func fnt(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
}

enum Shadows {
    static let popover = (color: Color.black.opacity(0.22), radius: 22.0, y: 14.0)
    static let modal = (color: Color.black.opacity(0.3), radius: 30.0, y: 20.0)
    static let pill = (color: Color.black.opacity(0.14), radius: 1.5, y: 1.0)
}
