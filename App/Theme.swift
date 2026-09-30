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

    /// Status chip colours: Open is amber, everything else counts as resolved.
    func chip(for status: CommentStatus) -> (bg: Color, fg: Color) {
        switch status {
        case .open: (Color(hex: tokens.chipOpenBg, alpha: tokens.chipOpenBgAlpha), Color(hex: tokens.chipOpenFg))
        case .rejected: (Color(hex: tokens.danger, alpha: isDark ? 0.16 : 0.12), Color(hex: tokens.danger))
        default: (Color(hex: tokens.chipResolvedBg, alpha: tokens.chipResolvedBgAlpha), Color(hex: tokens.chipResolvedFg))
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

enum Shadows {
    static let popover = (color: Color.black.opacity(0.22), radius: 22.0, y: 14.0)
    static let modal = (color: Color.black.opacity(0.3), radius: 30.0, y: 20.0)
    static let pill = (color: Color.black.opacity(0.14), radius: 1.5, y: 1.0)
}
