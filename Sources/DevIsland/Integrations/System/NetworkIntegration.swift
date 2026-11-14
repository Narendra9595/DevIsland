import Foundation
import Network

/// Alerts while the Mac is offline, and briefly confirms when it's back.
final class NetworkIntegration: Integration {
    let id = "network"
    let name = "Network"
    let summary = "Alerts while your Mac is offline."
    let symbol = "wifi"

    private var monitor: NWPathMonitor?
    private var isOffline = false

    func start(publish: @escaping Publish) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.update(offline: offline, publish: publish) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        isOffline = false
    }

    private func update(offline: Bool, publish: Publish) {
        guard offline != isOffline else { return }
        isOffline = offline
        if offline {
            publish(ActivityEvent(source: id, kind: .alert, title: "You're offline",
                                  detail: "DevIsland will let you know when you're back.",
                                  symbol: "wifi.slash", expiresAfter: 6 * 3600, priority: .high))
        } else {
            publish(ActivityEvent(source: id, kind: .update, title: "Back online",
                                  symbol: "wifi", expiresAfter: 4))
        }
    }
}
