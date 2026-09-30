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
    var danger: Color { Color(hex: tokens.danger) }
    var field: Color { Color(hex: tokens.field) }
    var popShadow: Color { Color.black.opacity(tokens.popShadowAlpha) }

    /// Status chip colours (handoff v2): Open amber, Accepted green, Rejected destructive, Completed muted.
    func chip(for status: CommentStatus) -> (bg: Color, fg: Color) {
        switch status {
        case .open: (Color(hex: tokens.chipOpenBg, alpha: tokens.chipOpenBgAlpha), Color(hex: tokens.chipOpenFg))
        case .accepted: (Color(hex: tokens.chipResolvedBg, alpha: tokens.chipResolvedBgAlpha), Color(hex: tokens.chipResolvedFg))
        case .rejected: (Color(hex: tokens.danger, alpha: 0.14), Color(hex: tokens.danger))
        case .completed: (hov2, ink4)
        }
    }

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

/// Default face for text on the page (text boxes, callouts, stamps): Source Sans 3, bundled with the app
/// (App/Fonts, SIL Open Font License) so an iPad and a Windows build draw the same glyphs and embed the same
/// subset into PDFs. Falls back to the system font if the files are missing.
enum RedlineFonts {
    static let family = "Source Sans 3"
    static func page(size: CGFloat, weight: TextWeight?) -> UIFont {
        let name: String
        let sys: UIFont.Weight
        switch weight {
        case .regular: name = "SourceSans3-Regular"; sys = .regular
        case .medium: name = "SourceSans3-Medium"; sys = .medium
        case .bold: name = "SourceSans3-Bold"; sys = .bold
        case .semibold, nil: name = "SourceSans3-Semibold"; sys = .semibold
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: sys)
    }

    /// Every font family on the device (built in, bundled, and user-installed), one entry per family.
    static var families: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for f in UIFont.familyNames where !f.hasPrefix(".") {
            // Static weights that declare their own family ("Source Sans 3 Semibold") fold into the base family.
            let base = f.hasPrefix(family) ? family : f
            if seen.insert(base).inserted { out.append(base) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The non-italic face of `name` (a family, or an older PostScript name) closest to the wanted weight.
    static func face(_ name: String, size: CGFloat, weight: TextWeight?) -> UIFont {
        if name == family { return page(size: size, weight: weight) }
        let target: CGFloat
        switch weight { case .regular: target = 0; case .medium: target = 0.23; case .bold: target = 0.4; default: target = 0.3 }
        var faces = UIFont.fontNames(forFamilyName: name)
        // Families split across several family names (e.g. "X Medium") — gather them all.
        for other in UIFont.familyNames where other != name && other.hasPrefix(name + " ") { faces += UIFont.fontNames(forFamilyName: other) }
        if faces.isEmpty {
            guard let f = UIFont(name: name, size: size) else { return page(size: size, weight: weight) }
            return f
        }
        var best: (name: String, diff: CGFloat)? = nil
        for f in faces {
            guard let font = UIFont(name: f, size: size) else { continue }
            let d = font.fontDescriptor
            if d.symbolicTraits.contains(.traitItalic) { continue }
            let w = ((d.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat) ?? 0
            let diff = abs(w - target)
            if best == nil || diff < best!.diff { best = (f, diff) }
        }
        return UIFont(name: best?.name ?? faces[0], size: size) ?? page(size: size, weight: weight)
    }
}

/// Font for text boxes / callouts: optional font (PostScript or family name, any font installed on the device)
/// plus weight (nil = the page default, Avenir Next).
func textFont(_ name: String?, size: Double, weight: TextWeight?) -> Font {
    if let name, !name.isEmpty { return Font(RedlineFonts.face(name, size: size, weight: weight) as CTFont) }
    return Font(RedlineFonts.page(size: size, weight: weight) as CTFont)
}

/// The family name to show for a stored font (families are stored as-is; older data may hold a PostScript name).
func fontDisplayName(_ name: String?) -> String {
    guard let name, !name.isEmpty else { return RedlineFonts.family }
    if UIFont.fontNames(forFamilyName: name).isEmpty, let f = UIFont(name: name, size: 12) { return f.familyName }
    return name
}

/// System font at a point size (README type scale).
func fnt(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
}

/// Titles and section labels: SF Pro Rounded, never heavier than 700 (handoff v2).
func titleFnt(_ size: Double, _ weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

extension View {
    /// Two-layer "paper" shadow for tiles, pages and covers.
    func pageShadow(_ t: Theme) -> some View {
        self.shadow(color: t.isDark ? .black.opacity(0.4) : Color(hex: "#281e14", alpha: 0.12), radius: 1, y: 1)
            .shadow(color: t.isDark ? .black.opacity(0.35) : Color(hex: "#281e14", alpha: 0.10), radius: 12, y: 8)
    }
    /// Two-layer popover shadow.
    func popShadow(_ t: Theme) -> some View {
        self.shadow(color: Color(hex: "#281e14", alpha: t.isDark ? 0.3 : 0.08), radius: 3, y: 2)
            .shadow(color: Color(hex: "#281e14", alpha: t.isDark ? 0.5 : 0.16), radius: 20, y: 16)
    }
}

/// Paper grain (light mode only): a 160 pt noise tile multiplied at 4 % over `bg`-type surfaces.
/// Never on bars, sidebars or popovers.
struct GrainBackground: View {
    @Environment(\.theme) private var theme
    var color: Color
    var body: some View {
        ZStack {
            color
            if !theme.isDark {
                Image(uiImage: PaperGrain.shared.image).resizable(resizingMode: .tile)
                    .opacity(0.04).blendMode(.multiply).allowsHitTesting(false)
            }
        }
    }
}

final class PaperGrain: @unchecked Sendable {
    static let shared = PaperGrain()
    let image: UIImage
    private init() {
        let n = 160
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = ctx.data else { image = UIImage(); return }
        let p = base.assumingMemoryBound(to: UInt8.self)
        let stride = ctx.bytesPerRow
        var seed: UInt64 = 0x2545F4914F6CDD1D
        for y in 0..<n {
            for x in 0..<n {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let a = Double(seed >> 11) / Double(1 << 53)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let b = Double(seed >> 11) / Double(1 << 53)
                let v = UInt8(max(0, min(255, 96 + (a + b) * 80)))   // soft, mid-grey noise
                let o = y * stride + x * 4
                p[o] = v; p[o + 1] = v; p[o + 2] = v; p[o + 3] = 255
            }
        }
        image = ctx.makeImage().map { UIImage(cgImage: $0, scale: 1, orientation: .up) } ?? UIImage()
    }
}

enum Shadows {
    static let popover = (color: Color.black.opacity(0.22), radius: 22.0, y: 14.0)
    static let modal = (color: Color.black.opacity(0.3), radius: 30.0, y: 20.0)
    static let pill = (color: Color.black.opacity(0.14), radius: 1.5, y: 1.0)
}
