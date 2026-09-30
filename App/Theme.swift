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

/// Font for text boxes / callouts: optional font (PostScript or family name, any font installed on the device)
/// plus weight (nil = system semibold).
func textFont(_ name: String?, size: Double, weight: TextWeight?) -> Font {
    let w: Font.Weight
    switch weight {
    case .regular: w = .regular
    case .medium: w = .medium
    case .bold: w = .bold
    case .semibold, nil: w = .semibold
    }
    if let name, !name.isEmpty {
        if let ui = UIFont(name: name, size: size) { return Font(ui as CTFont) }
        return Font.custom(name, size: size).weight(w)
    }
    return .system(size: size, weight: w)
}

/// "Avenir Next Demi Bold" for a stored font name; "System" when nil.
func fontDisplayName(_ name: String?) -> String {
    guard let name, !name.isEmpty else { return "System" }
    if let f = UIFont(name: name, size: 12) {
        let face = (f.fontDescriptor.object(forKey: .face) as? String) ?? ""
        return face.isEmpty || face == "Regular" ? f.familyName : "\(f.familyName) \(face)"
    }
    return name
}

/// System font picker: every font on the device, including user-installed ones (which it also grants access to).
struct FontPicker: UIViewControllerRepresentable {
    var onPick: (String) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let config = UIFontPickerViewController.Configuration()
        config.includeFaces = true
        config.displayUsingSystemFont = false
        let vc = UIFontPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIFontPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    @MainActor
    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }
        func fontPickerViewControllerDidPickFont(_ vc: UIFontPickerViewController) {
            if let d = vc.selectedFontDescriptor {
                let name = d.postscriptName.isEmpty ? ((d.object(forKey: .family) as? String) ?? "") : d.postscriptName
                if !name.isEmpty { onPick(name) }
            }
            vc.dismiss(animated: true)
        }
        func fontPickerViewControllerDidCancel(_ vc: UIFontPickerViewController) { vc.dismiss(animated: true) }
    }
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
