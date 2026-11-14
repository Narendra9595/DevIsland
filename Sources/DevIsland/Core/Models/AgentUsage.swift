import Foundation

/// One plan-limit window (e.g. Claude's 5-hour or weekly limit).
struct UsageWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetsAt: Date

    /// 0...1 of the limit that's still available.
    var leftFraction: Double { max(0, min(1, 1 - usedPercent / 100)) }
}

/// Claude Code plan usage, as reported by Claude Code's status line (Pro, Max and Ultra plans).
struct ClaudeUsage: Codable, Equatable, Sendable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var updatedAt: Date

    /// Without windows that have already reset (their numbers are no longer true).
    func current(now: Date = .now) -> ClaudeUsage? {
        var usage = self
        if let window = usage.fiveHour, window.resetsAt <= now { usage.fiveHour = nil }
        if let window = usage.sevenDay, window.resetsAt <= now { usage.sevenDay = nil }
        return usage.fiveHour == nil && usage.sevenDay == nil ? nil : usage
    }
}
