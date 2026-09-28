// Colour palettes managed in Settings and shown in every Style Popover.

import Foundation

public struct Palette: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var name: String
    public var colors: [String]
    public var builtIn: Bool
    public init(id: ID = IDGen.make(), name: String, colors: [String], builtIn: Bool = false) {
        self.id = id; self.name = name; self.colors = colors; self.builtIn = builtIn
    }
}

public struct PaletteStore: Codable, Sendable, Equatable {
    public var palettes: [Palette]
    public var defaultID: ID

    public static let builtIns: [Palette] = [
        Palette(id: "redline", name: "Redline", colors: ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93", "#1C1C1E"], builtIn: true),
        Palette(id: "trades", name: "Trades", colors: ["#C0392B", "#2980B9", "#27AE60", "#E67E22", "#8E44AD", "#16A085", "#D4AC0D", "#7F8C8D", "#2C3E50", "#6D4C41", "#E84393", "#0984E3"], builtIn: true),
        Palette(id: "pastel", name: "Pastel", colors: ["#FFADAD", "#FFD6A5", "#FDFFB6", "#CAFFBF", "#9BF6FF", "#A0C4FF", "#BDB2FF", "#FFC6FF", "#E2E2E2", "#B5EAD7", "#F1C0E8", "#CFBAF0"], builtIn: true),
        Palette(id: "grays", name: "Grayscale", colors: ["#FFFFFF", "#E5E5EA", "#C7C7CC", "#AEAEB2", "#8E8E93", "#636366", "#48484A", "#3A3A3C", "#2C2C2E", "#1C1C1E", "#000000"], builtIn: true)
    ]

    public static let newPaletteSeed: [String] = ["#FF3B30", "#007AFF", "#34C759", "#FFCC00"]

    public init(palettes: [Palette] = PaletteStore.builtIns, defaultID: ID = "redline") {
        self.palettes = palettes
        self.defaultID = palettes.contains { $0.id == defaultID } ? defaultID : (palettes.first?.id ?? "redline")
    }

    public var defaultPalette: Palette { palettes.first { $0.id == defaultID } ?? palettes[0] }

    /// Default palette first, then the rest in list order — the order the Style Popover shows.
    public var ordered: [Palette] {
        let d = defaultPalette
        return [d] + palettes.filter { $0.id != d.id }
    }

    /// Built-ins first, then custom — the Settings list order.
    public var listed: [Palette] { palettes.filter(\.builtIn) + palettes.filter { !$0.builtIn } }

    public func palette(_ id: ID) -> Palette? { palettes.first { $0.id == id } }

    @discardableResult
    public mutating func addNew() -> Palette {
        let p = Palette(name: "New palette", colors: PaletteStore.newPaletteSeed)
        palettes.append(p)
        return p
    }
    @discardableResult
    public mutating func duplicate(_ id: ID) -> Palette? {
        guard let src = palette(id) else { return nil }
        let p = Palette(name: src.name + " copy", colors: src.colors)
        palettes.append(p)
        return p
    }
    public mutating func delete(_ id: ID) {
        guard let p = palette(id), !p.builtIn else { return }
        palettes.removeAll { $0.id == id }
        if defaultID == id { defaultID = palettes.first?.id ?? "redline" }
    }
    public mutating func makeDefault(_ id: ID) {
        if palette(id) != nil { defaultID = id }
    }
    public mutating func rename(_ id: ID, to name: String) {
        edit(id) { $0.name = name }
    }
    public mutating func setSwatch(_ id: ID, index: Int, hex: String) {
        edit(id) { p in
            guard p.colors.indices.contains(index) else { return }
            p.colors[index] = HexColor.normalize(hex) ?? p.colors[index]
        }
    }
    @discardableResult
    public mutating func addSwatch(_ id: ID, hex: String = "#8E8E93") -> Int {
        var n = 0
        edit(id) { p in p.colors.append(hex); n = p.colors.count - 1 }
        return n
    }
    public mutating func removeSwatch(_ id: ID, index: Int) {
        edit(id) { p in
            guard p.colors.count > 2, p.colors.indices.contains(index) else { return }
            p.colors.remove(at: index)
        }
    }
    private mutating func edit(_ id: ID, _ body: (inout Palette) -> Void) {
        guard let i = palettes.firstIndex(where: { $0.id == id }), !palettes[i].builtIn else { return }
        body(&palettes[i])
    }
}
