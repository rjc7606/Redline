// Layout constants and theme tokens from the README ("Device sizing", "Design tokens").
// All values are points.

import Foundation

public enum Metrics {
    public static let barHeight: Double = 54
    public static let toolButton: Double = 36
    public static let toolHit: Double = 44
    public static let toolGap: Double = 3
    public static let barPadding: Double = 12
    public static let sidebarMarkup: Double = 232
    public static let sidebarStudio: Double = 262
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

    public static let light = ThemeTokens(accent: "#007AFF", bg: "#f2f2f7", bg2: "#eceaef", bg3: "#e4e2e8", card: "#ffffff",
                                          bar: "#f9f9fb", barAlpha: 0.94, pop: "#fafafc", popAlpha: 0.97,
                                          ink1: "#1c1c1e", ink2: "#3a3a3c", ink3: "#6d6d72", ink4: "#8e8e93", dis: "#c7c7cc",
                                          lineAlpha: 0.09, line2Alpha: 0.25, hovAlpha: 0.05, hov2Alpha: 0.08, overlayBase: "#000000",
                                          canvas: "#d9d8dd", isDark: false)
    public static let dark = ThemeTokens(accent: "#007AFF", bg: "#000000", bg2: "#1c1c1e", bg3: "#2c2c2e", card: "#1c1c1e",
                                         bar: "#1c1c1e", barAlpha: 0.94, pop: "#242426", popAlpha: 0.97,
                                         ink1: "#f2f2f7", ink2: "#d1d1d6", ink3: "#a1a1a6", ink4: "#8e8e93", dis: "#48484a",
                                         lineAlpha: 0.10, line2Alpha: 0.28, hovAlpha: 0.07, hov2Alpha: 0.12, overlayBase: "#ffffff",
                                         canvas: "#0d0d0f", isDark: true)

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
