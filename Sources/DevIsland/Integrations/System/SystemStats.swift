import Darwin
import Foundation

/// Reads CPU and memory usage from the kernel (Mach APIs). No permission needed.
final class SystemStats {
    private var previous: (used: UInt64, total: UInt64)?

    /// CPU usage (0...1) since the previous call. The first call returns nil.
    func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let (user, system, idle, nice) = info.cpu_ticks
        let used = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = used + UInt64(idle)
        defer { previous = (used, total) }

        guard let previous, total > previous.total else { return nil }
        return Double(used - previous.used) / Double(total - previous.total)
    }

    /// Memory in use (app + wired + compressed), close to Activity Monitor's number.
    static func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let appPages = stats.internal_page_count > stats.purgeable_count
            ? stats.internal_page_count - stats.purgeable_count : 0
        let pages = UInt64(appPages) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (pages * UInt64(getpagesize()), ProcessInfo.processInfo.physicalMemory)
    }
}
