import Foundation
import Observation

/// CPU and memory samples for the dashboard. Samples only while a view is watching.
@MainActor
@Observable
final class SystemMonitor {
    struct Sample: Identifiable, Equatable {
        let id: Int
        let cpu: Double
        let memory: Double
    }

    private(set) var samples: [Sample] = []
    private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    @ObservationIgnored private let stats = SystemStats()
    @ObservationIgnored private var lastSample = Date.distantPast
    @ObservationIgnored private var counter = 0

    init() {
        _ = stats.cpuUsage() // prime the counters so the first real sample has a baseline
    }

    var cpu: Double? { samples.last?.cpu }
    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    /// Call from `.task { await monitor.observe() }`; it stops when the view disappears.
    func observe() async {
        sample()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            sample()
        }
    }

    private func sample() {
        guard Date().timeIntervalSince(lastSample) >= 1.5 else { return }
        lastSample = Date()
        if let memory = SystemStats.memoryUsage() { memoryUsed = memory.used }
        guard let cpu = stats.cpuUsage() else { return }
        counter += 1
        samples.append(Sample(id: counter, cpu: cpu, memory: memoryFraction))
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
    }
}
