import Foundation
import Observation

/// Live activities + saved history. Views redraw when these change.
@MainActor
@Observable
final class ActivityStore {
    /// Highest priority first, then newest.
    private(set) var live: [LiveActivity] = []
    private(set) var history: [ActivityEvent] = []
    private(set) var lastSeen: [String: Date] = [:]
    private(set) var selectedKey: String?
    /// Bumped whenever saved history changes, so views can reload database-backed data.
    private(set) var revision = 0

    let database: EventDatabase?
    private let historyLimit = 100

    /// What the island shows: the user's pick, or the most important activity.
    var current: LiveActivity? {
        live.first { $0.key == selectedKey } ?? live.first
    }

    init(database: EventDatabase?) {
        self.database = database
        history = database?.recent(limit: historyLimit) ?? []

        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.removeStale()
            }
        }
    }

    func handle(_ event: ActivityEvent) {
        guard !history.contains(where: { $0.id == event.id }),
              !live.contains(where: { $0.event.id == event.id }) else { return }

        lastSeen[event.source] = event.timestamp
        updateLive(with: event)
        scheduleExpiry(for: event)

        guard event.kind.isLogged else { return }
        history.insert(event, at: 0)
        if history.count > historyLimit { history.removeLast() }
        database?.insert(event)
        revision += 1
    }

    func select(_ key: String) {
        selectedKey = key
    }

    /// Back to showing the most important activity.
    func clearSelection() {
        selectedKey = nil
    }

    /// Removes every live activity from a source (e.g. when its integration is turned off).
    /// Removes one live activity (e.g. a finished turn you've just seen).
    func dismiss(_ key: String) {
        live.removeAll { $0.key == key }
    }

    func endActivities(from source: String) {
        live.removeAll { $0.event.source == source }
    }

    func clearHistory() {
        history.removeAll()
        database?.deleteAll()
        revision += 1
    }

    func pruneHistory(olderThan date: Date) {
        database?.prune(olderThan: date)
        history.removeAll { $0.timestamp < date }
        revision += 1
    }

    /// Drops activities whose lifetime has passed.
    func removeStale(now: Date = .now) {
        live.removeAll { now.timeIntervalSince($0.event.timestamp) > Self.lifetime(of: $0.event) }
    }

    /// Finished things linger for a minute; silent ones disappear after 30 minutes.
    static func lifetime(of event: ActivityEvent) -> TimeInterval {
        event.expiresAfter ?? (event.kind == .completed ? 60 : 30 * 60)
    }

    private func scheduleExpiry(for event: ActivityEvent) {
        let lifetime = Self.lifetime(of: event)
        guard lifetime <= 120 else { return } // longer ones are handled by the periodic sweep
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime + 0.25))
            self?.removeStale()
        }
    }

    private func updateLive(with event: ActivityEvent) {
        if event.kind == .ended {
            // No session ID = end everything from that source.
            live.removeAll {
                event.sessionID == nil ? $0.event.source == event.source : $0.key == event.activityKey
            }
            return
        }

        if let index = live.firstIndex(where: { $0.key == event.activityKey }) {
            live[index].event = event
            if event.kind == .started { live[index].startedAt = event.timestamp }
        } else {
            live.append(LiveActivity(key: event.activityKey, event: event, startedAt: event.timestamp))
        }
        live.sort { ($0.event.priority, $0.event.timestamp) > ($1.event.priority, $1.event.timestamp) }
    }
}
