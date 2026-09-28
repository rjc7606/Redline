// Human-readable dates and small text helpers.

import Foundation

public enum Formatting {
    /// "just now", "5m ago", "3h ago", "2d ago", or "Aug 14".
    public static func ago(_ t: Date, now: Date = Date()) -> String {
        let d = now.timeIntervalSince(t)
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int((d / 60).rounded()))m ago" }
        if d < 86400 { return "\(Int((d / 3600).rounded()))h ago" }
        if d < 7 * 86400 { return "\(Int((d / 86400).rounded()))d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: t)
    }

    /// "Aug 14, 2026"
    public static func date(_ t: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: t)
    }

    /// "08/14/26" for the date stamp.
    public static func shortDate(_ t: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yy"
        return f.string(from: t)
    }

    public static func plural(_ n: Int, _ word: String, _ plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? word : (plural ?? word + "s"))
    }

    /// "3 pages · 2h ago"
    public static func tileMeta(pages: Int, modified: Date, now: Date = Date()) -> String {
        plural(pages, "page") + " · " + ago(modified, now: now)
    }
}
