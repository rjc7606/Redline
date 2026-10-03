import SwiftUI
import PDFKit
import RedlineCore

// MARK: - Bookmarks

struct BookmarksPanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        let doc = editor.doc
        let items: [(id: ID, index: Int, label: String)] = doc.bookmarks.compactMap { id in
            if id.hasPrefix("page:"), let i = Int(id.dropFirst(5)) { return i < editor.pageCount ? (id, i, "Page \(i + 1)") : nil }
            guard let i = doc.pageIndex(of: id) else { return nil }
            let pg = doc.pages[i]
            return (id, i, pg.label.isEmpty ? "Page \(i + 1)" : pg.label)
        }
        let current = editor.isPDF ? doc.bookmarks.contains("page:\(editor.pageIndex)") : doc.bookmarks.contains(editor.page.id)
        ScrollView {
            VStack(spacing: 2) {
                Button { editor.toggleBookmark() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: current ? "bookmark.slash" : "bookmark").font(fnt(14, .semibold))
                        Text(current ? "Remove bookmark" : "Bookmark this page").font(fnt(14, .semibold))
                    }
                    .foregroundStyle(theme.ink1).frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.bg3))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
                ForEach(items, id: \.id) { b in
                    HStack(spacing: 10) {
                        Image(systemName: "bookmark.fill").font(fnt(14)).foregroundStyle(theme.accent)
                        Text(b.label).font(fnt(14, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("p.\(b.index + 1)").font(fnt(11, .semibold)).foregroundStyle(theme.ink4)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(b.index == editor.pageIndex ? theme.hov2 : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(b.index) }
                    .contextMenu {
                        Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) { editor.app.mutate(editor.docID) { $0.bookmarks.removeAll { $0 == b.id } } }
                    }
                }
                if items.isEmpty {
                    Text("No bookmarks yet.").font(fnt(12.5)).foregroundStyle(theme.ink4).padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 12)
        }
    }
}

// MARK: - Outline

struct OutlineItem: Identifiable {
    var id: String
    var label: String
    var pageIndex: Int
    var depth: Int
    /// The PDF outline node behind this row (nil for page-list fallbacks).
    var node: PDFOutline? = nil
    var hasChildren = false
}

extension WorkspaceModel {
    /// The document's own outline (bookmarks tree in the PDF). Falls back to the page list when there is none.
    var outlineItems: [OutlineItem] {
        var out: [OutlineItem] = []
        if let pdf = isPDF ? mk.pdf : (doc.pdfFile.flatMap { app.pdf.document($0) }), let root = pdf.outlineRoot, root.numberOfChildren > 0 {
            func walk(_ node: PDFOutline, depth: Int) {
                for i in 0..<node.numberOfChildren {
                    guard let c = node.child(at: i) else { continue }
                    var pi = 0
                    if let pg = c.destination?.page {
                        let idx = pdf.index(for: pg)
                        pi = isPDF ? idx : (doc.pages.firstIndex { $0.pdfPageIndex == idx } ?? min(idx, doc.pages.count - 1))
                    }
                    out.append(OutlineItem(id: ObjectIdentifier(c).debugDescription, label: c.label ?? "Untitled", pageIndex: max(0, pi), depth: depth, node: c, hasChildren: c.numberOfChildren > 0))
                    if !mk.collapsedOutline.contains(ObjectIdentifier(c).debugDescription), depth < 6 { walk(c, depth: depth + 1) }
                }
            }
            walk(root, depth: 0)
            return out
        }
        if isPDF {
            for i in 0..<mk.pageCount { out.append(OutlineItem(id: "p\(i)", label: "Page \(i + 1)", pageIndex: i, depth: 0)) }
            return out
        }
        for (i, pg) in doc.pages.enumerated() {
            out.append(OutlineItem(id: pg.id, label: pg.label.isEmpty ? "Page \(i + 1)" : pg.label, pageIndex: i, depth: 0))
        }
        return out
    }

    private func mkOutlineRoot() -> PDFOutline? {
        guard let pdf = mk.pdf else { return nil }
        if let r = pdf.outlineRoot { return r }
        let r = PDFOutline()
        pdf.outlineRoot = r
        return r
    }

    private func mkOutlineDestination(_ i: Int) -> PDFDestination? {
        guard let page = mk.page(i) else { return nil }
        return PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).maxY))
    }

    private func mkOutlineChanged() { mkMarkDirty(); mk.renderTick += 1 }

    /// New entry for the current page, after `after` (as a sibling) or at the end of the root.
    func mkOutlineAdd(label: String, after: PDFOutline? = nil, asChildOf parent: PDFOutline? = nil) {
        guard let root = mkOutlineRoot() else { return }
        let o = PDFOutline()
        o.label = label
        o.destination = mkOutlineDestination(pageIndex)
        if let parent { parent.insertChild(o, at: parent.numberOfChildren) }
        else if let after, let p = after.parent { p.insertChild(o, at: after.index + 1) }
        else { root.insertChild(o, at: root.numberOfChildren) }
        mkOutlineChanged()
    }

    func mkOutlineRename(_ o: PDFOutline, to label: String) {
        let t = label.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        o.label = t
        mkOutlineChanged()
    }

    /// Becomes the last child of the previous sibling.
    func mkOutlineIndent(_ o: PDFOutline) {
        guard let p = o.parent, o.index > 0, let prev = p.child(at: o.index - 1) else { return }
        o.removeFromParent()
        prev.insertChild(o, at: prev.numberOfChildren)
        mkOutlineChanged()
    }

    /// Moves up one level, right after its former parent.
    func mkOutlineOutdent(_ o: PDFOutline) {
        guard let p = o.parent, let g = p.parent else { return }
        let at = p.index + 1
        o.removeFromParent()
        g.insertChild(o, at: at)
        mkOutlineChanged()
    }

    func mkOutlineMove(_ o: PDFOutline, by delta: Int) {
        guard let p = o.parent else { return }
        let to = o.index + delta
        guard to >= 0, to < p.numberOfChildren else { return }
        o.removeFromParent()
        p.insertChild(o, at: to)
        mkOutlineChanged()
    }

    func mkOutlineRetarget(_ o: PDFOutline) { o.destination = mkOutlineDestination(pageIndex); mkOutlineChanged() }

    func mkOutlineDelete(_ o: PDFOutline) { o.removeFromParent(); mkOutlineChanged() }

    func mkOutlineToggle(_ o: PDFOutline) {
        let k = ObjectIdentifier(o).debugDescription
        if mk.collapsedOutline.contains(k) { mk.collapsedOutline.remove(k) } else { mk.collapsedOutline.insert(k) }
        mk.renderTick += 1
    }
}

struct OutlinePanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    @State private var renameTarget: PDFOutline? = nil
    @State private var renameOn = false
    @State private var draft = ""
    @State private var addOn = false
    @State private var addParent: PDFOutline? = nil

    var body: some View {
        let _ = editor.mk.renderTick
        let items = editor.outlineItems
        let editable = editor.isPDF
        ScrollView {
            VStack(spacing: 2) {
                if editable {
                    Button { addParent = nil; renameTarget = nil; draft = "Page \(editor.pageIndex + 1)"; addOn = true } label: {
                        HStack(spacing: 6) { Image(systemName: "plus").font(fnt(14, .semibold)); Text("Add to outline").font(fnt(14, .semibold)) }
                            .foregroundStyle(theme.ink1).frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.bg3))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
                ForEach(items) { o in
                    HStack(spacing: 6) {
                        if let node = o.node, o.hasChildren {
                            Button { editor.mkOutlineToggle(node) } label: {
                                Image(systemName: "chevron.right").font(fnt(11, .bold)).foregroundStyle(theme.ink4)
                                    .rotationEffect(.degrees(editor.mk.collapsedOutline.contains(o.id) ? 0 : 90))
                                    .frame(width: 18, height: 18).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 18, height: 18)
                        }
                        Text(o.label).font(fnt(o.depth == 0 ? 14 : 13, o.depth == 0 ? .semibold : .medium))
                            .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink2).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("p.\(o.pageIndex + 1)").font(fnt(11, .semibold)).monospacedDigit().foregroundStyle(theme.ink4)
                    }
                    .padding(.trailing, 10)
                    .padding(.leading, 6 + Double(o.depth) * 16)
                    .frame(height: o.depth == 0 ? 44 : 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(o.pageIndex == editor.pageIndex && o.depth == 0 ? theme.hov2 : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(o.pageIndex) }
                    .contextMenu {
                        if let node = o.node, editable {
                            Button("Rename", systemImage: "pencil") { renameTarget = node; draft = o.label; renameOn = true }
                            Button("Add entry below", systemImage: "plus") { addParent = nil; renameTarget = node; draft = "Page \(editor.pageIndex + 1)"; addOn = true }
                            Button("Add child entry", systemImage: "arrow.turn.down.right") { addParent = node; renameTarget = nil; draft = "Page \(editor.pageIndex + 1)"; addOn = true }
                            Divider()
                            Button("Indent", systemImage: "increase.indent") { editor.mkOutlineIndent(node) }
                            Button("Outdent", systemImage: "decrease.indent") { editor.mkOutlineOutdent(node) }
                            Button("Move up", systemImage: "arrow.up") { editor.mkOutlineMove(node, by: -1) }
                            Button("Move down", systemImage: "arrow.down") { editor.mkOutlineMove(node, by: 1) }
                            Divider()
                            Button("Point at this page", systemImage: "doc.text") { editor.mkOutlineRetarget(node) }
                            Button("Delete", systemImage: "trash", role: .destructive) { editor.mkOutlineDelete(node) }
                        }
                    }
                }
                if items.isEmpty {
                    Text(editable ? "No outline yet. Add an entry for the current page." : "No outline.").font(fnt(12.5)).foregroundStyle(theme.ink4).padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 12)
        }
        .alert("Rename entry", isPresented: $renameOn) {
            TextField("Title", text: $draft)
            Button("Rename") { if let t = renameTarget { editor.mkOutlineRename(t, to: draft) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Outline entry", isPresented: $addOn) {
            TextField("Title", text: $draft)
            Button("Add") { editor.mkOutlineAdd(label: draft.isEmpty ? "Page \(editor.pageIndex + 1)" : draft, after: addParent == nil ? renameTarget : nil, asChildOf: addParent) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Points at page \(editor.pageIndex + 1).")
        }
    }
}

// MARK: - Field inspector (Forms tab)

/// Floating editor for the selected form field, shown while the Forms tab is active.
struct FieldInspector: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel
    var field: FormField

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Field")
                Spacer()
                Button { editor.selectedField = nil } label: {
                    Image(systemName: "xmark").font(fnt(11, .bold)).foregroundStyle(theme.ink3).frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            ScrollView { FieldEditor(editor: editor, field: field) }
                .frame(maxHeight: 420)
            Text("Tap a placed field with Select to edit it; pick a type in the Forms tab, then tap the page to add one.")
                .font(fnt(10.5)).foregroundStyle(theme.ink4).lineSpacing(2)
        }
        .padding(12)
        .frame(width: 262)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
            .popShadow(theme))
    }
}
