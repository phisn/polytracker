import Foundation

/// Small display formatters, kept in one place for a consistent minimal look.
enum Fmt {
    /// Whole-number percentage everywhere (menu bar, rows, detail), e.g. "62%".
    static func percent(_ p: Double) -> String {
        "\(Int((p * 100).rounded()))%"
    }

    /// Magnitude of a 24h change in percentage points, e.g. "3.1" (sign/arrow handled by the view).
    static func changeValue(_ d: Double) -> String {
        String(format: "%.1f", abs(d * 100))
    }

    /// Compact USD, e.g. "$1.2M", "$340K".
    static func usd(_ v: Double) -> String {
        let a = abs(v)
        switch a {
        case 1_000_000_000...: return String(format: "$%.1fB", v / 1_000_000_000)
        case 1_000_000...:     return String(format: "$%.1fM", v / 1_000_000)
        case 1_000...:         return String(format: "$%.0fK", v / 1_000)
        default:               return String(format: "$%.0f", v)
        }
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
