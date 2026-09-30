// Top-level state: documents, settings, palettes, presets, plus per-document
// undo history (not persisted). The app wraps this in an observable object.

import Foundation

public struct FavoritesTab: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: ID
    public var name: String
    /// Tool raw values; a tool may appear more than once ("pen#2") to hold different presets.
    public var pins: [String]
    public init(id: ID = IDGen.make(), name: String, pins: [String]) { self.id = id; self.name = name; self.pins = pins }

    public var tools: [Tool] { pins.compactMap { Tool(rawValue: String($0.split(separator: "#")[0])) } }
}

/// Whether a finger may ink with the pens. `auto` blocks finger inking while an Apple Pencil is in use.
public enum FingerDrawing: String, Codable, Sendable, CaseIterable, Hashable {
    case auto = "Auto", always = "Always", never = "Never"
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var author: String
    public var theme: ThemePreference
    public var shelf: DocumentType
    public var favorites: [FavoritesTab]
    /// Sheet appearance for markups: white paper or blueprint blue.
    public var blueprint: Bool
    /// Optional so older saved settings still decode; see `fingerDrawingMode`.
    public var fingerDrawing: FingerDrawing?
    /// Library folders created by the user (paths like "Projects/Meridian"), including empty ones.
    public var folders: [String]?
    public var fingerDrawingMode: FingerDrawing {
        get { fingerDrawing ?? .auto }
        set { fingerDrawing = newValue }
    }

    public init(author: String = "", theme: ThemePreference = .system, shelf: DocumentType = .markup,
                favorites: [FavoritesTab] = [FavoritesTab(name: "★", pins: ToolCatalog.defaultFavorites.map(\.rawValue))], blueprint: Bool = false) {
        self.author = author; self.theme = theme; self.shelf = shelf; self.favorites = favorites; self.blueprint = blueprint
    }

    public var authorOrDefault: String { author.isEmpty ? "You" : author }
}

public struct RedlineData: Codable, Sendable, Equatable {
    public var version: Int
    public var docs: [Document]
    public var settings: AppSettings
    public var palettes: PaletteStore
    public var styles: ToolStyles

    public static let currentVersion = 1

    public init(docs: [Document] = [], settings: AppSettings = AppSettings(), palettes: PaletteStore = PaletteStore(), styles: ToolStyles = ToolStyles()) {
        self.version = RedlineData.currentVersion
        self.docs = docs; self.settings = settings; self.palettes = palettes; self.styles = styles
    }

    public static func decode(_ data: Data) throws -> RedlineData {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try dec.decode(RedlineData.self, from: data)
    }
    public func encode() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return try enc.encode(self)
    }
}

public struct RedlineStore: Sendable {
    public var data: RedlineData
    public private(set) var histories: [ID: History<Document>] = [:]

    public init(data: RedlineData) { self.data = data }

    public var docs: [Document] {
        get { data.docs }
        set { data.docs = newValue }
    }

    public func document(_ id: ID) -> Document? { data.docs.first { $0.id == id } }
    public func index(of id: ID) -> Int? { data.docs.firstIndex { $0.id == id } }

    /// Undoable mutation.
    public mutating func mutate(_ id: ID, _ body: (inout Document) -> Void) {
        guard let i = index(of: id) else { return }
        var h = histories[id] ?? History()
        h.record(data.docs[i])
        histories[id] = h
        body(&data.docs[i])
        data.docs[i].modified = Date()
    }

    /// Non-undoable mutation (slider drags, text typing).
    public mutating func patch(_ id: ID, _ body: (inout Document) -> Void) {
        guard let i = index(of: id) else { return }
        body(&data.docs[i])
    }

    public func canUndo(_ id: ID) -> Bool { histories[id]?.canUndo ?? false }
    public func canRedo(_ id: ID) -> Bool { histories[id]?.canRedo ?? false }

    @discardableResult
    public mutating func undo(_ id: ID) -> Bool {
        guard let i = index(of: id), var h = histories[id], let v = h.undo(current: data.docs[i]) else { return false }
        histories[id] = h
        data.docs[i] = v
        return true
    }

    @discardableResult
    public mutating func redo(_ id: ID) -> Bool {
        guard let i = index(of: id), var h = histories[id], let v = h.redo(current: data.docs[i]) else { return false }
        histories[id] = h
        data.docs[i] = v
        return true
    }

    // MARK: documents

    @discardableResult
    public mutating func createDocument(type: DocumentType, name rawName: String, template: PageTemplate = .lined, paper: Paper = .cream,
                                        pageCount: Int = 3, pdfFile: String? = nil, now: Date = Date()) -> Document {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? type.untitledName : trimmed
        let doc: Document
        switch type {
        case .markup:
            let pages = (0..<max(1, pageCount)).map { i in Page.markup(label: "Page \(i + 1)", artwork: pdfFile == nil ? "blank" : "pdf", pdfPageIndex: pdfFile == nil ? nil : i, created: now) }
            doc = Document(type: .markup, name: name, created: now, pages: pages, pdfFile: pdfFile)
        case .drawing:
            doc = Document(type: .drawing, name: name, created: now, pages: [.drawing(created: now)], paper: paper)
        case .journal:
            // Page 0 is the cover: blank, drawable, rendered as the notebook's thumbnail.
            let cover = Page.journal(template: .blank, paper: paper == .white ? .grey : paper, created: now)
            doc = Document(type: .journal, name: name, created: now, pages: [cover, .journal(template: template, paper: paper, created: now)])
        }
        data.docs.insert(doc, at: 0)
        return doc
    }

    public mutating func deleteDocument(_ id: ID) {
        data.docs.removeAll { $0.id == id }
        histories[id] = nil
    }

    public mutating func renameDocument(_ id: ID, to name: String) {
        patch(id) { $0.name = name }
    }

    public func documents(on shelf: DocumentType) -> [Document] {
        data.docs.filter { $0.type == shelf }.sorted { $0.modified > $1.modified }
    }

    public func count(on shelf: DocumentType) -> Int { data.docs.filter { $0.type == shelf }.count }

    // MARK: library (folders, favorites, recents)

    public func recents(on shelf: DocumentType, limit: Int = 20) -> [Document] {
        data.docs.filter { $0.type == shelf && $0.lastOpened != nil }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            .prefix(limit).map { $0 }
    }

    public func favorites(on shelf: DocumentType) -> [Document] {
        documents(on: shelf).filter(\.isFavorite)
    }

    /// Documents directly inside a folder.
    public func documents(on shelf: DocumentType, in folder: String) -> [Document] {
        documents(on: shelf).filter { $0.folderPath == folder }
    }

    /// Every folder path in use (created or implied by documents), sorted.
    public var allFolders: [String] {
        var set = Set(data.settings.folders ?? [])
        for d in data.docs { var p = d.folderPath; while !p.isEmpty { set.insert(p); p = RedlineStore.parent(of: p) } }
        for f in Array(set) { var p = RedlineStore.parent(of: f); while !p.isEmpty { set.insert(p); p = RedlineStore.parent(of: p) } }
        return set.sorted()
    }

    /// Immediate subfolders of a folder ("" = root).
    public func subfolders(of folder: String) -> [String] {
        allFolders.filter { RedlineStore.parent(of: $0) == folder }
    }

    public static func parent(of path: String) -> String {
        guard let i = path.lastIndex(of: "/") else { return "" }
        return String(path[..<i])
    }
    public static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Creates a folder; returns its path (deduplicated with " 2", " 3"…).
    @discardableResult
    public mutating func createFolder(named raw: String, in parent: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let name = base.isEmpty ? "New Folder" : base
        var candidate = parent.isEmpty ? name : parent + "/" + name
        var n = 2
        let existing = Set(allFolders)
        while existing.contains(candidate) { candidate = (parent.isEmpty ? "" : parent + "/") + "\(name) \(n)"; n += 1 }
        var fs = data.settings.folders ?? []
        fs.append(candidate)
        data.settings.folders = fs
        return candidate
    }

    public mutating func renameFolder(_ path: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        let parent = RedlineStore.parent(of: path)
        let newPath = parent.isEmpty ? name : parent + "/" + name
        guard newPath != path, !allFolders.contains(newPath) else { return }
        func remap(_ p: String) -> String {
            if p == path { return newPath }
            if p.hasPrefix(path + "/") { return newPath + p.dropFirst(path.count) }
            return p
        }
        data.settings.folders = (data.settings.folders ?? []).map(remap)
        for i in data.docs.indices where data.docs[i].folder != nil { data.docs[i].folder = remap(data.docs[i].folderPath) }
    }

    /// Deletes a folder; its documents and subfolders move up to the parent.
    public mutating func deleteFolder(_ path: String) {
        let parent = RedlineStore.parent(of: path)
        func remap(_ p: String) -> String {
            if p == path { return parent }
            if p.hasPrefix(path + "/") { let rest = String(p.dropFirst(path.count + 1)); return parent.isEmpty ? rest : parent + "/" + rest }
            return p
        }
        data.settings.folders = (data.settings.folders ?? []).filter { $0 != path }.map(remap)
        for i in data.docs.indices { data.docs[i].folder = remap(data.docs[i].folderPath) }
    }

    public mutating func move(_ id: ID, toFolder folder: String) {
        patch(id) { $0.folder = folder }
    }

    public mutating func setFavorite(_ id: ID, _ on: Bool) {
        patch(id) { $0.favorite = on }
    }

    public mutating func noteOpened(_ id: ID, now: Date = Date()) {
        patch(id) { $0.lastOpened = now }
    }
}
