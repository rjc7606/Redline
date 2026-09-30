// The shared tool catalogue. One enum covers the Markup tabs (Draw / Annotate /
// Edit / Forms) and the simpler Drawing & Notes toolbars so that a preset set
// belongs to one tool everywhere ("one shared tool/style system").

import Foundation

public enum Tool: String, Codable, Sendable, CaseIterable, Hashable {
    // selection
    case none, select, lasso
    // pens
    case pen, fineliner, felt, marker, highlighter
    // draw
    case fill, eraser, rect, ellipse, line, arrow, dblarrow, polyline, polygon, check, xmark, cloud
    case distance, perimeter, area, calibrate
    // annotate
    case underline, strike, squiggly, textbox, note, callout, stamps, signature, datestamp, initials
    // edit
    case edittext, image, link, redact, rotatepg, crop
    // forms
    case ftext, farea, fcheck, fradio, fdrop, fdate, fsig, ftoggle
    // studio-only form placement (Drawing/Notes-style Forms panel)
    case flist

    public var info: ToolInfo { ToolCatalog.info[self] ?? ToolInfo(label: rawValue, kind: .flash) }
    public var label: String { info.label }
    public var kind: ToolKind { info.kind }
    public var hasPresets: Bool { info.hasPresets }
    public var isPen: Bool { ToolCatalog.pens.contains(self) }
    public var isShape: Bool { ToolCatalog.closedShapes.contains(self) }
    public var isLineLike: Bool { ToolCatalog.lineLike.contains(self) }
    public var fieldType: FieldType? { info.fieldType }
}

public enum ToolKind: String, Sendable, Hashable {
    /// No tool / pan.
    case none
    case select, lasso
    /// Freehand ink: pens and signature.
    case ink
    /// Drag-drawn highlighter band (horizontal).
    case highlight
    /// Drag-drawn horizontal text markup (underline / strike / squiggly).
    case textMarkup
    /// Drag-drawn geometry (rect, ellipse, line, arrows, polyline, polygon, cloud, callout, redact).
    case shape
    /// Tap-placed glyph (check, x mark, note).
    case place
    /// Tap-placed text box (prompts for text).
    case text
    case eraser, fill, stampGallery, stampPreset
    /// Prototype-only: shows a toast.
    case flash
    /// Immediate page action (rotate).
    case pageAction
    /// Tap-placed form field.
    case form
}

public enum PageAction: String, Sendable, Hashable { case rotate }

public struct ToolInfo: Sendable, Hashable {
    public var label: String
    public var kind: ToolKind
    /// SF Symbol name, when a system glyph is used.
    public var symbol: String?
    /// Custom outline glyph on a 24×24 grid (SVG path data), plus optional secondary/filled paths.
    public var glyph: String?
    public var glyph2: String?
    public var glyphFill: String?
    public var hasPresets: Bool
    public var message: String?
    public var stampText: String?
    public var stampColor: String?
    public var fieldType: FieldType?
    public var pageAction: PageAction?

    public init(label: String, kind: ToolKind, symbol: String? = nil, glyph: String? = nil, glyph2: String? = nil,
                glyphFill: String? = nil, hasPresets: Bool = false, message: String? = nil, stampText: String? = nil,
                stampColor: String? = nil, fieldType: FieldType? = nil, pageAction: PageAction? = nil) {
        self.label = label; self.kind = kind; self.symbol = symbol; self.glyph = glyph; self.glyph2 = glyph2
        self.glyphFill = glyphFill; self.hasPresets = hasPresets; self.message = message; self.stampText = stampText
        self.stampColor = stampColor; self.fieldType = fieldType; self.pageAction = pageAction
    }

    /// Strokes whose geometry lives entirely in `points` (scaled by moving points, not `scale`).
    public var isPathBased: Bool {
        switch kind { case .ink, .highlight, .textMarkup, .shape: true; default: false }
    }
    /// Whether this tool draws by dragging on the page.
    public var isDrag: Bool {
        switch kind { case .ink, .highlight, .textMarkup, .shape: true; default: false }
    }
    /// Whether a tap on the page places something.
    public var isTap: Bool {
        switch kind { case .place, .text, .stampGallery, .stampPreset, .form: true; default: false }
    }
}

public struct ToolTab: Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var tools: [Tool]
    public init(id: String, label: String, tools: [Tool]) { self.id = id; self.label = label; self.tools = tools }
}

public enum ToolCatalog {
    public static let pens: Set<Tool> = [.pen, .fineliner, .felt, .marker]
    public static let closedShapes: Set<Tool> = [.rect, .ellipse, .polygon, .cloud]
    public static let lineLike: Set<Tool> = [.line, .arrow, .dblarrow, .polyline, .underline, .strike]

    /// Markup workspace tabs (excluding the user-defined Favorites tabs).
    public static let markupTabs: [ToolTab] = [
        ToolTab(id: "draw", label: "Draw", tools: [.fineliner, .felt, .marker, .fill, .eraser, .rect, .ellipse, .line, .arrow, .dblarrow, .polyline, .polygon, .check, .xmark, .cloud, .distance, .perimeter, .area, .calibrate]),
        ToolTab(id: "annotate", label: "Annotate", tools: [.highlighter, .underline, .strike, .squiggly, .textbox, .note, .callout, .stamps, .signature, .datestamp, .initials]),
        ToolTab(id: "edit", label: "Edit", tools: [.edittext, .image, .link, .redact, .rotatepg, .crop]),
        ToolTab(id: "forms", label: "Forms", tools: [.ftext, .farea, .fcheck, .fradio, .fdrop, .fdate, .fsig, .ftoggle])
    ]

    /// Default Favorites tab contents.
    public static let defaultFavorites: [Tool] = [.highlighter, .fineliner, .eraser, .textbox, .cloud, .rect, .arrow, .stamps]

    /// Drawing workspace tools.
    public static let drawingTools: [Tool] = [.select, .pen, .fineliner, .felt, .marker, .eraser, .textbox, .rect, .ellipse]
    /// Notes workspace tools (Drawing + Highlighter).
    public static let notesTools: [Tool] = [.select, .pen, .fineliner, .felt, .marker, .highlighter, .eraser, .textbox, .rect, .ellipse]

    public static func tool(for field: FieldType) -> Tool {
        switch field {
        case .text: .ftext; case .area: .farea; case .check: .fcheck; case .radio: .fradio
        case .drop: .fdrop; case .list: .flist; case .date: .fdate; case .sig: .fsig; case .toggle: .ftoggle
        }
    }

    public static let stampPresets: [(text: String, color: String)] = [
        ("APPROVED", "#34C759"), ("REJECTED", "#FF3B30"), ("REVISED", "#007AFF"), ("FOR REVIEW", "#FF9500"),
        ("DRAFT", "#8E8E93"), ("VOID", "#FF3B30"), ("FINAL", "#34C759"), ("SIGN HERE", "#5856D6")
    ]

    // swiftlint:disable line_length
    public static let info: [Tool: ToolInfo] = [
        .none: ToolInfo(label: "Pan", kind: .none, symbol: "hand.raised"),
        .select: ToolInfo(label: "Select — tap an item, drag a box, or draw a lasso", kind: .select, symbol: "cursorarrow"),
        .lasso: ToolInfo(label: "Lasso select", kind: .lasso, symbol: "lasso"),

        .pen: ToolInfo(label: "Pen", kind: .ink, glyph: "M6.5 12.5h11v9h-11z", glyph2: "M6.5 12.5L10 4.5h4L17.5 12.5", glyphFill: "M10.5 3.5a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0", hasPresets: true),
        .fineliner: ToolInfo(label: "Fineliner", kind: .ink, glyph: "M7 13h10v8.5H7z", glyph2: "M7 13c0-3.4 2.1-5 5-5s5 1.6 5 5M10.5 8V5.5h3V8M12 5.5v-3", hasPresets: true),
        .felt: ToolInfo(label: "Felt tip", kind: .ink, glyph: "M7 13h10v8.5H7z", glyph2: "M7.5 13v-3h9v3M9.5 10V7l2.5-3.5L14.5 7v3", hasPresets: true),
        .marker: ToolInfo(label: "Marker", kind: .ink, glyph: "M6 13h12v8.5H6z", glyph2: "M6.5 13v-2.5h11V13M8.5 10.5V5l7-3v8.5", hasPresets: true),
        .highlighter: ToolInfo(label: "Highlighter", kind: .highlight, symbol: "highlighter", hasPresets: true),

        .fill: ToolInfo(label: "Bucket fill", kind: .fill, glyph: "M18.5 11.5L11 4l-7.6 7.6a1.8 1.8 0 0 0 0 2.5l4.5 4.5a1.8 1.8 0 0 0 2.5 0z", glyph2: "M5.5 2.5L11 8M2.5 12.5h15", glyphFill: "M21.5 19.5a2 2 0 1 1-4 0c0-1.6 1.7-2.4 2-4 .3 1.6 2 2.4 2 4z", hasPresets: true),
        .eraser: ToolInfo(label: "Eraser", kind: .eraser, symbol: "eraser", hasPresets: true),
        .rect: ToolInfo(label: "Rectangle", kind: .shape, glyph: "M4 5.5h16v13H4z", hasPresets: true),
        .ellipse: ToolInfo(label: "Ellipse", kind: .shape, glyph: "M3.5 12a8.5 6.5 0 1 0 17 0a8.5 6.5 0 1 0 -17 0", hasPresets: true),
        .line: ToolInfo(label: "Line", kind: .shape, glyph: "M4 20L20 4", hasPresets: true),
        .arrow: ToolInfo(label: "Arrow", kind: .shape, symbol: "arrow.up.right", hasPresets: true),
        .dblarrow: ToolInfo(label: "Double arrow", kind: .shape, glyph: "M4 20L20 4M20 4l-5.5 1.2M20 4l-1.2 5.5M4 20l5.5-1.2M4 20l1.2-5.5", hasPresets: true),
        .polyline: ToolInfo(label: "Polyline", kind: .shape, glyph: "M3.5 18.5l5-9 5 4.5 7-10", glyphFill: "M2.1 18.5a1.4 1.4 0 1 0 2.8 0a1.4 1.4 0 1 0 -2.8 0M7.1 9.5a1.4 1.4 0 1 0 2.8 0a1.4 1.4 0 1 0 -2.8 0M12.1 14a1.4 1.4 0 1 0 2.8 0a1.4 1.4 0 1 0 -2.8 0M19.1 4a1.4 1.4 0 1 0 2.8 0a1.4 1.4 0 1 0 -2.8 0", hasPresets: true),
        .polygon: ToolInfo(label: "Polygon", kind: .shape, glyph: "M12 3.5l8 6-3 10.5H7L4 9.5z", hasPresets: true),
        .check: ToolInfo(label: "Check mark", kind: .place, symbol: "checkmark", hasPresets: true),
        .xmark: ToolInfo(label: "X mark", kind: .place, symbol: "xmark", hasPresets: true),
        .cloud: ToolInfo(label: "Revision cloud", kind: .shape, glyph: "M6.5 15.5A4 4 0 0 1 7 7.6a5.2 5.2 0 0 1 10.2 1.3A3.4 3.4 0 0 1 16.8 15.5z", hasPresets: true),
        .distance: ToolInfo(label: "Distance", kind: .flash, symbol: "ruler", message: "Measure tools are preview-only"),
        .perimeter: ToolInfo(label: "Perimeter", kind: .flash, symbol: "point.topleft.down.to.point.bottomright.curvepath", message: "Measure tools are preview-only"),
        .area: ToolInfo(label: "Area", kind: .flash, symbol: "square.dashed", message: "Measure tools are preview-only"),
        .calibrate: ToolInfo(label: "Calibrate", kind: .flash, symbol: "arrow.left.and.right", message: "Measure tools are preview-only"),

        .underline: ToolInfo(label: "Underline", kind: .textMarkup, symbol: "underline", hasPresets: true),
        .strike: ToolInfo(label: "Strikethrough", kind: .textMarkup, symbol: "strikethrough", hasPresets: true),
        .squiggly: ToolInfo(label: "Squiggly", kind: .textMarkup, symbol: "scribble.variable", hasPresets: true),
        .textbox: ToolInfo(label: "Text box", kind: .text, glyph: "M3.5 5h17v14h-17z", glyph2: "M8 8.5h8M8 8.5v1.8M16 8.5v1.8M12 8.5v7M10.3 15.5h3.4", hasPresets: true),
        .note: ToolInfo(label: "Sticky note", kind: .place, glyph: "M6 4h12a2 2 0 0 1 2 2v7h-5a2 2 0 0 0 -2 2v5h-7a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2z", glyph2: "M20 13v.172a2 2 0 0 1 -.586 1.414l-4.828 4.828a2 2 0 0 1 -1.414 .586h-.172", hasPresets: true),
        .callout: ToolInfo(label: "Callout", kind: .shape, glyph: "M9 3.5h11.5v9H9z", glyph2: "M12 7h5.5M12 9.5h3.5M9 12.5L3.5 20.5M3.5 20.5l.8-4.2M3.5 20.5l4.2-.8", hasPresets: true),
        .stamps: ToolInfo(label: "Stamps", kind: .stampGallery, symbol: "seal"),
        .signature: ToolInfo(label: "Signature", kind: .ink, symbol: "signature", hasPresets: true),
        .datestamp: ToolInfo(label: "Date stamp", kind: .stampPreset, symbol: "calendar.badge.checkmark", stampText: "RECEIVED", stampColor: "#FF3B30"),
        .initials: ToolInfo(label: "Initials", kind: .stampPreset, symbol: "textformat.abc", stampText: "T.M.", stampColor: "#007AFF"),

        .edittext: ToolInfo(label: "Edit text", kind: .flash, symbol: "text.cursor", message: "Edit text — coming soon"),
        .image: ToolInfo(label: "Insert image", kind: .flash, symbol: "photo.badge.plus", message: "Insert image — coming soon"),
        .link: ToolInfo(label: "Link", kind: .flash, symbol: "link", message: "Add link — coming soon"),
        .redact: ToolInfo(label: "Redact", kind: .shape, symbol: "eye.slash"),
        .rotatepg: ToolInfo(label: "Rotate page", kind: .pageAction, symbol: "rotate.right", pageAction: .rotate),
        .crop: ToolInfo(label: "Crop", kind: .flash, symbol: "crop", message: "Crop page — coming soon"),

        .ftext: ToolInfo(label: "Text input", kind: .form, symbol: "character.textbox", fieldType: .text),
        .farea: ToolInfo(label: "Text area", kind: .form, glyph: "M6 4.5h12a2.5 2.5 0 0 1 2.5 2.5v10a2.5 2.5 0 0 1-2.5 2.5H6a2.5 2.5 0 0 1-2.5-2.5V7A2.5 2.5 0 0 1 6 4.5z", glyph2: "M7 9h10M7 12.5h7M17.5 17l2-2", fieldType: .area),
        .fcheck: ToolInfo(label: "Checkbox", kind: .form, symbol: "checkmark.square", fieldType: .check),
        .fradio: ToolInfo(label: "Radio button", kind: .form, glyph: "M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0 -17 0", glyphFill: "M8.5 12a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0 -7 0", fieldType: .radio),
        .fdrop: ToolInfo(label: "Dropdown", kind: .form, symbol: "chevron.down.square", fieldType: .drop),
        .fdate: ToolInfo(label: "Date field", kind: .form, symbol: "calendar", fieldType: .date),
        .fsig: ToolInfo(label: "Signature field", kind: .form, symbol: "signature", fieldType: .sig),
        .ftoggle: ToolInfo(label: "Toggle", kind: .form, symbol: "switch.2", fieldType: .toggle),
        .flist: ToolInfo(label: "List", kind: .form, symbol: "list.bullet", fieldType: .list)
    ]
    // swiftlint:enable line_length

    /// Hint shown when a tool is picked.
    public static func pickHint(for tool: Tool, rulerLocked: Bool) -> String? {
        let t = tool.info
        switch t.kind {
        case .flash: return t.message
        case .stampPreset: return "Tap the page to place \"\(t.stampText ?? "")\""
        case .ink: return rulerLocked ? "Ruler locked — every stroke is a straight line" : "Drag on the page to draw"
        case .shape where tool == .callout: return "Drag from the arrow tip to where the text goes"
        case .highlight, .textMarkup, .shape: return "Drag on the page — \(t.label.lowercased())"
        case .place, .text, .form: return "Tap the page to place — \(t.label.lowercased())"
        case .eraser: return "Tap or drag over an annotation to erase it"
        case .fill: return "Tap inside a closed shape to fill it"
        case .stampGallery: return "Pick a stamp, then tap the page"
        default: return nil
        }
    }
}
