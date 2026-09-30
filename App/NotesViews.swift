import SwiftUI
import RedlineCore

// MARK: - Book view (single page or facing spread)

struct BookView: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    @State private var fitted = false

    var body: some View {
        let g = editor.book
        VStack(spacing: 0) {
            // Tag rows for the visible pages
            HStack(alignment: .top, spacing: 18) {
                ForEach(g.visiblePages, id: \.self) { i in TagRow(editor: editor, pageIndex: i) }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            .frame(minHeight: 34)
            GeometryReader { geo in
                ZStack {
                    GrainBackground(color: theme.canvas)
                    HStack(spacing: 0) {
                        ForEach(g.visiblePages, id: \.self) { i in
                            PageView(editor: editor, pageIndex: i)
                                .id(i)
                                .transition(.asymmetric(insertion: .move(edge: editor.flipDx < 0 ? .trailing : .leading).combined(with: .opacity), removal: .opacity))
                        }
                        if g.spread && g.rightSlotEmpty {
                            GhostPage(editor: editor, label: "Tap to add a page")
                        }
                    }
                    .offset(x: editor.flipDx * 0.6)
                    .animation(.easeInOut(duration: 0.35), value: editor.pageIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !g.spread && !g.nextExists && editor.flipDx < -40 {
                        GhostPage(editor: editor, label: editor.flipDx < -editor.canvas.w * editor.zoom * 0.54 ? "Release to add a page" : "Pull to add a page")
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 20)
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { v in editor.flipDx = v.translation.width }
                        .onEnded { v in
                            let dx = v.translation.width
                            editor.flipDx = 0
                            if dx < -60 { editor.nextPage() } else if dx > 60 { editor.prevPage() }
                        },
                    including: (editor.tool == .select || editor.tool == .none) ? .all : .none
                )
                .onAppear { if !fitted { fitted = true; editor.fitZoom(available: geo.size) } }
                .onChange(of: geo.size) { _, s in editor.fitZoom(available: s) }
                .overlay(alignment: .leading) {
                    roundButton("chevron.left", tint: g.canBack ? theme.ink2 : theme.dis) { editor.prevPage() }.padding(.leading, 14)
                }
                .overlay(alignment: .trailing) {
                    roundButton(g.nextExists ? "chevron.right" : "plus", tint: theme.accent) { editor.nextPage() }.padding(.trailing, 14)
                }
                .overlay(alignment: .top) { if !editor.selection.isEmpty { SelectionBar(editor: editor).padding(.top, 14) } }
                .overlay(alignment: .bottom) {
                    let label = g.visiblePages.map { BookGeometry.label(for: $0) }.joined(separator: "–")
                    let count = Formatting.plural(max(0, editor.pageCount - 1), "page")
                    let hint = !g.nextExists ? (g.spread && g.rightSlotEmpty ? "tap the empty side to add a page" : "last page — swipe further to add") : "swipe to flip"
                    Text("\(label) · \(count) · \(hint)")
                        .font(fnt(12, .bold)).foregroundStyle(theme.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.pop).shadow(color: .black.opacity(0.12), radius: 4, y: 2))
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private func roundButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(fnt(18, .semibold)).foregroundStyle(tint).frame(width: 40, height: 40)
                .background(Circle().fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 5, y: 2))
        }.buttonStyle(.plain)
    }
}

struct GhostPage: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var label: String
    var body: some View {
        let z = editor.zoom
        VStack(spacing: 10) {
            Image(systemName: "plus").font(fnt(28, .medium)).frame(width: 56, height: 56).overlay(Circle().stroke(theme.accent, lineWidth: 2))
            Text(label).font(fnt(14, .bold))
        }
        .foregroundStyle(theme.accent)
        .frame(width: editor.canvas.w * z, height: editor.canvas.h * z)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        .contentShape(Rectangle())
        .onTapGesture { editor.addJournalPage() }
    }
}

/// "Page N · date  [tags…] [+ Tag]" row above a notebook page.
struct TagRow: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    var pageIndex: Int

    var body: some View {
        let pg = editor.doc.pages[pageIndex]
        let date = Formatting.date(editor.dateMode == .modified ? pg.modified : pg.created)
        HStack(spacing: 6) {
            SectionLabel(text: "\(BookGeometry.longLabel(for: pageIndex)) · \(date)").padding(.trailing, 4)
            ForEach(pg.tags, id: \.self) { t in
                HStack(spacing: 4) {
                    Text(t).font(fnt(11.5, .bold))
                    Button { editor.removeTag(t, page: pageIndex) } label: { Text("×").font(fnt(12, .bold)).opacity(0.6) }.buttonStyle(.plain)
                }
                .foregroundStyle(theme.accent).padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(theme.accent.opacity(0.12)))
            }
            Button { editor.tagPopoverPage = editor.tagPopoverPage == pageIndex ? nil : pageIndex; editor.tagDraft = "" } label: {
                HStack(spacing: 4) { Image(systemName: "tag").font(fnt(11)); Text("Tag").font(fnt(12, .semibold)) }
                    .foregroundStyle(theme.ink3).padding(.horizontal, 10).frame(height: 26)
                    .overlay(Capsule().stroke(theme.line2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { editor.tagPopoverPage == pageIndex }, set: { if !$0 { editor.tagPopoverPage = nil } }), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldText(placeholder: "New tag, ↵ to add", text: $editor.tagDraft, height: 30, font: fnt(12.5))
                        .onSubmit { editor.addTag(editor.tagDraft, page: pageIndex) }
                    let suggestions = editor.doc.tagCounts().map(\.name).filter { !pg.tags.contains($0) && (editor.tagDraft.isEmpty || $0.contains(editor.tagDraft.lowercased())) }.prefix(8)
                    FlowLayout(spacing: 4) {
                        ForEach(Array(suggestions), id: \.self) { t in
                            Text(t).font(fnt(11, .bold)).foregroundStyle(theme.ink1).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(theme.hov))
                                .onTapGesture { editor.addTag(t, page: pageIndex) }
                        }
                    }
                }
                .padding(8).frame(width: 220)
                .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calendar view

struct CalendarView: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let month = CalendarMonth(document: editor.doc, monthOffset: editor.calOffset, mode: editor.dateMode)
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                BarButton(symbol: "chevron.left", label: "Previous month", size: 32) { editor.calOffset -= 1 }
                Text(month.title).font(titleFnt(20)).foregroundStyle(theme.ink1).frame(minWidth: 180, alignment: .leading)
                BarButton(symbol: "chevron.right", label: "Next month", size: 32) { editor.calOffset += 1 }
                Spacer()
                SegmentControl(options: DateMode.allCases.map { SegmentOption(value: $0, label: $0.rawValue) },
                               selection: Binding(get: { editor.dateMode }, set: { editor.dateMode = $0 }), fontSize: 12.5, vPad: 6, hPad: 14)
            }
            HStack(spacing: 6) {
                ForEach(CalendarMonth.weekdayLabels, id: \.self) { d in SectionLabel(text: d).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(month.cells) { cell in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(cell.day.map(String.init) ?? "").font(fnt(13, .semibold)).foregroundStyle(cell.isToday ? theme.accent : theme.ink2)
                        FlowLayout(spacing: 4) {
                            ForEach(cell.pages, id: \.self) { i in
                                let pg = editor.doc.pages[i]
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: pg.paper.hex))
                                    Text("\(i)").font(fnt(8, .bold)).foregroundStyle(Color.black.opacity(0.5)).padding(.bottom, 2)
                                }
                                .frame(width: 28, height: 36)
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                                .onTapGesture { editor.setPage(i); editor.journalView = .book }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 150, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(cell.isToday ? theme.accent : theme.line, lineWidth: cell.isToday ? 2 : 1))
                    .opacity(cell.day == nil ? 0.35 : 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvas)
    }
}
