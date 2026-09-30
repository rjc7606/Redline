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
}

extension WorkspaceModel {
    /// The PDF's own outline when it has one; otherwise the page labels.
    var outlineItems: [OutlineItem] {
        var out: [OutlineItem] = []
        if let f = doc.pdfFile, let pdf = app.pdf.document(f), let root = pdf.outlineRoot, root.numberOfChildren > 0 {
            func walk(_ node: PDFOutline, depth: Int) {
                for i in 0..<node.numberOfChildren {
                    guard let c = node.child(at: i) else { continue }
                    var pi = 0
                    if let pg = c.destination?.page {
                        let idx = pdf.index(for: pg)
                        pi = doc.pages.firstIndex { $0.pdfPageIndex == idx } ?? min(idx, doc.pages.count - 1)
                    }
                    out.append(OutlineItem(id: "o\(out.count)", label: c.label ?? "Untitled", pageIndex: max(0, pi), depth: depth))
                    if depth < 3 { walk(c, depth: depth + 1) }
                }
            }
            walk(root, depth: 0)
            if !out.isEmpty { return out }
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
}

struct OutlinePanel: View {
    @Environment(\.theme) private var theme
    var editor: WorkspaceModel

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(editor.outlineItems) { o in
                    HStack(spacing: 7) {
                        Text(o.label).font(fnt(o.depth == 0 ? 14 : 13, o.depth == 0 ? .semibold : .medium))
                            .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink3).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("p.\(o.pageIndex + 1)").font(fnt(11, .semibold)).foregroundStyle(theme.ink4)
                    }
                    .padding(.trailing, 10)
                    .padding(.leading, 10 + Double(o.depth) * 16)
                    .frame(height: o.depth == 0 ? 44 : 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(o.depth == 0 && o.pageIndex == editor.pageIndex ? theme.hov2 : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(o.pageIndex) }
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 12)
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
