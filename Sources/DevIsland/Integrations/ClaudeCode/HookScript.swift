import Foundation

/// The tiny shell script Claude Code / Codex run for each event. It forwards the event to
/// DevIsland's socket in the background and always exits immediately with success, so it can
/// never slow down or break the tool that calls it.
enum HookScript {
    static let contents = #"""
    #!/bin/sh
    # DevIsland hook forwarder. Installed and kept up to date by DevIsland.
    #   Claude Code (JSON on stdin):  devisland-hook claude
    #   Codex notify (JSON as arg):   devisland-hook codex '<json>'
    SOCKET="$HOME/Library/Application Support/DevIsland/devisland.sock"
    SOURCE="${1:-unknown}"
    PAYLOAD="${2:-$(cat)}"
    [ -S "$SOCKET" ] || exit 0
    printf '{"source":"%s","payload":%s}\n' "$SOURCE" "$(printf '%s' "$PAYLOAD" | tr -d '\n')" \
      | nc -U -w 1 "$SOCKET" >/dev/null 2>&1 &
    exit 0

    """#

    /// Claude Code's status line gets the plan usage (5-hour and weekly limits) on stdin.
    /// This forwards it to DevIsland, then runs the user's own status line command (passed as $1), if any.
    static let statusLineContents = #"""
    #!/bin/sh
    # DevIsland status line. Installed and kept up to date by DevIsland.
    # Forwards Claude Code's plan usage to DevIsland, then shows your own status line (if any).
    SOCKET="$HOME/Library/Application Support/DevIsland/devisland.sock"
    INPUT="$(cat)"
    if [ -S "$SOCKET" ]; then
      printf '{"source":"claude-usage","payload":%s}\n' "$(printf '%s' "$INPUT" | tr -d '\n')" \
        | nc -U -w 1 "$SOCKET" >/dev/null 2>&1 &
    fi
    if [ -n "$1" ]; then printf '%s' "$INPUT" | sh -c "$1"; fi
    exit 0

    """#

    /// Writes the hook script if it's missing or outdated, and makes it executable.
    static func install(at url: URL = AppPaths.hookScript) throws {
        try write(contents, to: url)
    }

    static func installStatusLine(at url: URL = AppPaths.statusLineScript) throws {
        try write(statusLineContents, to: url)
    }

    private static func write(_ text: String, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? String(contentsOf: url, encoding: .utf8)) != text {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
