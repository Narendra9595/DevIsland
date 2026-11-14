import Foundation

/// Claude Code sessions, received from Claude Code hooks via the forwarder script.
/// Shows the step Claude is on: the first line of what it's saying, the description it wrote for a
/// command, the file it's reading or editing, the subagent's task, or the current plan item.
/// Commands, file contents, edits and prompts are never decoded, so they can't be shown or saved.
final class ClaudeCodeIntegration: Integration, BridgeAdapter {
    let id = "claude"
    let name = "Claude Code"
    let summary = "Live session status: what Claude is doing right now, files it touches, and turn time."
    let symbol = "sparkles"

    /// Replaceable in tests.
    var branchLookup: (String) -> String? = GitInfo.branch(at:)
    /// Whether to show the first line of Claude's messages (Settings → Privacy).
    var showsMessages: () -> Bool = { true }
    private var turnStarts: [String: Date] = [:]
    private var plans: [String: Plan] = [:]
    /// The last message already shown per session, so each message updates the island once.
    private var shownMessages: [String: String] = [:]
    /// Sessions currently waiting on you (a permission prompt or a question).
    private var waiting: Set<String> = []

    private struct Plan {
        let done: Int
        let total: Int
        var label: String? { done < total ? "Step \(done + 1) of \(total)" : nil }
    }

    private struct Payload: Decodable {
        let hookEventName: String
        let sessionId: String?
        let cwd: String?
        let toolName: String?
        let toolInput: ToolInput?
        let message: String?
        /// MessageDisplay: new lines of the message Claude is showing.
        let messageId: String?
        let delta: String?
        /// Stop: the text of Claude's final response.
        let lastAssistantMessage: String?

        private enum CodingKeys: String, CodingKey {
            case hookEventName, sessionId, cwd, toolName, toolInput, message, messageId, delta, lastAssistantMessage
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hookEventName = try c.decode(String.self, forKey: .hookEventName)
            sessionId = try? c.decode(String.self, forKey: .sessionId)
            cwd = try? c.decode(String.self, forKey: .cwd)
            toolName = try? c.decode(String.self, forKey: .toolName)
            toolInput = try? c.decode(ToolInput.self, forKey: .toolInput)
            message = try? c.decode(String.self, forKey: .message)
            messageId = try? c.decode(String.self, forKey: .messageId)
            delta = try? c.decode(String.self, forKey: .delta)
            lastAssistantMessage = try? c.decode(String.self, forKey: .lastAssistantMessage)
        }
    }

    /// Only the human-readable parts of a tool call.
    struct ToolInput: Decodable {
        var description: String?
        var filePath: String?
        var notebookPath: String?
        var url: String?
        var skill: String?
        var todos: [Todo]?

        struct Todo: Decodable {
            var status: String?
            var activeForm: String?
        }

        private enum CodingKeys: String, CodingKey {
            case description, filePath, notebookPath, url, skill, todos
        }

        init(description: String? = nil, filePath: String? = nil, url: String? = nil, skill: String? = nil, todos: [Todo]? = nil) {
            self.description = description
            self.filePath = filePath
            self.url = url
            self.skill = skill
            self.todos = todos
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = try? c.decode(String.self, forKey: .description)
            filePath = try? c.decode(String.self, forKey: .filePath)
            notebookPath = try? c.decode(String.self, forKey: .notebookPath)
            url = try? c.decode(String.self, forKey: .url)
            skill = try? c.decode(String.self, forKey: .skill)
            todos = try? c.decode([Todo].self, forKey: .todos)
        }
    }

    func event(from data: Data) -> ActivityEvent? {
        guard let payload = EventDecoder.payload(Payload.self, from: data) else { return nil }
        let now = Date()
        let session = payload.sessionId ?? "default"
        let project = payload.cwd.map { ($0 as NSString).lastPathComponent }
        let branch = payload.cwd.flatMap(branchLookup)

        if payload.hookEventName == "PreToolUse", payload.toolName == "TodoWrite", let todos = payload.toolInput?.todos {
            plans[session] = Plan(done: todos.filter { $0.status == "completed" }.count, total: todos.count)
        }
        let context = [project, branch, plans[session]?.label].compactMap { $0 }.joined(separator: " · ")

        func make(_ kind: ActivityEvent.Kind, _ title: String, detail: String? = nil, state: String,
                  priority: ActivityEvent.Priority = .normal, duration: TimeInterval? = nil,
                  expiresAfter: TimeInterval? = nil) -> ActivityEvent {
            var metadata = ["state": state]
            metadata["project"] = project
            metadata["branch"] = branch
            metadata["tool"] = payload.toolName
            return ActivityEvent(
                source: id,
                kind: kind,
                sessionID: payload.sessionId,
                title: title,
                detail: detail ?? (context.isEmpty ? nil : context),
                symbol: "sparkles",
                startDate: turnStarts[session],
                duration: duration,
                expiresAfter: expiresAfter,
                priority: priority,
                metadata: metadata,
                timestamp: now)
        }

        // Anything other than a new prompt for attention means you've answered.
        let wasWaiting = waiting.contains(session)
        if payload.hookEventName != "Notification" { waiting.remove(session) }

        switch payload.hookEventName {
        case "PostToolUse":
            // Fires as soon as you answer a question or approve a tool; only matters if Claude was waiting.
            guard wasWaiting else { return nil }
            let title = payload.toolName == "AskUserQuestion" ? "Got your answer, continuing" : "Approved, continuing"
            return make(.update, title, state: "working", expiresAfter: 2 * 3600)
        case "SessionStart":
            turnStarts[session] = nil
            return make(.started, "Session started", state: "idle")
        case "UserPromptSubmit":
            turnStarts[session] = now
            return make(.update, "Thinking…", state: "working", expiresAfter: 2 * 3600)
        case "PreToolUse":
            if turnStarts[session] == nil { turnStarts[session] = now }
            return make(.update, Self.step(forTool: payload.toolName, input: payload.toolInput),
                        state: "working", expiresAfter: 2 * 3600)
        case "MessageDisplay":
            // Show each new message once, as soon as its first readable line arrives.
            guard showsMessages(), let messageID = payload.messageId, shownMessages[session] != messageID,
                  let headline = Self.headline(from: payload.delta ?? "") else { return nil }
            shownMessages[session] = messageID
            if turnStarts[session] == nil { turnStarts[session] = now }
            return make(.update, headline, state: "working", expiresAfter: 2 * 3600)
        case "Notification":
            waiting.insert(session)
            return make(.alert, "Needs your attention", detail: payload.message, state: "attention",
                        priority: .high, expiresAfter: 2 * 3600)
        case "Stop":
            let duration = turnStarts.removeValue(forKey: session).map { now.timeIntervalSince($0) }
            let summary = showsMessages() ? payload.lastAssistantMessage.flatMap(Self.headline) : nil
            // A short ✓, then the notch goes back to whatever was there (e.g. your music).
            return make(.completed, "Finished", detail: summary, state: "done", duration: duration, expiresAfter: 12)
        case "SessionEnd":
            turnStarts[session] = nil
            plans[session] = nil
            shownMessages[session] = nil
            return make(.ended, "Session ended", state: "idle")
        default:
            return nil
        }
    }

    /// Plan usage from Claude Code's status line JSON (`rate_limits.five_hour` / `seven_day`).
    /// Only these numbers are decoded; everything else in the status line input is ignored.
    static func usage(from data: Data, now: Date = .now) -> ClaudeUsage? {
        struct StatusLine: Decodable {
            struct Limits: Decodable { let fiveHour: Window?; let sevenDay: Window? }
            struct Window: Decodable { let usedPercentage: Double; let resetsAt: Double }
            let rateLimits: Limits?
        }
        guard let limits = EventDecoder.payload(StatusLine.self, from: data)?.rateLimits else { return nil }
        func window(_ value: StatusLine.Window?) -> UsageWindow? {
            value.map { UsageWindow(usedPercent: $0.usedPercentage, resetsAt: Date(timeIntervalSince1970: $0.resetsAt)) }
        }
        return ClaudeUsage(fiveHour: window(limits.fiveHour), sevenDay: window(limits.sevenDay), updatedAt: now).current(now: now)
    }

    /// The step Claude is on, in plain words.
    static func step(forTool tool: String?, input: ToolInput?) -> String {
        guard let tool else { return "Working…" }
        let file = (input?.filePath ?? input?.notebookPath).map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Bash":
            return input?.description.flatMap(Self.cleaned) ?? "Running a command"
        case "Read":
            return file.map { "Reading \($0)" } ?? "Reading files"
        case "Edit", "MultiEdit", "NotebookEdit":
            return file.map { "Editing \($0)" } ?? "Editing files"
        case "Write":
            return file.map { "Writing \($0)" } ?? "Writing a file"
        case "Grep", "Glob", "LS":
            return "Searching the code"
        case "WebFetch":
            return input?.url.flatMap { URL(string: $0)?.host() }.map { "Reading \($0)" } ?? "Browsing the web"
        case "WebSearch":
            return "Searching the web"
        case "Task", "Agent":
            return input?.description.flatMap(Self.cleaned).map { "Subagent: \($0)" } ?? "Running a subagent"
        case "TodoWrite":
            return input?.todos?.first { $0.status == "in_progress" }?.activeForm.flatMap(Self.cleaned) ?? "Updating the plan"
        case "Skill":
            return input?.skill.map { "Using the \($0) skill" } ?? "Using a skill"
        default:
            if tool.hasPrefix("mcp__") {
                let server = tool.split(separator: "_").dropFirst().first.map(String.init) ?? "a tool"
                return "Using \(server)"
            }
            return "Using \(tool)"
        }
    }

    /// The first readable line of a message: skips code blocks and tables, strips markdown
    /// (headings, bullets, bold, code ticks, links), at most 120 characters.
    static func headline(from text: String) -> String? {
        var inCode = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode || trimmed.isEmpty || trimmed.hasPrefix("|") { continue }
            let plain = trimmed
                .replacingOccurrences(of: #"^(#{1,6}\s+|[-*+]\s+|>\s*|\d+\.\s+)+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            if let line = cleaned(plain) { return line }
        }
        return nil
    }

    /// One line, no surrounding whitespace, at most 120 characters.
    private static func cleaned(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return nil }
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }
}
