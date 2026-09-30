// Core document model. Pure value types, no UI framework imports, so this
// builds and tests on every platform. Mirrors the shapes described in the
// handoff README ("Architecture summary → Document model").

import Foundation

public typealias ID = String

public enum IDGen {
    public static func make() -> ID { UUID().uuidString.lowercased() }
}

// MARK: - Enums

public enum DocumentType: String, Codable, Sendable, CaseIterable, Hashable {
    case markup, drawing, journal

    public var shelfLabel: String {
        switch self { case .markup: "Markups"; case .drawing: "Drawings"; case .journal: "Notes" }
    }
    public var newLabel: String {
        switch self { case .markup: "New markup"; case .drawing: "New plan set"; case .journal: "New notebook" }
    }
    public var modeLabel: String {
        switch self { case .markup: "Markup"; case .drawing: "Plan set"; case .journal: "Notes" }
    }
    public var untitledName: String {
        switch self { case .markup: "Untitled.pdf"; case .drawing: "Untitled plan set"; case .journal: "Untitled notebook" }
    }
    public var newSheetTitle: String {
        switch self { case .markup: "New markup"; case .drawing: "New plan set"; case .journal: "New notebook" }
    }
    /// Colour of the mode chip in the workspace top bar: (foreground, background alpha)
    public var modeChipHex: (fg: String, bgAlpha: Double) {
        switch self { case .markup: ("#C4554A", 0.12); case .drawing: ("#8B6BB1", 0.12); case .journal: ("#5B9A6B", 0.14) }
    }
    public var symbol: String {
        switch self { case .markup: "doc.text"; case .drawing: "ruler"; case .journal: "book.closed" }
    }
}

public enum Paper: String, Codable, Sendable, CaseIterable, Hashable {
    case white, cream, grey, blue, dark
    public var hex: String {
        switch self {
        case .white: "#ffffff"; case .cream: "#f7f0dc"; case .grey: "#e6e6ea"; case .blue: "#dfe9f5"; case .dark: "#2b2b30"
        }
    }
    public var isDark: Bool { self == .dark }
    public var label: String { rawValue.capitalized }
    /// The four page colours offered when creating a PDF.
    public static let pagePresets: [Paper] = [.white, .cream, .grey, .blue]
}

public enum PageTemplate: String, Codable, Sendable, CaseIterable, Hashable {
    case blank, dot, grid, lined
    public var label: String { rawValue.capitalized }
    /// Spacing in canvas points (dot 24, grid 28, lined 32).
    public var spacing: Double {
        switch self { case .blank: 0; case .dot: 24; case .grid: 28; case .lined: 32 }
    }
    /// Ink alpha of the template marks.
    public var alpha: Double {
        switch self { case .blank: 0; case .dot: 0.28; case .grid: 0.10; case .lined: 0.14 }
    }
}

public enum WeightMode: String, Codable, Sendable, Hashable { case constant, pressure }

public enum LineStyle: String, Codable, Sendable, CaseIterable, Hashable {
    case solid, dash, dot
    public var label: String { switch self { case .solid: "Solid"; case .dash: "Dashed"; case .dot: "Dotted" } }
}

public enum FillPattern: String, Codable, Sendable, CaseIterable, Hashable {
    case none, solid, hatch, cross, dots
    public var label: String { rawValue.capitalized }
}

public enum CommentStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case open = "Open", accepted = "Accepted", rejected = "Rejected", completed = "Completed"
    /// (foreground hex, background alpha applied to the same hex)
    public var chip: (fg: String, alpha: Double) {
        switch self {
        case .open: ("#FF9500", 0.14)
        case .accepted: ("#34C759", 0.14)
        case .rejected: ("#FF3B30", 0.12)
        case .completed: ("#8e8e93", 0.16)
        }
    }
}

public enum FieldType: String, Codable, Sendable, CaseIterable, Hashable {
    case text, area, check, radio, drop, list, date, sig, toggle
    public var label: String {
        switch self {
        case .text: "Text"; case .area: "Text area"; case .check: "Checkbox"; case .radio: "Radio"
        case .drop: "Dropdown"; case .list: "List"; case .date: "Date"; case .sig: "Signature"; case .toggle: "Toggle"
        }
    }
    public var symbol: String {
        switch self {
        case .text: "character.textbox"; case .area: "text.alignleft"; case .check: "checkmark.square"; case .radio: "circle.inset.filled"
        case .drop: "chevron.down.square"; case .list: "list.bullet"; case .date: "calendar"; case .sig: "signature"; case .toggle: "switch.2"
        }
    }
    public var defaultSize: Size {
        switch self {
        case .text: Size(180, 34); case .area: Size(200, 78); case .check: Size(28, 28); case .radio: Size(28, 28)
        case .drop: Size(180, 34); case .list: Size(180, 70); case .date: Size(160, 34); case .sig: Size(200, 44); case .toggle: Size(52, 28)
        }
    }
    public var hasOptions: Bool { self == .drop || self == .list }
    public var isToggleLike: Bool { self == .check || self == .radio || self == .toggle }
    public var cornerRadius: Double { self == .radio || self == .toggle ? 14 : 6 }
    /// Types offered in the Studio Forms panel (Markup sidebar).
    public static let panelTypes: [FieldType] = [.text, .check, .radio, .drop, .list, .date, .sig]
}

public enum ValidationRule: String, Codable, Sendable, CaseIterable, Hashable {
    case none, number, email, phone, date
    public var label: String { self == .none ? "None" : rawValue.capitalized }
}

public enum LayerKind: String, Codable, Sendable, Hashable { case base, trace }

public enum TextWeight: String, Codable, Sendable, CaseIterable, Hashable {
    case regular, medium, semibold, bold
    public var label: String { rawValue.capitalized }
}

/// Font families offered for text boxes and callouts (nil name = system font).
public enum TextFonts {
    public static let options: [(label: String, name: String?)] = [
        ("System", nil), ("Helvetica Neue", "Helvetica Neue"), ("Avenir Next", "Avenir Next"), ("Georgia", "Georgia"),
        ("Times New Roman", "Times New Roman"), ("Courier New", "Courier New"), ("Marker Felt", "Marker Felt"), ("Chalkboard", "Chalkboard SE")
    ]
    public static func label(for name: String?) -> String { (options + pdfOptions).first { $0.name == name }?.label ?? (name ?? "System") }

    /// Fonts every PDF reader can show without embedding (the standard base-14 families).
    public static let pdfOptions: [(label: String, name: String?)] = [
        ("Helvetica", nil), ("Times", "Times New Roman"), ("Courier", "Courier New")
    ]
    /// Standard PDF font name for a family + weight (used for FreeText annotations).
    public static func pdfFontName(for name: String?, bold: Bool) -> String {
        switch name {
        case "Times New Roman", "Georgia": return bold ? "Times-Bold" : "Times-Roman"
        case "Courier New": return bold ? "Courier-Bold" : "Courier"
        default: return bold ? "Helvetica-Bold" : "Helvetica"
        }
    }
}

// MARK: - Structs

public struct StrokePoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    /// Pencil pressure 0…1; 0.5 when unknown (finger / mouse).
    public var p: Double
    public init(_ x: Double, _ y: Double, _ p: Double = 0.5) { self.x = x; self.y = y; self.p = p }
    public var point: Point { Point(x, y) }
}

public struct Stroke: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var tool: Tool
    public var color: String
    public var points: [StrokePoint]
    public var width: Double?
    public var weight: WeightMode
    public var opacity: Double?
    public var lineStyle: LineStyle?
    public var fill: String?
    public var fillPattern: FillPattern?
    public var fillOpacity: Double?
    /// Text for text boxes, callouts, stamps and notes.
    public var text: String?
    public var background: String?
    public var backgroundOpacity: Double?
    public var borderColor: String?
    public var borderOpacity: Double?
    public var borderWidth: Double?
    /// Linked comment (Markup documents only).
    public var commentID: ID?
    /// Uniform scale applied to placed items (stamps, notes, check marks…).
    public var scale: Double
    /// Text-line rectangles (page coordinates) for markup snapped to PDF text: highlighter, underline, strike, squiggly.
    public var rects: [Rect]?
    /// Font family / weight for text boxes and callouts (nil = system, semibold).
    public var font: String?
    public var fontWeight: TextWeight?

    public init(id: ID = IDGen.make(), tool: Tool, color: String, points: [StrokePoint], width: Double? = nil,
                weight: WeightMode = .constant, opacity: Double? = nil, lineStyle: LineStyle? = nil,
                fill: String? = nil, fillPattern: FillPattern? = nil, fillOpacity: Double? = nil, text: String? = nil,
                background: String? = nil, backgroundOpacity: Double? = nil, borderColor: String? = nil,
                borderOpacity: Double? = nil, borderWidth: Double? = nil, commentID: ID? = nil, scale: Double = 1, rects: [Rect]? = nil,
                font: String? = nil, fontWeight: TextWeight? = nil) {
        self.id = id; self.tool = tool; self.color = color; self.points = points; self.width = width
        self.weight = weight; self.opacity = opacity; self.lineStyle = lineStyle; self.fill = fill
        self.fillPattern = fillPattern; self.fillOpacity = fillOpacity; self.text = text
        self.background = background; self.backgroundOpacity = backgroundOpacity; self.borderColor = borderColor
        self.borderOpacity = borderOpacity; self.borderWidth = borderWidth; self.commentID = commentID; self.scale = scale
        self.rects = rects
        self.font = font; self.fontWeight = fontWeight
    }

    /// Whether this stroke is anchored to PDF text lines.
    public var isTextAnchored: Bool { !(rects?.isEmpty ?? true) }

    /// Axis-aligned bounds of the control points.
    public var bounds: Rect { Rect.bounding(points.map { $0.point }) }
    public var anchor: Point { points.first?.point ?? .zero }
    public var center: Point { bounds.center }

    public func shifted(dx: Double, dy: Double) -> Stroke {
        var s = self
        s.points = points.map { StrokePoint($0.x + dx, $0.y + dy, $0.p) }
        s.rects = rects?.map { Rect(x: $0.x + dx, y: $0.y + dy, w: $0.w, h: $0.h) }
        return s
    }

    public func scaled(by f: Double) -> Stroke {
        var s = self
        if tool.info.isPathBased {
            let c = center
            s.points = points.map { StrokePoint(c.x + ($0.x - c.x) * f, c.y + ($0.y - c.y) * f, $0.p) }
        } else {
            s.scale = min(6, max(0.2, scale * f))
        }
        return s
    }
}

public struct Reply: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var author: String
    public var time: Date
    public var text: String
    public init(id: ID = IDGen.make(), author: String, time: Date, text: String) {
        self.id = id; self.author = author; self.time = time; self.text = text
    }
}

public struct Comment: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var pageID: ID
    /// Tool raw value that created this comment ("pen", "highlighter", "textbox"…).
    public var kind: String
    public var author: String
    public var time: Date
    public var status: CommentStatus
    public var text: String
    public var color: String
    public var replies: [Reply]
    public init(id: ID = IDGen.make(), pageID: ID, kind: String, author: String, time: Date, status: CommentStatus = .open,
                text: String = "", color: String, replies: [Reply] = []) {
        self.id = id; self.pageID = pageID; self.kind = kind; self.author = author; self.time = time
        self.status = status; self.text = text; self.color = color; self.replies = replies
    }
}

public struct FormField: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var type: FieldType
    public var name: String
    public var x: Double, y: Double, w: Double, h: Double
    public var defaultValue: String
    public var value: String
    public var tab: Int
    public var validation: ValidationRule
    public var calculation: String
    public var required: Bool
    /// One option per line.
    public var options: String
    public init(id: ID = IDGen.make(), type: FieldType, name: String, x: Double, y: Double, w: Double, h: Double,
                defaultValue: String = "", value: String = "", tab: Int, validation: ValidationRule = .none,
                calculation: String = "", required: Bool = false, options: String = "") {
        self.id = id; self.type = type; self.name = name; self.x = x; self.y = y; self.w = w; self.h = h
        self.defaultValue = defaultValue; self.value = value; self.tab = tab; self.validation = validation
        self.calculation = calculation; self.required = required; self.options = options
    }
    public var frame: Rect { Rect(x: x, y: y, w: w, h: h) }
    public var optionList: [String] { options.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
    public var isOn: Bool { value == "on" }
}

public struct Layer: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var name: String
    public var kind: LayerKind
    /// Veil strength 0…1 (trace layers only).
    public var opacity: Double
    public var visible: Bool
    public var locked: Bool
    public var strokes: [Stroke]
    public init(id: ID = IDGen.make(), name: String, kind: LayerKind, opacity: Double, visible: Bool = true, locked: Bool = false, strokes: [Stroke] = []) {
        self.id = id; self.name = name; self.kind = kind; self.opacity = opacity; self.visible = visible; self.locked = locked; self.strokes = strokes
    }
    public var isTrace: Bool { kind == .trace }
}

public struct Page: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var strokes: [Stroke]
    public var fields: [FormField]
    public var layers: [Layer]
    public var template: PageTemplate
    public var paper: Paper
    public var tags: [String]
    public var created: Date
    public var modified: Date
    /// Rotation in degrees (0, 90, 180, 270) — Markup pages.
    public var rotation: Int
    /// Optional label such as "A-101 Floor Plan" — Markup pages.
    public var label: String
    /// Sample artwork key for seeded sheets ("plan", "elev", "detail", "blank").
    public var artwork: String
    /// Index into the source PDF for imported markups.
    public var pdfPageIndex: Int?

    public init(id: ID = IDGen.make(), strokes: [Stroke] = [], fields: [FormField] = [], layers: [Layer] = [],
                template: PageTemplate = .blank, paper: Paper = .white, tags: [String] = [], created: Date = Date(),
                modified: Date? = nil, rotation: Int = 0, label: String = "", artwork: String = "blank", pdfPageIndex: Int? = nil) {
        self.id = id; self.strokes = strokes; self.fields = fields; self.layers = layers; self.template = template
        self.paper = paper; self.tags = tags; self.created = created; self.modified = modified ?? created
        self.rotation = rotation; self.label = label; self.artwork = artwork; self.pdfPageIndex = pdfPageIndex
    }

    public static func markup(label: String = "", artwork: String = "blank", pdfPageIndex: Int? = nil, created: Date = Date()) -> Page {
        Page(created: created, label: label, artwork: artwork, pdfPageIndex: pdfPageIndex)
    }
    public static func drawing(created: Date = Date()) -> Page {
        Page(layers: [Layer(name: "Base", kind: .base, opacity: 0)], created: created)
    }
    public static func journal(template: PageTemplate, paper: Paper, tags: [String] = [], created: Date = Date()) -> Page {
        Page(template: template, paper: paper, tags: tags, created: created)
    }
}

public struct Document: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: ID
    public var type: DocumentType
    public var name: String
    public var created: Date
    public var modified: Date
    public var pages: [Page]
    public var comments: [Comment]
    /// Paper colour for plan sets (Drawing).
    public var paper: Paper
    /// File name (inside the app's documents directory) of an imported PDF.
    public var pdfFile: String?
    /// Page IDs the user bookmarked (Markup).
    public var bookmarks: [ID]
    /// Logical page size override (imported PDFs keep their own aspect ratio).
    public var sheetSize: Size?
    /// Library folder path ("" = root, "Projects/Meridian" nested). Optional so older data decodes.
    public var folder: String?
    public var favorite: Bool?
    public var lastOpened: Date?
    /// Notebook cover colour (hex). Optional so older data decodes; falls back to a palette pick by id.
    public var coverColor: String?

    public var folderPath: String { folder ?? "" }
    public var isFavorite: Bool { favorite ?? false }
    /// The notebook cover colour, always resolved.
    public var coverHex: String { coverColor ?? Covers.pick(for: id) }

    public init(id: ID = IDGen.make(), type: DocumentType, name: String, created: Date = Date(), modified: Date? = nil,
                pages: [Page], comments: [Comment] = [], paper: Paper = .white, pdfFile: String? = nil, bookmarks: [ID] = [],
                sheetSize: Size? = nil) {
        self.id = id; self.type = type; self.name = name; self.created = created; self.modified = modified ?? created
        self.pages = pages; self.comments = comments; self.paper = paper; self.pdfFile = pdfFile; self.bookmarks = bookmarks
        self.sheetSize = sheetSize
    }

    /// Logical canvas size in points.
    public var canvasSize: Size { sheetSize ?? (type == .journal ? Metrics.notesCanvas : Metrics.sheetCanvas) }

    public func pageIndex(of id: ID) -> Int? { pages.firstIndex { $0.id == id } }

    /// Trace layers across all pages (the "N layers" badge on Home).
    public var layerCount: Int { pages.reduce(0) { $0 + max(0, $1.layers.count - 1) } }
}

// MARK: - Simple geometry values

public struct Point: Codable, Sendable, Equatable, Hashable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Point(0, 0)
    public func distance(to o: Point) -> Double { ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)).squareRoot() }
}

public struct Size: Codable, Sendable, Equatable, Hashable {
    public var w: Double, h: Double
    public init(_ w: Double, _ h: Double) { self.w = w; self.h = h }
}

public struct Rect: Codable, Sendable, Equatable, Hashable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public static let zero = Rect(x: 0, y: 0, w: 0, h: 0)
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var center: Point { Point(x + w / 2, y + h / 2) }
    public func insetBy(_ d: Double) -> Rect { Rect(x: x + d, y: y + d, w: w - 2 * d, h: h - 2 * d) }
    public func contains(_ p: Point) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }
    public static func bounding(_ pts: [Point]) -> Rect {
        guard let f = pts.first else { return .zero }
        var x0 = f.x, y0 = f.y, x1 = f.x, y1 = f.y
        for p in pts { x0 = min(x0, p.x); y0 = min(y0, p.y); x1 = max(x1, p.x); y1 = max(y1, p.y) }
        return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
    public static func from(_ a: Point, _ b: Point) -> Rect {
        Rect(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(b.x - a.x), h: abs(b.y - a.y))
    }
}
