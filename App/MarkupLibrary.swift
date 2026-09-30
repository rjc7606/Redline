import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

/// Where the Markups library is looking.
enum LibraryLocation: Hashable {
    case recents
    case favorites
    case folder(String)   // "" = root (On My iPad › Redline)
}

/// Home browser (handoff v2): NavColumn 240 on the left, and on the right the Recents rails (root), a Markups
/// folder (Recents / Favorites / folder tree / Browse Files…) or a Drawings / Notes gallery.
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

    private var inMarkups: Bool { app.homeShelf == .markup }
    private var currentFolder: String? { if inMarkups, case .folder(let f) = app.library { return f }; return nil }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < Metrics.compactThreshold
            HStack(spacing: 0) {
                if !compact { navColumn }
                pane(compact: compact)
            }
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

    // MARK: - NavColumn (240, bg2, 1 px line right, padding 18/12)

    private var navColumn: some View {
        @Bindable var app = app
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Button { app.homeShelf = nil } label: { Text("Redline").font(titleFnt(22)).foregroundStyle(theme.ink1) }.buttonStyle(.plain)
                    Spacer()
                    BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
                }
                .frame(height: 40).padding(.leading, 8)
                SearchField(text: $app.homeQuery).padding(.top, 10).padding(.bottom, 14)

                sectionLabel("Markups", DocumentType.markup.tint)
                NavRow(label: "Recents", symbol: "clock", active: inMarkups && app.library == .recents, trailing: "\(app.store.recents(on: .markup).count)") { go(.recents) }
                NavRow(label: "Favorites", symbol: "star", active: inMarkups && app.library == .favorites, trailing: "\(app.store.favorites(on: .markup).count)") { go(.favorites) }
                NavRow(label: "On My iPad", symbol: "ipad", active: false) { go(.folder("")); expanded.insert("") }
                folderRow(path: "", depth: 0)
                NavRow(label: "Browse Files…", symbol: "folder.badge.plus") { importing = true }

                toolRow(.drawing, open: $drawingsOpen).padding(.top, 14)
                toolRow(.journal, open: $notesOpen)
            }
            .padding(.horizontal, 12).padding(.vertical, 18)
        }
        .frame(width: Metrics.homeNav)
        .background(theme.bg2)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }

    private func sectionLabel(_ text: String, _ dot: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(dot).frame(width: 8, height: 8); SectionLabel(text: text) }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
    }

    private func go(_ loc: LibraryLocation) {
        app.library = loc
        app.homeShelf = .markup
        app.settings.shelf = .markup
    }

    /// Drawings / Notes row: dot · label · count · chevron that expands the six most recent documents.
    private func toolRow(_ type: DocumentType, open: Binding<Bool>) -> some View {
        let docs = recent(type)
        let active = app.homeShelf == type
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Button { app.homeShelf = type; app.settings.shelf = type; app.homeSort = .recent } label: {
                    HStack(spacing: 10) {
                        Circle().fill(type.tint).frame(width: 8, height: 8).frame(width: 20)
                        Text(type.shelfLabel).font(fnt(14, active ? .semibold : .medium)).foregroundStyle(active ? theme.ink1 : theme.ink2)
                        Spacer(minLength: 0)
                        Text("\(app.store.documents(on: type).count)").font(fnt(11.5, .medium)).monospacedDigit().foregroundStyle(theme.ink4)
                    }
                    .padding(.leading, 10).frame(height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { withAnimation(.easeOut(duration: 0.15)) { open.wrappedValue.toggle() } } label: {
                    Image(systemName: "chevron.right").font(fnt(11, .bold)).foregroundStyle(theme.ink4)
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0)).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.trailing, 4)
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? theme.hov2 : .clear))
            if open.wrappedValue {
                ForEach(docs.prefix(6)) { d in
                    if type == .journal {
                        NavRow(label: d.name, indent: 26, swatch: Color(hex: d.coverHex)) { app.openDocument(d.id) }
                    } else {
                        NavRow(label: d.name, symbol: "square.stack", indent: 26) { app.openDocument(d.id) }
                    }
                }
                if docs.isEmpty {
                    Text("No \(type.singular)s yet").font(fnt(12)).foregroundStyle(theme.ink4).padding(.leading, 36).frame(height: 30)
                }
            }
        }
    }

    /// Recursive folder tree: "Redline" at indent 26 under On My iPad, subfolders 16 per level.
    private func folderRow(path: String, depth: Int) -> AnyView {
        let kids = app.store.subfolders(of: path)
        let name = path.isEmpty ? "Redline" : RedlineStore.name(of: path)
        let active = inMarkups && app.library == .folder(path)
        let isOpen = expanded.contains(path)
        let count = app.store.documents(on: .markup, in: path).count
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                NavRow(label: name, symbol: isOpen ? "folder" : "folder.fill", active: active, trailing: "\(count)", indent: 26 + Double(depth) * 16) {
                    go(.folder(path)); expanded.insert(path)
                }
                .overlay(alignment: .leading) {
                    if !kids.isEmpty {
                        Button { if isOpen { expanded.remove(path) } else { expanded.insert(path) } } label: {
                            Image(systemName: "chevron.right").font(fnt(10, .bold)).foregroundStyle(theme.ink4)
                                .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 20, height: 36).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.leading, 12 + Double(depth) * 16)
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

    // MARK: - Right pane (padding 28)

    @ViewBuilder
    private func pane(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if compact { compactHeader }
            switch app.homeShelf {
            case nil: recentsPane
            case .markup?: markupPane
            case .drawing?, .journal?: galleryPane(app.homeShelf!)
            }
        }
    }

    /// Compact width: the NavColumn collapses into a location menu.
    private var compactHeader: some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            Menu {
                Button("Recents") { app.homeShelf = nil }
                Section("Markups") {
                    Button("Recents") { go(.recents) }
                    Button("Favorites") { go(.favorites) }
                    Button("Redline (On My iPad)") { go(.folder("")) }
                    ForEach(app.store.allFolders, id: \.self) { f in Button(f) { go(.folder(f)) } }
                    Button("Browse Files…") { importing = true }
                }
                Section("Drawings") { Button("All drawings") { app.homeShelf = .drawing } }
                Section("Notes") { Button("All notebooks") { app.homeShelf = .journal } }
            } label: {
                HStack(spacing: 6) { Image(systemName: "folder").font(fnt(14, .semibold)); Text(locationTitle).font(fnt(14, .semibold)).lineLimit(1) }
                    .foregroundStyle(theme.ink1).padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.bg3))
            }
            Spacer()
            SearchField(text: $app.homeQuery).frame(maxWidth: 220)
            BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
        }
        .padding(.horizontal, 28).padding(.top, 14)
    }

    private var locationTitle: String {
        switch app.homeShelf {
        case nil: return "Recents"
        case .drawing?: return "Drawings"
        case .journal?: return "Notes"
        case .markup?:
            switch app.library {
            case .recents: return "Markups · Recents"
            case .favorites: return "Markups · Favorites"
            case .folder(let f): return f.isEmpty ? "Redline" : RedlineStore.name(of: f)
            }
        }
    }

    // MARK: Recents (root): three rails

    private var recentsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recents").font(titleFnt(26)).foregroundStyle(theme.ink1).padding(.bottom, 4)
                ForEach(DocumentType.allCases, id: \.self) { t in rail(t) }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
    }

    private func rail(_ type: DocumentType) -> some View {
        let q = app.homeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let docs = recent(type).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(type.tint).frame(width: 8, height: 8)
                Text(type.railLabel).font(fnt(15, .semibold)).foregroundStyle(theme.ink1)
                Spacer()
                SecondaryButton(label: "New", height: 30) { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) }
                Button { seeAll(type) } label: {
                    HStack(spacing: 2) { Text("See all").font(fnt(13, .semibold)); Image(systemName: "chevron.right").font(fnt(11, .bold)) }.foregroundStyle(theme.accent)
                }.buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(docs.prefix(8)) { d in DocTile(doc: d) { libraryMenu(d) } }
                    if docs.isEmpty {
                        Button { app.settings.shelf = type; app.newDraft = NewDocumentDraft(type: type) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: q.isEmpty ? "plus" : "magnifyingglass").font(fnt(20, .medium))
                                Text(q.isEmpty ? "No \(type.singular)s yet" : "No matches").font(fnt(12.5, .semibold))
                            }
                            .foregroundStyle(q.isEmpty ? type.tint : theme.ink4)
                            .frame(width: 132, height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.line2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        }.buttonStyle(.plain).disabled(!q.isEmpty)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }
        }
        .padding(.top, 24).padding(.bottom, 28)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func seeAll(_ type: DocumentType) {
        app.settings.shelf = type
        app.homeSort = .recent
        if type == .markup { app.library = .recents }
        app.homeShelf = type
    }

    // MARK: Markups folder view

    private var markupPane: some View {
        @Bindable var app = app
        let q = app.homeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var docs: [Document]
        switch app.library {
        case .recents: docs = app.store.recents(on: .markup)
        case .favorites: docs = app.store.favorites(on: .markup)
        case .folder(let f): docs = q.isEmpty ? app.store.documents(on: .markup, in: f) : app.store.documents(on: .markup)
        }
        if !q.isEmpty { docs = docs.filter { $0.name.lowercased().contains(q) } }
        if app.homeSort == .name { docs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        let folders = (currentFolder.map { app.store.subfolders(of: $0) } ?? []).filter { q.isEmpty || RedlineStore.name(of: $0).lowercased().contains(q) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 10) {
                    breadcrumb
                    Spacer(minLength: 8)
                    SegmentControl(options: HomeSort.allCases.map { SegmentOption(value: $0, label: $0.rawValue) }, selection: $app.homeSort, fontSize: 13, vPad: 6, hPad: 12)
                    if currentFolder != nil {
                        SecondaryButton(label: "New Folder", symbol: "folder.badge.plus") { folderDraft = ""; newFolderOn = true }
                    }
                    SecondaryButton(label: "Import PDF", symbol: "square.and.arrow.down") { importing = true }
                    PrimaryButton(label: "New PDF", symbol: "plus", tint: DocumentType.markup.tint) {
                        app.settings.shelf = .markup
                        var d = NewDocumentDraft(type: .markup); d.folder = currentFolder ?? ""
                        app.newDraft = d
                    }
                }
                if folders.isEmpty && docs.isEmpty {
                    emptyState(q: q)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 148), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(folders, id: \.self) { f in
                            FolderTile(path: f, count: app.store.documents(on: .markup, in: f).count) { go(.folder(f)); expanded.insert(RedlineStore.parent(of: f)) }
                                .contextMenu { folderMenu(f) }
                        }
                        ForEach(docs) { d in
                            DocTile(doc: d, showFolder: currentFolder == nil || !q.isEmpty) { libraryMenu(d) }
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
    }

    /// "On My iPad › Redline › Folder": parents 15/500 accent, current 26/heavy.
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            switch app.library {
            case .recents:
                Text("Recents").font(titleFnt(26)).foregroundStyle(theme.ink1)
            case .favorites:
                Text("Favorites").font(titleFnt(26)).foregroundStyle(theme.ink1)
            case .folder(let f):
                let parts = f.isEmpty ? [] : f.split(separator: "/").map(String.init)
                Text("On My iPad").font(fnt(15, .medium)).foregroundStyle(theme.accent)
                Image(systemName: "chevron.right").font(fnt(12, .bold)).foregroundStyle(theme.ink4)
                Button { go(.folder("")) } label: {
                    Text("Redline").font(fnt(parts.isEmpty ? 26 : 15, parts.isEmpty ? .bold : .medium)).foregroundStyle(parts.isEmpty ? theme.ink1 : theme.accent)
                }.buttonStyle(.plain)
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    let last = i == parts.count - 1
                    Image(systemName: "chevron.right").font(fnt(12, .bold)).foregroundStyle(theme.ink4)
                    Button { go(.folder(parts[0...i].joined(separator: "/"))) } label: {
                        Text(part).font(fnt(last ? 26 : 15, last ? .bold : .medium)).foregroundStyle(last ? theme.ink1 : theme.accent).lineLimit(1)
                    }.buttonStyle(.plain)
                }
            }
        }
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

    /// Empty folder: `doc.text` 40 `ink4`, copy 14/500 `ink3`, then an Import PDF button.
    private func emptyState(q: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: app.library == .recents ? "clock" : (app.library == .favorites ? "star" : "doc.text")).font(fnt(40, .regular)).foregroundStyle(theme.ink4)
            Text(!q.isEmpty ? "No matches for \"\(app.homeQuery)\"." :
                 app.library == .recents ? "Nothing opened yet." :
                 app.library == .favorites ? "No favorites yet. Long-press a markup and choose Add to Favorites." :
                 "This folder is empty.")
                .font(fnt(14, .medium)).foregroundStyle(theme.ink3).multilineTextAlignment(.center)
            if q.isEmpty, currentFolder != nil { SecondaryButton(label: "Import PDF", symbol: "square.and.arrow.down") { importing = true } }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Drawings / Notes gallery

    private func galleryPane(_ shelf: DocumentType) -> some View {
        @Bindable var app = app
        let q = app.homeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var docs = app.store.documents(on: shelf).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        if app.homeSort == .name { docs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(shelf.shelfLabel).font(titleFnt(26)).foregroundStyle(theme.ink1)
                    Spacer()
                    SegmentControl(options: HomeSort.allCases.map { SegmentOption(value: $0, label: $0.rawValue) }, selection: $app.homeSort, fontSize: 13, vPad: 6, hPad: 12)
                    PrimaryButton(label: shelf.newLabel, symbol: "plus", tint: shelf.tint) { app.settings.shelf = shelf; app.newDraft = NewDocumentDraft(type: shelf) }
                }
                if docs.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: shelf.symbol).font(fnt(40, .regular)).foregroundStyle(theme.ink4)
                        Text(q.isEmpty ? "No \(shelf.singular)s yet." : "No \(shelf.shelfLabel.lowercased()) match \"\(app.homeQuery)\".")
                            .font(fnt(14, .medium)).foregroundStyle(theme.ink3)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: shelf == .journal ? 104 : 132, maximum: shelf == .journal ? 120 : 148), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(docs) { d in DocTile(doc: d) { libraryMenu(d) } }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
    }
}

/// Folder tile (handoff v2): 132 × 96 face, `folder.fill` 44 accent, no dashed border.
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
                    Text(RedlineStore.name(of: path)).font(fnt(13, .medium)).foregroundStyle(theme.ink1).lineLimit(1)
                    Text(Formatting.plural(count, "file")).font(fnt(11.5, .medium)).foregroundStyle(theme.ink4)
                }
            }
            .frame(width: Metrics.docTile, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
