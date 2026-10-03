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
        let isText = tool == .textbox, isShape = tool.isShape, isFill = tool == .fill, isEraser = tool == .eraser
        let range = ToolStyles.widthRange(for: tool)
        HStack(spacing: 12) {
            ForEach(Array(presets.enumerated()), id: \.offset) { i, p in
                let fill: Color = isText ? Color(hex: p.background ?? "#ffffff", alpha: p.backgroundOpacity ?? 1)
                    : isShape ? ((p.fillPattern ?? FillPattern.none) == FillPattern.none ? .clear : Color(hex: p.fill ?? p.color, alpha: max(0.35, p.fillOpacity ?? 0.5)))
                    : isFill ? Color(hex: p.color, alpha: max(0.35, p.opacity ?? 0.5)) : .white
                let border: Color = isText ? Color(hex: p.borderColor ?? p.color) : isShape ? Color(hex: p.color) : .clear
                let h = max(2.5, min(16, 2 + (p.width - range.lowerBound) / max(0.01, range.upperBound - range.lowerBound) * 12))
                ZStack {
                    Circle().fill(isShape || isText || isFill ? fill : .white)
                    Circle().strokeBorder(border, lineWidth: 2.5)
                    Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    if isText {
                        Text("A").font(fnt(13, .bold)).foregroundStyle(Color(hex: p.color))
                    } else if isEraser {
                        Circle().fill(theme.ink3).frame(width: max(4, min(24, p.width * 0.6)), height: max(4, min(24, p.width * 0.6)))
                    } else if !isShape && !isFill {
                        Capsule().fill(Color(hex: p.color)).frame(width: 16, height: h)
                    }
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(sel == i ? theme.accent : .clear, lineWidth: 2.5).padding(-4))
                .contentShape(Circle())
                .onTapGesture { editor.selectPreset(i) }
                .accessibilityLabel("Preset \(i + 1)")
                .accessibilityHint("Tap the selected preset again to edit it")
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
    /// When set, the editor changes this style (an annotation) through `apply` instead of the tool's preset.
    var stroke: StylePreset? = nil
    var apply: (((inout StylePreset) -> Void) -> Void)? = nil
    var forTool: Tool? = nil
    var showPresets = true
    /// Inside the annotation popup: no presets, no preview row, takes the parent's width.
    var embedded = false
    @State private var fontListOpen = false

    var body: some View {
        let tool = forTool ?? editor.styleTool
        let st = stroke ?? app.styles.current(for: tool)
        let set: ((inout StylePreset) -> Void) -> Void = { body in if let apply { apply(body) } else { editor.updateStyle(body) } }
        let isText = tool == .textbox, isShape = tool.isShape, isFill = tool == .fill
        let isLine = tool.isLineLike
        let target: StylePreset.Target = {
            if isText { return [.color, .font, .border, .background].contains(editor.styleTarget) ? editor.styleTarget : .color }
            if isShape { return [.color, .fill].contains(editor.styleTarget) ? editor.styleTarget : .color }
            return .color
        }()
        let cur = st.color(for: target)
        let range = ToolStyles.widthRange(for: tool)

        VStack(alignment: .leading, spacing: 0) {
            if showPresets && !embedded { PresetsRow(editor: editor).padding(.bottom, 12) }

            if tool == .eraser {
                SliderRow(label: "Eraser size", value: Binding(get: { st.width }, set: { v in set { $0.width = v } }),
                          range: range, step: 1, valueLabel: "\(Int(st.width.rounded())) pt")
                HStack(spacing: 10) {
                    Text("Preview").font(fnt(11)).foregroundStyle(theme.ink4)
                    Circle().fill(theme.ink3.opacity(0.5)).frame(width: min(60, st.width), height: min(60, st.width))
                }
                .padding(.top, 14)
            } else {

            if isShape || isText {
                let opts: [SegmentOption<StylePreset.Target>] = isShape
                    ? [SegmentOption(value: .color, label: "Border"), SegmentOption(value: .fill, label: "Fill")]
                    : [SegmentOption(value: .color, label: "Text"), SegmentOption(value: .font, label: "Font"), SegmentOption(value: .border, label: "Border"), SegmentOption(value: .background, label: "Fill")]
                SegmentControl(options: opts, selection: Binding(get: { target }, set: { v in editor.styleTarget = v }), fontSize: 11.5, vPad: 4, hPad: 6, radius: 8, fill: true)
                    .padding(.bottom, 10)
            }

            if isText && target == .font {
                SectionLabel(text: "Font").padding(.bottom, 8)
                // Redline's own list: one row per family, each name drawn in that family. Weight is set below.
                Button { withAnimation(.easeOut(duration: 0.15)) { fontListOpen.toggle() } } label: {
                    HStack {
                        Text(fontDisplayName(st.font)).font(textFont(st.font, size: 14, weight: st.fontWeight)).foregroundStyle(theme.ink1).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down").font(fnt(12, .semibold)).foregroundStyle(theme.ink4).rotationEffect(.degrees(fontListOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.field))
                }
                .buttonStyle(.plain)
                if fontListOpen {
                    FontFamilyList(selected: st.font) { name in set { $0.font = name }; withAnimation(.easeOut(duration: 0.15)) { fontListOpen = false } }
                        .padding(.top, 6)
                }
                Spacer().frame(height: 12)
                SectionLabel(text: "Weight").padding(.bottom, 8)
                SegmentControl(options: TextWeight.allCases.map { SegmentOption(value: $0, label: $0.label) },
                               selection: Binding(get: { st.fontWeight ?? .semibold }, set: { v in set { $0.fontWeight = v } }), fontSize: 11.5, vPad: 4, hPad: 4, radius: 8, fill: true)
                    .padding(.bottom, 12)
            }
            SectionLabel(text: colorHeader(isText: isText, isShape: isShape, isFill: isFill, target: target)).padding(.bottom, 8)
            // Full spectrum: greys on the top row, then hue columns with lighter → darker shades.
            ColorGrid(colors: Spectrum.grid, selected: cur, rounded: false) { hex in set { $0.setColor(hex, for: target) } }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line, lineWidth: 1))

            PalettesDisclosure(editor: editor, selected: cur) { hex in set { $0.setColor(hex, for: target) } }
                .padding(.top, 10)

            if isShape && target == .fill {
                SectionLabel(text: "Fill pattern").padding(.top, 16).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(FillPattern.allCases, id: \.self) { fp in
                        VStack(spacing: 4) {
                            PatternSwatch(pattern: fp, color: Color(hex: st.fill ?? st.color))
                                .frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke((st.fillPattern ?? FillPattern.none) == fp ? theme.accent : Color.black.opacity(0.18), lineWidth: (st.fillPattern ?? FillPattern.none) == fp ? 2 : 1.5))
                            Text(fp.label).font(fnt(9.5, .bold)).foregroundStyle(theme.ink3)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { set { $0.fillPattern = fp } }
                    }
                }
            }

            if !isFill && (target == .color || target == .font) {
                SliderRow(label: isText ? "Text size" : (isShape ? "Border thickness" : "Line thickness"),
                          value: Binding(get: { st.width }, set: { v in set { $0.width = v } }),
                          range: range, step: ToolStyles.widthStep(for: tool),
                          valueLabel: isText ? "\(Int((10 + st.width).rounded()))pt" : String(format: "%.1f pt", st.width))
                    .padding(.top, 16)
            }

            if isText && target == .border {
                SliderRow(label: "Border size", value: Binding(get: { st.borderWidth ?? 0 }, set: { v in set { $0.borderWidth = v } }),
                          range: 0...6, step: 0.5, valueLabel: String(format: "%.1f pt", st.borderWidth ?? 0))
                    .padding(.top, 16)
            }

            if tool == .cloud && target == .color {
                SectionLabel(text: "Border shape").padding(.top, 16).padding(.bottom, 8)
                SegmentControl(options: [SegmentOption(value: "arcs", label: "Cloud"), SegmentOption(value: "straight", label: "Straight")],
                               selection: Binding(get: { st.cloudStyle ?? "arcs" }, set: { v in set { $0.cloudStyle = v == "arcs" ? nil : v } }), fontSize: 12, vPad: 5, radius: 8, fill: true)
            }
            if (isShape && target == .color) || isLine || tool.isPen {
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
                        .onTapGesture { set { $0.lineStyle = ls } }
                    }
                }
            }

            let opVal = st.opacity(for: target, tool: tool)
            SliderRow(label: opacityLabel(isText: isText, isShape: isShape, isFill: isFill, target: target),
                      value: Binding(get: { opVal }, set: { v in set { $0.setOpacity(v, for: target) } }),
                      range: 0.1...1, step: 0.05, valueLabel: "\(Int((opVal * 100).rounded()))%")
                .padding(.top, 16)

            if !embedded {
            HStack(spacing: 10) {
                Text("Preview").font(fnt(11)).foregroundStyle(theme.ink4)
                if isText {
                    Text("Text note").font(textFont(st.font, size: 10 + st.width, weight: st.fontWeight))
                        .foregroundStyle(Color(hex: st.color, alpha: st.opacity ?? 1))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: st.background ?? "#ffffff", alpha: st.backgroundOpacity ?? 1)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: st.borderColor ?? st.color, alpha: st.borderOpacity ?? 1), lineWidth: st.borderWidth ?? 0))
                } else if isShape {
                    PatternSwatch(pattern: st.fillPattern ?? FillPattern.none, color: Color(hex: st.fill ?? st.color, alpha: st.fillOpacity ?? 0.5))
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
            }
        }
        .frame(width: embedded ? nil : CGFloat(Metrics.popoverWidth))
    }

    private func colorHeader(isText: Bool, isShape: Bool, isFill: Bool, target: StylePreset.Target) -> String {
        if isFill { return "Fill color" }
        if isText { return (target == .color || target == .font) ? "Text color" : (target == .border ? "Border color" : "Fill color") }
        if isShape { return target == .color ? "Border color" : "Fill color" }
        return "Color"
    }
    private func opacityLabel(isText: Bool, isShape: Bool, isFill: Bool, target: StylePreset.Target) -> String {
        if isFill || target == .fill || target == .background { return "Fill opacity" }
        if isShape || target == .border { return "Border opacity" }
        if isText { return "Text opacity" }
        return "Opacity"
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
            if pattern == FillPattern.none {
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


/// Every font family on the device, each row set in its own face. "Default" is Source Sans 3.
struct FontFamilyList: View {
    @Environment(\.theme) private var theme
    var selected: String?
    var onPick: (String?) -> Void
    private let families = RedlineFonts.families

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 0) {
                row(label: "Default · " + RedlineFonts.family, family: nil, on: selected == nil || selected == RedlineFonts.family)
                ForEach(families.filter { $0 != RedlineFonts.family }, id: \.self) { f in
                    row(label: f, family: f, on: selected == f)
                }
            }
        }
        .frame(maxHeight: 260)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(label: String, family: String?, on: Bool) -> some View {
        Button { onPick(family) } label: {
            HStack(spacing: 8) {
                Text(label).font(Font(RedlineFonts.face(family ?? RedlineFonts.family, size: 15, weight: .regular) as CTFont))
                    .foregroundStyle(theme.ink1).lineLimit(1)
                Spacer(minLength: 4)
                if on { Image(systemName: "checkmark").font(fnt(12, .bold)).foregroundStyle(theme.accent) }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(on ? theme.hov : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1).padding(.leading, 12) }
    }
}
