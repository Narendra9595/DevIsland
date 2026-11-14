import Foundation
import Testing
@testable import DevIsland

@MainActor
struct AgentAdapterTests {
    private func message(_ source: String, _ payload: String) -> Data {
        Data(#"{"source":"\#(source)","payload":\#(payload)}"#.utf8)
    }

    private func claude() -> ClaudeCodeIntegration {
        let adapter = ClaudeCodeIntegration()
        adapter.branchLookup = { _ in "main" }
        return adapter
    }

    @Test func toolUseBecomesAFriendlyWorkingUpdate() throws {
        let data = message("claude", #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/x/MyApp","tool_name":"Bash"}"#)
        let event = try #require(claude().event(from: data))
        #expect(event.kind == .update)
        #expect(event.title == "Running a command")
        #expect(event.detail == "MyApp · main")
        #expect(event.sessionID == "s1")
        #expect(event.metadata["state"] == "working")
        #expect(event.metadata["tool"] == "Bash")
        #expect(event.startDate != nil)
    }

    @Test func neverKeepsThePrompt() throws {
        let data = message("claude", #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"my secret plan"}"#)
        let event = try #require(claude().event(from: data))
        let everything = [event.title, event.detail ?? ""] + Array(event.metadata.values)
        #expect(!everything.contains { $0.contains("secret") })
    }

    @Test func stopReportsHowLongTheTurnTook() throws {
        let adapter = claude()
        _ = adapter.event(from: message("claude", #"{"hook_event_name":"UserPromptSubmit","session_id":"s1"}"#))
        let stop = try #require(adapter.event(from: message("claude", #"{"hook_event_name":"Stop","session_id":"s1"}"#)))
        #expect(stop.kind == .completed)
        #expect(stop.duration != nil)
        #expect(stop.metadata["state"] == "done")
    }

    @Test func notificationAsksForAttention() throws {
        let data = message("claude", #"{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission to use Bash"}"#)
        let event = try #require(claude().event(from: data))
        #expect(event.kind == .alert)
        #expect(event.priority == .high)
        #expect(event.detail == "Claude needs your permission to use Bash")
    }

    @Test func readsPlanUsageFromTheStatusLine() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let data = message("claude-usage",
            #"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":58,"resets_at":1003600},"seven_day":{"used_percentage":19.5,"resets_at":999000}}}"#)
        let usage = try #require(ClaudeCodeIntegration.usage(from: data, now: now))
        #expect(abs((usage.fiveHour?.leftFraction ?? 0) - 0.42) < 0.0001)
        #expect(usage.sevenDay == nil) // its reset time already passed
        #expect(ClaudeCodeIntegration.usage(from: message("claude-usage", #"{"model":{}}"#), now: now) == nil)
    }

    @Test func answeringClearsNeedsYouRightAway() throws {
        let adapter = claude()
        _ = adapter.event(from: message("claude", #"{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission"}"#))
        let answered = try #require(adapter.event(from: message("claude",
            #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"AskUserQuestion"}"#)))
        #expect(answered.metadata["state"] == "working")
        // Ordinary tool completions don't produce extra events.
        #expect(adapter.event(from: message("claude", #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Read"}"#)) == nil)
    }

    @Test func namesStepsInPlainWords() {
        typealias Input = ClaudeCodeIntegration.ToolInput
        #expect(ClaudeCodeIntegration.step(forTool: "Bash", input: Input(description: "Check app process and socket")) == "Check app process and socket")
        #expect(ClaudeCodeIntegration.step(forTool: "Bash", input: nil) == "Running a command")
        #expect(ClaudeCodeIntegration.step(forTool: "Edit", input: Input(filePath: "/x/App/IslandView.swift")) == "Editing IslandView.swift")
        #expect(ClaudeCodeIntegration.step(forTool: "Read", input: Input(filePath: "/x/README.md")) == "Reading README.md")
        #expect(ClaudeCodeIntegration.step(forTool: "WebFetch", input: Input(url: "https://example.com/docs")) == "Reading example.com")
        #expect(ClaudeCodeIntegration.step(forTool: "Agent", input: Input(description: "Review the diff")) == "Subagent: Review the diff")
        #expect(ClaudeCodeIntegration.step(forTool: "Grep", input: nil) == "Searching the code")
        #expect(ClaudeCodeIntegration.step(forTool: "mcp__github__create_issue", input: nil) == "Using github")
        #expect(ClaudeCodeIntegration.step(forTool: "Mystery", input: nil) == "Using Mystery")
    }

    @Test func showsTheCommandDescriptionButNeverTheCommandOrFileContents() throws {
        let adapter = claude()
        let bash = try #require(adapter.event(from: message("claude",
            #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"curl -H 'token: SECRET1'","description":"Fetch the release list"}}"#)))
        #expect(bash.title == "Fetch the release list")
        let write = try #require(adapter.event(from: message("claude",
            #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Write","tool_input":{"file_path":"/x/Keys.swift","content":"let key = SECRET2"}}"#)))
        #expect(write.title == "Writing Keys.swift")
        for event in [bash, write] {
            let everything = [event.title, event.detail ?? ""] + Array(event.metadata.values)
            #expect(!everything.contains { $0.contains("SECRET") })
        }
    }

    @Test func showsTheFirstLineOfWhatClaudeSays() throws {
        let adapter = claude()
        let first = try #require(adapter.event(from: message("claude",
            #"{"hook_event_name":"MessageDisplay","session_id":"s1","message_id":"m1","index":0,"final":false,"delta":"I'll check the running app first.\nThen we fix it."}"#)))
        #expect(first.title == "I'll check the running app first.")
        #expect(first.metadata["state"] == "working")
        // More lines of the same message don't change the island again.
        #expect(adapter.event(from: message("claude",
            #"{"hook_event_name":"MessageDisplay","session_id":"s1","message_id":"m1","index":1,"final":true,"delta":"More text"}"#)) == nil)
    }

    @Test func headlinesSkipCodeAndMarkdown() {
        #expect(ClaudeCodeIntegration.headline(from: "```swift\nlet x = 1\n```\n## **Where** we are") == "Where we are")
        #expect(ClaudeCodeIntegration.headline(from: "- See [README.md](README.md) for `details`") == "See README.md for details")
        #expect(ClaudeCodeIntegration.headline(from: "| a | b |\n\n") == nil)
    }

    @Test func finishedTurnsCarryASummary() throws {
        let stop = try #require(claude().event(from: message("claude",
            #"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"**Done.** The island now shows each step.\n\nDetails follow."}"#)))
        #expect(stop.detail == "Done. The island now shows each step.")
    }

    @Test func messagesCanBeTurnedOff() {
        let adapter = claude()
        adapter.showsMessages = { false }
        #expect(adapter.event(from: message("claude",
            #"{"hook_event_name":"MessageDisplay","session_id":"s1","message_id":"m1","delta":"Hello"}"#)) == nil)
    }

    @Test func followsThePlanStep() throws {
        let adapter = claude()
        let plan = #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/x/App","tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Build","status":"completed","activeForm":"Building"},{"content":"Test","status":"in_progress","activeForm":"Running the tests"},{"content":"Ship","status":"pending","activeForm":"Shipping"}]}}"#
        let planned = try #require(adapter.event(from: message("claude", plan)))
        #expect(planned.title == "Running the tests")
        #expect(planned.detail == "App · main · Step 2 of 3")
        let next = try #require(adapter.event(from: message("claude",
            #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/x/App","tool_name":"Read","tool_input":{"file_path":"/x/App/Tests.swift"}}"#)))
        #expect(next.detail == "App · main · Step 2 of 3")
    }

    @Test func ignoresUntrackedEvents() {
        #expect(claude().event(from: message("claude", #"{"hook_event_name":"PostToolUse"}"#)) == nil)
    }

    @Test func codexTurnCompleteIsFinishedWork() throws {
        let data = message("codex", #"{"type":"agent-turn-complete","turn-id":"1","cwd":"/x/Web"}"#)
        let event = try #require(CodexIntegration().event(from: data))
        #expect(event.kind == .completed)
        #expect(event.detail == "Web")
    }

    @Test func malformedMessagesHaveNoSource() {
        #expect(EventDecoder.source(of: Data("not json".utf8)) == nil)
    }
}

@MainActor
struct IntegrationManagerTests {
    private func makeManager() throws -> (IntegrationManager, EventRecorder, DiagnosticsLog) {
        let suite = "devisland-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let bus = EventBus()
        let log = DiagnosticsLog()
        let claude = ClaudeCodeIntegration()
        claude.branchLookup = { _ in nil }
        let manager = IntegrationManager(integrations: [claude, ClipboardIntegration()], defaults: defaults,
                                         bus: bus, store: ActivityStore(database: nil), log: log)
        let recorder = EventRecorder()
        bus.subscribe(recorder.record)
        return (manager, recorder, log)
    }

    @Test func routesHookMessagesToTheMatchingAdapter() throws {
        let (manager, recorder, log) = try makeManager()
        manager.receive(Data(#"{"source":"claude","payload":{"hook_event_name":"Stop","session_id":"a"}}"#.utf8))
        #expect(recorder.events.map(\.kind) == [.completed])
        manager.receive(Data(#"{"source":"unknown","payload":{}}"#.utf8))
        #expect(recorder.events.count == 1)
        #expect(log.entries.first?.level == .warning)
    }

    @Test func ignoresMessagesForDisabledIntegrations() throws {
        let (manager, recorder, _) = try makeManager()
        manager.setEnabled(false, for: "claude")
        manager.receive(Data(#"{"source":"claude","payload":{"hook_event_name":"Stop","session_id":"a"}}"#.utf8))
        #expect(recorder.events.isEmpty)
    }

    @Test func clipboardIsOptIn() throws {
        let (manager, _, _) = try makeManager()
        #expect(manager.isEnabled("claude"))
        #expect(!manager.isEnabled("clipboard"))
    }

    @Test func forwardsCommandsFromAnotherInstance() throws {
        let (manager, _, _) = try makeManager()
        var command: String?
        manager.onAppCommand = { command = $0 }
        manager.receive(Data(#"{"source":"devisland","payload":{"command":"open-dashboard"}}"#.utf8))
        #expect(command == "open-dashboard")
    }
}

@MainActor
struct TimerIntegrationTests {
    @Test func startsPausesResumesAndStops() throws {
        let timer = TimerIntegration()
        let recorder = EventRecorder()
        timer.start(publish: recorder.record)
        defer { timer.stop() }

        timer.perform(action: "focus")
        let started = try #require(recorder.events.last)
        #expect(started.kind == .started)
        #expect(started.duration == 1_500)
        #expect(started.endDate != nil)
        #expect(started.actions.map(\.id) == ["pause", "stop"])

        timer.perform(action: "pause")
        let paused = try #require(recorder.events.last)
        #expect(paused.kind == .update)
        #expect(paused.endDate == nil)
        #expect(paused.actions.first?.id == "resume")

        timer.perform(action: "resume")
        #expect(recorder.events.last?.endDate != nil)

        timer.perform(action: "stop")
        #expect(recorder.events.last?.kind == .ended)
    }
}

@MainActor
struct ClipboardTests {
    @Test func copyingAgainMovesToTopAndKeepsThePin() {
        let clipboard = ClipboardIntegration()
        clipboard.record("one")
        clipboard.record("two")
        clipboard.togglePin(clipboard.items[1])
        clipboard.record("one")
        #expect(clipboard.items.map(\.text) == ["one", "two"])
        #expect(clipboard.items[0].isPinned)
    }

    @Test func clearKeepsPinnedItems() {
        let clipboard = ClipboardIntegration()
        clipboard.record("keep")
        clipboard.togglePin(clipboard.items[0])
        clipboard.record("drop")
        clipboard.clear()
        #expect(clipboard.items.map(\.text) == ["keep"])
    }

    @Test func ignoresBlankTextAndCapsTheList() {
        let clipboard = ClipboardIntegration()
        clipboard.record("   ")
        #expect(clipboard.items.isEmpty)
        for index in 0..<70 { clipboard.record("item \(index)") }
        #expect(clipboard.items.count == 60)
        #expect(clipboard.items.first?.text == "item 69")
    }

    @Test func recognizesLinks() {
        #expect(ClipItem(text: "https://apple.com", date: .now).isLink)
        #expect(!ClipItem(text: "not a link", date: .now).isLink)
    }
}

@MainActor
struct ClaudeHookInstallerTests {
    let command = ClaudeHookInstaller.command(scriptPath: "/Users/me/Library/Application Support/DevIsland/bin/devisland-hook")

    private func hooks(_ settings: [String: Any]) -> [String: Any]? {
        settings["hooks"] as? [String: Any]
    }

    @Test func quotesTheScriptPathForTheShell() {
        #expect(command == "'/Users/me/Library/Application Support/DevIsland/bin/devisland-hook' claude")
        #expect(ClaudeHookInstaller.command(scriptPath: "/it's/devisland-hook") == #"'/it'\''s/devisland-hook' claude"#)
    }

    @Test func addsOneHookPerEvent() {
        let merged = ClaudeHookInstaller.merged([:], command: command)
        #expect(hooks(merged)?.count == ClaudeHookInstaller.events.count)
        #expect(ClaudeHookInstaller.status(of: merged, command: command) == .installed)
        let preToolUse = (hooks(merged)?["PreToolUse"] as? [[String: Any]])?.first
        #expect(preToolUse?["matcher"] as? String == "*")
    }

    @Test func keepsTheUsersOwnSettingsAndHooks() {
        let userHook: [String: Any] = ["matcher": "Bash", "hooks": [["type": "command", "command": "echo mine"]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [userHook]]]
        let merged = ClaudeHookInstaller.merged(settings, command: command)
        #expect(merged["model"] as? String == "opus")
        #expect((hooks(merged)?["PreToolUse"] as? [[String: Any]])?.count == 2)

        let removed = ClaudeHookInstaller.removed(merged)
        #expect((hooks(removed)?["PreToolUse"] as? [[String: Any]])?.count == 1)
        #expect(hooks(removed)?.count == 1)
        #expect(ClaudeHookInstaller.status(of: removed, command: command) == .notInstalled)
    }

    @Test func installingTwiceDoesNotDuplicate() {
        let twice = ClaudeHookInstaller.merged(ClaudeHookInstaller.merged([:], command: command), command: command)
        #expect((hooks(twice)?["Stop"] as? [[String: Any]])?.count == 1)
    }

    @Test func updatesHooksFromAnOldLocation() {
        let old = ClaudeHookInstaller.merged([:], command: "'/old/devisland-hook' claude")
        #expect(ClaudeHookInstaller.status(of: old, command: command) == .outdated)
        let updated = ClaudeHookInstaller.merged(old, command: command)
        #expect(ClaudeHookInstaller.status(of: updated, command: command) == .installed)
    }

    @Test func installsAndUninstallsOnDiskWithABackup() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "devisland-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settingsURL = folder.appending(path: "settings.json")
        let scriptURL = folder.appending(path: "bin/devisland-hook")
        try Data(#"{"theme": "dark"}"#.utf8).write(to: settingsURL)

        let installer = ClaudeHookInstaller(settingsURL: settingsURL, scriptURL: scriptURL)
        try installer.install()
        #expect(installer.status == .installed)
        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        let backup = try #require(installer.lastBackup)
        #expect(FileManager.default.fileExists(atPath: backup.path))

        let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        #expect(saved["theme"] as? String == "dark")

        try installer.uninstall()
        let cleaned = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        #expect(cleaned["hooks"] == nil)
        #expect(cleaned["theme"] as? String == "dark")
    }

    @Test func leavesInvalidSettingsUntouched() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "devisland-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settingsURL = folder.appending(path: "settings.json")
        try Data("{ not json".utf8).write(to: settingsURL)

        let installer = ClaudeHookInstaller(settingsURL: settingsURL, scriptURL: folder.appending(path: "bin/devisland-hook"))
        #expect(throws: ClaudeHookInstaller.InstallError.self) { try installer.install() }
        #expect(try String(contentsOf: settingsURL, encoding: .utf8) == "{ not json")
        #expect(installer.lastError != nil)
    }
}

/// Collects messages from the socket's background queue.
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func append(_ data: Data) { lock.withLock { items.append(data) } }
    var first: Data? { lock.withLock { items.first } }
}

struct LocalBridgeTests {
    @Test func deliversMessagesAndDetectsASecondInstance() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "di-\(UUID().uuidString.prefix(8)).sock").path
        let inbox = Inbox()
        let server = IPCServer(path: path, onMessage: { inbox.append($0) }, onReject: { _ in })
        #expect(server.start() == .listening)
        defer { server.stop() }

        let second = IPCServer(path: path, onMessage: { _ in }, onReject: { _ in })
        #expect(second.start() == .alreadyRunning)

        let message = Data(#"{"source":"claude","payload":{}}"#.utf8)
        #expect(IPCServer.send(message, to: path))
        var attempts = 0
        while inbox.first == nil && attempts < 100 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(inbox.first == message)
    }
}
