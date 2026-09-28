import SwiftUI
import RedlineCore

// MARK: - Segmented pill (README: bg hov, radius 8, selected pill card with shadow)

struct SegmentOption<T: Hashable>: Identifiable {
    var id: T { value }
    var value: T
    var label: String
    var symbol: String? = nil
}

struct SegmentControl<T: Hashable>: View {
    @Environment(\.theme) private var theme
    var options: [SegmentOption<T>]
    @Binding var selection: T
    var fontSize: Double = 13
    var vPad: Double = 5
    var hPad: Double = 13
    var radius: Double = 9
    var fill: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                HStack(spacing: 6) {
                    if let s = o.symbol { Image(systemName: s).font(fnt(fontSize + 1, .medium)) }
                    Text(o.label)
                }
                .font(fnt(fontSize, .semibold))
                .foregroundStyle(on ? theme.ink1 : theme.ink3)
                .padding(.vertical, vPad)
                .padding(.horizontal, hPad)
                .frame(maxWidth: fill ? CGFloat.infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: radius - 2, style: .continuous)
                        .fill(on ? theme.card : .clear)
                        .shadow(color: on ? Shadows.pill.color : .clear, radius: Shadows.pill.radius, y: Shadows.pill.y)
                )
                .contentShape(Rectangle())
                .onTapGesture { selection = o.value }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.hov))
    }
}

// MARK: - Icon buttons

/// 40×40 bar button (44 hit area) with optional active tint.
struct BarButton: View {
    @Environment(\.theme) private var theme
    var symbol: String
    var label: String
    var active: Bool = false
    var enabled: Bool = true
    var filledWhenActive: Bool = false
    var size: Double = 40
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(fnt(19, .medium))
                .foregroundStyle(!enabled ? theme.dis : (active ? (filledWhenActive ? .white : theme.accent) : theme.ink2))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? (filledWhenActive ? theme.accent : theme.accentSoft) : .clear)
                )
                .frame(width: Metrics.toolHit, height: Metrics.toolHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Accent pill button ("New", "Done", "Create").
struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    var label: String
    var symbol: String? = nil
    var height: Double = 36
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let s = symbol { Image(systemName: s).font(fnt(14, .semibold)) }
                Text(label).font(fnt(13.5, .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    @Environment(\.theme) private var theme
    var label: String
    var symbol: String? = nil
    var tint: Color? = nil
    var height: Double = 34
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = symbol { Image(systemName: s).font(fnt(14, .semibold)) }
                if !label.isEmpty { Text(label).font(fnt(13, .semibold)) }
            }
            .foregroundStyle(tint ?? theme.ink2)
            .padding(.horizontal, label.isEmpty ? 0 : 12)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.bg3))
        }
        .buttonStyle(.plain)
    }
}

/// 11pt/700 uppercase section label.
struct SectionLabel: View {
    @Environment(\.theme) private var theme
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(fnt(11, .bold))
            .tracking(0.5)
            .foregroundStyle(theme.ink4)
    }
}

/// Floating card chrome for popovers/menus (radius 14, popover shadow).
struct PopoverCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var width: CGFloat? = nil
    var padding: Double = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.popSolid)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .shadow(color: Shadows.popover.color, radius: Shadows.popover.radius, y: Shadows.popover.y)
            )
    }
}

/// Sidebar/nav row.
struct NavRow: View {
    @Environment(\.theme) private var theme
    var label: String
    var symbol: String
    var active: Bool = false
    var trailing: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(fnt(17, .medium)).frame(width: 20)
                Text(label).font(fnt(15, active ? .semibold : .regular))
                Spacer(minLength: 0)
                if let t = trailing { Text(t).font(fnt(12, .semibold)).foregroundStyle(theme.ink4) }
            }
            .foregroundStyle(active ? theme.accent : theme.ink2)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bottom-centre toast pill.
struct ToastView: View {
    var text: String
    var body: some View {
        Text(text)
            .font(fnt(13, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#1c1c1e", alpha: 0.88)))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// Labelled slider row with a right-aligned value (README: 12/700 ink2, min-width 36).
struct SliderRow: View {
    @Environment(\.theme) private var theme
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var valueLabel: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step).tint(theme.accent)
                Text(valueLabel).font(fnt(12, .bold)).foregroundStyle(theme.ink2).frame(minWidth: 36, alignment: .trailing)
            }
        }
    }
}

/// Author avatar circle with initials.
struct AvatarView: View {
    var name: String
    var size: Double = 20
    var body: some View {
        Text(Avatar.initials(name))
            .font(fnt(size * 0.45, .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: Avatar.color(for: name))))
    }
}

/// Text field styled like the prototype inputs.
struct FieldText: View {
    @Environment(\.theme) private var theme
    var placeholder: String
    @Binding var text: String
    var height: Double = 38
    var font: Font = fnt(14)
    var mono: Bool = false
    var body: some View {
        TextField(placeholder, text: $text)
            .font(mono ? .system(size: 14, design: .monospaced) : font)
            .textFieldStyle(.plain)
            .foregroundStyle(theme.ink1)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

/// Swatch ring used for selected colours in grids.
struct SelectedRing: View {
    var on: Bool
    var radius: Double
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white, lineWidth: on ? 2 : 0)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).inset(by: 2).strokeBorder(Color.black.opacity(0.85), lineWidth: on ? 1.5 : 0))
    }
}

/// Scrim + centred modal container.
struct ModalScrim<Content: View>: View {
    var dismiss: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: dismiss)
            content
        }
        .transition(.opacity)
    }
}

extension View {
    /// 160 ms fade + 6pt slide-down (README "dcpop").
    func popIn() -> some View {
        self.transition(.opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.16)))
    }
}
