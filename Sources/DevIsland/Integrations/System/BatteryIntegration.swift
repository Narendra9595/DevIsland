import Foundation
import IOKit.ps

/// Charging changes and low-battery alerts. Optionally shows the level all the time.
final class BatteryIntegration: Integration {
    struct Reading: Equatable {
        let level: Double
        let isCharging: Bool
        let isPluggedIn: Bool
        let minutesRemaining: Int?
        var isLow: Bool { level <= 0.2 && !isPluggedIn }
    }

    let id = "battery"
    let name = "Battery"
    let summary = "Charging changes and low-battery alerts."
    let symbol = "battery.75percent"

    private var publish: Publish?
    private var task: Task<Void, Never>?
    private var last: Reading?

    /// Desktop Macs have no battery.
    static var isAvailable: Bool { read() != nil }

    func start(publish: @escaping Publish) {
        self.publish = publish
        last = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        publish = nil
        last = nil
    }

    /// "refresh" re-checks right away and clears anything shown.
    func perform(action: String) {
        if action == "refresh" { poll(force: true) }
    }

    private func poll(force: Bool = false) {
        guard let publish, let reading = Self.read() else { return }
        let previous = last
        last = reading

        if reading.isLow {
            publish(event(reading, kind: previous?.isLow == true ? .update : .alert, priority: .high))
        } else if let previous, previous.isPluggedIn != reading.isPluggedIn || previous.isLow {
            // Plugged in or out (or recovered from low): show it briefly.
                publish(event(reading, kind: .update, priority: .normal, expiresAfter: 4))
        } else if force {
                publish(ActivityEvent(source: id, kind: .ended, title: "Battery"))
        }
    }

    private func event(_ reading: Reading, kind: ActivityEvent.Kind, priority: ActivityEvent.Priority,
                       expiresAfter: TimeInterval? = nil) -> ActivityEvent {
        ActivityEvent(
            source: id,
            kind: kind,
            title: reading.isLow ? "Low battery" : "Battery",
            detail: Self.detail(for: reading),
            symbol: Self.symbol(for: reading),
            progress: reading.level,
            expiresAfter: expiresAfter,
            priority: priority,
            metadata: ["charging": reading.isCharging ? "true" : "false", "low": reading.isLow ? "true" : "false"])
    }

    static func detail(for reading: Reading) -> String {
        if reading.isCharging {
            return reading.minutesRemaining.map { "Charging · \(Format.minutes($0)) until full" } ?? "Charging"
        }
        if reading.isPluggedIn { return "Plugged in" }
        return reading.minutesRemaining.map { "\(Format.minutes($0)) remaining" } ?? "On battery"
    }

    static func symbol(for reading: Reading) -> String {
        if reading.isCharging || reading.isPluggedIn { return "battery.100percent.bolt" }
        switch reading.level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let battery = sources.first,
              let details = IOPSGetPowerSourceDescription(info, battery)?.takeUnretainedValue() as? [String: Any],
              let current = details[kIOPSCurrentCapacityKey] as? Int,
              let max = details[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }

        let charging = details[kIOPSIsChargingKey] as? Bool ?? false
        let minutes = details[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
        return Reading(
            level: Double(current) / Double(max),
            isCharging: charging,
            isPluggedIn: details[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            minutesRemaining: minutes.flatMap { $0 > 0 ? $0 : nil })
    }
}
