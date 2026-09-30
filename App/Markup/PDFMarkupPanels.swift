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
            let est: CGFloat = min(560, 190 + CGFloat(item.replies.count) * 44 + (mk.replyFieldOpen ? 48 : 0) + (mk.annotationProps ? 360 : 0))
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
                        // 6. Footer: Properties ⌄ · Reply · trash
                        HStack(spacing: 12) {
                            if !a.isWidget {
                                SecondaryButton(label: "Properties", symbol: "slider.horizontal.3", height: 32, chevron: true, open: mk.annotationProps) {
                                    withAnimation(.easeOut(duration: 0.15)) { mk.annotationProps.toggle() }
                                }
                            }
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
                        // 7. Properties: the Style editor, embedded
                        if mk.annotationProps, let preset = editor.mkSelectedPreset(), let tool = editor.mkSelectedTool {
                            Rectangle().fill(theme.line).frame(height: 1).padding(.top, 2)
                            if let f = editor.mkSelectedFill {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: f.annotation.interiorColor ?? .clear).opacity(f.isPolygon ? f.annotation.opacityValue : 1)).frame(width: 18, height: 18)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1))
                                    Text("Fill").font(fnt(13, .medium)).foregroundStyle(theme.ink2)
                                    Spacer()
                                    SecondaryButton(label: "Remove fill", symbol: "drop.slash", height: 30) { editor.mkRemoveFill() }
                                }
                            }
                            StylePopoverView(editor: editor, stroke: preset, apply: { body in editor.mkUpdateSelectedStyle(body) }, forTool: tool, showPresets: false, embedded: true)
                                .frame(width: width - 28)
                                .padding(.top, 2)
                        }
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

// MARK: - Organize pages (PDF) — 160 pt thumbnails, action pill below the selected page

struct PDFOrganizePages: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var selected: Int? = nil

    var body: some View {
        let _ = editor.mk.renderTick
        let count = editor.mk.pageCount
        let sel = selected ?? editor.pageIndex
        VStack(spacing: 0) {
            HStack {
                Text("Organize Pages").font(titleFnt(21)).foregroundStyle(theme.ink1)
                Spacer()
                PrimaryButton(label: "Done", height: 32) { editor.organizeOpen = false }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
            Text("Tap a page to select it, tap again to open · drag to reorder").font(fnt(12)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 160), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(0..<count, id: \.self) { i in
                        VStack(spacing: 8) {
                            PDFPageThumb(editor: editor, index: i).frame(width: 160)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == sel ? theme.accent : .clear, lineWidth: 2).padding(-3))
                                .contentShape(Rectangle())
                                .onTapGesture { if sel == i { editor.setPage(i); editor.organizeOpen = false } else { selected = i } }
                                .draggable(String(i))
                                .dropDestination(for: String.self) { items, _ in
                                    guard let s = items.first, let from = Int(s) else { return false }
                                    editor.mkMovePage(from: from, to: i)
                                    return true
                                }
                            Text("Page \(i + 1)").font(fnt(12, .semibold)).foregroundStyle(theme.ink3)
                            if i == sel {
                                OrganizeActionPill(rotate: { editor.mkRotatePage(i) }, duplicate: { editor.mkDuplicatePage(i) }, delete: { editor.mkDeletePage(i); selected = nil })
                            }
                        }
                    }
                    Button { editor.mkInsertBlankPage(after: count - 1) } label: {
                        BlankPageTile(aspect: 0.77)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .background(theme.bg2)
    }
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
    var editor: WorkspaceModel
    var index: Int
    var body: some View {
        if let page = editor.mk.page(index) {
            let size = PDFService.displaySize(page)
            let img = page.thumbnail(of: CGSize(width: 320, height: 320 * size.height / max(1, size.width)), for: .mediaBox)
            Image(uiImage: img).resizable().aspectRatio(size.width / max(1, size.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6)).shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
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
            let s = PDFService.displaySize(page)
            let img = page.thumbnail(of: CGSize(width: 2000, height: 2000 * s.height / max(1, s.width)), for: .mediaBox)
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
