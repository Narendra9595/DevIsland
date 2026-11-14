import Foundation
import Observation
import OSLog

/// A short in-memory log shown in Diagnostics (also sent to the system log).
/// Never contains payloads, prompts or file contents.
@MainActor
@Observable
final class DiagnosticsLog {
    enum Level: String { case info, warning, error }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let logger = Logger(subsystem: "app.devisland", category: "diagnostics")

    func add(_ message: String, level: Level = .info) {
        entries.insert(Entry(level: level, message: message), at: 0)
        if entries.count > 300 { entries.removeLast() }
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    func clear() {
        entries.removeAll()
    }

    var report: String {
        entries.reversed()
            .map { "\($0.date.ISO8601Format()) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}
