import Foundation
import Observation

/// The AI tools "Ask" can use: whichever are installed and signed in on this Mac.
enum AskProvider: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var name: String { self == .claude ? "Claude" : "Codex" }

    /// The installed command-line tool, from a standalone install, Homebrew or an editor extension.
    var binary: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let name = self == .claude ? "claude" : "codex"
        let fixed = [".local/bin/\(name)", ".claude/local/claude", ".npm-global/bin/\(name)"].map { home.appending(path: $0) }
            + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"].map { URL(filePath: $0) }
        if let found = fixed.first(where: { $0.lastPathComponent == name && FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        let prefix = self == .claude ? "anthropic.claude-code-" : "openai.chatgpt-"
        let inside = self == .claude ? "resources/native-binary/claude" : "bin/macos-aarch64/codex"
        for editor in [".antigravity-ide", ".vscode", ".cursor", ".windsurf"] {
            let extensions = home.appending(path: "\(editor)/extensions")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: extensions.path)) ?? []
            for folder in names.filter({ $0.hasPrefix(prefix) }).sorted().reversed() {
                let url = extensions.appending(path: "\(folder)/\(inside)")
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// Where to ask in the browser, with the question filled in (uses your browser's sign-in).
    func webURL(for question: String) -> URL? {
        let encoded = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: self == .claude ? "https://claude.ai/new?q=\(encoded)" : "https://chatgpt.com/?q=\(encoded)")
    }

    var webName: String { self == .claude ? "claude.ai" : "ChatGPT" }

    /// Official pages explaining how to install the command-line tool.
    var installURL: URL {
        URL(string: self == .claude ? "https://claude.ai/code" : "https://developers.openai.com/codex/cli")!
    }

    enum Status: Equatable { case unknown, notInstalled, signedOut, signedIn }
}

/// "Ask" from the notch: runs Claude Code or Codex in the background with your existing sign-in and
/// shows the answer. Read-only: Claude gets no tools at all, Codex runs in its read-only sandbox.
/// Your hooks and notifications aren't triggered by these questions.
@MainActor
@Observable
final class AskService {
    enum State: Equatable {
        case idle, asking, done
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var provider = AskProvider.claude
    /// The current question and its answer (streaming in while asking).
    private(set) var question = ""
    private(set) var answer = ""
    /// Earlier questions and answers in this chat; sent along so follow-ups have context.
    private(set) var history: [ChatTurn] = []

    struct ChatTurn: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let answer: String
        let provider: AskProvider
    }
    /// When the last answer finished, so the island can reopen on it for a little while.
    private(set) var finishedAt: Date?

    /// Asking now, or answered in the last two minutes and not closed.
    var isFresh: Bool {
        if state == .asking { return true }
        guard let finishedAt, !question.isEmpty else { return false }
        return Date.now.timeIntervalSince(finishedAt) < 120
    }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    /// Installed and signed in, per tool (checked with each tool's own status command).
    private(set) var statuses: [AskProvider: AskProvider.Status] = [:]

    /// The AI tools ready to answer in the island.
    var providers: [AskProvider] { AskProvider.allCases.filter { statuses[$0] == .signedIn } }

    /// Tools being installed right now, and why an install failed.
    private(set) var installing: Set<AskProvider> = []
    private(set) var installErrors: [AskProvider: String] = [:]

    /// Re-checks which tools are installed and signed in.
    func refreshProviders() {
        Task { await refresh() }
    }

    private func refresh() async {
        for provider in AskProvider.allCases { statuses[provider] = await Self.status(of: provider) }
    }

    /// The official install command: Anthropic's installer for Claude Code; Homebrew or npm for Codex.
    /// nil when there's no way to install from here (then Settings opens the install page instead).
    static func installCommand(for provider: AskProvider) -> String? {
        let tools = ["/opt/homebrew/bin", "/usr/local/bin"]
        let brew = tools.map { "\($0)/brew" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        let npm = tools.map { "\($0)/npm" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        switch provider {
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex:
            if let brew { return "\(brew) install --cask codex" }
            if let npm { return "\(npm) install -g @openai/codex" }
            return nil
        }
    }

    /// Installs the tool, then opens its sign-in. Nothing needs an admin password.
    func install(_ provider: AskProvider) {
        guard let command = Self.installCommand(for: provider), !installing.contains(provider) else { return }
        installing.insert(provider)
        installErrors[provider] = nil
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", command]
        process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                               "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "USER": NSUserName(),
                               "NONINTERACTIVE": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let ok = finished.terminationStatus == 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.installing.remove(provider)
                await self.refresh()
                if !ok || self.statuses[provider] == .notInstalled {
                    self.installErrors[provider] = "Install didn't finish. Try “How to Install” instead."
                } else if self.statuses[provider] == .signedOut {
                    self.signIn(provider) // straight on to the browser sign-in
                }
            }
        }
        do {
            try process.run()
        } catch {
            installing.remove(provider)
            installErrors[provider] = "Couldn't start the installer."
        }
    }

    /// Opens the tool's official sign-in in your browser; re-checks when it finishes.
    func signIn(_ provider: AskProvider) {
        runTool(provider, arguments: provider == .claude ? ["auth", "login"] : ["login"])
    }

    func signOut(_ provider: AskProvider) {
        runTool(provider, arguments: provider == .claude ? ["auth", "logout"] : ["logout"])
    }

    private func runTool(_ provider: AskProvider, arguments: [String]) {
        guard let binary = provider.binary else { return }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in self?.refreshProviders() } }
        try? process.run()
    }

    private static func status(of provider: AskProvider) async -> AskProvider.Status {
        guard let binary = provider.binary else { return .notInstalled }
        return await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = binary
            process.arguments = provider == .claude ? ["auth", "status", "--json"] : ["login", "status"]
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return .signedOut }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if provider == .claude {
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                return object?["loggedIn"] as? Bool == true ? .signedIn : .signedOut
            }
            let text = String(decoding: data, as: UTF8.self).lowercased()
            return process.terminationStatus == 0 && text.contains("logged in") && !text.contains("not logged in") ? .signedIn : .signedOut
        }.value
    }
    /// A Codex model your sign-in supports (your config may name one it doesn't).
    @ObservationIgnored private var codexModel: String?

    /// Folder the tools run in: empty, so there's no project for them to pick up.
    private static let folder: URL = {
        let url = AppPaths.folder.appending(path: "ask", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Ask's own instructions (instead of the coding-agent ones, which describe tools it doesn't have here).
    private static let brevity = """
        You are a helpful assistant answering in a small panel in the Mac's notch. Be brief and direct; use short paragraphs or a short list.
        You have no tools and no access to this computer, its files, projects, terminal or the internet. Never write tool calls, commands to run, \
        or XML. If a question needs the user's files or project, say in one sentence that you can't see them from here and suggest asking \
        Claude Code in their editor; then help with what you can from general knowledge.
        """

    func ask(_ text: String, using provider: AskProvider) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancel()
        if !question.isEmpty, !answer.isEmpty {
            history.append(ChatTurn(question: question, answer: answer, provider: self.provider))
            if history.count > 20 { history.removeFirst() }
        }
        self.provider = provider
        question = text
        answer = ""
        finishedAt = nil
        guard let binary = provider.binary else {
            state = .failed("\(provider.name) isn't installed on this Mac.")
            return
        }
        state = .asking
        Task {
            if provider == .codex, codexModel == nil { codexModel = await Self.supportedCodexModel(binary) }
            guard state == .asking, question == text else { return }
            run(binary, arguments: arguments(for: provider, question: Self.prompt(text, after: history)))
        }
    }

    func cancel() {
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        if state == .asking { state = answer.isEmpty ? .idle : .done }
    }

    /// Closed by you: keep the conversation, but don't reopen the island on it.
    func dismiss() {
        finishedAt = nil
    }

    func reset() {
        cancel()
        state = .idle
        question = ""
        answer = ""
        history = []
        finishedAt = nil
    }

    private func arguments(for provider: AskProvider, question: String) -> [String] {
        switch provider {
        case .claude:
            ["-p", question, "--output-format", "stream-json", "--verbose", "--include-partial-messages",
             "--tools", "", "--strict-mcp-config", "--setting-sources", "local", "--no-session-persistence",
             "--system-prompt", Self.brevity]
        case .codex:
            ["exec", "--json", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "--color", "never",
             "-c", "notify=[]"] + (codexModel.map { ["-m", $0] } ?? []) + ["\(Self.brevity)\n\n\(question)"]
        }
    }

    private func run(_ binary: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = Self.folder
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.finish(status: status) }
        }
        buffer = Data()
        self.process = process
        do {
            try process.run()
        } catch {
            state = .failed("Couldn't start \(provider.name): \(error.localizedDescription)")
        }
    }

    /// One JSON object per line, in each tool's own format.
    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            provider == .claude ? receiveClaude(object) : receiveCodex(object)
        }
    }

    /// Claude: text deltas as they arrive, then the final result (or an error).
    private func receiveClaude(_ object: [String: Any]) {
        switch object["type"] as? String {
        case "stream_event":
            let event = object["event"] as? [String: Any]
            if event?["type"] as? String == "content_block_delta",
               let text = (event?["delta"] as? [String: Any])?["text"] as? String {
                answer += text
                if Self.looksLikeToolCalls(answer) {
                    cancel()
                    finishedAt = .now
                    state = .failed("This needs your files or project, which Ask can't see. Ask Claude Code in your editor for that.")
                }
            }
        case "result":
            if object["is_error"] as? Bool == true {
                state = .failed((object["result"] as? String) ?? "Claude couldn't answer. Try again.")
            } else if let result = object["result"] as? String, !result.isEmpty {
                answer = Self.withoutToolCalls(result)
            }
        default:
            break
        }
    }

    /// Codex: the finished message, or why the turn failed (e.g. a usage limit).
    private func receiveCodex(_ object: [String: Any]) {
        let item = object["item"] as? [String: Any]
        switch object["type"] as? String {
        case "item.completed" where item?["type"] as? String == "agent_message":
            if let text = item?["text"] as? String { answer = text }
        case "turn.failed":
            let message = (object["error"] as? [String: Any])?["message"] as? String
            state = .failed(message ?? "Codex couldn't answer. Try again.")
        default:
            break
        }
    }

    private func finish(status: Int32) {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        finishedAt = .now
        if case .failed = state { return }
        if answer.isEmpty {
            state = .failed(status == 0 ? "No answer came back. Try again."
                            : "\(provider.name) stopped. Open it once in your editor to sign in, then try again.")
        } else {
            state = .done
        }
    }

    /// The question with the recent conversation before it (the tools run fresh each time, so they need the context).
    private static func prompt(_ question: String, after history: [ChatTurn]) -> String {
        guard !history.isEmpty else { return question }
        let earlier = history.suffix(8).map { "User: \($0.question.prefix(1500))\nAssistant: \($0.answer.prefix(1500))" }
        return "Conversation so far:\n\n\(earlier.joined(separator: "\n\n"))\n\nUser: \(question)"
    }

    /// True when the answer so far is only pretend tool calls (a model trying to use tools it doesn't have).
    private static func looksLikeToolCalls(_ text: String) -> Bool {
        let lower = text.lowercased()
        return (lower.contains("<invoke") || lower.contains("<function_calls") || lower.contains("<parameter name="))
            && withoutToolCalls(text).trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    /// Removes pretend tool-call markup from an answer.
    private static func withoutToolCalls(_ text: String) -> String {
        var result = text
        for pattern in ["(?s)<function_calls>.*?</function_calls>", "(?s)<invoke[^>]*>.*?</invoke>", "(?s)<invoke[^>]*>.*$"] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first model Codex lists for your sign-in.
    private static func supportedCodexModel(_ binary: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = binary
            process.arguments = ["debug", "models"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let models = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]]
            return models?.first { $0["visibility"] as? String == "list" }?["slug"] as? String
        }.value
    }
}
