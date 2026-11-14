import Foundation

/// Where DevIsland keeps its files: ~/Library/Application Support/DevIsland/
enum AppPaths {
    static let folder: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "DevIsland")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let database = folder.appending(path: "devisland.sqlite")
    static let socket = folder.appending(path: "devisland.sock")
    /// The forwarder script that Claude Code / Codex hooks run.
    static let hookScript = folder.appending(path: "bin/devisland-hook")
    /// The status line script that forwards Claude Code's plan usage.
    static let statusLineScript = folder.appending(path: "bin/devisland-statusline")
    static let claudeSettings = URL.homeDirectory.appending(path: ".claude/settings.json")
    static let codexConfig = URL.homeDirectory.appending(path: ".codex/config.toml")
}
