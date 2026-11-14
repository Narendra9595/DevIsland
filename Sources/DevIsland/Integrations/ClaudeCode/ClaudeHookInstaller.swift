import Foundation
import Observation

/// Adds or removes DevIsland's hooks in Claude Code's settings.json — only when the user asks.
/// It backs the file up first and leaves everything else in it untouched.
@MainActor
@Observable
final class ClaudeHookInstaller {
    enum Status: Equatable {
        case notInstalled, installed, outdated
    }

    enum InstallError: LocalizedError {
        case invalidSettings
        var errorDescription: String? {
            "Your Claude Code settings file isn't valid JSON, so DevIsland left it untouched."
        }
    }

    nonisolated static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "MessageDisplay",
                                     "Notification", "Stop", "SessionEnd"]
    /// Tool events need a matcher; "*" means every tool.
    nonisolated static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    private(set) var status: Status = .notInstalled
    private(set) var lastError: String?
    private(set) var lastBackup: URL?

    let settingsURL: URL
    let scriptURL: URL
    /// The status line script that forwards plan usage (5-hour and weekly limits).
    let statusLineURL: URL
    /// The user's own status line command, kept so we can run it and restore it on disconnect.
    private let originalStatusLineURL: URL

    init(settingsURL: URL = AppPaths.claudeSettings, scriptURL: URL = AppPaths.hookScript) {
        self.settingsURL = settingsURL
        self.scriptURL = scriptURL
        statusLineURL = scriptURL.deletingLastPathComponent().appending(path: "devisland-statusline")
        originalStatusLineURL = scriptURL.deletingLastPathComponent().appending(path: "statusline-original.txt")
    }

    var command: String { Self.command(scriptPath: scriptURL.path) }

    func refresh() {
        do {
            let settings = try readSettings()
            status = Self.status(of: settings, command: command)
            if status == .installed, !Self.isDevIslandStatusLine(settings["statusLine"], path: statusLineURL.path) {
                status = .outdated // connected before usage limits were added
            }
            lastError = nil
        } catch {
            status = .notInstalled
            lastError = error.localizedDescription
        }
    }

    func install() throws {
        do {
            try HookScript.install(at: scriptURL)
            try HookScript.installStatusLine(at: statusLineURL)
            var settings = Self.merged(try readSettings(), command: command)
            settings["statusLine"] = try statusLine(replacing: settings["statusLine"])
            try write(settings)
            status = .installed
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func uninstall() throws {
        do {
            var settings = Self.removed(try readSettings())
            if Self.isDevIslandStatusLine(settings["statusLine"], path: nil) {
                // Put back the user's own status line, if they had one.
                if let original = try? String(contentsOf: originalStatusLineURL, encoding: .utf8), !original.isEmpty,
                   var line = settings["statusLine"] as? [String: Any] {
                    line["command"] = original
                    settings["statusLine"] = line
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try? FileManager.default.removeItem(at: originalStatusLineURL)
            }
            try write(settings)
            status = .notInstalled
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Our status line, wrapping the user's own one (if any) so it keeps showing.
    private func statusLine(replacing existing: Any?) throws -> [String: Any] {
        var line = existing as? [String: Any] ?? [:]
        let original: String?
        if Self.isDevIslandStatusLine(existing, path: nil) {
            original = try? String(contentsOf: originalStatusLineURL, encoding: .utf8)
        } else {
            original = line["command"] as? String
            try (original ?? "").write(to: originalStatusLineURL, atomically: true, encoding: .utf8)
        }
        line["type"] = "command"
        line["command"] = Self.statusLineCommand(scriptPath: statusLineURL.path, wrapping: original)
        return line
    }

    // MARK: Pure helpers (unit tested)

    nonisolated static func statusLineCommand(scriptPath: String, wrapping original: String?) -> String {
        var command = shellQuoted(scriptPath)
        if let original, !original.isEmpty { command += " " + shellQuoted(original) }
        return command
    }

    /// Whether a statusLine setting is DevIsland's (optionally at a specific script path).
    nonisolated static func isDevIslandStatusLine(_ value: Any?, path: String?) -> Bool {
        guard let command = (value as? [String: Any])?["command"] as? String,
              command.contains("devisland-statusline") else { return false }
        return path.map { command.contains($0) } ?? true
    }

    nonisolated static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Quoted for the shell, since the path contains "Application Support".
    nonisolated static func command(scriptPath: String) -> String {
        "'" + scriptPath.replacingOccurrences(of: "'", with: #"'\''"#) + "' claude"
    }

    nonisolated static func isDevIslandHook(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains("devisland-hook") == true
    }

    /// The settings with exactly one up-to-date DevIsland hook per event.
    nonisolated static func merged(_ settings: [String: Any], command: String) -> [String: Any] {
        var result = removed(settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    /// The settings without any DevIsland hooks; the user's own hooks stay.
    nonisolated static func removed(_ settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { !isDevIslandHook($0) }
                if kept.count == entries.count { return group }
                if kept.isEmpty { return nil }
                var updated = group
                updated["hooks"] = kept
                return updated
            }
            if cleaned.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = cleaned }
        }
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }

    nonisolated static func status(of settings: [String: Any], command: String) -> Status {
        guard let hooks = settings["hooks"] as? [String: Any] else { return .notInstalled }
        var current = 0
        var any = 0
        for event in events {
            let entries = (hooks[event] as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            if entries.contains(where: isDevIslandHook) { any += 1 }
            if entries.contains(where: { ($0["command"] as? String) == command }) { current += 1 }
        }
        if current == events.count { return .installed }
        return any > 0 ? .outdated : .notInstalled
    }

    // MARK: File access

    /// Follows symlinks so dotfile setups keep working.
    private var resolvedURL: URL { settingsURL.resolvingSymlinksInPath() }

    private func readSettings() throws -> [String: Any] {
        let url = resolvedURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallError.invalidSettings
        }
        return settings
    }

    private func write(_ settings: [String: Any]) throws {
        let url = resolvedURL
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted).dateSeparator(.omitted))
            let base = "\(url.lastPathComponent).devisland-backup-\(stamp)"
            var backup = url.deletingLastPathComponent().appending(path: base)
            var attempt = 2
            while fileManager.fileExists(atPath: backup.path) { // never overwrite an earlier backup
                backup = url.deletingLastPathComponent().appending(path: "\(base)-\(attempt)")
                attempt += 1
            }
            try fileManager.copyItem(at: url, to: backup)
            lastBackup = backup
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
