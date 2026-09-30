import SwiftUI
import UniformTypeIdentifiers
import RedlineCore

/// Where the Markups library is looking.
enum LibraryLocation: Hashable {
    case recents
    case favorites
    case folder(String)   // "" = root (On My iPad › Redline)
}

/// File-browser style library for Markups: Recents, Favorites, the app's folder tree, and Files locations.
struct MarkupLibrary: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @State private var expanded: Set<String> = [""]
    @State private var importing = false
    @State private var newFolderOn = false
    @State private var folderDraft = ""
    @State private var renameFolderPath: String? = nil
    @State private var renameFolderOn = false
    @State private var renameDocID: ID? = nil
    @State private var renameDocOn = false
    @State private var renameDraft = ""

    private var currentFolder: String? { if case .folder(let f) = app.library { f } else { nil } }

    var body: some View {
        @Bindable var app = app
        GeometryReader { geo in
            let compact = geo.size.width < Metrics.compactThreshold
            HStack(spacing: 0) {
                if !compact { sidebar.frame(width: Metrics.homeNav) }
                content(compact: compact)
            }
        }
        .background(theme.bg)
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

    // MARK: sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Button { app.homeShelf = nil } label: {
                    HStack(spacing: 2) { Image(systemName: "chevron.left").font(fnt(17, .semibold)); Text("Home").font(fnt(15)) }.foregroundStyle(theme.accent)
                }.buttonStyle(.plain).padding(.horizontal, 6).padding(.bottom, 12)
                HStack(spacing: 10) {
                    Image(systemName: DocumentType.markup.symbol).font(fnt(17, .semibold)).foregroundStyle(DocumentType.markup.tint)
                        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DocumentType.markup.tint.opacity(0.14)))
                    Text("Markups").font(fnt(22, .bold)).foregroundStyle(theme.ink1)
                }
                .padding(.horizontal, 6).padding(.bottom, 14)
                NavRow(label: "Recents", symbol: "clock", active: app.library == .recents, trailing: "\(app.store.recents(on: .markup).count)") { app.library = .recents }
                NavRow(label: "Favorites", symbol: "star", active: app.library == .favorites, trailing: "\(app.store.favorites(on: .markup).count)") { app.library = .favorites }
                SectionLabel(text: "On My iPad").padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 6)
                folderRow(path: "", depth: 0)
                SectionLabel(text: "Locations").padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 6)
                NavRow(label: "Browse Files…", symbol: "icloud") { importing = true }
                Text("iCloud Drive, OneDrive, Dropbox and any other app in Files. Picked PDFs are imported here.")
                    .font(fnt(11)).foregroundStyle(theme.ink4).lineSpacing(2).padding(.horizontal, 10).padding(.top, 2)
                Spacer(minLength: 20)
                NavRow(label: "Settings", symbol: "gearshape") { app.openSettings() }
            }
            .padding(.horizontal, 12).padding(.vertical, 18)
        }
        .background(theme.bg2)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    }

    /// Recursive folder tree row with an expand chevron.
    private func folderRow(path: String, depth: Int) -> AnyView {
        let kids = app.store.subfolders(of: path)
        let name = path.isEmpty ? "Redline" : RedlineStore.name(of: path)
        let active = app.library == .folder(path)
        let isOpen = expanded.contains(path)
        let count = app.store.documents(on: .markup, in: path).count
        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Button { if isOpen { expanded.remove(path) } else { expanded.insert(path) } } label: {
                        Image(systemName: "chevron.right").font(fnt(11, .bold)).foregroundStyle(theme.ink4)
                            .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 18, height: 18)
                            .opacity(kids.isEmpty ? 0 : 1)
                    }.buttonStyle(.plain).disabled(kids.isEmpty)
                    Button { app.library = .folder(path); expanded.insert(path) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: path.isEmpty ? "ipad" : (isOpen ? "folder" : "folder.fill")).font(fnt(15, .medium)).foregroundStyle(active ? theme.accent : theme.ink3).frame(width: 20)
                            Text(name).font(fnt(14, active ? .semibold : .regular)).foregroundStyle(active ? theme.accent : theme.ink2).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(count)").font(fnt(11.5, .semibold)).foregroundStyle(theme.ink4)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(active ? theme.accentSoft : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { if !path.isEmpty { folderMenu(path) } }
                }
                .padding(.leading, Double(depth) * 14)
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

    // MARK: content

    private func content(compact: Bool) -> some View {
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
            VStack(alignment: .leading, spacing: 18) {
                if compact {
                    HStack(spacing: 8) {
                        Button { app.homeShelf = nil } label: { HStack(spacing: 2) { Image(systemName: "chevron.left").font(fnt(17, .semibold)); Text("Home").font(fnt(15)) }.foregroundStyle(theme.accent) }.buttonStyle(.plain)
                        Spacer()
                        Menu {
                            Button("Recents") { app.library = .recents }
                            Button("Favorites") { app.library = .favorites }
                            Button("Redline (On My iPad)") { app.library = .folder("") }
                            ForEach(app.store.allFolders, id: \.self) { f in Button(f) { app.library = .folder(f) } }
                            Divider()
                            Button("Browse Files…") { importing = true }
                        } label: {
                            HStack(spacing: 6) { Image(systemName: "folder"); Text(locationTitle).lineLimit(1) }.font(fnt(13.5, .semibold)).foregroundStyle(theme.ink1)
                                .padding(.horizontal, 12).frame(height: 34).background(RoundedRectangle(cornerRadius: 9).fill(theme.bg3))
                        }
                        BarButton(symbol: "gearshape", label: "Settings") { app.openSettings() }
                    }
                }
                HStack(spacing: 10) {
                    breadcrumb
                    Spacer()
                    SearchField(text: $app.homeQuery).frame(maxWidth: 220)
                    SegmentControl(options: HomeSort.allCases.map { SegmentOption(value: $0, label: $0.rawValue) }, selection: $app.homeSort, fontSize: 12.5, vPad: 6, hPad: 12)
                }
                HStack(spacing: 8) {
                    if currentFolder != nil {
                        SecondaryButton(label: "New Folder", symbol: "folder.badge.plus") { folderDraft = ""; newFolderOn = true }
                    }
                    SecondaryButton(label: "Import PDF", symbol: "square.and.arrow.down") { importing = true }
                    Button {
                        app.settings.shelf = .markup
                        var d = NewDocumentDraft(type: .markup); d.folder = currentFolder ?? ""
                        app.newDraft = d
                    } label: {
                        HStack(spacing: 7) { Image(systemName: "plus").font(fnt(14, .bold)); Text("New PDF").font(fnt(13, .bold)) }
                            .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DocumentType.markup.tint))
                    }.buttonStyle(.plain)
                }
                if folders.isEmpty && docs.isEmpty {
                    emptyState(q: q)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 22)], spacing: 26) {
                        ForEach(folders, id: \.self) { f in FolderTile(path: f, count: app.store.documents(on: .markup, in: f).count) { app.library = .folder(f); expanded.insert(RedlineStore.parent(of: f)) }
                            .contextMenu { folderMenu(f) } }
                        ForEach(docs) { d in
                            DocTile(doc: d, showFolder: currentFolder == nil || !q.isEmpty) {
                                libraryMenu(d)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
        }
    }

    private var locationTitle: String {
        switch app.library {
        case .recents: "Recents"
        case .favorites: "Favorites"
        case .folder(let f): f.isEmpty ? "Redline" : RedlineStore.name(of: f)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            switch app.library {
            case .recents:
                Image(systemName: "clock").font(fnt(20, .semibold)).foregroundStyle(theme.ink3)
                Text("Recents").font(fnt(26, .heavy)).foregroundStyle(theme.ink1)
            case .favorites:
                Image(systemName: "star").font(fnt(20, .semibold)).foregroundStyle(Color(hex: "#FF9500"))
                Text("Favorites").font(fnt(26, .heavy)).foregroundStyle(theme.ink1)
            case .folder(let f):
                let parts = f.isEmpty ? [] : f.split(separator: "/").map(String.init)
                Button { app.library = .folder("") } label: {
                    Text("Redline").font(fnt(parts.isEmpty ? 26 : 15, parts.isEmpty ? .heavy : .semibold)).foregroundStyle(parts.isEmpty ? theme.ink1 : theme.accent)
                }.buttonStyle(.plain)
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    let last = i == parts.count - 1
                    Image(systemName: "chevron.right").font(fnt(12, .bold)).foregroundStyle(theme.ink4)
                    Button { app.library = .folder(parts[0...i].joined(separator: "/")) } label: {
                        Text(part).font(fnt(last ? 26 : 15, last ? .heavy : .semibold)).foregroundStyle(last ? theme.ink1 : theme.accent).lineLimit(1)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func libraryMenu(_ d: Document) -> some View {
        Button(d.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: d.isFavorite ? "star.slash" : "star") { app.store.setFavorite(d.id, !d.isFavorite); app.scheduleSave() }
        Menu("Move to", systemImage: "folder") {
            Button("Redline") { app.store.move(d.id, toFolder: ""); app.scheduleSave() }
            ForEach(app.store.allFolders, id: \.self) { f in Button(f) { app.store.move(d.id, toFolder: f); app.scheduleSave() } }
        }
        Button("Rename", systemImage: "pencil") { renameDocID = d.id; renameDraft = d.name; renameDocOn = true }
    }

    private func emptyState(q: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: app.library == .recents ? "clock" : (app.library == .favorites ? "star" : "doc.text")).font(fnt(30, .medium)).foregroundStyle(theme.ink4)
            Text(!q.isEmpty ? "No matches for \"\(app.homeQuery)\"." :
                 app.library == .recents ? "Nothing opened yet." :
                 app.library == .favorites ? "No favorites yet. Long-press a markup and choose Add to Favorites." :
                 "This folder is empty. Import a PDF from Files or create a new one.")
                .font(fnt(14)).foregroundStyle(theme.ink4).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

struct FolderTile: View {
    @Environment(\.theme) private var theme
    var path: String
    var count: Int
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(theme.accent.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    Image(systemName: "folder.fill").font(fnt(48, .regular)).foregroundStyle(theme.accent.opacity(0.75))
                }
                .aspectRatio(1.32, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RedlineStore.name(of: path)).font(fnt(13.5, .semibold)).foregroundStyle(theme.ink1).lineLimit(1)
                    Text(Formatting.plural(count, "file")).font(fnt(11.5)).foregroundStyle(theme.ink4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
