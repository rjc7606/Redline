import SwiftUI
import PDFKit
import RedlineCore

enum Screen: Equatable {
    case home
    case workspace(ID)
}

enum SettingsTab: String, CaseIterable {
    case general, palettes
    var label: String { self == .general ? "General" : "Color palettes" }
    var symbol: String { self == .general ? "person" : "paintpalette" }
}

struct NewDocumentDraft {
    var type: DocumentType
    var name: String = ""
    var template: PageTemplate
    var paper: Paper
    /// Imported PDF (file name inside the PDF store) and its page count.
    var pdfFile: String? = nil
    var pdfPages: Int? = nil
    var sheetSize: Size? = nil
    var landscape: Bool = false

    init(type: DocumentType) {
        self.type = type
        template = type == .journal ? .lined : .blank
        paper = type == .journal ? .cream : .white
    }
}

/// App-wide state: the store, navigation, theme, persistence and toasts.
@MainActor
@Observable
final class AppModel {
    var store: RedlineStore
    var screen: Screen = .home
    var editor: WorkspaceModel? = nil

    var settingsOpen = false
    var settingsTab: SettingsTab = .general
    var settingsPaletteID: ID? = nil
    var settingsSwatch = 0

    var newDraft: NewDocumentDraft? = nil
    var pendingDelete: ID? = nil

    var toast: String? = nil
    private var toastTask: Task<Void, Never>? = nil
    private var saveTask: Task<Void, Never>? = nil

    let pdf = PDFService()

    init() {
        store = RedlineStore(data: AppModel.load() ?? Seed.data())
    }

    // MARK: settings passthrough

    var settings: AppSettings {
        get { store.data.settings }
        set { store.data.settings = newValue; scheduleSave() }
    }
    var styles: ToolStyles {
        get { store.data.styles }
        set { store.data.styles = newValue; scheduleSave() }
    }
    var palettes: PaletteStore {
        get { store.data.palettes }
        set { store.data.palettes = newValue; scheduleSave() }
    }
    var author: String { settings.authorOrDefault }

    func theme(systemDark: Bool) -> Theme { Theme.resolve(settings.theme, systemDark: systemDark) }

    var preferredColorScheme: ColorScheme? {
        switch settings.theme { case .light: .light; case .dark: .dark; case .system: nil }
    }

    // MARK: navigation

    func openDocument(_ id: ID) {
        guard store.document(id) != nil else { return }
        editor = WorkspaceModel(app: self, docID: id)
        screen = .workspace(id)
    }

    func goHome() {
        editor = nil
        screen = .home
        scheduleSave()
    }

    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        if tab == .palettes { settingsPaletteID = palettes.defaultID; settingsSwatch = 0 }
        settingsOpen = true
    }

    // MARK: documents

    func createFromDraft() {
        guard let d = newDraft else { return }
        let doc = store.createDocument(type: d.type, name: d.name, template: d.template, paper: d.paper,
                                       pageCount: d.pdfPages ?? 3, pdfFile: d.pdfFile)
        var created = doc
        created.sheetSize = d.sheetSize
        if d.type == .markup && d.pdfFile == nil {
            var p = Page.markup(label: "Page 1")
            p.template = d.template
            created.pages = [p]
            created.sheetSize = d.landscape ? Metrics.letterLandscape : Metrics.letterPortrait
        }
        store.patch(doc.id) { $0 = created }
        newDraft = nil
        scheduleSave()
        openDocument(doc.id)
    }

    func deleteDocument(_ id: ID) {
        if let doc = store.document(id), let f = doc.pdfFile, !store.data.docs.contains(where: { $0.id != id && $0.pdfFile == f }) {
            pdf.forget(f)
            try? FileManager.default.removeItem(at: pdf.url(for: f))
        }
        store.deleteDocument(id)
        scheduleSave()
    }

    /// "Open in Redline" from Files / Share sheet: import the PDF as a new markup and open it.
    func openPDF(from url: URL) {
        guard url.pathExtension.lowercased() == "pdf", let r = importPDF(from: url) else {
            flash("Redline can open PDF files")
            return
        }
        let doc = store.createDocument(type: .markup, name: url.deletingPathExtension().lastPathComponent, pageCount: r.pages, pdfFile: r.file)
        store.patch(doc.id) { $0.sheetSize = r.sheetSize }
        settings.shelf = .markup
        settingsOpen = false
        scheduleSave()
        openDocument(doc.id)
    }

    /// Records an undoable mutation on a document and schedules a save.
    func mutate(_ id: ID, _ body: (inout Document) -> Void) {
        store.mutate(id, body)
        scheduleSave()
    }
    func patch(_ id: ID, _ body: (inout Document) -> Void) {
        store.patch(id, body)
        scheduleSave()
    }

    // MARK: toast

    func flash(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Metrics.toastSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }

    // MARK: persistence

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Redline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var dataFile: URL { directory.appendingPathComponent("redline.json") }
    /// Exports the user saves "to Files" land here (Documents/Exports, visible in the Files app).
    static var exportsDirectory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func load() -> RedlineData? {
        guard let bytes = try? Data(contentsOf: dataFile) else { return nil }
        return try? RedlineData.decode(bytes)
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            let bytes = try store.data.encode()
            try bytes.write(to: AppModel.dataFile, options: .atomic)
        } catch {
            print("Redline: save failed — \(error)")
        }
    }

    // MARK: PDF import & rendering

    /// Copies a picked PDF into Documents/PDFs (keeping its name, visible in Files).
    /// Returns the stored file name, page count and the canvas size matching page 1's aspect ratio.
    func importPDF(from url: URL) -> (file: String, pages: Int, sheetSize: Size)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        var name = base + ".pdf"
        var n = 2
        while FileManager.default.fileExists(atPath: PDFService.directory.appendingPathComponent(name).path) {
            name = "\(base) \(n).pdf"
            n += 1
        }
        let dest = PDFService.directory.appendingPathComponent(name)
        var coordError: NSError? = nil
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            copied = (try? FileManager.default.copyItem(at: readURL, to: dest)) != nil
        }
        guard copied, let doc = pdf.document(name), doc.pageCount > 0, let first = doc.page(at: 0) else {
            pdf.forget(name)
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
        return (name, doc.pageCount, PDFService.canvasSize(for: first))
    }

    func pdfImage(file: String, pageIndex: Int, canvas: Size) -> UIImage? {
        pdf.image(file: file, index: pageIndex, canvas: canvas)
    }
}
