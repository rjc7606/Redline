import SwiftUI
import PDFKit
import RedlineCore

/// Everything shared between windows: the library store and its file, the PDF service and the clipboard.
/// Each window (scene) has its own `AppModel` for navigation and open documents; all of them read and write here.
/// The library always lives on this iPad; a sync folder (for example in iCloud Drive) mirrors it so other iPads
/// can pick the same folder and merge.
@MainActor
@Observable
final class LibraryHub {
    static let shared = LibraryHub()

    var store: RedlineStore
    let pdf = PDFService()
    /// Copied annotations (detached clones) — paste into any open PDF, in any window.
    var clipboard: [PDFAnnotation] = []
    /// The folder the library is mirrored to (nil = no sync).
    private(set) var syncFolder: URL? = nil
    private(set) var lastSync: Date? = nil
    private(set) var syncNote: String = ""
    /// Bumped when the store was replaced or merged from the sync folder.
    private(set) var reloadTick = 0

    @ObservationIgnored private var saveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var syncTask: Task<Void, Never>? = nil
    @ObservationIgnored private var presenter: PDFFilePresenter? = nil
    @ObservationIgnored private var lastPush: Date? = nil
    @ObservationIgnored private var lastForegroundSync: Date? = nil
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var scenes: [WeakScene] = []
    @ObservationIgnored var resolvedExternal = false

    private struct WeakScene { weak var app: AppModel? }
    static let syncBookmarkKey = "redline.syncFolderBookmark"

    private init() {
        store = RedlineStore(data: LibraryHub.load(from: LibraryHub.dataFile) ?? Seed.data())
        var folder: URL? = nil
        if let bm = UserDefaults.standard.data(forKey: LibraryHub.syncBookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                folder = url
                if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: LibraryHub.syncBookmarkKey)
                }
            }
        }
        syncFolder = folder
        watchSyncFile()
        if folder != nil { scheduleSync(after: 2) }
    }

    // MARK: windows

    func register(_ app: AppModel) { scenes.append(WeakScene(app: app)); scenes.removeAll { $0.app == nil } }
    var apps: [AppModel] { scenes.compactMap(\.app) }
    var anyDocumentOpen: Bool { apps.contains { !$0.openDocs.isEmpty } }
    /// Every editor (in every window) showing the PDF file `file`.
    func editors(for file: String) -> [WorkspaceModel] {
        apps.flatMap { $0.allEditors }.filter { $0.doc.pdfFile == file }
    }
    /// One editor changed a PDF that other windows show too: they redraw.
    func noteEdited(_ file: String, by editor: WorkspaceModel) {
        for e in editors(for: file) where e !== editor { e.mk.renderTick += 1 }
    }
    /// The file on disk replaced what was loaded: every editor adopts the fresh document.
    func reloadPDF(_ file: String) {
        pdf.reload(file)
        for e in editors(for: file) { e.mkAdoptReloaded() }
    }

    // MARK: locations (always on this iPad)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Redline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var dataFile: URL { directory.appendingPathComponent("redline.json") }
    /// Library PDFs (new markups, appended copies) live in Documents/PDFs so they show in the Files app.
    var pdfDirectory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PDFs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: load · save

    /// Coordinated read: an iCloud Drive file that is not downloaded yet is fetched first.
    static func load(from url: URL) -> RedlineData? {
        var bytes: Data? = nil
        var err: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in bytes = try? Data(contentsOf: u) }
        return bytes.flatMap { try? RedlineData.decode($0) }
    }

    func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard dirty else { return }
        do {
            let bytes = try store.data.encode()
            try bytes.write(to: LibraryHub.dataFile, options: .atomic)
            dirty = false
            if syncFolder != nil { scheduleSync(after: 3) }
        } catch {
            print("Redline: save failed — \(error)")
        }
    }

    // MARK: sync folder

    /// Starts mirroring the library to `folder` (nil stops). Returns an error message, or nil.
    func setSyncFolder(_ folder: URL?) -> String? {
        if let folder {
            _ = folder.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: folder.path) else { return "Couldn't read that folder" }
            guard let bm = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return "Couldn't keep access to that folder" }
            UserDefaults.standard.set(bm, forKey: LibraryHub.syncBookmarkKey)
            syncFolder?.stopAccessingSecurityScopedResource()
            syncFolder = folder
            watchSyncFile()
            syncNow()
        } else {
            UserDefaults.standard.removeObject(forKey: LibraryHub.syncBookmarkKey)
            syncFolder?.stopAccessingSecurityScopedResource()
            syncFolder = nil
            syncNote = ""
            lastSync = nil
            watchSyncFile()
        }
        return nil
    }

    /// Coming to the foreground: pick up what other iPads wrote (at most every 20 s).
    func foreground() {
        guard syncFolder != nil else { return }
        if let t = lastForegroundSync, Date().timeIntervalSince(t) < 20 { return }
        lastForegroundSync = Date()
        syncNow()
    }

    private func scheduleSync(after seconds: Double) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    private func watchSyncFile() {
        if let p = presenter { NSFileCoordinator.removeFilePresenter(p); presenter = nil }
        guard let folder = syncFolder else { return }
        let p = PDFFilePresenter(url: folder.appendingPathComponent("redline.json")) { [weak self] in
            guard let self else { return }
            if let w = self.lastPush, Date().timeIntervalSince(w) < 3 { return }   // our own write
            self.scheduleSync(after: 1)
        }
        NSFileCoordinator.addFilePresenter(p)
        presenter = p
    }

    /// Pull (merge the folder's library into ours), push (write ours back), and copy PDFs whichever way is newer.
    func syncNow() {
        guard let folder = syncFolder else { return }
        saveNow()
        let remoteJSON = folder.appendingPathComponent("redline.json")
        var notes: [String] = []
        if let remote = LibraryHub.load(from: remoteJSON) {
            if merge(remote) {
                reloadTick += 1
                for app in apps { app.reconcileAfterReload() }
                dirty = true
                saveNow()
            }
        }
        if let bytes = try? store.data.encode() {
            if !LibraryHub.write(bytes, to: remoteJSON) { notes.append("couldn't write the library file") }
            lastPush = Date()
        }
        syncPDFs(remoteDir: folder.appendingPathComponent("PDFs", isDirectory: true), notes: &notes)
        lastSync = Date()
        syncNote = notes.isEmpty ? "" : notes.joined(separator: " · ")
    }

    /// Newer wins per document; a deletion wins over copies older than it. Returns true when ours changed.
    private func merge(_ remote: RedlineData) -> Bool {
        var local = store.data
        var changed = false
        var tomb = local.deleted ?? [:]
        for (id, d) in remote.deleted ?? [:] { if (tomb[id] ?? .distantPast) < d { tomb[id] = d } }
        for rd in remote.docs {
            if let t = tomb[rd.id], t > rd.modified { continue }
            if let i = local.docs.firstIndex(where: { $0.id == rd.id }) {
                if rd.modified.timeIntervalSince(local.docs[i].modified) > 0.5 { local.docs[i] = rd; changed = true }
            } else {
                // A PDF opened in place on the other iPad has no file here: leave it there.
                if let f = rd.pdfFile, f.hasPrefix("ext:") { continue }
                local.docs.append(rd); changed = true
            }
        }
        let before = local.docs.count
        local.docs.removeAll { d in (tomb[d.id] ?? .distantPast) > d.modified }
        if local.docs.count != before { changed = true }
        if tomb != (local.deleted ?? [:]) { local.deleted = tomb; changed = true }
        if changed { store = RedlineStore(data: local) }
        return changed
    }

    private func syncPDFs(remoteDir: URL, notes: inout [String]) {
        try? FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        let localDir = pdfDirectory
        let fm = FileManager.default
        let localNames = ((try? fm.contentsOfDirectory(atPath: localDir.path)) ?? []).filter { $0.lowercased().hasSuffix(".pdf") }
        let remoteNames = ((try? fm.contentsOfDirectory(atPath: remoteDir.path)) ?? []).filter { $0.lowercased().hasSuffix(".pdf") }
        func date(_ u: URL) -> Date? { (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }
        for name in Set(localNames).union(remoteNames) {
            let l = localDir.appendingPathComponent(name), r = remoteDir.appendingPathComponent(name)
            let ld = date(l), rd = date(r)
            if let ld, rd == nil || ld.timeIntervalSince(rd!) > 1 {
                if LibraryHub.copy(l, to: r) { try? fm.setAttributes([.modificationDate: ld], ofItemAtPath: r.path) }
            } else if let rd, ld == nil || rd.timeIntervalSince(ld!) > 1 {
                let open = editors(for: name)
                if open.contains(where: { $0.mk.dirty }) { notes.append("\(name) has unsaved edits here; not replaced"); continue }
                if LibraryHub.copy(r, to: l) {
                    try? fm.setAttributes([.modificationDate: rd], ofItemAtPath: l.path)
                    pdf.noteSaved(name)
                    if !open.isEmpty { reloadPDF(name) } else { pdf.reload(name) }
                }
            }
        }
    }

    private static func write(_ bytes: Data, to url: URL) -> Bool {
        var ok = false
        var err: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in ok = (try? bytes.write(to: u, options: .atomic)) != nil }
        return ok && err == nil
    }

    private static func copy(_ src: URL, to dst: URL) -> Bool {
        var ok = false
        var err: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: src, options: [], writingItemAt: dst, options: .forReplacing, error: &err) { s, d in
            try? FileManager.default.removeItem(at: d)
            ok = (try? FileManager.default.copyItem(at: s, to: d)) != nil
        }
        return ok && err == nil
    }
}
