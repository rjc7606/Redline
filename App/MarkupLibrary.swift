import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

/// Where the Markups library is looking.
enum LibraryLocation: Hashable {
    case recents
    case favorites
    case folder(String)   // "" = root (On My iPad › Redline)
}

/// Home, built from the `Redline Studio` prototype: a fixed 240 pt sidebar (title, search, the Markups places and
/// folder tree, then Drawings and Notes rows that expand to their recent documents) and a pane that shows the Recents
/// rails at the root, or one shelf (crumbs, sort, New) as a tile grid.
struct HomeBrowser: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @State private var expanded: Set<String> = [""]
    @State private var drawingsOpen = false
    @State private var notesOpen = false
    @State private var importing = false
    @State private var newFolderOn = false
    @State private var folderDraft = ""
    @State private var renameFolderPath: String? = nil
    @State private var renameFolderOn = false
    @State private var renameDocID: ID? = nil
    @State private var renameDocOn = false
    @State private var renameDraft = ""

    private var shelf: DocumentType? { app.homeShelf }
    private var currentFolder: String? { if shelf == .markup, case .folder(let f) = app.library { return f }; return nil }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: Metrics.homeNav)
            pane
        }
        .background(GrainBackground(color: theme.bg))
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { app.importPDFs(urls, into: currentFolder ?? "") }
        }
        .alert("New folder", isPresented: $newFolderOn) {
            TextField("Name", text: $folderDraft)
            Button("Create") { let p = app.store.createFolder(named: folderDraft, in: currentFolder ?? ""); app.scheduleSave(); expanded.insert(RedlineStore.parent(of: p)) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename folder", isPresented: $renameFolderOn) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { if let p = renameFolderPath { app.store.renameFolder(p, to: renameDraft); app.scheduleSave() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: $renameDocOn) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { if let id = renameDocID, !renameDraft.trimmingCharacters(in: .whitespaces).isEmpty { app.store.renameDocument(id, to: renameDraft); app.scheduleSave() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sidebar (240 · bg2 · padding 18/12 · rows 36)

    private var sidebar: some View {
        @Bindable var app = app
        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                Button { go(nil) } label: { Text("Redline").font(titleFnt(22)).foregroundStyle(theme.ink1) }.buttonStyle(.plain)
                Spacer(minLength: 0)
                BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
            }
            .frame(height: 40).padding(.leading, 10).padding(.trailing, 4)
            SearchField(text: $app.homeQuery).padding(.top, 10).padding(.bottom, 14)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Markups", DocumentType.markup.tint)
                    NavRow(label: "Recents", symbol: "clock", active: shelf == nil) { go(nil) }
                    NavRow(label: "Favorites", symbol: "star", active: shelf == .markup && app.library == .favorites, trailing: count(app.store.favorites(on: .markup).count)) { go(.markup, .favorites) }
                    NavRow(label: "On My iPad", symbol: "ipad") { go(.markup, .folder("")); expanded.insert("") }
                    folderRow(path: "", depth: 0)
                    NavRow(label: "Browse Files…", symbol: "folder.badge.plus") { importing = true }
                    Color.clear.frame(height: 14)
                    toolRow(.drawing, open: $drawingsOpen)
                    toolRow(.journal, open: $notesOpen)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 18, trailing: 12))
        .frame(maxHeight: .infinity)
        .background(theme.bg2)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }

    private func sectionHeader(_ text: String, _ dot: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(dot).frame(width: 8, height: 8); SectionLabel(text: text) }
            .padding(EdgeInsets(top: 14, leading: 10, bottom: 6, trailing: 10))
    }

    private func count(_ n: Int) -> String? { n > 0 ? "\(n)" : nil }

    private func go(_ type: DocumentType?, _ location: LibraryLocation? = nil) {
        if let type { app.settings.shelf = type }
        if let location { app.library = location }
        app.homeShelf = type
    }

    /// Drawings / Notes: dot · label · count · chevron; the chevron expands the six most recent documents.
    private func toolRow(_ type: DocumentType, open: Binding<Bool>) -> some View {
        let docs = recent(type)
        let active = shelf == type
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Button { go(type) } label: {
                    HStack(spacing: 9) {
                        Circle().fill(type.tint).frame(width: 8, height: 8)
                        Text(type.shelfLabel).font(fnt(14, active ? .semibold : .medium)).foregroundStyle(active ? theme.ink1 : theme.ink2).lineLimit(1)
                        Spacer(minLength: 0)
                        if let c = count(app.store.documents(on: type).count) { Text(c).font(fnt(11.5, .medium)).monospacedDigit().foregroundStyle(theme.ink4) }
                    }
                    .padding(.leading, 10).frame(height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { withAnimation(.easeOut(duration: 0.15)) { open.wrappedValue.toggle() } } label: {
                    Image(systemName: "chevron.right").font(fnt(12, .semibold)).foregroundStyle(theme.ink4)
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0)).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 6)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? theme.hov2 : .clear))
            if open.wrappedValue {
                ForEach(docs.prefix(6)) { d in
                    if type == .journal { NavRow(label: d.name, indent: 16, swatch: Color(hex: d.coverHex)) { app.openDocument(d.id) } }
                    else { NavRow(label: d.name, symbol: "square.stack", indent: 16) { app.openDocument(d.id) } }
                }
                if docs.isEmpty { Text("No \(type.singular)s yet").font(fnt(12.5)).foregroundStyle(theme.ink4).padding(.leading, 36).frame(height: 30) }
            }
        }
    }

    /// The Markups folder tree: "Redline" at indent 16 under On My iPad, subfolders 16 per level.
    private func folderRow(path: String, depth: Int) -> AnyView {
        let kids = app.store.subfolders(of: path)
        let name = path.isEmpty ? "Redline" : RedlineStore.name(of: path)
        let active = shelf == .markup && app.library == .folder(path)
        let isOpen = expanded.contains(path)
        let n = app.store.documents(on: .markup, in: path).count
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                NavRow(label: name, symbol: isOpen && !kids.isEmpty ? "folder" : "folder.fill", active: active, trailing: count(n), indent: 16 + Double(depth) * 16) {
                    go(.markup, .folder(path)); expanded.insert(path)
                }
                .overlay(alignment: .trailing) {
                    if !kids.isEmpty {
                        Button { withAnimation(.easeOut(duration: 0.15)) { if isOpen { expanded.remove(path) } else { expanded.insert(path) } } } label: {
                            Image(systemName: "chevron.right").font(fnt(12, .semibold)).foregroundStyle(theme.ink4)
                                .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 28, height: 28).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.trailing, 6)
                    }
                }
                .contextMenu { if !path.isEmpty { folderMenu(path) } }
                if isOpen { ForEach(kids, id: \.self) { k in folderRow(path: k, depth: depth + 1) } }
            }
        )
    }

    @ViewBuilder
    private func folderMenu(_ path: String) -> some View {
        Button("Rename") { renameFolderPath = path; renameDraft = RedlineStore.name(of: path); renameFolderOn = true }
        Button("Delete folder", role: .destructive) {
            app.store.deleteFolder(path); app.scheduleSave()
            if case .folder(let f) = app.library, f == path || f.hasPrefix(path + "/") { app.library = .folder(RedlineStore.parent(of: path)) }
        }
    }

    private func recent(_ type: DocumentType) -> [Document] {
        let r = app.store.recents(on: type)
        return r.isEmpty ? app.store.documents(on: type) : r
    }

    // MARK: - Pane (padding 28)

    private var pane: some View {
        let q = app.homeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let shelf {
                    let docs = shelfDocs(shelf, query: q)
                    let folders = (currentFolder.map { app.store.subfolders(of: $0) } ?? []).filter { q.isEmpty || RedlineStore.name(of: $0).lowercased().contains(q) }
                    if docs.isEmpty && folders.isEmpty {
                        emptyState(shelf, query: q)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 148), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(folders, id: \.self) { f in
                                FolderTile(path: f, count: app.store.documents(on: .markup, in: f).count) { go(.markup, .folder(f)); expanded.insert(RedlineStore.parent(of: f)) }
                                    .contextMenu { folderMenu(f) }
                            }
                            ForEach(docs) { d in DocTile(doc: d, showFolder: shelf == .markup && (currentFolder == nil || !q.isEmpty)) { libraryMenu(d) } }
                        }
                        .padding(.top, 26)
                    }
                } else {
                    VStack(spacing: 0) { ForEach(DocumentType.allCases, id: \.self) { t in rail(t, query: q) } }.padding(.top, 8)
                }
            }
            .padding(28)
        }
    }

    /// Crumbs + title on the left; sort, New Folder / Import PDF and New on the right.
    private var header: some View {
        @Bindable var app = app
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if shelf == .markup {
                    switch app.library {
                    case .recents: Text("Recents").font(titleFnt(26)).foregroundStyle(theme.ink1)
                    case .favorites: Text("Favorites").font(titleFnt(26)).foregroundStyle(theme.ink1)
                    case .folder(let f):
                        let parts = f.isEmpty ? [] : f.split(separator: "/").map(String.init)
                        crumb("On My iPad") { go(.markup, .folder("")) }
                        if !parts.isEmpty { crumb("Redline") { go(.markup, .folder("")) } }
                        ForEach(Array(parts.dropLast().enumerated()), id: \.offset) { i, part in
                            crumb(part) { go(.markup, .folder(parts[0...i].joined(separator: "/"))) }
                        }
                        Text(parts.last ?? "Redline").font(titleFnt(26)).foregroundStyle(theme.ink1).lineLimit(1)
                    }
                } else {
                    Text(shelf?.shelfLabel ?? "Recents").font(titleFnt(26)).foregroundStyle(theme.ink1)
                }
            }
            Spacer(minLength: 8)
            if let shelf {
                SegmentControl(options: HomeSort.allCases.map { SegmentOption(value: $0, label: $0.rawValue) }, selection: $app.homeSort, fontSize: 13, vPad: 5, hPad: 14, radius: 9)
                if shelf == .markup {
                    SecondaryButton(label: "New Folder", symbol: "folder.badge.plus") { folderDraft = ""; newFolderOn = true }
                }
                PrimaryButton(label: shelf.newLabel, symbol: "plus", tint: shelf.tint) {
                    app.settings.shelf = shelf
                    var d = NewDocumentDraft(type: shelf); d.folder = currentFolder ?? ""
                    app.newDraft = d
                }
            }
        }
    }

    private func crumb(_ label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: action) { Text(label).font(fnt(15, .medium)).foregroundStyle(theme.accent).lineLimit(1) }.buttonStyle(.plain)
            Image(systemName: "chevron.right").font(fnt(12, .semibold)).foregroundStyle(theme.ink4)
        }
    }

    private func shelfDocs(_ shelf: DocumentType, query q: String) -> [Document] {
        var docs: [Document]
        if shelf == .markup {
            switch app.library {
            case .recents: docs = app.store.recents(on: .markup)
            case .favorites: docs = app.store.favorites(on: .markup)
            case .folder(let f): docs = q.isEmpty ? app.store.documents(on: .markup, in: f) : app.store.documents(on: .markup)
            }
        } else {
            docs = app.store.documents(on: shelf)
        }
        if !q.isEmpty { docs = docs.filter { $0.name.lowercased().contains(q) } }
        if app.homeSort == .name { docs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        return docs
    }

    /// One rail: dot · label · New · See all, then the eight most recent tiles (or a dashed "No … yet" tile).
    private func rail(_ type: DocumentType, query q: String) -> some View {
        let docs = recent(type).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(type.tint).frame(width: 8, height: 8)
                Text(type.railLabel).font(fnt(15, .semibold)).foregroundStyle(theme.ink1)
                Spacer(minLength: 0)
                SecondaryButton(label: "New", symbol: "plus", height: 30) { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) }
                Button { go(type, type == .markup ? .folder("") : nil) } label: {
                    HStack(spacing: 2) { Text("See all").font(fnt(13, .semibold)); Image(systemName: "chevron.right").font(fnt(11, .bold)) }
                        .foregroundStyle(theme.accent).padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(docs.prefix(8)) { d in DocTile(doc: d) { libraryMenu(d) } }
                    if docs.isEmpty {
                        Button { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) } label: {
                            Text(q.isEmpty ? "No \(type.singular)s yet" : "No matches").font(fnt(12, .semibold)).foregroundStyle(theme.ink4)
                                .frame(width: 132, height: 100)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!q.isEmpty)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 24).padding(.bottom, 28)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func emptyState(_ shelf: DocumentType, query q: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: shelf == .markup ? "doc.text" : shelf.symbol).font(fnt(40, .regular)).foregroundStyle(theme.ink4)
            Text(!q.isEmpty ? "No matches for \"\(app.homeQuery)\"." :
                 shelf == .markup ? (app.library == .favorites ? "No favorites yet. Long-press a markup and choose Add to Favorites." : "This folder is empty. Open a PDF with Browse Files… or create a new one.") :
                 shelf == .drawing ? "No drawings yet. Create your first plan set." : "No notebooks yet. Create your first notebook.")
                .font(fnt(14, .medium)).foregroundStyle(theme.ink3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    @ViewBuilder
    private func libraryMenu(_ d: Document) -> some View {
        Button(d.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: d.isFavorite ? "star.slash" : "star") { app.store.setFavorite(d.id, !d.isFavorite); app.scheduleSave() }
        if d.type == .markup {
            Menu("Move to", systemImage: "folder") {
                Button("Redline") { app.store.move(d.id, toFolder: ""); app.scheduleSave() }
                ForEach(app.store.allFolders, id: \.self) { f in Button(f) { app.store.move(d.id, toFolder: f); app.scheduleSave() } }
            }
        }
        Button("Rename", systemImage: "pencil") { renameDocID = d.id; renameDraft = d.name; renameDocOn = true }
    }
}

/// Folder tile: 132 × 96 face, `folder.fill` 44 accent.
struct FolderTile: View {
    @Environment(\.theme) private var theme
    var path: String
    var count: Int
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accent.opacity(0.07))
                    Image(systemName: "folder.fill").font(fnt(44, .regular)).foregroundStyle(theme.accent)
                }
                .frame(width: Metrics.docTile, height: 96)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RedlineStore.name(of: path)).font(fnt(13, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                    Text(Formatting.plural(count, "file")).font(fnt(11.5, .medium)).foregroundStyle(theme.ink4)
                }
            }
            .frame(width: Metrics.docTile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
