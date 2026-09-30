// Layout constants and theme tokens from the README ("Device sizing", "Design tokens").
// All values are points.

import Foundation

public enum Metrics {
    public static let barHeight: Double = 54
    public static let toolButton: Double = 36
    public static let toolHit: Double = 44
    public static let toolGap: Double = 3
    public static let barPadding: Double = 12
    public static let sidebarMarkup: Double = 260
    public static let sidebarStudio: Double = 260
    /// Library tiles (handoff v2): document tile width, notebook cover size.
    public static let docTile: Double = 132
    public static let notebookTile = Size(104, 140)
    public static let homeNav: Double = 240
    public static let settingsNav: Double = 250
    public static let popoverWidth: Double = 250
    public static let presetsWidth: Double = 176
    public static let modalWidth: Double = 560
    public static let flattenWidth: Double = 400
    public static let exportWidth: Double = 300
    public static let docTabsHeight: Double = 48
    /// Below this width the layout is "compact" (overlay sidebar, stacked nav, scrolling tool row).
    public static let compactThreshold: Double = 900
    public static let longPress: Double = 0.45
    public static let toastSeconds: Double = 2

    public static let sheetCanvas = Size(1000, 707)
    /// Created (non-imported) markup pages: US Letter portrait / landscape at 1000 wide.
    public static let letterPortrait = Size(1000, 1294)
    public static let letterLandscape = Size(1000, 773)
    public static let notesCanvas = Size(600, 800)
    public static let defaultZoom: Double = 0.72
    public static let minZoom: Double = 0.3
    public static let maxZoom: Double = 2.2

    /// Fit-to-width zoom: (available − sidebar) ÷ canvas width, also bounded by height.
    public static func fitZoom(canvas: Size, available: Size, spread: Bool = false) -> Double {
        let w = spread ? canvas.w * 2 : canvas.w
        let availW = max(120, available.w - 56)
        let availH = max(120, available.h - 40)
        let z = min(availW / w, availH / canvas.h)
        return max(minZoom, min(1.4, (z * 100).rounded(.down) / 100))
    }
}

public enum ThemePreference: String, Codable, Sendable, CaseIterable, Hashable {
    case system = "System", light = "Light", dark = "Dark"
}

/// Colour tokens as hex strings with alpha (the app maps them to Color).
public struct ThemeTokens: Sendable, Equatable {
    public var accent: String
    public var bg: String, bg2: String, bg3: String, card: String
    public var bar: String, barAlpha: Double
    public var pop: String, popAlpha: Double
    public var ink1: String, ink2: String, ink3: String, ink4: String, dis: String
    public var lineAlpha: Double, line2Alpha: Double, hovAlpha: Double, hov2Alpha: Double
    /// Base colour for line/hover overlays (black in light, white in dark).
    public var overlayBase: String
    public var canvas: String
    public var isDark: Bool
    /// Text-field background (handoff v2).
    public var field: String = "#e9e8ee"
    /// Status chips: Open (amber) and resolved (green). Background hex + alpha, foreground hex.
    public var chipOpenBg: String = "#FFF1DC", chipOpenBgAlpha: Double = 1, chipOpenFg: String = "#B25E00"
    public var chipResolvedBg: String = "#E2F7E8", chipResolvedBgAlpha: Double = 1, chipResolvedFg: String = "#1D7A3B"
    /// Destructive tint (system red; brighter in dark).
    public var danger: String = "#FF3B30"
    /// Popover shadow opacity.
    public var popShadowAlpha: Double = 0.22

    /// Light theme (handoff v2, "warm paper"): warm neutrals, no pure grey or black; overlays are tinted brown.
    public static let light: ThemeTokens = {
        var t = ThemeTokens(accent: "#2F6FE4", bg: "#f4f1ea", bg2: "#ece8df", bg3: "#e2ddd2", card: "#fbf9f4",
                            bar: "#f4f1ea", barAlpha: 0.94, pop: "#fbf9f4", popAlpha: 0.97,
                            ink1: "#2a2622", ink2: "#4a443d", ink3: "#7a736a", ink4: "#968e84", dis: "#cfc9be",
                            lineAlpha: 0.10, line2Alpha: 0.22, hovAlpha: 0.05, hov2Alpha: 0.09, overlayBase: "#3c2d1e",
                            canvas: "#d9d4c8", isDark: false)
        t.field = "#eae6dc"
        t.chipOpenBg = "#FBEBD3"; t.chipOpenBgAlpha = 1; t.chipOpenFg = "#9A5A12"
        t.chipResolvedBg = "#5B9A6B"; t.chipResolvedBgAlpha = 0.16; t.chipResolvedFg = "#5B9A6B"
        t.danger = "#C4554A"
        t.popShadowAlpha = 0.16
        return t
    }()
    /// Dark theme (handoff v2): neutral, not warm; the warmth only lives in light mode.
    public static let dark: ThemeTokens = {
        var t = ThemeTokens(accent: "#6C96E0", bg: "#1f1f22", bg2: "#26262a", bg3: "#323236", card: "#2b2b2f",
                            bar: "#26262a", barAlpha: 0.94, pop: "#303035", popAlpha: 0.97,
                            ink1: "#ecebe8", ink2: "#cfcecb", ink3: "#a09f9c", ink4: "#84837f", dis: "#4b4b4f",
                            lineAlpha: 0.08, line2Alpha: 0.16, hovAlpha: 0.06, hov2Alpha: 0.10, overlayBase: "#ffffff",
                            canvas: "#151517", isDark: true)
        t.field = "#323236"
        t.chipOpenBg = "#E6AA5A"; t.chipOpenBgAlpha = 0.16; t.chipOpenFg = "#E4B276"
        t.chipResolvedBg = "#5B9A6B"; t.chipResolvedBgAlpha = 0.16; t.chipResolvedFg = "#5B9A6B"
        t.danger = "#C4554A"
        t.popShadowAlpha = 0.5
        return t
    }()

    public init(accent: String, bg: String, bg2: String, bg3: String, card: String, bar: String, barAlpha: Double, pop: String,
                popAlpha: Double, ink1: String, ink2: String, ink3: String, ink4: String, dis: String, lineAlpha: Double,
                line2Alpha: Double, hovAlpha: Double, hov2Alpha: Double, overlayBase: String, canvas: String, isDark: Bool) {
        self.accent = accent; self.bg = bg; self.bg2 = bg2; self.bg3 = bg3; self.card = card; self.bar = bar; self.barAlpha = barAlpha
        self.pop = pop; self.popAlpha = popAlpha; self.ink1 = ink1; self.ink2 = ink2; self.ink3 = ink3; self.ink4 = ink4; self.dis = dis
        self.lineAlpha = lineAlpha; self.line2Alpha = line2Alpha; self.hovAlpha = hovAlpha; self.hov2Alpha = hov2Alpha
        self.overlayBase = overlayBase; self.canvas = canvas; self.isDark = isDark
    }
}

/// Avatar colours, picked by a stable hash of the author's name.
public enum Avatar {
    public static let colors = ["#007AFF", "#FF9500", "#AF52DE", "#34C759", "#e8483f"]
    public static func color(for name: String) -> String {
        var h = 0
        for u in name.unicodeScalars { h = (h * 31 + Int(u.value)) % 997 }
        return colors[h % colors.count]
    }
    public static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").compactMap { $0.first }
        return String(parts.prefix(2)).uppercased()
    }
}
