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
                HStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if editor.sidebarOpen && !compact { SidebarView(editor: editor) }
                }
                .overlay(alignment: .trailing) {
                    if editor.sidebarOpen && compact {
                        ZStack(alignment: .trailing) {
                            Color.black.opacity(0.28).onTapGesture { editor.sidebarOpen = false }
                            SidebarView(editor: editor).shadow(color: .black.opacity(0.2), radius: 20)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay { if editor.organizeOpen { OrganizePagesView(editor: editor).transition(.opacity) } }
            }
            .overlay(alignment: .top) { popovers.padding(.top, Metrics.barHeight * 2 + 6) }
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
        .alert("Text", isPresented: $editor.textAlertVisible) {
            TextField("Text", text: $editor.textDraft)
            Button("Add") { editor.commitText() }
            Button("Cancel", role: .cancel) { editor.textPrompt = nil }
        }
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
        case .markup, .drawing:
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
