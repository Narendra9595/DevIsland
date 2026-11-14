import Foundation

/// The one event format every source (battery, music, Claude Code, ...) sends.
/// Stored as JSON, so decoding tolerates fields added or removed between versions.
struct ActivityEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case started, update, completed, alert, ended

        /// Only these are saved to history. Updates and endings are live-only.
        var isLogged: Bool { self == .started || self == .completed || self == .alert }
    }

    enum Priority: Int, Codable, Comparable, Sendable {
        case low, normal, high
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A button shown with the activity (play/pause, stop timer, ...).
    struct Action: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let symbol: String
        let label: String
    }

    var id = UUID()
    var source: String
    var kind: Kind
    var sessionID: String?
    var title: String
    var detail: String?
    var symbol: String?
    /// 0...1, only when the source knows real progress (battery level, paused timer).
    var progress: Double?
    /// When the current piece of work began (an agent's turn).
    var startDate: Date?
    /// When a countdown ends (timers).
    var endDate: Date?
    /// How long the finished thing took (agent turn, focus session).
    var duration: TimeInterval?
    /// Remove the live activity this many seconds after the event.
    var expiresAfter: TimeInterval?
    var priority: Priority = .normal
    var actions: [Action] = []
    /// Source-specific details: project, branch, player, state, ...
    var metadata: [String: String] = [:]
    var timestamp = Date()

    /// Events with the same key update the same live activity.
    var activityKey: String { "\(source):\(sessionID ?? "")" }
}

extension ActivityEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, source, kind, sessionID, title, detail, symbol, progress, startDate, endDate
        case duration, expiresAfter, priority, actions, metadata, timestamp
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try c.decode(String.self, forKey: .source)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .update
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        expiresAfter = try c.decodeIfPresent(TimeInterval.self, forKey: .expiresAfter)
        priority = (try? c.decode(Priority.self, forKey: .priority)) ?? .normal
        actions = (try? c.decode([Action].self, forKey: .actions)) ?? []
        metadata = (try? c.decode([String: String].self, forKey: .metadata)) ?? [:]
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}
