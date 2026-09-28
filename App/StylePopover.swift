import SwiftUI
import RedlineCore

// MARK: - Presets row (4 × 30pt circles)

struct PresetsRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        let tool = editor.styleTool
        let presets = app.styles.presets(for: tool)
        let sel = app.styles.selectedIndex(for: tool)
        let isText = tool == .textbox, isShape = tool.isShape, isFill = tool == .fill
        let range = ToolStyles.widthRange(for: tool)
        HStack(spacing: 12) {
            ForEach(Array(presets.enumerated()), id: \.offset) { i, p in
                let fill: Color = isText ? Color(hex: p.background ?? "#ffffff", alpha: p.backgroundOpacity ?? 1)
                    : isShape ? ((p.fillPattern ?? .none) == .none ? .clear : Color(hex: p.fill ?? p.color, alpha: max(0.35, p.fillOpacity ?? 0.5)))
                    : isFill ? Color(hex: p.color, alpha: max(0.35, p.opacity ?? 0.5)) : .white
                let border: Color = isText ? Color(hex: p.borderColor ?? p.color) : isShape ? Color(hex: p.color) : .clear
                let h = max(2.5, min(16, 2 + (p.width - range.lowerBound) / max(0.01, range.upperBound - range.lowerBound) * 12))
                ZStack {
                    Circle().fill(isShape || isText || isFill ? fill : .white)
                    Circle().strokeBorder(border, lineWidth: 2.5)
                    Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    if isText {
                        Text("A").font(fnt(13, .heavy)).foregroundStyle(Color(hex: p.color))
                    } else if !isShape && !isFill {
                        Capsule().fill(Color(hex: p.color)).frame(width: 16, height: h)
                    }
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(sel == i ? theme.accent : .clear, lineWidth: 2.5).padding(-4))
                .contentShape(Circle())
                .onTapGesture { editor.selectPreset(i) }
                .accessibilityLabel("Preset \(i + 1)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Style popover (README "Style Popover")

struct StylePopoverView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel

    var body: some View {
        let tool = editor.styleTool
        let st = app.styles.current(for: tool)
        let isText = tool == .textbox, isShape = tool.isShape, isFill = tool == .fill, isPen = tool.isPen
        let isLine = tool.isLineLike
        let target: StylePreset.Target = {
            if isText { return [.color, .border, .background].contains(editor.styleTarget) ? editor.styleTarget : .color }
            if isShape { return [.color, .fill].contains(editor.styleTarget) ? editor.styleTarget : .color }
            return .color
        }()
        let cur = st.color(for: target)
        let range = ToolStyles.widthRange(for: tool)

        VStack(alignment: .leading, spacing: 0) {
            PresetsRow(editor: editor).padding(.bottom, 12)

            if isShape || isText {
                let opts: [SegmentOption<StylePreset.Target>] = isShape
                    ? [SegmentOption(value: .color, label: "Border"), SegmentOption(value: .fill, label: "Fill")]
                    : [SegmentOption(value: .color, label: "Text"), SegmentOption(value: .border, label: "Border"), SegmentOption(value: .background, label: "Fill")]
                SegmentControl(options: opts, selection: Binding(get: { target }, set: { editor.styleTarget = $0 }), fontSize: 11.5, vPad: 4, hPad: 6, radius: 8, fill: true)
                    .padding(.bottom, 10)
            }

            SectionLabel(text: colorHeader(isText: isText, isShape: isShape, isFill: isFill, target: target)).padding(.bottom, 8)
            ColorGrid(colors: ToolStyles.quickPalette, selected: cur, rounded: false) { hex in editor.updateStyle { $0.setColor(hex, for: target) } }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line, lineWidth: 1))

            PalettesDisclosure(editor: editor, selected: cur) { hex in editor.updateStyle { $0.setColor(hex, for: target) } }
                .padding(.top, 10)

            if isShape && target == .fill {
                SectionLabel(text: "Fill pattern").padding(.top, 16).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(FillPattern.allCases, id: \.self) { fp in
                        VStack(spacing: 4) {
                            PatternSwatch(pattern: fp, color: Color(hex: st.fill ?? st.color))
                                .frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke((st.fillPattern ?? .none) == fp ? theme.accent : Color.black.opacity(0.18), lineWidth: (st.fillPattern ?? .none) == fp ? 2 : 1.5))
                            Text(fp.label).font(fnt(9.5, .bold)).foregroundStyle(theme.ink3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editor.updateStyle { $0.fillPattern = fp } }
                    }
                }
            }

            if !isFill && target == .color {
                SliderRow(label: isText ? "Text size" : (isShape ? "Border thickness" : "Line thickness"),
                          value: Binding(get: { st.width }, set: { v in editor.updateStyle { $0.width = v } }),
                          range: range, step: ToolStyles.widthStep(for: tool),
                          valueLabel: isText ? "\(Int((10 + st.width).rounded()))pt" : String(format: "%.1fpx", st.width))
                    .padding(.top, 16)
            }

            if isPen {
                SectionLabel(text: "Line weight").padding(.top, 16).padding(.bottom, 8)
                HStack(spacing: 2) {
                    pressureOption(label: "Constant", on: !(st.pressure ?? false), color: st.color, pressure: false) { editor.updateStyle { $0.pressure = false } }
                    pressureOption(label: "Pressure", on: st.pressure ?? false, color: st.color, pressure: true) { editor.updateStyle { $0.pressure = true } }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.hov))
            }

            if isText && target == .border {
                SliderRow(label: "Border size", value: Binding(get: { st.borderWidth ?? 0 }, set: { v in editor.updateStyle { $0.borderWidth = v } }),
                          range: 0...6, step: 0.5, valueLabel: String(format: "%.1fpx", st.borderWidth ?? 0))
                    .padding(.top, 16)
            }

            if (isShape && target == .color) || isLine {
                SectionLabel(text: isShape ? "Border style" : "Line style").padding(.top, 16).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(LineStyle.allCases, id: \.self) { ls in
                        VStack(spacing: 5) {
                            LineSample(style: ls, color: Color(hex: st.color)).frame(height: 3)
                            Text(ls.label).font(fnt(9.5, .bold)).foregroundStyle(theme.ink3)
                        }
                        .padding(.top, 9).padding(.bottom, 4).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke((st.lineStyle ?? .solid) == ls ? theme.accent : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                        .onTapGesture { editor.updateStyle { $0.lineStyle = ls } }
                    }
                }
            }

            let opVal = st.opacity(for: target, tool: tool)
            SliderRow(label: opacityLabel(isText: isText, isShape: isShape, isFill: isFill, target: target),
                      value: Binding(get: { opVal }, set: { v in editor.updateStyle { $0.setOpacity(v, for: target) } }),
                      range: 0.1...1, step: 0.05, valueLabel: "\(Int((opVal * 100).rounded()))%")
                .padding(.top, 16)

            HStack(spacing: 10) {
                Text("Preview").font(fnt(11)).foregroundStyle(theme.ink4)
                if isText {
                    Text("Text note").font(fnt(10 + st.width, .semibold))
                        .foregroundStyle(Color(hex: st.color, alpha: st.opacity ?? 1))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: st.background ?? "#ffffff", alpha: st.backgroundOpacity ?? 1)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: st.borderColor ?? st.color, alpha: st.borderOpacity ?? 1), lineWidth: st.borderWidth ?? 0))
                } else if isShape {
                    PatternSwatch(pattern: st.fillPattern ?? .none, color: Color(hex: st.fill ?? st.color, alpha: st.fillOpacity ?? 0.5))
                        .frame(height: 30)
                        .overlay(LineSampleRect(style: st.lineStyle ?? .solid, color: Color(hex: st.color, alpha: st.opacity ?? 1), width: max(1.5, st.width)))
                } else {
                    let h = tool == .highlighter ? 8 + st.width * 0.6 : (isFill ? 30 : max(1.5, min(20, st.width)))
                    RoundedRectangle(cornerRadius: 9).fill(Color(hex: st.color)).frame(height: h)
                        .opacity(st.opacity ?? ToolStyles.defaultOpacity(for: tool))
                }
            }
            .padding(.top, 14)
        }
        .frame(width: Metrics.popoverWidth)
    }

    private func colorHeader(isText: Bool, isShape: Bool, isFill: Bool, target: StylePreset.Target) -> String {
        if isFill { return "Fill color" }
        if isText { return target == .color ? "Text color" : (target == .border ? "Border color" : "Fill color") }
        if isShape { return target == .color ? "Border color" : "Fill color" }
        return "Color"
    }
    private func opacityLabel(isText: Bool, isShape: Bool, isFill: Bool, target: StylePreset.Target) -> String {
        if isFill || target == .fill || target == .background { return "Fill opacity" }
        if isShape || target == .border { return "Border opacity" }
        if isText { return "Text opacity" }
        return "Opacity"
    }

    private func pressureOption(label: String, on: Bool, color: String, pressure: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Path { p in
                if pressure {
                    p.move(to: CGPoint(x: 2, y: 6)); p.addCurve(to: CGPoint(x: 62, y: 6), control1: CGPoint(x: 18, y: 0), control2: CGPoint(x: 44, y: 0))
                    p.addCurve(to: CGPoint(x: 2, y: 6), control1: CGPoint(x: 44, y: 12), control2: CGPoint(x: 18, y: 12)); p.closeSubpath()
                } else {
                    p.addRect(CGRect(x: 2, y: 5, width: 60, height: 2))
                }
            }
            .fill(on ? Color(hex: color) : Color(hex: "#8e8e93"))
            .frame(width: 64, height: 12)
            Text(label).font(fnt(11, .bold)).foregroundStyle(on ? theme.ink1 : theme.ink3)
        }
        .padding(.top, 7).padding(.bottom, 5).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? theme.card : .clear).shadow(color: on ? Shadows.pill.color : .clear, radius: 1.5, y: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 12-column colour grid.
struct ColorGrid: View {
    var colors: [String]
    var selected: String
    var rounded: Bool = true
    var gap: Double = 0
    var onPick: (String) -> Void
    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: gap), count: 12)
        LazyVGrid(columns: cols, spacing: gap) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                let on = HexColor.same(c, selected)
                RoundedRectangle(cornerRadius: rounded ? 6 : 0)
                    .fill(Color(hex: c))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(SelectedRing(on: on, radius: rounded ? 6 : 0))
                    .overlay(rounded ? RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.1), lineWidth: 1) : nil)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(c) }
            }
        }
    }
}

/// "Palettes" disclosure card inside the Style Popover.
struct PalettesDisclosure: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    var selected: String
    var onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { editor.palettesExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette").font(fnt(16, .medium)).foregroundStyle(theme.ink3)
                    Text("Palettes").font(fnt(13, .semibold)).foregroundStyle(theme.ink1)
                    Spacer()
                    HStack(spacing: 2) { ForEach(Array(app.palettes.defaultPalette.colors.prefix(5).enumerated()), id: \.offset) { _, c in Circle().fill(Color(hex: c)).frame(width: 8, height: 8) } }
                    Image(systemName: "chevron.down").font(fnt(13, .semibold)).foregroundStyle(theme.ink4)
                        .rotationEffect(.degrees(editor.palettesExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12).frame(height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if editor.palettesExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(app.palettes.ordered) { p in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(p.name).font(fnt(11, .bold)).foregroundStyle(theme.ink4)
                            ColorGrid(colors: p.colors, selected: selected, rounded: true, gap: 4, onPick: onPick)
                        }
                    }
                    Button { editor.closePopovers(); app.openSettings(tab: .palettes) } label: {
                        Text("Manage palettes in Settings…").font(fnt(12, .semibold)).foregroundStyle(theme.accent)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
                .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

struct PatternSwatch: View {
    var pattern: FillPattern
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            let path = Path(roundedRect: r, cornerRadius: 6)
            if pattern == .none {
                var p = Path(); var d = -size.height
                while d < size.width { p.move(to: CGPoint(x: d, y: size.height)); p.addLine(to: CGPoint(x: d + size.height, y: 0)); d += 8 }
                ctx.drawLayer { l in l.clip(to: path); l.stroke(p, with: .color(.black.opacity(0.08)), lineWidth: 2) }
            } else {
                ctx.drawLayer { l in
                    l.clip(to: path)
                    switch pattern {
                    case .solid: l.fill(path, with: .color(color))
                    case .hatch, .cross:
                        var p = Path(); var d = -size.height
                        while d < size.width {
                            p.move(to: CGPoint(x: d, y: size.height)); p.addLine(to: CGPoint(x: d + size.height, y: 0))
                            if pattern == .cross { p.move(to: CGPoint(x: d, y: 0)); p.addLine(to: CGPoint(x: d + size.height, y: size.height)) }
                            d += 7
                        }
                        l.stroke(p, with: .color(color), lineWidth: 1.5)
                    case .dots:
                        var p = Path(); var y = 3.5
                        while y < size.height { var x = 3.5; while x < size.width { p.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)); x += 7 }; y += 7 }
                        l.fill(p, with: .color(color))
                    case .none: break
                    }
                }
            }
        }
    }
}

struct LineSample: View {
    var style: LineStyle
    var color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: CGPoint(x: g.size.width * 0.1, y: 1.5)); p.addLine(to: CGPoint(x: g.size.width * 0.9, y: 1.5)) }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: style == .solid ? [] : (style == .dash ? [8, 6] : [0.1, 6])))
        }
    }
}

struct LineSampleRect: View {
    var style: LineStyle
    var color: Color
    var width: Double
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(color, style: StrokeStyle(lineWidth: width, dash: style == .solid ? [] : (style == .dash ? [width * 3, width * 2] : [0.1, width * 2.2])))
    }
}
