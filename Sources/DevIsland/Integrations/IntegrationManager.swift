import Foundation
import Observation

/// Starts and stops integrations, and routes button presses and hook messages to them.
@MainActor
@Observable
final class IntegrationManager {
    let integrations: [any Integration]
    private(set) var enabledIDs: Set<String>
    private(set) var lastHookMessage: Date?
    /// Commands sent by another DevIsland process (e.g. "open-dashboard").
    @ObservationIgnored var onAppCommand: ((String) -> Void)?
    /// Claude Code's status line input (plan usage).
    @ObservationIgnored var onClaudeUsage: ((Data) -> Void)?

    private let defaults: UserDefaults
    private let bus: EventBus
    private let store: ActivityStore
    private let log: DiagnosticsLog

    init(integrations: [any Integration], defaults: UserDefaults, bus: EventBus, store: ActivityStore, log: DiagnosticsLog) {
        self.integrations = integrations
        self.defaults = defaults
        self.bus = bus
        self.store = store
        self.log = log
        enabledIDs = Set(integrations
            .filter { defaults.object(forKey: Self.key($0.id)) as? Bool ?? $0.enabledByDefault }
            .map(\.id))
    }

    func startEnabled() {
        for integration in integrations where enabledIDs.contains(integration.id) {
            start(integration)
        }
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func integration(_ id: String) -> (any Integration)? {
        integrations.first { $0.id == id }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let integration = integration(id), enabled != isEnabled(id) else { return }
        defaults.set(enabled, forKey: Self.key(id))
        if enabled {
            enabledIDs.insert(id)
            start(integration)
        } else {
            enabledIDs.remove(id)
            integration.stop()
            store.endActivities(from: id)
            log.add("Stopped \(integration.name)")
        }
    }

    func perform(_ action: String, source: String) {
        guard isEnabled(source) else { return }
        integration(source)?.perform(action: action)
    }

    /// A message from the hook socket: route it to the matching adapter.
    func receive(_ data: Data) {
        guard let source = EventDecoder.source(of: data) else {
            log.add("Rejected a malformed hook message", level: .warning)
            return
        }
        if source == "claude-usage" {
            if isEnabled("claude") { onClaudeUsage?(data) }
            return
        }
        if source == "devisland" {
            if let command = EventDecoder.payload(AppCommand.self, from: data)?.command {
                onAppCommand?(command)
            }
            return
        }
        guard let adapter = integration(source) as? any BridgeAdapter else {
            log.add("Rejected a hook message from unknown source “\(source)”", level: .warning)
            return
        }
        lastHookMessage = .now
        guard isEnabled(source), let event = adapter.event(from: data) else { return }
        bus.publish(event)
    }

    private func start(_ integration: any Integration) {
        integration.start { [bus] event in bus.publish(event) }
        log.add("Started \(integration.name)")
    }

    private static func key(_ id: String) -> String {
        "integration.\(id)"
    }
}
