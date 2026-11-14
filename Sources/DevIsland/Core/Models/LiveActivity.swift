import Foundation

/// Something happening right now: the latest event for one source + session.
struct LiveActivity: Identifiable, Equatable {
    let key: String
    var event: ActivityEvent
    var startedAt: Date
    var id: String { key }
}
