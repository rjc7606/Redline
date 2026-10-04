// The shared style system: every stylable tool has four presets; one preset is
// selected per tool. Defaults follow the README ("Shared style system").

import Foundation

public struct StylePreset: Codable, Sendable, Equatable, Hashable {
    public var color: String
    public var width: Double
    public var opacity: Double?
    public var lineStyle: LineStyle?
    public var pressure: Bool?
    // shapes
    public var fill: String?
    public var fillPattern: FillPattern?
    public var fillOpacity: Double?
    // text
    public var background: String?
    public var backgroundOpacity: Double?
    public var borderColor: String?
    public var borderOpacity: Double?
    public var borderWidth: Double?
    // text
    public var font: String?
    public var fontWeight: TextWeight?
    /// Revision cloud: "arcs" (default) or "straight" (a plain box outline you can select through).
    public var cloudStyle: String?
    /// Lines and arrows: what each end looks like (nil = the tool's default: plain line, arrow head at the end…).
    public var lineStart: LineEnding?
    public var lineEnd: LineEnding?

    public init(color: String, width: Double, opacity: Double? = nil, lineStyle: LineStyle? = nil, pressure: Bool? = nil,
                fill: String? = nil, fillPattern: FillPattern? = nil, fillOpacity: Double? = nil, background: String? = nil,
                backgroundOpacity: Double? = nil, borderColor: String? = nil, borderOpacity: Double? = nil, borderWidth: Double? = nil,
                font: String? = nil, fontWeight: TextWeight? = nil) {
        self.color = color; self.width = width; self.opacity = opacity; self.lineStyle = lineStyle; self.pressure = pressure
        self.fill = fill; self.fillPattern = fillPattern; self.fillOpacity = fillOpacity; self.background = background
        self.backgroundOpacity = backgroundOpacity; self.borderColor = borderColor; self.borderOpacity = borderOpacity
        self.borderWidth = borderWidth; self.font = font; self.fontWeight = fontWeight
    }

    /// Which slot the Style Popover edits (`font` = text colour + family / weight / size).
    public enum Target: String, Sendable, CaseIterable, Hashable {
        case color = "c", fill = "f", background = "bg", border = "bc", font = "font"
    }

    public func color(for target: Target) -> String {
        switch target {
        case .color, .font: color
        case .fill: fill ?? color
        case .background: background ?? "#FFFFFF"
        case .border: borderColor ?? color
        }
    }
    public mutating func setColor(_ hex: String, for target: Target) {
        switch target {
        case .color, .font: color = hex
        case .fill: fill = hex
        case .background: background = hex
        case .border: borderColor = hex
        }
    }
    public func opacity(for target: Target, tool: Tool) -> Double {
        switch target {
        case .color, .font: opacity ?? ToolStyles.defaultOpacity(for: tool)
        case .fill: fillOpacity ?? 0.5
        case .background: backgroundOpacity ?? (tool == .textbox ? 1 : 0)
        case .border: borderOpacity ?? 1
        }
    }
    public mutating func setOpacity(_ v: Double, for target: Target) {
        switch target {
        case .color, .font: opacity = v
        case .fill: fillOpacity = v
        case .background: backgroundOpacity = v
        case .border: borderOpacity = v
        }
    }
}

public struct ToolStyles: Codable, Sendable, Equatable {
    /// Custom preset sets keyed by tool raw value. Absent → defaults.
    public var sets: [String: [StylePreset]]
    public var selected: [String: Int]

    public init(sets: [String: [StylePreset]] = [:], selected: [String: Int] = [:]) {
        self.sets = sets; self.selected = selected
    }

    public func presets(for tool: Tool) -> [StylePreset] {
        if let s = sets[tool.rawValue], s.count == 4 { return s }
        return ToolStyles.defaultPresets(for: tool)
    }
    public func selectedIndex(for tool: Tool) -> Int {
        min(3, max(0, selected[tool.rawValue] ?? 0))
    }
    public func current(for tool: Tool) -> StylePreset {
        presets(for: tool)[selectedIndex(for: tool)]
    }
    public mutating func select(_ index: Int, for tool: Tool) {
        selected[tool.rawValue] = min(3, max(0, index))
    }
    public mutating func update(_ tool: Tool, _ body: (inout StylePreset) -> Void) {
        var arr = presets(for: tool)
        let i = selectedIndex(for: tool)
        body(&arr[i])
        sets[tool.rawValue] = arr
    }
    public mutating func reset(_ tool: Tool) {
        sets[tool.rawValue] = nil
        selected[tool.rawValue] = nil
    }

    // MARK: defaults

    public struct Default: Sendable { public var color: String; public var width: Double; public var opacity: Double? }

    public static func base(for tool: Tool) -> Default {
        switch tool {
        case .pen: Default(color: "#1c1c1e", width: 2.4, opacity: nil)
        case .fineliner: Default(color: "#1c1c1e", width: 1.3, opacity: nil)
        case .felt: Default(color: "#E0332A", width: 4.2, opacity: nil)
        case .marker: Default(color: "#ffd60a", width: 14, opacity: 0.55)
        case .highlighter: Default(color: "#ffd60a", width: 22, opacity: 0.4)
        case .textbox: Default(color: "#E0332A", width: 6, opacity: nil)
        case .note: Default(color: "#FFCC00", width: 2.5, opacity: nil)
        case .signature: Default(color: "#1c1c1e", width: 2.5, opacity: nil)
        case .fill: Default(color: "#FFCC00", width: 0, opacity: 0.5)
        case .check: Default(color: "#34C759", width: 4, opacity: nil)
        case .xmark: Default(color: "#FF3B30", width: 4, opacity: nil)
        case .eraser: Default(color: "#8e8e93", width: 12, opacity: nil)
        default: Default(color: "#E0332A", width: 2.5, opacity: nil)
        }
    }

    /// The four preset colours for a tool.
    public static func presetColors(for tool: Tool) -> [String] {
        switch tool {
        case .pen, .fineliner, .signature: ["#1c1c1e", "#E0332A", "#007AFF", "#34C759"]
        case .marker, .highlighter: ["#ffd60a", "#ff6fa8", "#34C759", "#007AFF"]
        case .fill, .note: ["#FFCC00", "#FF3B30", "#007AFF", "#34C759"]
        case .check: ["#34C759", "#E0332A", "#007AFF", "#FF9500"]
        default: ["#E0332A", "#1c1c1e", "#007AFF", "#FF9500"]
        }
    }

    /// Eraser presets are sizes (diameter in page points).
    public static let eraserSizes: [Double] = [6, 12, 24, 40]

    public static func defaultPresets(for tool: Tool) -> [StylePreset] {
        let d = base(for: tool)
        if tool == .eraser { return eraserSizes.map { StylePreset(color: d.color, width: $0) } }
        if tool == .textbox {
            return [
                StylePreset(color: "#FF3B30", width: 5, background: "#FFFFFF", backgroundOpacity: 1, borderColor: "#FF3B30", borderOpacity: 1, borderWidth: 1.5),
                StylePreset(color: "#1c1c1e", width: 5, background: "#FFF9C4", backgroundOpacity: 1, borderColor: "#1c1c1e", borderOpacity: 1, borderWidth: 1.5),
                StylePreset(color: "#007AFF", width: 5, background: "#FFFFFF", backgroundOpacity: 1, borderColor: "#007AFF", borderOpacity: 1, borderWidth: 1.5),
                StylePreset(color: "#FFFFFF", width: 5, background: "#1c1c1e", backgroundOpacity: 1, borderColor: "#1c1c1e", borderOpacity: 1, borderWidth: 1.5)
            ]
        }
        return presetColors(for: tool).map { c in
            if tool.isShape {
                return StylePreset(color: c, width: d.width, opacity: 1, fill: c, fillPattern: FillPattern.none, fillOpacity: 0.5)
            }
            return StylePreset(color: c, width: d.width, opacity: d.opacity)
        }
    }

    public static func defaultOpacity(for tool: Tool) -> Double {
        base(for: tool).opacity ?? 1
    }

    /// Slider range for the weight control.
    public static func widthRange(for tool: Tool) -> ClosedRange<Double> {
        switch tool {
        case .pen: 1...12
        case .fineliner: 0.5...6
        case .felt: 2...20
        case .marker: 6...40
        case .highlighter: 10...40
        case .textbox: 1...14
        case .signature: 1...8
        case .eraser: 2...80
        default: 1...16
        }
    }
    public static func widthStep(for tool: Tool) -> Double {
        let r = widthRange(for: tool)
        return (tool == .textbox || r.upperBound > 10) ? 1 : 0.1
    }

    /// Quick palette shown as the 12-column grid header row in the Style Popover.
    public static let quickPalette: [String] = ["#1c1c1e", "#6d6d72", "#ffffff", "#E0332A", "#FF9500", "#ffd60a", "#34C759", "#00a3a3", "#007AFF", "#5856D6", "#AF52DE", "#ff6fa8"]
}

/// A 12×10 spectrum grid (greys row + 9 hue rows) used by colour pickers.
public enum Spectrum {
    public static let grid: [String] = {
        var g: [String] = []
        for c in 0..<12 { g.append(HexColor.hsl(0, 0, 100 - Double(c) * 100 / 11)) }
        for r in 0..<9 {
            for c in 0..<12 { g.append(HexColor.hsl(Double(c * 30), 95 - Double(r) * 3, 88 - Double(r) * 8)) }
        }
        return g
    }()
}


/// How a line or arrow ends.
public enum LineEnding: String, Codable, Sendable, CaseIterable, Hashable {
    case plain, open, closed, dot, square
    public var label: String {
        switch self { case .plain: "None"; case .open: "Open"; case .closed: "Filled"; case .dot: "Dot"; case .square: "Square" }
    }
}
