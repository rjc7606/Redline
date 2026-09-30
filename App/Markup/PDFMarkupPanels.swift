import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import RedlineCore

// MARK: - Annotations sidebar (from the PDF)

struct PDFCommentsPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let _ = editor.mk.renderTick
        let items = editor.mkComments()
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(AuthorFilter.allCases, id: \.self) { f in
                    let on = editor.authorFilter == f
                    Text(f.rawValue).font(fnt(11, .bold)).foregroundStyle(on ? theme.bg : theme.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(on ? theme.ink1 : theme.hov))
                        .onTapGesture { editor.authorFilter = f }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(items) { c in PDFCommentCard(editor: editor, item: c) }
                    if items.isEmpty {
                        Text("No annotations yet. Every mark you make is a PDF annotation with your name and time.")
                            .font(fnt(12)).foregroundStyle(theme.ink4).multilineTextAlignment(.center).lineSpacing(3)
                            .padding(.vertical, 22).padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
    }
}

struct PDFCommentCard: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var item: MarkupComment

    var body: some View {
        let selected = editor.mk.selected.contains { $0 === item.annotation }
        let chip = item.status.chip
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: item.colorHex)).frame(width: 10, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12), lineWidth: 1))
                Image(systemName: commentSymbol(for: item.tool.rawValue)).font(fnt(12)).foregroundStyle(theme.ink3)
                Text(item.tool.label + (item.tool.isPen && item.markCount > 1 ? " · \(item.markCount) strokes" : "")).font(fnt(12.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                Spacer(minLength: 2)
                Text("p.\(item.pageIndex + 1)").font(fnt(10.5)).foregroundStyle(theme.ink4)
            }
            HStack(spacing: 6) {
                AvatarView(name: item.author, size: 20)
                Text(item.author).font(fnt(11.5, .semibold)).foregroundStyle(theme.ink2).lineLimit(1)
                Text(Formatting.ago(item.time)).font(fnt(10.5)).foregroundStyle(theme.ink4)
                Spacer(minLength: 2)
                Text(item.status.rawValue).font(fnt(10.5, .bold)).foregroundStyle(Color(hex: chip.fg))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: chip.fg, alpha: chip.alpha)))
            }
            if !item.text.isEmpty { Text(item.text).font(fnt(12)).foregroundStyle(theme.ink2).lineLimit(2).lineSpacing(2) }
            if !item.replies.isEmpty { Text(Formatting.plural(item.replies.count, "reply", "replies")).font(fnt(11, .semibold)).foregroundStyle(theme.accent) }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? theme.accent : theme.line, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { editor.mkSelectComment(item) }
    }
}

// MARK: - Popup beside the selected annotation

struct PDFAnnotationPopup: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Bindable var editor: WorkspaceModel
    @FocusState private var commentFocused: Bool
    private let width: CGFloat = 300

    var body: some View {
        let mk = editor.mk
        let _ = mk.viewportTick
        let _ = mk.renderTick
        if let a = mk.selectedPrimary, let page = a.page, let v = mk.pdfView, let b = editor.mkSelectionBounds,
           let item = editor.mkComments().first(where: { $0.annotation === a }) ?? Optional(editor.mkItem(a, page: page)) {
            let r = v.convert(b, from: page)
            let fw = v.bounds.width, fh = v.bounds.height
            let estHeight: CGFloat = mk.annotationProps ? 520 : 260
            let x = min(max(8, r.midX - width / 2), max(8, fw - width - 8))
            let below = r.maxY + 14 + estHeight <= fh || r.minY - estHeight - 14 < 0
            let y = below ? r.maxY + 14 : max(8, r.minY - estHeight - 14)
            let textual = [Tool.textbox, .callout, .stamps, .datestamp, .initials].contains(item.tool)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: item.colorHex)).frame(width: 12, height: 12)
                    Image(systemName: commentSymbol(for: item.tool.rawValue)).font(fnt(13)).foregroundStyle(theme.ink3)
                    Text(item.tool.label + (item.markCount > 1 && item.tool.isPen ? " · \(item.markCount) strokes" : "")).font(fnt(13, .bold)).foregroundStyle(theme.ink1).lineLimit(1)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(CommentStatus.allCases, id: \.self) { s in Button(s.rawValue) { editor.mkSetStatus(a, s) } }
                    } label: {
                        let chip = item.status.chip
                        Text(item.status.rawValue).font(fnt(10.5, .bold)).foregroundStyle(Color(hex: chip.fg))
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Color(hex: chip.fg, alpha: chip.alpha)))
                    }
                    Button { editor.mkClearSelection() } label: {
                        Image(systemName: "xmark").font(fnt(11, .bold)).foregroundStyle(theme.ink3).frame(width: 24, height: 24).background(Circle().fill(theme.hov))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    AvatarView(name: item.author, size: 18)
                    Text(item.author).font(fnt(11.5, .semibold)).foregroundStyle(theme.ink2).lineLimit(1)
                    Text(Formatting.ago(item.time)).font(fnt(10.5)).foregroundStyle(theme.ink4)
                    Spacer()
                }
                if !textual {
                    TextField("Add a comment…", text: Binding(get: { a.contents ?? "" }, set: { editor.mkSetText(a, $0) }), axis: .vertical)
                        .lineLimit(1...5).font(fnt(13)).foregroundStyle(theme.ink1)
                        .focused($commentFocused)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                } else {
                    Button { editor.mkBeginTextEdit(a, page: page, isNew: false) } label: {
                        HStack { Text((a.contents ?? "").isEmpty ? "Edit text…" : (a.contents ?? "")).font(fnt(13)).foregroundStyle(theme.ink1).lineLimit(2); Spacer(); Image(systemName: "pencil").foregroundStyle(theme.ink3) }
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                if !item.replies.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.replies.enumerated()), id: \.offset) { _, r in
                                HStack(alignment: .top, spacing: 7) {
                                    AvatarView(name: r.author, size: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) { Text(r.author).font(fnt(11, .bold)).foregroundStyle(theme.ink1); Text(Formatting.ago(r.time)).font(fnt(10)).foregroundStyle(theme.ink4) }
                                        Text(r.text).font(fnt(12)).foregroundStyle(theme.ink2)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 6).overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 2) }
                    }
                    .frame(maxHeight: 120)
                }
                HStack(spacing: 6) {
                    TextField("Reply…", text: Binding(get: { mk.replyDraft }, set: { mk.replyDraft = $0 }))
                        .font(fnt(12)).foregroundStyle(theme.ink1).padding(.horizontal, 9).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.bg)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
                        .onSubmit { editor.mkAddReply(a) }
                    Button { editor.mkAddReply(a) } label: {
                        Text("Reply").font(fnt(12, .bold)).foregroundStyle(.white).padding(.horizontal, 10).frame(height: 30).background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    if !a.isWidget {
                        Button { mk.annotationProps.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3").font(fnt(13, .semibold)); Text("Properties").font(fnt(12.5, .bold))
                                Image(systemName: "chevron.down").font(fnt(10, .bold)).rotationEffect(.degrees(mk.annotationProps ? 180 : 0))
                            }
                            .foregroundStyle(mk.annotationProps ? .white : theme.ink2).padding(.horizontal, 12).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(mk.annotationProps ? theme.accent : theme.bg3))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { editor.mkDeleteSelection() } label: {
                        HStack(spacing: 6) { Image(systemName: "trash").font(fnt(13, .semibold)); Text("Delete").font(fnt(12.5, .bold)) }
                            .foregroundStyle(theme.danger).padding(.horizontal, 12).frame(height: 32).background(RoundedRectangle(cornerRadius: 8).fill(theme.bg3))
                    }.buttonStyle(.plain)
                }
                if mk.annotationProps, let preset = editor.mkSelectedPreset(), let tool = editor.mkSelectedTool {
                    Rectangle().fill(theme.line).frame(height: 1)
                    ScrollView(showsIndicators: false) {
                        StylePopoverView(editor: editor, stroke: preset, apply: { body in editor.mkUpdateSelectedStyle(body) }, forTool: tool, showPresets: false)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .padding(12)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.popSolid)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.line, lineWidth: 1))
                .shadow(color: Shadows.popover.color, radius: Shadows.popover.radius, y: Shadows.popover.y))
            .offset(x: x, y: y)
            .popIn()
            .onAppear { if mk.focusComment { commentFocused = true; mk.focusComment = false } }
        }
    }
}

extension WorkspaceModel {
    /// Sidebar-style item for an annotation not currently in the filtered list.
    func mkItem(_ a: PDFAnnotation, page: PDFPage) -> MarkupComment {
        MarkupComment(id: a.stableID, annotation: a, pageIndex: mk.index(of: page), tool: a.redlineTool,
                      author: (a.userName ?? "").isEmpty ? "Unknown" : a.userName!, time: a.modificationDate ?? Date(),
                      text: a.contents ?? "", replies: [], status: .open, colorHex: PDFColors.hex(a.color), markCount: 1)
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
            let r = v.convert(a.bounds, from: edit.page)
            let z = v.scaleFactor
            let font = a.font ?? UIFont.systemFont(ofSize: 16)
            let fs = font.pointSize * z
            HStack(alignment: .top, spacing: 4) {
                TextField("Text", text: Binding(get: { mk.textDraft }, set: { mk.textDraft = $0 }), axis: .vertical)
                    .font(Font(font.withSize(fs) as CTFont))
                    .foregroundStyle(Color(uiColor: a.fontColor ?? .black))
                    .textFieldStyle(.plain).lineLimit(1...8)
                    .frame(width: max(120, 240 * z))
                    .focused($focused)
                    .onSubmit { editor.mkCommitTextEdit() }
                Button { editor.mkCommitTextEdit() } label: {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(theme.accent))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 6 * z).padding(.vertical, 3 * z)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(uiColor: a.interiorColor ?? .white)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(uiColor: a.color), lineWidth: max(1, (a.border?.lineWidth ?? 1) * z)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).padding(-3))
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: r.minX, y: r.minY)
            .onAppear { focused = true }
        }
    }
}

// MARK: - Organize pages (PDF)

struct PDFOrganizePages: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let _ = editor.mk.renderTick
        let count = editor.mk.pageCount
        VStack(spacing: 0) {
            HStack {
                Text("Organize Pages").font(fnt(21, .heavy)).foregroundStyle(theme.ink1)
                Spacer()
                PrimaryButton(label: "Done", height: 32) { editor.organizeOpen = false }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
            Text("Drag to reorder · tap a page to open it").font(fnt(12)).foregroundStyle(theme.ink4).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 4)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 24)], spacing: 24) {
                    ForEach(0..<count, id: \.self) { i in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                PDFPageThumb(editor: editor, index: i).frame(maxWidth: .infinity)
                                HStack(spacing: 8) {
                                    orgButton("rotate.right", tint: theme.ink2) { editor.mkRotatePage(i) }
                                    orgButton("doc.on.doc", tint: theme.ink2) { editor.mkDuplicatePage(i) }
                                    orgButton("trash", tint: theme.danger) { editor.mkDeletePage(i) }
                                }
                                .padding(5).background(RoundedRectangle(cornerRadius: 7).fill(theme.popSolid).shadow(color: .black.opacity(0.18), radius: 2, y: 1)).padding(6)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == editor.pageIndex ? theme.accent : .clear, lineWidth: 2.5).padding(-2))
                            .contentShape(Rectangle())
                            .onTapGesture { editor.setPage(i); editor.organizeOpen = false }
                            .draggable(String(i))
                            .dropDestination(for: String.self) { items, _ in
                                guard let s = items.first, let from = Int(s) else { return false }
                                editor.mkMovePage(from: from, to: i)
                                return true
                            }
                            Text("Page \(i + 1)").font(fnt(11.5, .bold)).foregroundStyle(theme.ink4)
                        }
                    }
                    Button { editor.mkInsertBlankPage(after: count - 1) } label: {
                        HStack(spacing: 7) { Image(systemName: "plus").font(fnt(13, .bold)); Text("Blank Page").font(fnt(13, .semibold)) }
                            .foregroundStyle(theme.accent).frame(maxWidth: .infinity).aspectRatio(0.77, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .background(theme.bg2)
    }

    private func orgButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(fnt(13, .medium)).foregroundStyle(tint).frame(width: 30, height: 26) }.buttonStyle(.plain)
    }
}

/// Synchronous small page image (annotations included) for modal grids.
struct PDFPageThumb: View {
    var editor: WorkspaceModel
    var index: Int
    var body: some View {
        if let page = editor.mk.page(index) {
            let size = PDFService.displaySize(page)
            let img = page.thumbnail(of: CGSize(width: 420, height: 420 * size.height / max(1, size.width)), for: .mediaBox)
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
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg)).overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line, lineWidth: 1))
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.line, lineWidth: 1))
            .shadow(color: Shadows.popover.color, radius: Shadows.popover.radius, y: Shadows.popover.y))
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
