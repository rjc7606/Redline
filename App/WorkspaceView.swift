import SwiftUI
import RedlineCore

/// Workspace shell shared by Markup, Drawing and Notes: bars, canvas, sidebar and overlays.
struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Bindable var editor: WorkspaceModel

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < Metrics.compactThreshold
            VStack(spacing: 0) {
                TopBar(editor: editor, compact: compact) { topCenter(compact: compact) }
                if editor.type == .markup { MarkupToolStrip(editor: editor) } else { StudioToolRow(editor: editor, compact: compact) }
                DocTabsRow(current: editor.docID)
                HStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if editor.sidebarOpen && !compact { SidebarView(editor: editor) }
                }
                .overlay(alignment: .trailing) {
                    // Compact width: the sidebar floats over the canvas without a scrim, so you can keep marking up.
                    if editor.sidebarOpen && compact {
                        SidebarView(editor: editor)
                            .shadow(color: .black.opacity(0.2), radius: 20)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if editor.isPDF, editor.onFormsTab, let w = editor.mk.selected.first(where: { $0.isWidget }) {
                        PDFFieldInspector(editor: editor, widget: w)
                            .padding(.top, 14)
                            .padding(.trailing, (editor.sidebarOpen ? editor.sidebarWidth : 0) + 14)
                            .popIn()
                    } else if editor.type == .markup, !editor.isPDF, editor.onFormsTab, let fid = editor.selectedField,
                       let f = editor.page.fields.first(where: { $0.id == fid }) {
                        FieldInspector(editor: editor, field: f)
                            .padding(.top, 14)
                            .padding(.trailing, (editor.sidebarOpen ? editor.sidebarWidth : 0) + 14)
                            .popIn()
                    }
                }
                .overlay {
                    if editor.organizeOpen {
                        Group { if editor.isPDF { PDFOrganizePages(editor: editor) } else { OrganizePagesView(editor: editor) } }.transition(.opacity)
                    }
                }
            }
            .overlay(alignment: .top) { popovers.padding(.top, Metrics.barHeight * 2 + 6) }
            .overlayPreferenceValue(ToolAnchorKey.self) { anchors in PresetsDropdownHost(editor: editor, anchors: anchors) }
            .overlay(alignment: .topTrailing) {
                if editor.popover == .export { ExportMenu(editor: editor).padding(.top, Metrics.barHeight - 2).padding(.trailing, 12).popIn() }
            }
            .overlay { if let f = editor.flatten { FlattenDialog(editor: editor, request: f) } }
            .background(theme.bg)
            .onAppear { editor.isCompact = compact }
            .onChange(of: compact) { _, c in editor.isCompact = c; if c { editor.sidebarOpen = false } }
        }
        .animation(.easeInOut(duration: 0.18), value: editor.sidebarOpen)
        .animation(.easeInOut(duration: 0.16), value: editor.popover)
        .animation(.easeInOut(duration: 0.16), value: editor.organizeOpen)
        .animation(.easeInOut(duration: 0.16), value: editor.flatten)
        .alert("Layer name", isPresented: $editor.layerRenameVisible) {
            TextField("Name", text: $editor.renameDraft)
            Button("Rename") { editor.commitLayerRename() }
            Button("Cancel", role: .cancel) { editor.renameLayerID = nil }
        }
        .alert("Tab name", isPresented: $editor.favRenameVisible) {
            TextField("Name", text: $editor.renameDraft)
            Button("Rename") { editor.commitFavRename() }
            Button("Cancel", role: .cancel) { editor.renameFavIndex = nil }
        }
        .sheet(isPresented: Binding(get: { editor.shareURL != nil }, set: { if !$0 { editor.shareURL = nil } })) {
            if let url = editor.shareURL { ActivityView(items: [url]) }
        }
        .background { KeyboardShortcuts(editor: editor) }
    }

    @ViewBuilder
    private var content: some View {
        switch editor.type {
        case .markup:
            if editor.isPDF { MarkupCanvas(editor: editor) } else { SheetCanvasArea(editor: editor) }
        case .drawing:
            SheetCanvasArea(editor: editor)
        case .journal:
            if editor.journalView == .book { BookView(editor: editor) } else { CalendarView(editor: editor) }
        }
    }

    @ViewBuilder
    private func topCenter(compact: Bool) -> some View {
        switch editor.type {
        case .markup:
            MarkupTabSegment(editor: editor, compact: compact)
        case .journal:
            HStack(spacing: 8) {
                SegmentControl(options: [SegmentOption(value: JournalView.book, label: "Pages", symbol: "book"),
                                         SegmentOption(value: JournalView.calendar, label: "Calendar", symbol: "calendar")],
                               selection: Binding(get: { editor.journalView }, set: { editor.journalView = $0; editor.tagPopoverPage = nil }))
                if editor.journalView == .book && !compact {
                    HStack(spacing: 1) {
                        spreadPill(false, "rectangle.portrait")
                        spreadPill(true, "book.pages")
                    }
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.hov))
                }
            }
        case .drawing:
            EmptyView()
        }
    }

    private func spreadPill(_ v: Bool, _ symbol: String) -> some View {
        let on = editor.spread == v
        return Button {
            editor.spread = v
            editor.tagPopoverPage = nil
            editor.pan = .zero
        } label: {
            Image(systemName: symbol).font(fnt(15, .medium)).foregroundStyle(on ? theme.ink1 : theme.ink3)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? theme.card : .clear)
                    .shadow(color: on ? Shadows.pill.color : .clear, radius: 1.5, y: 1))
        }.buttonStyle(.plain).help(v ? "Two pages" : "One page")
    }

    @ViewBuilder
    private var popovers: some View {
        switch editor.popover {
        case .tray: FavoritesTrayView(editor: editor).popIn()
        case .stamps: StampGalleryView(editor: editor).popIn()
        default: EmptyView()
        }
    }
}

/// Hidden buttons providing hardware-keyboard shortcuts (README "Keyboard").
struct KeyboardShortcuts: View {
    var editor: WorkspaceModel
    var body: some View {
        Group {
            Button("Undo") { editor.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("Redo") { editor.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Duplicate") { editor.duplicateSelection() }.keyboardShortcut("d", modifiers: .command)
            Button("Copy") { if editor.isPDF { editor.mkCopySelection() } }.keyboardShortcut("c", modifiers: .command)
            Button("Paste") { if editor.isPDF { editor.mkPaste() } }.keyboardShortcut("v", modifiers: .command)
            Button("Lock") { if editor.isPDF { editor.mkToggleLock() } }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Next unresolved") { if editor.isPDF { editor.mkNextUnresolved() } }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Select all") { editor.selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("Delete") { editor.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            Button("Escape") { _ = editor.handleKey(.escape, modifiers: []) }.keyboardShortcut(.escape, modifiers: [])
            Button("Select tool") { editor.tool = .select }.keyboardShortcut("v", modifiers: [])
            Button("Eraser") { editor.tool = .eraser }.keyboardShortcut("e", modifiers: [])
            Button("Next") { editor.nextPage() }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Prev") { editor.prevPage() }.keyboardShortcut(.leftArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}


/// Open documents (README "open-document tabs row"): 48 tall, `bg2`, tabs radius 9 on top, min 130 / max 230.
/// Tap switches, × closes. Documents stay open across Home until closed; opening from anywhere adds a tab.
struct DocTabsRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var current: ID

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(app.openDocs, id: \.self) { id in
                        if let d = app.store.document(id) { tab(d, on: id == current) }
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.docTabsHeight)
        .background(theme.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .zIndex(54)
    }

    private func tab(_ d: Document, on: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9, style: .continuous)
        return HStack(spacing: 8) {
            Circle().fill(d.type.tint).frame(width: 8, height: 8)
            Text(d.name).font(fnt(13, .semibold)).foregroundStyle(on ? theme.ink1 : theme.ink3).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button { app.closeDocument(d.id) } label: {
                Image(systemName: "xmark").font(fnt(10, .bold)).foregroundStyle(theme.ink4).frame(width: 20, height: 20)
                    .background(Circle().fill(on ? theme.hov : .clear))
            }.buttonStyle(.plain).accessibilityLabel("Close \(d.name)")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(minWidth: 130, maxWidth: 230)
        .frame(height: 40)
        .background(shape.fill(on ? theme.card : .clear))
        .overlay(shape.stroke(on ? theme.line : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if !on { app.openDocument(d.id) } }
        .contextMenu {
            Button("Close", systemImage: "xmark") { app.closeDocument(d.id) }
            if app.openDocs.count > 1 {
                Button("Close others") { for other in app.openDocs where other != d.id { app.closeDocument(other) } }
            }
        }
    }
}
