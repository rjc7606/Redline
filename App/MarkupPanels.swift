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
            guard let i = doc.pageIndex(of: id) else { return nil }
            let pg = doc.pages[i]
            return (id, i, pg.label.isEmpty ? "Page \(i + 1)" : pg.label)
        }
        let current = doc.bookmarks.contains(editor.page.id)
        ScrollView {
            VStack(spacing: 2) {
                ForEach(items, id: \.id) { b in
                    HStack(spacing: 9) {
                        Image(systemName: "bookmark.fill").font(fnt(13)).foregroundStyle(Color(hex: "#FF9500"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.label).font(fnt(12.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                            Text("Page \(b.index + 1)").font(fnt(10.5)).foregroundStyle(theme.ink4)
                        }
                        Spacer(minLength: 0)
                        Button { editor.app.mutate(editor.docID) { $0.bookmarks.removeAll { $0 == b.id } } } label: {
                            Image(systemName: "xmark").font(fnt(10, .bold)).foregroundStyle(theme.ink4).frame(width: 20, height: 20)
                        }.buttonStyle(.plain).opacity(0.4)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(b.index == editor.pageIndex ? theme.accentSoft : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(b.index) }
                }
                if items.isEmpty {
                    Text("No bookmarks yet.").font(fnt(12)).foregroundStyle(theme.ink4).padding(.vertical, 18)
                }
                Button { editor.toggleBookmark() } label: {
                    Text(current ? "✓ Bookmarked — tap to remove" : "＋ Bookmark this page")
                        .font(fnt(12, .semibold)).foregroundStyle(current ? theme.ink4 : theme.accent)
                        .frame(maxWidth: .infinity).padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
                .padding(.top, 8).padding(.horizontal, 2)
            }
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
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
                        Text(o.label).font(fnt(o.depth == 0 ? 12.5 : 12, o.depth == 0 ? .bold : .medium))
                            .foregroundStyle(o.depth == 0 ? theme.ink1 : theme.ink3).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(o.pageIndex + 1)").font(fnt(10, .semibold)).foregroundStyle(theme.dis)
                    }
                    .padding(.vertical, 7).padding(.trailing, 9)
                    .padding(.leading, 9 + Double(o.depth) * 16)
                    .background(RoundedRectangle(cornerRadius: 7).fill(o.depth == 0 && o.pageIndex == editor.pageIndex ? theme.accentSoft : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { editor.setPage(o.pageIndex) }
                }
            }
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.popSolid)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.line, lineWidth: 1))
            .shadow(color: Shadows.popover.color, radius: Shadows.popover.radius, y: Shadows.popover.y))
    }
}
