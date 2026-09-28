// Notebook geometry: single page vs facing-page spreads, and the calendar view.

import Foundation

/// Which pages are visible and where the prev/next navigation lands.
/// Page 0 is the cover; in spread mode the cover sits alone on the right, then (1,2), (3,4)…
public struct BookGeometry: Sendable, Equatable {
    public var spread: Bool
    public var pageCount: Int
    public var pageIndex: Int
    /// Spread index (0 = cover alone).
    public var spreadIndex: Int
    public var visiblePages: [Int]
    public var nextIndex: Int
    public var prevIndex: Int
    public var nextExists: Bool
    public var canBack: Bool
    /// In spread mode: whether the right-hand slot is empty (tap to add a page).
    public var rightSlotEmpty: Bool

    public init(pageCount n: Int, pageIndex pi: Int, spread: Bool) {
        self.spread = spread
        self.pageCount = n
        self.pageIndex = max(0, min(max(0, n - 1), pi))
        let si = (self.pageIndex + 1) / 2
        spreadIndex = si
        if spread {
            visiblePages = [2 * si - 1, 2 * si].filter { $0 >= 0 && $0 < n }
            nextIndex = 2 * si + 1
            prevIndex = max(0, 2 * si - 2)
            canBack = si > 0
            rightSlotEmpty = 2 * si >= n
        } else {
            visiblePages = [self.pageIndex]
            nextIndex = self.pageIndex + 1
            prevIndex = self.pageIndex - 1
            canBack = self.pageIndex > 0
            rightSlotEmpty = false
        }
        nextExists = nextIndex < n
    }

    public static func label(for index: Int) -> String { index == 0 ? "Cover" : "\(index)" }
    public static func longLabel(for index: Int) -> String { index == 0 ? "Cover" : "Page \(index)" }
}

public enum DateMode: String, Sendable, CaseIterable, Hashable {
    case created = "Created", modified = "Modified"
}

public struct CalendarCell: Sendable, Equatable, Identifiable {
    public var id: Int
    /// Day of month, or nil for padding cells.
    public var day: Int?
    public var isToday: Bool
    /// Page indices whose date falls on this day.
    public var pages: [Int]
}

public struct CalendarMonth: Sendable, Equatable {
    public var year: Int
    public var month: Int
    public var title: String
    public var cells: [CalendarCell]

    public init(document: Document, monthOffset: Int, mode: DateMode, now: Date = Date(), calendar cal: Calendar = .current) {
        let base = cal.date(byAdding: .month, value: monthOffset, to: cal.date(from: cal.dateComponents([.year, .month], from: now))!)!
        let comps = cal.dateComponents([.year, .month], from: base)
        year = comps.year!; month = comps.month!
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "LLLL yyyy"
        title = f.string(from: base)
        let firstWeekday = cal.component(.weekday, from: base) - 1 // 0 = Sunday
        let days = cal.range(of: .day, in: .month, for: base)!.count
        let todayComps = cal.dateComponents([.year, .month, .day], from: now)
        var byDay: [Int: [Int]] = [:]
        for (i, p) in document.pages.enumerated() {
            let d = mode == .modified ? p.modified : p.created
            let c = cal.dateComponents([.year, .month, .day], from: d)
            if c.year == year && c.month == month, let day = c.day { byDay[day, default: []].append(i) }
        }
        var cells: [CalendarCell] = []
        for i in 0..<42 {
            let day = i - firstWeekday + 1
            let inMonth = day >= 1 && day <= days
            let isToday = inMonth && todayComps.year == year && todayComps.month == month && todayComps.day == day
            cells.append(CalendarCell(id: i, day: inMonth ? day : nil, isToday: isToday, pages: inMonth ? (byDay[day] ?? []) : []))
        }
        if cells[35...].allSatisfy({ $0.day == nil }) { cells.removeLast(7) }
        self.cells = cells
    }

    public static let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}
