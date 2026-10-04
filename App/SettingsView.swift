import SwiftUI
import RedlineCore

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < Metrics.compactThreshold
            HStack(spacing: 0) {
                if !compact { nav.frame(width: Metrics.settingsNav) }
                VStack(spacing: 0) {
                    if compact {
                        HStack(spacing: 8) {
                            backButton
                            Spacer()
                            SegmentControl(options: SettingsTab.allCases.map { SegmentOption(value: $0, label: $0.label) },
                                           selection: Binding(get: { app.settingsTab }, set: { app.settingsTab = $0 }), fontSize: 12.5)
                        }
                        .padding(.horizontal, 16).padding(.top, 12)
                    }
                    switch app.settingsTab {
                    case .general: GeneralSettings()
                    case .palettes: PalettesSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var backButton: some View {
        Button { app.settingsOpen = false } label: {
            HStack(spacing: 2) { Image(systemName: "chevron.left").font(fnt(17, .semibold)); Text(app.screen == .home ? "Library" : "Back").font(fnt(15)) }
                .foregroundStyle(theme.accent)
        }.buttonStyle(.plain)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            backButton.padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 14)
            Text("Settings").font(titleFnt(22)).foregroundStyle(theme.ink1).padding(.horizontal, 10).padding(.bottom, 16)
            ForEach(SettingsTab.allCases, id: \.self) { t in
                NavRow(label: t.label, symbol: t.symbol, active: app.settingsTab == t) {
                    app.settingsTab = t
                    if t == .palettes, app.settingsPaletteID == nil { app.settingsPaletteID = app.palettes.defaultID }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 18)
        .frame(maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }
}

struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("General").font(titleFnt(20)).foregroundStyle(theme.ink1)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Your name on comments")
                FieldText(placeholder: "Name", text: Binding(get: { app.settings.author }, set: { app.settings.author = $0 }))
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Appearance")
                SegmentControl(options: ThemePreference.allCases.map { SegmentOption(value: $0, label: $0.rawValue) },
                               selection: Binding(get: { app.settings.theme }, set: { app.settings.theme = $0 }), fontSize: 12.5, vPad: 7, fill: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Finger drawing")
                SegmentControl(options: FingerDrawing.allCases.map { SegmentOption(value: $0, label: $0.rawValue) },
                               selection: Binding(get: { app.settings.fingerDrawingMode }, set: { app.settings.fingerDrawingMode = $0 }), fontSize: 12.5, vPad: 7, fill: true)
                Text("Auto: after you pick a pen, whichever touches the page first decides — a finger first lets fingers ink with that tool; the Pencil first makes fingers pan instead. Picking another tool decides again. A finger can always use every non-ink tool and pans with no tool selected.")
                    .font(fnt(12)).foregroundStyle(theme.ink3).lineSpacing(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Snapping")
                Toggle(isOn: Binding(get: { app.settings.snapEnabled }, set: { app.settings.snapEnabled = $0 })) {
                    Text("Snap annotations while placing and moving").font(fnt(14, .medium)).foregroundStyle(theme.ink1)
                }.tint(theme.accent)
                Text("Shapes, text, stamps, notes and form fields snap to each other's edges and centres, touch each other, and match the spacing of their neighbours. Guides show what they snapped to. Pens never snap. The tool bar has a quick toggle.")
                    .font(fnt(12)).foregroundStyle(theme.ink3).lineSpacing(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Markup sheets")
                SegmentControl(options: [SegmentOption(value: false, label: "White paper"), SegmentOption(value: true, label: "Blueprint blue")],
                               selection: Binding(get: { app.settings.blueprint }, set: { app.settings.blueprint = $0 }), fontSize: 12.5, vPad: 7, fill: true)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 26)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

struct PalettesSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app

    var body: some View {
        let ps = app.palettes
        let edP = ps.palette(app.settingsPaletteID ?? "") ?? ps.defaultPalette
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Text("Color palettes").font(titleFnt(20)).foregroundStyle(theme.ink1)
                        Spacer()
                        PrimaryButton(label: "New", symbol: "plus", height: 34) {
                            let p = app.palettes.addNew()
                            app.settingsPaletteID = p.id; app.settingsSwatch = 0
                        }
                    }
                    .padding(.horizontal, 4).padding(.bottom, 10)
                    ForEach(ps.listed) { p in
                        let on = p.id == edP.id
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(p.name).font(fnt(14, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                                Spacer()
                                if p.id == ps.defaultID { tag("Default", theme.accent, theme.accent.opacity(0.16)) }
                                if p.builtIn { tag("Built in", theme.ink3, theme.bg3) }
                            }
                            HStack(spacing: 4) {
                                ForEach(Array(p.colors.prefix(8).enumerated()), id: \.offset) { _, c in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: c)).frame(width: 28, height: 28)
                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? theme.accent : theme.line, lineWidth: on ? 2 : 1))
                        .contentShape(Rectangle())
                        .onTapGesture { app.settingsPaletteID = p.id; app.settingsSwatch = 0 }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 26)
            }
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 320)
            .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
            PaletteEditor(palette: edP)
        }
    }

    private func tag(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text.uppercased()).font(fnt(10, .bold)).tracking(0.3).foregroundStyle(fg)
            .padding(.horizontal, 6).frame(height: 20).background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(bg))
    }
}

struct PaletteEditor: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var palette: Palette
    @State private var hexDraft = ""

    var body: some View {
        let locked = palette.builtIn
        let idx = min(app.settingsSwatch, palette.colors.count - 1)
        let cur = palette.colors.indices.contains(idx) ? palette.colors[idx] : "#000000"
        let isDefault = palette.id == app.palettes.defaultID
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    TextField("Palette name", text: Binding(get: { palette.name }, set: { app.palettes.rename(palette.id, to: $0) }))
                        .font(fnt(22, .bold)).foregroundStyle(theme.ink1).textFieldStyle(.plain).disabled(locked)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(locked ? .clear : theme.line).frame(height: 1.5) }
                    SecondaryButton(label: isDefault ? "Default palette" : "Make default", symbol: "star") { app.palettes.makeDefault(palette.id) }
                        .opacity(isDefault ? 0.5 : 1)
                    SecondaryButton(label: "", symbol: "doc.on.doc") {
                        if let p = app.palettes.duplicate(palette.id) { app.settingsPaletteID = p.id; app.settingsSwatch = 0 }
                    }
                    if !locked {
                        SecondaryButton(label: "", symbol: "trash", tint: theme.danger) {
                            app.palettes.delete(palette.id)
                            app.settingsPaletteID = app.palettes.defaultID; app.settingsSwatch = 0
                        }
                    }
                }
                if locked {
                    Text("Built-in palettes can't be edited. Duplicate one to make your own version.").font(fnt(13)).foregroundStyle(theme.ink3).padding(.top, -10)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Swatches · \(palette.colors.count)")
                    FlowLayout(spacing: 8) {
                        ForEach(Array(palette.colors.enumerated()), id: \.offset) { i, c in
                            RoundedRectangle(cornerRadius: 10).fill(Color(hex: c)).frame(width: 44, height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: i == idx && !locked ? 2 : 0).padding(-3))
                                .onTapGesture { app.settingsSwatch = i; hexDraft = c }
                        }
                        if !locked {
                            Button { app.settingsSwatch = app.palettes.addSwatch(palette.id) } label: {
                                Image(systemName: "plus").font(fnt(17, .medium)).foregroundStyle(theme.ink4).frame(width: 44, height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !locked {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10).fill(Color(hex: cur)).frame(width: 44, height: 44).overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
                        FieldText(placeholder: "#RRGGBB", text: $hexDraft, height: 36, mono: true)
                            .frame(width: 120)
                            .onSubmit { app.palettes.setSwatch(palette.id, index: idx, hex: hexDraft) }
                        Spacer()
                        SecondaryButton(label: "Remove swatch", symbol: "trash", tint: theme.danger) {
                            app.palettes.removeSwatch(palette.id, index: idx)
                            app.settingsSwatch = max(0, idx - 1)
                        }.opacity(palette.colors.count <= 2 ? 0.4 : 1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Pick a color for the selected swatch")
                        ColorGrid(colors: Spectrum.grid, selected: cur, rounded: false) { hex in
                            app.palettes.setSwatch(palette.id, index: idx, hex: hex)
                            hexDraft = hex
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 26)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { hexDraft = cur }
        .onChange(of: cur) { _, c in hexDraft = c }
    }
}
