import SwiftUI
import RedlineCore

/// Button frames, collected so the presets dropdown can be positioned under the active tool.
struct ToolAnchorKey: PreferenceKey {
    static var defaultValue: [Tool: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Tool: Anchor<CGRect>], nextValue: () -> [Tool: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tool button (tap = pick and show presets; tap again = deselect)

struct ToolButton: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var tool: Tool
    /// Favorites edit mode: index in the pins list (shows the remove badge).
    var editIndex: Int? = nil

    var body: some View {
        let on = editor.tool == tool && tool.kind != .pageAction && tool.kind != .flash
        let st = tool.hasPresets ? editor.style(for: tool) : nil
        let c = st?.color
        let unreadable = c.map { HexColor.isUnreadable($0, dark: theme.isDark) } ?? false
        let tint: Color = unreadable ? theme.ink1 : (c.map { Color(hex: $0) } ?? (on ? .white : theme.ink2))
        let bg: Color = on ? (c != nil ? theme.hov2 : theme.accent) : .clear
        var glyphFill: Color? = nil
        var glyphStroke: Color? = nil
        if let st, tool.isShape, (st.fillPattern ?? FillPattern.none) != FillPattern.none {
            glyphFill = Color(hex: st.fill ?? st.color, alpha: max(0.3, st.fillOpacity ?? 0.5))
        }
        if let st, tool == .textbox {
            glyphStroke = Color(hex: st.borderColor ?? st.color, alpha: st.borderOpacity ?? 1)
            glyphFill = Color(hex: st.background ?? "#ffffff", alpha: min(0.85, st.backgroundOpacity ?? 1))
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg)
            if on, let c {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(unreadable ? theme.ink1 : Color(hex: c), lineWidth: 2)
            }
            ToolIcon(tool: tool, size: 20, color: tint, glyphFill: glyphFill, glyphStroke: glyphStroke)
        }
        .frame(width: Metrics.toolButton, height: Metrics.toolButton)
        .frame(width: Metrics.toolHit, height: Metrics.toolHit)
        .contentShape(Rectangle())
        .onTapGesture { editor.pick(tool) }
        .anchorPreference(key: ToolAnchorKey.self, value: .bounds) { [tool: $0] }
        .overlay(alignment: .topTrailing) {
            if let i = editIndex {
                Button { editor.removePin(at: i) } label: {
                    Image(systemName: "xmark").font(fnt(8, .bold)).foregroundStyle(.white).frame(width: 15, height: 15)
                        .background(Circle().fill(theme.danger)).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }.buttonStyle(.plain).offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel(tool.label)
        .help(tool.label)
    }
}

/// A specific stamp pinned to a Favorites tab: tap arms the Stamps tool with it; tap again deselects.
struct StampPinButton: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    var stamp: StampDef
    var editIndex: Int? = nil

    var body: some View {
        let on = editor.tool == .stamps && editor.stamp.id == stamp.id
        let c = Color(hex: stamp.color)
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? theme.hov2 : .clear)
            if on { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c, lineWidth: 2) }
            Text(stamp.isMark ? stamp.text : stamp.resolved(author: app.author))
                .font(fnt(stamp.isMark ? 16 : 7.5, .bold)).foregroundStyle(c).lineLimit(stamp.isMark ? 1 : 2).minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 3).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(c, lineWidth: 1.5))
                .rotationEffect(.degrees(-2))
                .frame(width: 30, height: 30)
        }
        .frame(width: Metrics.toolButton, height: Metrics.toolButton)
        .frame(width: Metrics.toolHit, height: Metrics.toolHit)
        .contentShape(Rectangle())
        .onTapGesture { if on { editor.tool = .none; editor.popover = nil; editor.presetsTool = nil } else { editor.useStamp(stamp) } }
        .overlay(alignment: .topTrailing) {
            if let i = editIndex {
                Button { editor.removePin(at: i) } label: {
                    Image(systemName: "xmark").font(fnt(8, .bold)).foregroundStyle(.white).frame(width: 15, height: 15)
                        .background(Circle().fill(theme.danger)).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }.buttonStyle(.plain).offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel("Stamp \(stamp.text)")
        .help(stamp.text)
    }
}

/// Dropdown under the active tool: the 4 presets, or the full Style Popover after a long-press on one.
struct PresetsDropdown: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var body: some View {
        Group {
            if editor.styleExpanded {
                ScrollView(showsIndicators: false) { StylePopoverView(editor: editor).padding(14) }
                    .frame(width: Metrics.popoverWidth + 28)
                    .frame(maxHeight: 560)
            } else {
                PresetsRow(editor: editor)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(width: Metrics.presetsWidth)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.popSolid)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
                .popShadow(theme)
        )
    }
}

/// Places the presets dropdown under whichever tool button is active, clamped to the window.
struct PresetsDropdownHost: View {
    var editor: WorkspaceModel
    var anchors: [Tool: Anchor<CGRect>]
    var body: some View {
        GeometryReader { geo in
            if let t = editor.presetsTool, let a = anchors[t] {
                let r = geo[a]
                let w = editor.styleExpanded ? Metrics.popoverWidth + 28 : Metrics.presetsWidth
                let x = min(max(8, r.midX - w / 2), max(8, geo.size.width - w - 8))
                PresetsDropdown(editor: editor)
                    .fixedSize()
                    .offset(x: x, y: r.maxY + 6)
                    .popIn()
            }
        }
    }
}

// MARK: - Top bar

struct TopBar<Center: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    var compact: Bool
    @ViewBuilder var center: Center

    var body: some View {
        HStack(spacing: 6) {
            Button { app.goHome() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(fnt(17, .semibold))
                    Text(editor.type.shelfLabel).font(fnt(15, .medium))
                }
                .foregroundStyle(theme.accent).padding(.horizontal, 6).padding(.vertical, 4)
            }.buttonStyle(.plain)
            if !compact {
                Text(editor.doc.name).font(fnt(13, .bold)).foregroundStyle(theme.ink1).lineLimit(1).frame(maxWidth: 260, alignment: .leading)
            }
            Spacer(minLength: 4)
            center
            Spacer(minLength: 4)
            BarButton(symbol: "arrow.uturn.backward", label: "Undo", enabled: editor.canUndo) { editor.undo() }
            BarButton(symbol: "arrow.uturn.forward", label: "Redo", enabled: editor.canRedo) { editor.redo() }
            if !compact {
                BarButton(symbol: "minus.magnifyingglass", label: "Zoom out") { editor.zoomOut() }
                BarButton(symbol: "plus.magnifyingglass", label: "Zoom in") { editor.zoomIn() }
            }
            if editor.type != .markup {
                BarButton(symbol: "ruler", label: "Ruler", active: editor.ruler.on) { editor.toggleRuler() }
            }
            if editor.isPDF {
                BarButton(symbol: "magnifyingglass", label: "Find", active: editor.mk.searchOpen) {
                    if editor.mk.searchOpen { editor.mkCloseSearch() } else { editor.mk.searchOpen = true }
                }
            }
            BarButton(symbol: "square.and.arrow.up", label: "Share", active: editor.popover == .export, filledWhenActive: true) {
                editor.popover = editor.popover == .export ? nil : .export
            }
            Rectangle().fill(theme.line2).frame(width: 1, height: 28).padding(.horizontal, 4)
            BarButton(symbol: "sidebar.right", label: "Sidebar", active: editor.sidebarOpen) { editor.sidebarOpen.toggle() }
        }
        .padding(.horizontal, Metrics.barPadding)
        .frame(height: Metrics.barHeight)
        .background(theme.bar.background(.regularMaterial))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .zIndex(60)
    }
}

// MARK: - Studio tool row (Drawing / Notes)

struct StudioToolRow: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.toolGap) {
                    ForEach(editor.stripTools, id: \.self) { t in ToolButton(editor: editor, tool: t) }
                }
                .padding(.horizontal, Metrics.barPadding)
            }
            Spacer(minLength: 0)
            if !compact {
                Text(editor.statusHint).font(fnt(12)).foregroundStyle(theme.ink4).lineLimit(1).padding(.trailing, 16)
            }
        }
        .frame(height: Metrics.barHeight)
        .background(theme.bar.background(.regularMaterial))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .zIndex(55)
    }
}

// MARK: - Markup tabs (top bar centre) and tool strip (second bar)

struct MarkupTabSegment: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(editor.favorites.enumerated()), id: \.element.id) { i, f in
                tabPill(label: f.name, on: editor.markupTab == .favorites(i)) { editor.markupTab = .favorites(i); editor.closePopovers() }
                    .contextMenu {
                        Button("Rename") { editor.renameFavIndex = i; editor.renameDraft = f.name; editor.favRenameVisible = true }
                        if editor.favorites.count > 1 { Button("Remove tab", role: .destructive) { editor.removeFavoritesTab(i) } }
                    }
            }
            ForEach(ToolCatalog.markupTabs) { t in
                tabPill(label: compact ? String(t.label.prefix(4)) : t.label, on: editor.markupTab == .tab(t.id)) { editor.markupTab = .tab(t.id); editor.closePopovers() }
            }
            if editor.favorites.count < 4 {
                Button { editor.addFavoritesTab() } label: {
                    Text("+").font(fnt(13, .bold)).foregroundStyle(theme.ink4).padding(.horizontal, 9).padding(.vertical, 5)
                }.buttonStyle(.plain).help("New favorites tab")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.hov))
    }

    private func tabPill(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(fnt(13, .semibold)).foregroundStyle(on ? theme.ink1 : theme.ink2).lineLimit(1)
                .padding(.horizontal, compact ? 9 : 13).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? theme.card : .clear)
                    .shadow(color: on ? Shadows.pill.color : .clear, radius: Shadows.pill.radius, y: Shadows.pill.y))
        }.buttonStyle(.plain)
    }
}

struct MarkupToolStrip: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let editMode = editor.popover == .tray && editor.onFavoritesTab
        HStack(spacing: 0) {
            BarButton(symbol: "square.grid.2x2", label: "Organize pages", active: editor.organizeOpen, filledWhenActive: true, size: 44) {
                editor.organizeOpen.toggle(); editor.closePopovers()
            }
            .padding(.leading, 10)
            ToolButton(editor: editor, tool: .select)
            Rectangle().fill(theme.line2).frame(width: 1, height: 30).padding(.horizontal, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.toolGap) {
                    ForEach(Array(editor.stripTools.enumerated()), id: \.offset) { i, t in
                        Group {
                            if let s = editor.pinnedStamp(at: i) { StampPinButton(editor: editor, stamp: s, editIndex: editMode ? i : nil) }
                            else { ToolButton(editor: editor, tool: t, editIndex: editMode ? i : nil) }
                        }
                            .contextMenu {
                                if editor.onFavoritesTab {
                                    if i > 0 { Button("Move left") { editor.movePin(from: i, to: i - 1) } }
                                    if i < editor.stripTools.count - 1 { Button("Move right") { editor.movePin(from: i, to: i + 1) } }
                                    Button("Remove from tab", role: .destructive) { editor.removePin(at: i) }
                                }
                            }
                    }
                    if editor.onFavoritesTab {
                        Button { editor.popover = editor.popover == .tray ? nil : .tray } label: {
                            Image(systemName: "plus").font(fnt(17, .semibold))
                                .foregroundStyle(editor.popover == .tray ? .white : theme.ink2)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(editor.popover == .tray ? theme.accent : theme.hov))
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).help("Customize Favorites")
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Rectangle().fill(theme.line2).frame(width: 1, height: 30).padding(.horizontal, 8)
            if !editor.app.clipboard.isEmpty {
                BarButton(symbol: "doc.on.clipboard", label: "Paste") { editor.mkPaste() }
            }
            if editor.mkPendingRedactions > 0 {
                BarButton(symbol: "eye.slash.fill", label: "Apply redactions — remove the marked content for good") { editor.mk.redactConfirm = true }
            }
            BarButton(symbol: "square.on.square.dashed", label: "Snap to annotations", active: editor.app.settings.snapEnabled) {
                editor.app.settings.snapEnabled.toggle()
                editor.app.flash(editor.app.settings.snapEnabled ? "Snapping on" : "Snapping off")
            }
            BarButton(symbol: "ruler", label: "Ruler", active: editor.ruler.on) { editor.toggleRuler() }
                .padding(.trailing, 10)
        }
        .frame(height: Metrics.barHeight)
        .background(theme.bar.background(.regularMaterial))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .zIndex(55)
    }
}
