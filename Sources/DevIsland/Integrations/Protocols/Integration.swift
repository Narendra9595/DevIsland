import Foundation

typealias Publish = @MainActor (ActivityEvent) -> Void

/// Every feature that produces activity is an Integration, switchable in the dashboard.
@MainActor
protocol Integration: AnyObject {
    /// Also used as the `source` of its events.
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var symbol: String { get }
    var enabledByDefault: Bool { get }

    func start(publish: @escaping Publish)
    func stop()
    /// Called when the user presses one of this integration's buttons.
    func perform(action: String)
}

extension Integration {
    var enabledByDefault: Bool { true }
    func start(publish: @escaping Publish) {}
    func stop() {}
    func perform(action: String) {}
}

/// An integration fed by CLI hooks through the local socket.
@MainActor
protocol BridgeAdapter {
    /// Turns a raw hook message into an event, or nil if we don't track it.
    func event(from data: Data) -> ActivityEvent?
}
