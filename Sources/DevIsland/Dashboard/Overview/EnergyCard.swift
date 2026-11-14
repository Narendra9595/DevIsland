import Darwin
import IOKit
import SwiftUI

/// DevIsland's own battery use, from macOS's per-app counters (CPU time, wake-ups and, on Apple silicon,
/// measured energy). Nothing runs in the background for this: the totals come from macOS, and the
/// "right now" numbers are sampled only while this card is on screen.
struct EnergyCard: View {
    @State private var now: EnergyUsage.Rate?

    var body: some View {
        // Averages start 15 s after launch, so the one-off start-up work doesn't count.
        let baseline = EnergyUsage.baseline
        let total = EnergyUsage.read()
        let uptime = max(1, Date.now.timeIntervalSince(baseline?.time ?? .now))
        let averageCPU = baseline.map { ((total?.cpuSeconds ?? 0) - $0.cpuSeconds) / uptime * 100 } ?? 0
        let averageMilliwatts: Double? = {
            guard let start = baseline?.joules, let end = total?.joules else { return nil }
            return (end - start) / uptime * 1000
        }()
        let usedJoules: Double? = {
            guard let start = baseline?.joules, let end = total?.joules else { return nil }
            return end - start
        }()
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Energy", subtitle: "DevIsland's own battery use") {
                    if baseline != nil {
                        StatusPill(text: Self.rating(averageCPU).text, tint: Self.rating(averageCPU).tint)
                    } else {
                        StatusPill(text: "Starting up", tint: .gray)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 12) {
                    metric("Right now", now.map { String(format: "%.1f%% CPU", $0.cpu) } ?? "…",
                           now.map { String(format: "%.0f wake-ups/s", $0.wakeups) } ?? "measuring")
                    metric("Average", baseline == nil ? "…" : String(format: "%.1f%% CPU", averageCPU),
                           averageMilliwatts.map { String(format: "%.0f mW", $0) } ?? "over \(Format.duration(uptime))")
                    if let joules = usedJoules {
                        metric("Battery used", Self.batteryShare(joules), "in \(Format.duration(uptime))")
                    }
                    if let averageMilliwatts, let capacity = EnergyUsage.batteryWattHours {
                        metric("Per 8 hours", String(format: "~%.1f%%", averageMilliwatts * 8 / 1000 / capacity * 100), "of a full battery")
                    }
                }
                Text("Averages skip the first 15 s. Under 1% CPU is very light.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Sampled every 2 s only while the card is visible.
            var previous = EnergyUsage.read()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let current = EnergyUsage.read()
                if let previous, let current { now = current.rate(since: previous) }
                previous = current
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private static func rating(_ cpu: Double) -> (text: String, tint: Color) {
        cpu < 1 ? ("Very light", Theme.success) : cpu < 3 ? ("Light", Theme.attention) : ("Heavy", Theme.danger)
    }

    /// Energy as a share of a full battery (or in mWh on Macs without one).
    private static func batteryShare(_ joules: Double) -> String {
        let milliwattHours = joules / 3.6
        guard let capacity = EnergyUsage.batteryWattHours else { return String(format: "%.1f mWh", milliwattHours) }
        return String(format: "%.2f%%", milliwattHours / 1000 / capacity * 100)
    }
}

/// Reads this process's counters from macOS (`proc_pid_rusage`).
enum EnergyUsage {
    struct Totals {
        let cpuSeconds: Double
        let wakeups: UInt64
        /// Measured energy (Apple silicon); nil when macOS doesn't report it.
        let joules: Double?
        let time: Date

        func rate(since earlier: Totals) -> Rate {
            let seconds = max(0.001, time.timeIntervalSince(earlier.time))
            return Rate(cpu: (cpuSeconds - earlier.cpuSeconds) / seconds * 100,
                        wakeups: Double(wakeups &- earlier.wakeups) / seconds)
        }
    }

    struct Rate {
        let cpu: Double
        let wakeups: Double
    }

    @MainActor static let launchDate = Date.now
    /// Counters 15 s after launch (set by `AppModel.start`), the starting point for averages.
    @MainActor static var baseline: Totals?

    static func read() -> Totals? {
        var info = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) == 0
            }
        }
        guard ok else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        let seconds = ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        return Totals(cpuSeconds: seconds, wakeups: info.ri_interrupt_wkups + info.ri_pkg_idle_wkups,
                      joules: info.ri_energy_nj > 0 ? Double(info.ri_energy_nj) / 1_000_000_000 : nil, time: .now)
    }

    /// The battery's full capacity in watt-hours (nil on Macs without a battery).
    static let batteryWattHours: Double? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        // Newer Macs keep the capacities inside "BatteryData".
        let data = property("BatteryData") as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            ((property(key) as? NSNumber) ?? (data[key] as? NSNumber))?.doubleValue
        }
        guard let milliampHours = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity") ?? number("DesignCapacity"),
              let millivolts = number("Voltage"), milliampHours > 0, millivolts > 0 else { return nil }
        return milliampHours * millivolts / 1_000_000
    }()
}
