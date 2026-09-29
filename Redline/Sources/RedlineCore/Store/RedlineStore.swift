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
}
