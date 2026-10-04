import SwiftUI
import PDFKit
import RedlineCore

/// Everything shared between windows: the library store and its file, the PDF service and the clipboard.
/// Each window (scene) has its own `AppModel` for navigation and open documents; all of them read and write here.
@MainActor
@Observable
final class LibraryHub {
    static let shared = LibraryHub()

    var store: RedlineStore
    let pdf = PDFService()
    /// Copied annotations (detached clones) — paste into any open PDF, in any window.
    var clipboard: [PDFAnnotation] = []
    /// The folder the user picked for the library (for example in iCloud Drive), or nil for the app's own storage.
    private(set) var customFolder: URL? = nil
    /// Bumped when the library file was replaced by another device / app and reloaded.
    private(set) var reloadTick = 0

    @ObservationIgnored private var saveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var presenter: PDFFilePresenter? = nil
    @ObservationIgnored private var lastWrite: Date? = nil
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var scenes: [WeakScene] = []
    @ObservationIgnored var resolvedExternal = false

    private struct WeakScene { weak var app: AppModel? }
    static let folderBookmarkKey = "redline.libraryFolderBookmark"

    private init() {
        var folder: URL? = nil
        if let bm = UserDefaults.standard.data(forKey: LibraryHub.folderBookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                if FileManager.default.isReadableFile(atPath: url.path) {
                    folder = url
                    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(fresh, forKey: LibraryHub.folderBookmarkKey)
                    }
                }
            }
        }
        customFolder = folder
        store = RedlineStore(data: LibraryHub.load(from: LibraryHub.dataFile(in: folder)) ?? Seed.data())
        watch()
    }

    // MARK: windows

    func register(_ app: AppModel) { scenes.append(WeakScene(app: app)); scenes.removeAll { $0.app == nil } }
    var apps: [AppModel] { scenes.compactMap(\.app) }
    func isOpenElsewhere(_ id: ID, than app: AppModel) -> Bool { apps.contains { $0 !== app && $0.openDocs.contains(id) } }
    var anyDocumentOpen: Bool { apps.contains { !$0.openDocs.isEmpty } }

    // MARK: locations

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Redline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var defaultPDFDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PDFs", isDirectory: true)
    }
    static func dataFile(in folder: URL?) -> URL { (folder ?? defaultDirectory).appendingPathComponent("redline.json") }
    static func pdfDirectory(in folder: URL?) -> URL {
        let d = folder.map { $0.appendingPathComponent("PDFs", isDirectory: true) } ?? defaultPDFDirectory
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    var dataFile: URL { LibraryHub.dataFile(in: customFolder) }
    /// Library PDFs (new markups, extracted pages) live here; they show in the Files app.
    var pdfDirectory: URL { LibraryHub.pdfDirectory(in: customFolder) }

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
            var err: NSError? = nil
            var failed: Error? = nil
            NSFileCoordinator().coordinate(writingItemAt: dataFile, options: .forReplacing, error: &err) { u in
                do { try bytes.write(to: u, options: .atomic) } catch { failed = error }
            }
            if let e = err ?? failed.map({ $0 as NSError }) { print("Redline: save failed — \(e)"); return }
            dirty = false
            lastWrite = Date()
        } catch {
            print("Redline: save failed — \(error)")
        }
    }

    /// Another device (through iCloud Drive) or app replaced the library file: take it, unless edits here are
    /// still unsaved (then the next save writes over it — last writer wins).
    private func watch() {
        if let p = presenter { NSFileCoordinator.removeFilePresenter(p) }
        let p = PDFFilePresenter(url: dataFile) { [weak self] in self?.externalChange() }
        NSFileCoordinator.addFilePresenter(p)
        presenter = p
    }
    private func externalChange() {
        if let w = lastWrite, Date().timeIntervalSince(w) < 2 { return }   // our own write
        if dirty { return }
        guard let data = LibraryHub.load(from: dataFile) else { return }
        store = RedlineStore(data: data)
        reloadTick += 1
        for app in apps { app.reconcileAfterReload() }
    }

    // MARK: moving the library

    /// Switches the library to `folder` (nil = back to the app's storage). A folder that already holds a Redline
    /// library (another iPad's) is adopted; an empty one receives a copy of the current library. Returns an error
    /// message, or nil when done.
    func useFolder(_ folder: URL?) -> String? {
        saveNow()
        let oldPDFs = pdfDirectory
        if let folder {
            _ = folder.startAccessingSecurityScopedResource()
            guard FileManager.default.isReadableFile(atPath: folder.path) else { return "Couldn't read that folder" }
            guard let bm = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return "Couldn't keep access to that folder" }
            let target = LibraryHub.dataFile(in: folder)
            let existing = LibraryHub.load(from: target)
            if existing == nil {
                guard let bytes = try? store.data.encode(), LibraryHub.write(bytes, to: target) else { return "Couldn't write the library there" }
            }
            LibraryHub.copyPDFs(from: oldPDFs, to: LibraryHub.pdfDirectory(in: folder))
            UserDefaults.standard.set(bm, forKey: LibraryHub.folderBookmarkKey)
            customFolder?.stopAccessingSecurityScopedResource()
            customFolder = folder
            if let existing { store = RedlineStore(data: existing) }
        } else {
            guard customFolder != nil else { return nil }
            let target = LibraryHub.dataFile(in: nil)
            guard let bytes = try? store.data.encode(), LibraryHub.write(bytes, to: target) else { return "Couldn't write the library" }
            LibraryHub.copyPDFs(from: oldPDFs, to: LibraryHub.pdfDirectory(in: nil))
            UserDefaults.standard.removeObject(forKey: LibraryHub.folderBookmarkKey)
            customFolder?.stopAccessingSecurityScopedResource()
            customFolder = nil
        }
        pdf.resetCaches()
        dirty = false
        lastWrite = Date()
        reloadTick += 1
        watch()
        return nil
    }

    private static func write(_ bytes: Data, to url: URL) -> Bool {
        var ok = false
        var err: NSError? = nil
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in ok = (try? bytes.write(to: u, options: .atomic)) != nil }
        return ok && err == nil
    }

    /// Copies library PDFs that the destination doesn't have yet.
    private static func copyPDFs(from src: URL, to dst: URL) {
        guard src != dst, let files = try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension.lowercased() == "pdf" {
            let to = dst.appendingPathComponent(f.lastPathComponent)
            if FileManager.default.fileExists(atPath: to.path) { continue }
            var err: NSError? = nil
            NSFileCoordinator().coordinate(writingItemAt: to, options: .forReplacing, error: &err) { u in try? FileManager.default.copyItem(at: f, to: u) }
        }
    }
}
