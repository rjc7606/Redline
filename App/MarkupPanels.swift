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

    /// New entry for the current page: a level-1 entry at the end of the outline, or the last child of `parent`.
    @discardableResult
    func mkOutlineAdd(asChildOf parent: PDFOutline? = nil) -> PDFOutline? {
        guard let root = mkOutlineRoot() else { return nil }
        let o = PDFOutline()
        o.label = "Page \(pageIndex + 1)"
        o.destination = mkOutlineDestination(pageIndex)
        if let parent { parent.insertChild(o, at: parent.numberOfChildren) } else { root.insertChild(o, at: root.numberOfChildren) }
        mkOutlineChanged()
        return o
    }

    /// Reorder from the flat list: the moved entry (with its children) becomes a sibling of the entry it lands on.
    func mkOutlineMove(items: [OutlineItem], from: IndexSet, to: Int) {
        guard let f = from.first, items.indices.contains(f), let node = items[f].node else { return }
        if to >= items.count {
            guard let root = mkOutlineRoot() else { return }
            node.removeFromParent(); root.insertChild(node, at: root.numberOfChildren)
        } else {
            guard let anchor = items[to].node, anchor !== node, let p = anchor.parent else { return }
            // never into its own branch
            var q: PDFOutline? = anchor
            while let x = q { if x === node { return }; q = x.parent }
            node.removeFromParent()
            p.insertChild(node, at: anchor.index)
        }
        mkOutlineChanged()
    }

    func mkOutlineRename(_ o: PDFOutline, to label: String) {
        guard o.label != label else { return }
        o.label = label
        mkMarkDirty()   // no render tick: the field being typed in must keep focus
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
    @State private var reordering = false
    @State private var editing: String? = nil
    @FocusState private var focused: String?

    private func beginRename(_ id: String) {
        editing = id
        Task { @MainActor in focused = id }   // after the field exists
    }

    var body: some View {
        let _ = editor.mk.renderTick
        let items = editor.outlineItems
        VStack(spacing: 0) {
            if reordering {
                // Native list reorder: drag the handles; rows slide to show the drop.
                List {
                    ForEach(items) { o in
                        HStack(spacing: 6) {
                            Text(o.label).font(fnt(o.depth == 0 ? 14 : 13, o.depth == 0 ? .semibold : .medium))
                                .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink2).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("p.\(o.pageIndex + 1)").font(fnt(11, .semibold)).monospacedDigit().foregroundStyle(theme.ink4)
                        }
                        .padding(.leading, Double(o.depth) * 16)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
                    }
                    .onMove { from, to in editor.mkOutlineMove(items: items, from: from, to: to) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { o in row(o) }
                        if items.isEmpty {
                            Text("No outline yet.").font(fnt(12.5)).foregroundStyle(theme.ink4).padding(.vertical, 18)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 12)
                }
            }
            // Add (a level-1 entry for the current page, at the end) and Reorder, always at the bottom.
            HStack(spacing: 8) {
                SecondaryButton(label: "Add", symbol: "plus") {
                    reordering = false
                    if let o = editor.mkOutlineAdd() { beginRename(ObjectIdentifier(o).debugDescription) }
                }
                .disabled(!editor.isPDF)
                Spacer(minLength: 0)
                SecondaryButton(label: reordering ? "Done" : "Reorder", symbol: reordering ? "checkmark" : "arrow.up.arrow.down", tint: reordering ? theme.accent : nil) {
                    editing = nil; focused = nil
                    withAnimation(.easeOut(duration: 0.15)) { reordering.toggle() }
                }
                .disabled(items.count < 2 && !reordering)
            }
            .padding(12)
            .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
        }
    }

    /// One entry: chevron for branches, the name, the page. Tap goes to the page; Rename (long-press menu, or a
    /// just-added entry) swaps the name for an in-place field until you submit or tap away.
    private func row(_ o: OutlineItem) -> some View {
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
            if let node = o.node, editing == o.id {
                TextField("Title", text: Binding(get: { node.label ?? "" }, set: { editor.mkOutlineRename(node, to: $0) }))
                    .textFieldStyle(.plain)
                    .font(fnt(o.depth == 0 ? 14 : 13, o.depth == 0 ? .semibold : .medium))
                    .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink2)
                    .focused($focused, equals: o.id)
                    .onSubmit { editing = nil; focused = nil }
                    .onChange(of: focused) { _, f in if f != o.id { editing = nil } }
            } else {
                Text(o.label).font(fnt(o.depth == 0 ? 14 : 13, o.depth == 0 ? .semibold : .medium))
                    .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink2).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { focused = nil; editor.setPage(o.pageIndex) } label: {
                Text("p.\(o.pageIndex + 1)").font(fnt(11, .semibold)).monospacedDigit().foregroundStyle(theme.ink4)
                    .frame(height: 28).padding(.horizontal, 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.trailing, 4)
        .padding(.leading, 6 + Double(o.depth) * 16)
        .frame(height: o.depth == 0 ? 44 : 36)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(editing == o.id ? theme.card : (o.pageIndex == editor.pageIndex && o.depth == 0 ? theme.hov2 : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.accent, lineWidth: editing == o.id ? 1.5 : 0))
        .contentShape(Rectangle())
        .onTapGesture { if editing != o.id { editing = nil; focused = nil; editor.setPage(o.pageIndex) } }
        .contextMenu {
            if let node = o.node {
                Button("Rename", systemImage: "pencil") { beginRename(o.id) }
                Button("Add child entry", systemImage: "arrow.turn.down.right") { if let c = editor.mkOutlineAdd(asChildOf: node) { beginRename(ObjectIdentifier(c).debugDescription) } }
                Button("Indent", systemImage: "increase.indent") { editor.mkOutlineIndent(node) }
                Button("Outdent", systemImage: "decrease.indent") { editor.mkOutlineOutdent(node) }
                Divider()
                Button("Point at this page", systemImage: "doc.text") { editor.mkOutlineRetarget(node) }
                Button("Delete", systemImage: "trash", role: .destructive) { editor.mkOutlineDelete(node) }
            }
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
