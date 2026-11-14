import Foundation

struct DayStats: Equatable {
    var agentActiveTime: TimeInterval = 0
    var agentTurns = 0
    var agentSessions = 0
    var agentAlerts = 0
    var focusTime: TimeInterval = 0
    var focusSessions = 0
    var events = 0
}

struct HourCount: Identifiable, Equatable {
    let hour: Int
    let count: Int
    var id: Int { hour }
}

struct AgentSessionSummary: Identifiable, Equatable {
    let id: String
    let source: String
    let project: String?
    let branch: String?
    let start: Date
    let end: Date
    let turns: Int
    let activeTime: TimeInterval
    let alerts: Int
}

/// Numbers derived from saved events. Pure functions, so they're easy to test.
enum ActivityStats {
    static let agentSources: Set<String> = ["claude", "codex"]

    static func day(_ events: [ActivityEvent]) -> DayStats {
        var stats = DayStats(events: events.count)
        var sessions = Set<String>()
        for event in events {
            if agentSources.contains(event.source) {
                if event.sessionID != nil { sessions.insert(event.activityKey) }
                switch event.kind {
                case .completed:
                    stats.agentTurns += 1
                    stats.agentActiveTime += event.duration ?? 0
                case .alert:
                    stats.agentAlerts += 1
                default:
                    break
                }
            } else if event.source == TimerIntegration.sourceID, event.kind == .completed,
                      event.metadata["mode"] == TimerIntegration.Mode.focus.rawValue {
                stats.focusSessions += 1
                stats.focusTime += event.duration ?? 0
            }
        }
        stats.agentSessions = sessions.count
        return stats
    }

    static func agentTurnsByHour(_ events: [ActivityEvent], calendar: Calendar = .current) -> [HourCount] {
        var counts = [Int](repeating: 0, count: 24)
        for event in events where agentSources.contains(event.source) && event.kind == .completed {
            counts[calendar.component(.hour, from: event.timestamp)] += 1
        }
        return counts.enumerated().map { HourCount(hour: $0.offset, count: $0.element) }
    }

    /// Agent sessions (newest first), built from their saved events.
    static func agentSessions(_ events: [ActivityEvent]) -> [AgentSessionSummary] {
        let agentEvents = events.filter { agentSources.contains($0.source) && $0.sessionID != nil }
        return Dictionary(grouping: agentEvents, by: \.activityKey)
            .compactMap { key, items -> AgentSessionSummary? in
                let sorted = items.sorted { $0.timestamp < $1.timestamp }
                guard let first = sorted.first, let last = sorted.last else { return nil }
                let turns = sorted.filter { $0.kind == .completed }
                return AgentSessionSummary(
                    id: key,
                    source: first.source,
                    project: sorted.lazy.compactMap { $0.metadata["project"] }.first,
                    branch: sorted.reversed().lazy.compactMap { $0.metadata["branch"] }.first,
                    start: first.timestamp,
                    end: last.timestamp,
                    turns: turns.count,
                    activeTime: turns.reduce(0) { $0 + ($1.duration ?? 0) },
                    alerts: sorted.filter { $0.kind == .alert }.count)
            }
            .sorted { $0.end > $1.end }
    }
}
