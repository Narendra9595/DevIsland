import Foundation

/// Codex CLI, via its `notify` setting. Codex only reports "turn finished",
/// so DevIsland can't show live tool activity for Codex.
final class CodexIntegration: Integration, BridgeAdapter {
    let id = "codex"
    let name = "Codex"
    let summary = "Shows when a Codex turn finishes, via its notify setting."
    let symbol = "terminal"

    private struct Payload: Decodable {
        let type: String
        let cwd: String?
    }

    func event(from data: Data) -> ActivityEvent? {
        guard let payload = EventDecoder.payload(Payload.self, from: data),
              payload.type == "agent-turn-complete" else { return nil }
        let project = payload.cwd.map { ($0 as NSString).lastPathComponent }
        return ActivityEvent(
            source: id,
            kind: .completed,
            title: "Turn finished",
            detail: project,
            symbol: "terminal",
            metadata: ["state": "done", "project": project].compactMapValues { $0 })
    }
}
