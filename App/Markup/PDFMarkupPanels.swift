import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import RedlineCore

// MARK: - Comments sidebar (handoff v2 §8): rows, not cards

struct PDFCommentsPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let _ = editor.mk.renderTick
        let items = editor.mkComments()
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(AuthorFilter.allCases, id: \.self) { f in
                    let on = editor.authorFilter == f
                    Text(f.rawValue).font(fnt(12, .semibold)).foregroundStyle(on ? theme.bg : theme.ink2)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(on ? theme.ink1 : theme.hov))
                        .onTapGesture { editor.authorFilter = f }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { c in PDFCommentRow(editor: editor, item: c) }
                    if items.isEmpty {
                        Text("No annotations yet. Every mark you make is a PDF annotation with your name and time.")
                            .font(fnt(12.5)).foregroundStyle(theme.ink4).multilineTextAlignment(.center).lineSpacing(3)
                            .padding(.vertical, 22).padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }
}

/// One annotation: collapsed (2-line text) or expanded (full text, Edit / Delete, replies, reply field).
struct PDFCommentRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    var editor: WorkspaceModel
    var item: MarkupComment
    @FocusState private var editFocused: Bool

    var body: some View {
        let mk = editor.mk
        let selected = mk.selected.contains { $0 === item.annotation }
        let expanded = mk.expandedComment == item.id
        let a = item.annotation
        let who = item.author == app.author ? "You" : item.author
        VStack(alignment: .leading, spacing: 4) {
            // One meta line: colour · kind glyph · "You · 12h ago" · replies · page. Status lives in the context menu.
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: item.colorHex)).frame(width: 10, height: 10)
                Image(systemName: commentSymbol(for: item.tool.rawValue)).font(fnt(14)).foregroundStyle(theme.ink3).help(item.tool.label)
                Text("\(who) · \(Formatting.ago(item.time))").font(fnt(13, .medium)).foregroundStyle(theme.ink2).lineLimit(1)
                Spacer(minLength: 2)
                if !item.replies.isEmpty { Text(Formatting.plural(item.replies.count, "reply", "replies")).font(fnt(11.5, .semibold)).monospacedDigit().foregroundStyle(theme.accent) }
                if item.status != .open { Circle().fill(theme.chip(for: item.status).fg).frame(width: 6, height: 6).help(item.status.rawValue) }
                Text("p.\(item.pageIndex + 1)").font(fnt(11, .semibold)).monospacedDigit().foregroundStyle(theme.ink4)
            }
            if expanded {
                if mk.editingComment {
                    TextField("Add a comment…", text: Binding(get: { a.contents ?? "" }, set: { editor.mkSetText(a, $0) }), axis: .vertical)
                        .lineLimit(2...8).font(fnt(13)).foregroundStyle(theme.ink1)
                        .focused($editFocused)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.field))
                        .padding(.top, 4)
                        .onSubmit { mk.editingComment = false }
                        .onChange(of: editFocused) { _, f in if !f { mk.editingComment = false } }
                        .onAppear { editFocused = true }
                } else if !item.text.isEmpty {
                    Text(item.text).font(fnt(13)).foregroundStyle(theme.ink1).lineSpacing(2).padding(.top, 2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    if !item.tool.isTextual {
                        Button(item.text.isEmpty ? "Add text" : "Edit") { mk.editingComment = true }
                            .font(fnt(12, .semibold)).foregroundStyle(theme.accent).buttonStyle(.plain)
                    }
                    Button("Delete") { editor.mkSelectComment(item); editor.mkDeleteSelection() }
                        .font(fnt(12, .semibold)).foregroundStyle(theme.danger).buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
                ForEach(Array(item.replies.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(r.author == app.author ? "You" : r.author).font(fnt(12, .semibold)).foregroundStyle(theme.ink2)
                            Text(Formatting.ago(r.time)).font(fnt(11)).foregroundStyle(theme.ink4)
                        }
                        Text(r.text).font(fnt(12.5, .medium)).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 28).padding(.top, 4)
                }
                HStack(spacing: 6) {
                    TextField("Reply…", text: Binding(get: { mk.replyDraft }, set: { mk.replyDraft = $0 }))
                        .font(fnt(12.5)).foregroundStyle(theme.ink1).padding(.horizontal, 10).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.field))
                        .onSubmit { editor.mkAddReply(a) }
                    Button("Reply") { editor.mkAddReply(a) }
                        .font(fnt(12.5, .semibold)).foregroundStyle(theme.accent).buttonStyle(.plain)
                }
                .padding(.top, 6)
            } else if !item.text.isEmpty {
                Text(item.text).font(fnt(13)).foregroundStyle(theme.ink2).lineLimit(2).lineSpacing(2).padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? theme.card : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.accent, lineWidth: selected ? 2 : 0))
        .overlay(alignment: .bottom) { if !selected { Rectangle().fill(theme.line).frame(height: 1) } }
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded { mk.expandedComment = nil; mk.editingComment = false }
            else { mk.expandedComment = item.id; mk.editingComment = false; editor.mkSelectComment(item) }
        }
        .contextMenu {
            Section("Status · \(item.status.rawValue)") {
                ForEach(CommentStatus.allCases, id: \.self) { s in
                    Button { editor.mkSetStatus(a, s) } label: { if s == item.status { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) } }
                }
            }
            if editor.mkSelectedFill != nil, selected {
                Button("Remove fill", systemImage: "drop.slash") { editor.mkRemoveFill() }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { editor.mkSelectComment(item); editor.mkDeleteSelection() }
        }
        .animation(.easeOut(duration: 0.15), value: expanded)
    }
}

// MARK: - Popup beside the selected annotation (handoff v2 §6)

struct PDFAnnotationPopup: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Bindable var editor: WorkspaceModel
    @FocusState private var commentFocused: Bool
    @FocusState private var replyFocused: Bool
    private let width: CGFloat = 300

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        let _ = mk.renderTick
        if let a = mk.selectedPrimary, let page = a.page, let v = mk.pdfView, let b = editor.mkSelectionBounds,
           let item = editor.mkComments().first(where: { $0.annotation === a }) ?? Optional(editor.mkItem(a, page: page)) {
            let r = v.convert(b, from: page)
            let fw = v.bounds.width
            // Visible height: the keyboard may cover the bottom of the view.
            let fh = max(200, v.bounds.height - mk.keyboardOverlap)
            let est: CGFloat = min(560, 190 + CGFloat(item.replies.count) * 44 + (mk.replyFieldOpen ? 48 : 0))
            let x = min(max(8, r.midX - width / 2), max(8, fw - width - 8))
            let below = r.maxY + 14 + est <= fh || r.minY - est - 14 < 8
            // Never off the bottom (or under the keyboard): slide up over the annotation if it must.
            let y = max(8, min(below ? r.maxY + 14 : r.minY - est - 14, fh - est - 8))
            let who = item.author == app.author ? "You" : item.author
            VStack(alignment: .leading, spacing: 0) {
                // 1. Header (pinned): colour · glyph · kind · status · ×
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: item.colorHex)).frame(width: 12, height: 12)
                    Image(systemName: commentSymbol(for: item.tool.rawValue)).font(fnt(14)).foregroundStyle(theme.ink3)
                    Text(item.tool.label + (item.markCount > 1 && item.tool.isPen ? " · \(item.markCount) strokes" : "")).font(fnt(15, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                    Spacer(minLength: 4)
                    Menu {
                        Section("Status · \(item.status.rawValue)") {
                            ForEach(CommentStatus.allCases, id: \.self) { s in
                                Button { editor.mkSetStatus(a, s) } label: { if s == item.status { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) } }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(fnt(14, .semibold)).foregroundStyle(theme.ink3).frame(width: 28, height: 28).background(Circle().fill(theme.hov))
                    }
                    Button { editor.mkClosePopup() } label: {
                        Image(systemName: "xmark").font(fnt(12, .bold)).foregroundStyle(theme.ink3).frame(width: 28, height: 28).background(Circle().fill(theme.hov))
                    }.buttonStyle(.plain)
                }
                .frame(height: 24)
                .padding(.bottom, 12)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 2. Author line
                        HStack(spacing: 6) {
                            AvatarView(name: item.author, size: 20)
                            Text(who).font(fnt(12.5, .semibold)).foregroundStyle(theme.ink2).lineLimit(1)
                            Text(Formatting.ago(item.time)).font(fnt(12.5, .medium)).foregroundStyle(theme.ink4)
                            Spacer()
                        }
                        // 3. Comment field (text boxes edit their text inline on the page; the field holds the note)
                        TextField(item.tool.isTextual ? "Text on the page…" : "Add a comment…", text: Binding(get: { a.contents ?? "" }, set: { editor.mkSetText(a, $0) }), axis: .vertical)
                            .lineLimit(1...6).font(fnt(14, .medium)).foregroundStyle(theme.ink1)
                            .focused($commentFocused)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.field))
                        // 4. Replies
                        if !item.replies.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(item.replies.enumerated()), id: \.offset) { _, rp in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(rp.author == app.author ? "You" : rp.author).font(fnt(12, .semibold)).foregroundStyle(theme.ink2)
                                            Text(Formatting.ago(rp.time)).font(fnt(11)).foregroundStyle(theme.ink4)
                                        }
                                        Text(rp.text).font(fnt(12.5, .medium)).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.leading, 28)
                                }
                            }
                        }
                        // 5. Reply field, only after tapping Reply
                        if mk.replyFieldOpen {
                            TextField("Reply…", text: Binding(get: { mk.replyDraft }, set: { mk.replyDraft = $0 }))
                                .font(fnt(13)).foregroundStyle(theme.ink1).padding(.horizontal, 12).frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.field))
                                .focused($replyFocused)
                                .onSubmit { editor.mkAddReply(a); mk.replyFieldOpen = false }
                                .onAppear { replyFocused = true }
                        }
                        // 6. Footer: Reply · trash (styling lives in the selection bar's Properties)
                        HStack(spacing: 12) {
                            Spacer()
                            Button(mk.replyFieldOpen ? "Send" : "Reply") {
                                if mk.replyFieldOpen { editor.mkAddReply(a); mk.replyFieldOpen = false } else { mk.replyFieldOpen = true }
                            }
                            .font(fnt(12.5, .semibold)).foregroundStyle(theme.accent).buttonStyle(.plain)
                            Button { editor.mkDeleteSelection() } label: {
                                Image(systemName: "trash").font(fnt(15, .medium)).foregroundStyle(theme.danger).frame(width: 32, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.bg3))
                            }.buttonStyle(.plain).accessibilityLabel("Delete")
                        }
                        .frame(height: 32)
                    }
                }
                .frame(maxHeight: 560 - 28 - 36)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
                .popShadow(theme))
            .offset(x: x, y: y)
            .popIn()
            .onAppear { if mk.focusComment { commentFocused = true; mk.focusComment = false } }
        }
    }
}

extension Tool {
    /// Tools whose `contents` is the text drawn on the page (edited inline, not as a comment).
    var isTextual: Bool { [Tool.textbox, .callout, .stamps, .datestamp, .initials].contains(self) }
}

extension WorkspaceModel {
    /// Sidebar-style item for an annotation not currently in the filtered list.
    func mkItem(_ a: PDFAnnotation, page: PDFPage) -> MarkupComment {
        MarkupComment(id: a.stableID, annotation: a, pageIndex: mk.index(of: page), tool: a.redlineTool,
                      author: (a.userName ?? "").isEmpty ? "Unknown" : a.userName!, time: a.modificationDate ?? Date(),
                      text: a.contents ?? "", replies: [], status: .open, colorHex: PDFColors.hex(a.color), markCount: 1)
    }

    func mkClosePopup() {
        mk.annotationPopup = false
        mk.annotationProps = false
        mk.replyFieldOpen = false
    }
}

// MARK: - Inline FreeText editor

struct PDFTextEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    var edit: PDFTextEdit
    @FocusState private var focused: Bool

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        if let v = mk.pdfView {
            let a = edit.annotation
            let _ = mk.textDraft
            let r = v.convert(a.bounds, from: edit.page)
            let z = v.scaleFactor
            let font = a.font ?? RedlineFonts.page(size: 16, weight: nil)
            let fs = font.pointSize * z
            let padW = TextBoxLook.padding.width * z, padH = TextBoxLook.padding.height * z
            // The editor is exactly the box: it starts empty-sized and the box grows with the text (mkLiveTextChanged).
            TextField("", text: Binding(get: { mk.textDraft }, set: { mk.textDraft = $0 }), axis: .vertical)
                .font(Font(font.withSize(fs) as CTFont))
                .foregroundStyle(Color(uiColor: a.fontColor ?? .black))
                .textFieldStyle(.plain).lineLimit(1...40)
                .focused($focused)
                .padding(.horizontal, padW).padding(.vertical, padH)
                .frame(width: max(24, r.width), alignment: .topLeading)
                .frame(minHeight: max(10, r.height), alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: a.cornerRadius * z).fill(Color(uiColor: a.color)))
                .overlay(RoundedRectangle(cornerRadius: a.cornerRadius * z).stroke(Color(hex: a.borderColorHex ?? "#000000"), lineWidth: (a.border?.lineWidth ?? 1) * z))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(-3))
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: r.minX, y: r.minY)
                .onChange(of: mk.textDraft) { _, _ in editor.mkLiveTextChanged() }
                .onAppear { focused = true }
        }
    }
}

// MARK: - In-place form filling (outside the Forms tab)

/// Text, date and signature fields get a field over the widget; dropdowns and lists get their choices under it.
struct PDFFieldEditor: View {
    @Environment(\.theme) private var theme
    @Bindable var editor: WorkspaceModel
    var widget: PDFAnnotation
    @FocusState private var focused: Bool

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        let _ = mk.renderTick
        if let v = mk.pdfView, let page = widget.page {
            let r = v.convert(widget.bounds, from: page)
            if widget.widgetFieldType == .choice {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(widget.choices ?? [], id: \.self) { c in
                        Button { editor.mkSetWidgetValue(widget, c); mk.fieldEdit = nil } label: {
                            HStack {
                                Text(c).font(fnt(14)).foregroundStyle(theme.ink1)
                                Spacer()
                                if (widget.widgetStringValue ?? "") == c { Image(systemName: "checkmark").font(fnt(12, .bold)).foregroundStyle(theme.accent) }
                            }
                            .padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if (widget.choices ?? []).isEmpty { Text("No options").font(fnt(13)).foregroundStyle(theme.ink4).padding(12) }
                }
                .frame(width: max(180, r.width))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.popSolid)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .popShadow(theme))
                .offset(x: max(8, min(r.minX, v.bounds.width - max(180, r.width) - 8)), y: r.maxY + 4)
                .popIn()
            } else {
                let area = widget.redlineTool == .farea
                TextField(widget.fieldName?.replacingOccurrences(of: "_", with: " ") ?? "", text: Binding(get: { widget.widgetStringValue ?? "" }, set: { editor.mkSetWidgetValue(widget, $0) }), axis: area ? .vertical : .horizontal)
                    .font(fnt(max(11, min(14, r.height * (area ? 0.22 : 0.5)))))
                    .foregroundStyle(theme.ink1)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 6).padding(.vertical, area ? 4 : 0)
                    .frame(width: max(60, r.width), height: max(24, r.height), alignment: area ? .topLeading : .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.accent, lineWidth: 1.5))
                    .offset(x: r.minX, y: r.minY)
                    .onSubmit { mk.fieldEdit = nil }
                    .onAppear { focused = true }
            }
        }
    }
}

// MARK: - Organize pages (PDF) — 160 pt thumbnails, action pill below the selected page

struct PDFOrganizePages: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var selected: Int? = nil
    @State private var dragging: Int? = nil        // index (in the real order) of the tile being dragged
    @State private var target: Int? = nil          // where it would land
    @State private var dragPoint: CGPoint = .zero  // finger, in grid space
    @State private var tileFrames = TileFrameStore()
    /// Slot rectangles captured when a drag starts (reading order). The tiles slide during the drag, so the live
    /// frames can't be used for the target — that is what made the preview jump and snap back.
    @State private var slots: [CGRect] = []

    var body: some View {
        let tick = editor.mk.renderTick
        let count = editor.mk.pageCount
        let pages: [PDFPage] = (0..<count).compactMap { editor.mk.page($0) }
        let sel = min(selected ?? editor.pageIndex, max(0, count - 1))
        // While dragging, show the order the drop would produce; the tiles slide into place.
        let order: [Int] = {
            var o = Array(0..<count)
            if let d = dragging, let t = target, d != t, o.indices.contains(d) {
                o.remove(at: d); o.insert(d, at: min(t, o.count))
            }
            return o
        }()
        VStack(spacing: 0) {
            HStack {
                Text("Organize Pages").font(titleFnt(21)).foregroundStyle(theme.ink1)
                Spacer()
                PrimaryButton(label: "Done", height: 32) { editor.organizeOpen = false }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(order, id: \.self) { i in
                        if pages.indices.contains(i) {
                            tile(i, page: pages[i], sel: sel, tick: tick, isDragging: dragging == i)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: TileFrameKey.self, value: [i: g.frame(in: .named("organize"))])
                                })
                        }
                    }
                    Button { editor.mkInsertBlankPage(after: count - 1) } label: {
                        BlankPageTile(aspect: 0.77)
                    }.buttonStyle(.plain)
                }
                .animation(.easeInOut(duration: 0.18), value: order)
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
            .coordinateSpace(name: "organize")
            .scrollDisabled(dragging != nil)
            .onPreferenceChange(TileFrameKey.self) { [tileFrames] frames in tileFrames.map = frames }
            .overlay(alignment: .topLeading) {
                // The lifted tile follows the finger.
                if let d = dragging, pages.indices.contains(d) {
                    PDFPageThumb(page: pages[d], tick: tick).frame(width: 160)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        .offset(x: dragPoint.x - 80, y: dragPoint.y - 40)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(theme.bg2)
    }

    private func tile(_ i: Int, page: PDFPage, sel: Int, tick: Int, isDragging: Bool) -> some View {
        let bookmarked = editor.doc.bookmarks.contains("page:\(i)")
        return VStack(spacing: 8) {
            PDFPageThumb(page: page, tick: tick).frame(width: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == sel ? theme.accent : .clear, lineWidth: 2).padding(-3))
                .overlay(alignment: .topTrailing) {
                    if bookmarked {
                        Image(systemName: "bookmark.fill").font(fnt(13, .semibold)).foregroundStyle(theme.accent)
                            .padding(6).background(Circle().fill(theme.card)).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .padding(6)
                    }
                }
                .opacity(isDragging ? 0.25 : 1)
                .contentShape(Rectangle())
                .onTapGesture { if sel == i { editor.setPage(i); editor.organizeOpen = false } else { selected = i } }
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 4, coordinateSpace: .named("organize")))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            if dragging == nil {
                                // Freeze the slot layout for the whole drag.
                                slots = tileFrames.map.sorted { $0.key < $1.key }.map(\.value)
                                dragging = i
                                selected = i
                            }
                            dragPoint = drag.location
                            // Target = the slot nearest the finger (slots never move; the tiles do).
                            if let t = slots.indices.min(by: { dist(slots[$0], drag.location) < dist(slots[$1], drag.location) }) { target = t }
                        }
                        .onEnded { value in
                            if case .second(true, let drag?) = value, let d = dragging {
                                let t = slots.indices.min(by: { dist(slots[$0], drag.location) < dist(slots[$1], drag.location) }) ?? target ?? d
                                if d != t { editor.mkMovePage(from: d, to: t); selected = t }
                            }
                            dragging = nil; target = nil; slots = []
                        }
                )
            Text("Page \(i + 1)").font(fnt(12, .semibold)).foregroundStyle(theme.ink3)
            if i == sel && dragging == nil {
                OrganizeActionPill(rotate: { editor.mkRotatePage(i) }, duplicate: { editor.mkDuplicatePage(i) }, delete: { editor.mkDeletePage(i); selected = nil })
            }
        }
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat { hypot(r.midX - p.x, r.midY - p.y) }
}

/// Tile frames reported by the grid (written from the preference callback, read by the drag gesture; main thread).
final class TileFrameStore: @unchecked Sendable {
    var map: [Int: CGRect] = [:]
}

struct TileFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// Rotate · duplicate · delete, 36 tall, radius 10, `pop`.
struct OrganizeActionPill: View {
    @Environment(\.theme) private var theme
    var rotate: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            btn("rotate.right", tint: theme.ink2, action: rotate)
            btn("doc.on.doc", tint: theme.ink2, action: duplicate)
            btn("trash", tint: theme.danger, action: delete)
        }
        .padding(.horizontal, 4).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.line, lineWidth: 1))
            .shadow(color: Shadows.pill.color, radius: Shadows.pill.radius, y: Shadows.pill.y))
    }
    private func btn(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(fnt(14, .medium)).foregroundStyle(tint).frame(width: 36, height: 28) }.buttonStyle(.plain)
    }
}

/// "Blank Page" tile: 160 wide at the page aspect, 1.5 pt dashed `line2`, radius 8, plus 22 accent, label 12/600.
struct BlankPageTile: View {
    @Environment(\.theme) private var theme
    var aspect: CGFloat
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(fnt(22, .medium)).foregroundStyle(theme.accent)
            Text("Blank Page").font(fnt(12, .semibold)).foregroundStyle(theme.accent)
        }
        .frame(width: 160, height: (160 / aspect).rounded())
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(Rectangle())
    }
}

/// Synchronous small page image (annotations included) for modal grids.
struct PDFPageThumb: View {
    var page: PDFPage
    /// Changes whenever the document changes (rotation, annotations), so the image re-renders.
    var tick: Int
    var body: some View {
        let size = PDFService.displaySize(page)
        let img = PDFDraw.image(of: page, width: 320, scale: 2)
        Image(uiImage: img).resizable().aspectRatio(size.width / max(1, size.height), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6)).shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .id(tick)
    }
}

// MARK: - Form field inspector (widgets)

struct PDFFieldInspector: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var widget: PDFAnnotation

    var body: some View {
        let _ = editor.mk.renderTick
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Form field")
                Spacer()
                Button { editor.mkClearSelection() } label: { Image(systemName: "xmark").font(fnt(11, .bold)).foregroundStyle(theme.ink3).frame(width: 24, height: 24) }.buttonStyle(.plain)
            }
            labelled("Name") { FieldText(placeholder: "name", text: Binding(get: { widget.fieldName ?? "" }, set: { widget.fieldName = $0.replacingOccurrences(of: " ", with: "_"); editor.mkMarkDirty() }), height: 30, font: fnt(12.5)) }
            if widget.widgetFieldType == .text {
                labelled("Value") { FieldText(placeholder: "", text: Binding(get: { widget.widgetStringValue ?? "" }, set: { widget.widgetStringValue = $0; editor.mkMarkDirty() }), height: 30, font: fnt(12.5)) }
            }
            if widget.widgetFieldType == .choice {
                labelled("Options (one per line)") {
                    TextField("", text: Binding(get: { (widget.choices ?? []).joined(separator: "\n") }, set: { widget.choices = $0.split(separator: "\n").map(String.init); editor.mkMarkDirty() }), axis: .vertical)
                        .lineLimit(3...6).font(fnt(12.5)).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.field))
                }
            }
            if widget.widgetFieldType == .button {
                Toggle(isOn: Binding(get: { (widget.widgetStringValue ?? "Off") != "Off" }, set: { widget.widgetStringValue = $0 ? "Yes" : "Off"; editor.mkMarkDirty() })) {
                    Text("Checked").font(fnt(12.5, .semibold)).foregroundStyle(theme.ink1)
                }.tint(theme.accent)
            }
            Button { editor.mkDeleteSelection() } label: { Text("Delete field").font(fnt(12, .bold)).foregroundStyle(theme.danger) }.buttonStyle(.plain)
            Text("Fields are standard PDF form widgets, fillable in any PDF reader.").font(fnt(10.5)).foregroundStyle(theme.ink4).lineSpacing(2)
        }
        .padding(12)
        .frame(width: 262)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
            .popShadow(theme))
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(fnt(10.5, .bold)).foregroundStyle(theme.ink4); c() }
    }
}

// MARK: - Export helpers

@MainActor
enum PDFExport {
    static func write(_ data: Data, name: String, directory: URL? = nil) -> URL? {
        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("RedlineExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent(name)
        if directory != nil {
            var n = 2
            let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("\(stem) \(n).\(ext)"); n += 1 }
        }
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Share / save actions for a PDF markup. Returns a URL to share, or nil after an in-place "Save to Files".
    static func run(_ kind: ExportKind, editor: WorkspaceModel) -> URL? {
        let base = editor.doc.name.replacingOccurrences(of: ".pdf", with: "")
        switch kind {
        case .pdf, .commentReport, .taggedPDF:
            return editor.mkAnnotatedURL()
        case .png:
            guard let page = editor.mk.page(editor.pageIndex) else { return nil }
            let img = PDFDraw.image(of: page, width: 2000)
            return img.pngData().flatMap { write($0, name: "\(base) — page \(editor.pageIndex + 1).png") }
        case .saveToFiles:
            guard let data = editor.mkFlattenedData() else { return nil }
            return write(data, name: "\(base) — flattened.pdf", directory: AppModel.exportsDirectory)
        }
    }

    static func flattened(editor: WorkspaceModel) -> URL? {
        guard let data = editor.mkFlattenedData() else { return nil }
        return write(data, name: editor.doc.name.replacingOccurrences(of: ".pdf", with: "") + " — flattened.pdf")
    }
}
