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
    var sampleSet: Bool = true

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

    /// Rendered PDF pages keyed by "file#index".
    private var pdfCache: [String: UIImage] = [:]

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
        if d.type == .markup && d.pdfFile == nil {
            // Sample plan set: three seeded sheets.
            created.pages = [Page.markup(label: "A-101 Floor Plan", artwork: "plan"),
                             Page.markup(label: "A-201 Elevations", artwork: "elev"),
                             Page.markup(label: "S-301 Wall Details", artwork: "detail")]
            store.patch(doc.id) { $0 = created }
        }
        newDraft = nil
        scheduleSave()
        openDocument(doc.id)
    }

    func deleteDocument(_ id: ID) {
        if let doc = store.document(id), let f = doc.pdfFile {
            try? FileManager.default.removeItem(at: AppModel.pdfDirectory.appendingPathComponent(f))
        }
        store.deleteDocument(id)
        scheduleSave()
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
    static var pdfDirectory: URL {
        let d = directory.appendingPathComponent("PDFs", isDirectory: true)
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

    /// Copies a picked PDF into the app's store. Returns (stored file name, page count).
    func importPDF(from url: URL) -> (file: String, pages: Int)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = IDGen.make() + ".pdf"
        let dest = AppModel.pdfDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            return nil
        }
        guard let doc = PDFDocument(url: dest), doc.pageCount > 0 else {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
        return (name, doc.pageCount)
    }

    func pdfImage(file: String, pageIndex: Int) -> UIImage? {
        let key = "\(file)#\(pageIndex)"
        if let img = pdfCache[key] { return img }
        let url = AppModel.pdfDirectory.appendingPathComponent(file)
        guard let doc = PDFDocument(url: url), let page = doc.page(at: pageIndex) else { return nil }
        let img = page.thumbnail(of: CGSize(width: 2000, height: 1414), for: .mediaBox)
        pdfCache[key] = img
        return img
    }
}
