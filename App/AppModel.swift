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
    /// Library folder the new document lands in.
    var folder: String = ""
    /// Notebook cover colour.
    var coverColor: String = Covers.palette[0]

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
    /// Documents open in the workspace, in tab order; each keeps its editor (tool, page, zoom, undo) while open.
    var openDocs: [ID] = []
    @ObservationIgnored private var editors: [ID: WorkspaceModel] = [:]

    var settingsOpen = false
    var settingsTab: SettingsTab = .general
    var settingsPaletteID: ID? = nil
    var settingsSwatch = 0

    /// Home: nil shows the three-tool overview; a type shows that tool's full library.
    var homeShelf: DocumentType? = nil
    var homeQuery = ""
    var homeSort: HomeSort = .recent
    /// Markups library location.
    var library: LibraryLocation = .folder("")


    var newDraft: NewDocumentDraft? = nil
    var pendingDelete: ID? = nil

    var toast: String? = nil
    private var toastTask: Task<Void, Never>? = nil
    private var saveTask: Task<Void, Never>? = nil

    let pdf = PDFService()

    init() {
        store = RedlineStore(data: AppModel.load() ?? Seed.data())
        resolveExternalPDFs()
    }

    /// Re-attaches PDFs that were opened in place (security-scoped bookmarks) so they load, render and save where they live.
    private func resolveExternalPDFs() {
        for d in store.data.docs where d.type == .markup {
            guard let f = d.pdfFile, pdf.isExternal(f), let bm = d.pdfBookmark else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            pdf.register(f, url: url)
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                store.patch(d.id) { $0.pdfBookmark = fresh }
            }
        }
    }

    /// Opens PDFs where they live (Files, iCloud Drive, other providers): no copy, edits are written back in place.
    /// A PDF that is already in the library just opens. Returns the id of the last document opened.
    @discardableResult
    func openInPlace(_ urls: [URL], folder: String = "") -> ID? {
        var last: ID? = nil
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let std = url.standardizedFileURL
            if let existing = store.data.docs.first(where: { d in d.pdfFile.flatMap { pdf.externalURL($0) }?.standardizedFileURL == std
                || (d.pdfFile.map { !pdf.isExternal($0) && pdf.url(for: $0).standardizedFileURL == std } ?? false) }) {
                last = existing.id
                continue
            }
            _ = url.startAccessingSecurityScopedResource()   // kept while the document stays in the library
            guard let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { flash("Couldn't open \(url.lastPathComponent)"); continue }
            let key = "ext:" + IDGen.make()
            pdf.register(key, url: url)
            guard let doc = pdf.document(key), doc.pageCount > 0, let first = doc.page(at: 0) else { pdf.forget(key); flash("Couldn't open \(url.lastPathComponent)"); continue }
            let d = store.createDocument(type: .markup, name: url.deletingPathExtension().lastPathComponent, pageCount: doc.pageCount, pdfFile: key)
            store.patch(d.id) { $0.sheetSize = PDFService.canvasSize(for: first); $0.folder = folder; $0.pdfBookmark = bm }
            last = d.id
        }
        scheduleSave()
        return last
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

    /// Writes every pending edit now: open PDFs (their debounced save) and the JSON store.
    func flushSaves() {
        for e in editors.values where e.isPDF { e.mkSaveNow() }
        saveNow()
    }

    func openDocument(_ id: ID) {
        guard store.document(id) != nil else { return }
        if let cur = editor, cur.docID != id, cur.isPDF { cur.mkSaveNow() }
        store.noteOpened(id)
        if !openDocs.contains(id) { openDocs.append(id) }
        let e = editors[id] ?? WorkspaceModel(app: self, docID: id)
        editors[id] = e
        editor = e
        screen = .workspace(id)
    }

    /// Back to Home; open documents stay open (their tabs are waiting when you come back).
    func goHome() {
        if let cur = editor, cur.isPDF { cur.mkSaveNow() }
        editor = nil
        screen = .home
        scheduleSave()
    }

    /// Closes a tab. Pending PDF edits are written first. Switches to the neighbouring tab, or Home.
    func closeDocument(_ id: ID) {
        if let e = editors[id], e.isPDF { e.mkSaveNow() }
        let wasCurrent = editor?.docID == id
        let idx = openDocs.firstIndex(of: id) ?? 0
        openDocs.removeAll { $0 == id }
        editors[id] = nil
        if wasCurrent {
            if openDocs.isEmpty { goHome() }
            else { openDocument(openDocs[min(idx, openDocs.count - 1)]) }
        }
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
        created.folder = d.folder
        if d.type == .journal { created.coverColor = d.coverColor }
        if d.type == .markup && d.pdfFile == nil {
            // A new markup is a real PDF file on the chosen paper.
            let size = d.landscape ? CGSize(width: 792, height: 612) : CGSize(width: 612, height: 792)
            if let file = AppModel.createBlankPDF(name: created.name, size: size, template: d.template, paper: d.paper) {
                created.pdfFile = file
                created.pages = [Page.markup(label: "Page 1", artwork: "pdf", pdfPageIndex: 0)]
                created.sheetSize = Size(1000, (1000 * size.height / size.width).rounded())
            }
        }
        store.patch(doc.id) { $0 = created }
        newDraft = nil
        scheduleSave()
        openDocument(doc.id)
    }

    func deleteDocument(_ id: ID) {
        if openDocs.contains(id) { editors[id] = nil; openDocs.removeAll { $0 == id }; if editor?.docID == id { editor = nil; screen = .home } }
        if let doc = store.document(id), let f = doc.pdfFile, !store.data.docs.contains(where: { $0.id != id && $0.pdfFile == f }) {
            // Removing a markup only forgets a PDF opened in place; it is never deleted from where it lives.
            if pdf.isExternal(f) { pdf.externalURL(f)?.stopAccessingSecurityScopedResource(); pdf.forget(f) }
            else { pdf.forget(f); try? FileManager.default.removeItem(at: pdf.url(for: f)) }
        }
        store.deleteDocument(id)
        scheduleSave()
    }

    /// Browse Files…: open the picked PDFs in place; a single pick opens straight away.
    func importPDFs(_ urls: [URL], into folder: String) {
        guard let last = openInPlace(urls, folder: folder) else { flash("Nothing opened"); return }
        if urls.count == 1 { openDocument(last) } else { flash("Added " + Formatting.plural(urls.count, "PDF")) }
    }

    /// "Open in Redline" from Files / the share sheet: the PDF opens in place.
    func openPDF(from url: URL) {
        guard url.pathExtension.lowercased() == "pdf", let id = openInPlace([url]) else {
            flash("Redline can open PDF files")
            return
        }
        settings.shelf = .markup
        settingsOpen = false
        openDocument(id)
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

    // MARK: blank PDFs

    /// One-page PDF data on the given paper (template drawn in light ink).
    static func blankPDFData(size: CGSize, template: PageTemplate, paper: Paper) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { c in
            c.beginPage()
            let cg = c.cgContext
            cg.setFillColor(UIColor(hex: paper.hex).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let ink = (paper.isDark ? UIColor.white : UIColor.black).withAlphaComponent(template.alpha)
            let s = template.spacing * size.width / 1000 * 1.6
            guard template != .blank, s > 0 else { return }
            cg.setStrokeColor(ink.cgColor); cg.setFillColor(ink.cgColor); cg.setLineWidth(0.6)
            switch template {
            case .dot:
                var y = s
                while y < size.height { var x = s; while x < size.width { cg.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)); x += s }; y += s }
            case .grid:
                var x = s; while x < size.width { cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: size.height)); x += s }
                var y = s; while y < size.height { cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: size.width, y: y)); y += s }
                cg.strokePath()
            case .lined:
                var y = s; while y < size.height { cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: size.width, y: y)); y += s }
                cg.strokePath()
            case .blank: break
            }
        }
    }

    /// Writes a new blank PDF into Documents/PDFs and returns its file name.
    static func createBlankPDF(name: String, size: CGSize, template: PageTemplate, paper: Paper) -> String? {
        let base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".pdf", with: "")
        var file = base + ".pdf"
        var n = 2
        while FileManager.default.fileExists(atPath: PDFService.directory.appendingPathComponent(file).path) { file = "\(base) \(n).pdf"; n += 1 }
        let data = blankPDFData(size: size, template: template, paper: paper)
        do { try data.write(to: PDFService.directory.appendingPathComponent(file), options: .atomic); return file } catch { return nil }
    }

    /// A single blank page to insert into an existing PDF.
    static func blankPage(size: CGSize, template: PageTemplate, paper: Paper) -> PDFPage? {
        PDFDocument(data: blankPDFData(size: size, template: template, paper: paper))?.page(at: 0)
    }
}
