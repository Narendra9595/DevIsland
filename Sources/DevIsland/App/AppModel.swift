import AppKit
import Observation
import UniformTypeIdentifiers

enum SocketStatus: Equatable {
    case starting, listening, failed(String)
}

/// Opens the app's windows. Implemented by `WindowManager`.
@MainActor
protocol WindowPresenting: AnyObject {
    func showDashboard(_ section: DashboardSection?)
    /// Opens Settings, on a specific tab ("Customize", "AI"…) when given.
    func showSettings(tab: String?)
    func showOnboarding()
}

extension WindowPresenting {
    func showSettings() { showSettings(tab: nil) }
}

/// Everything the app knows and can do. Shared by the island, dashboard, settings and menu.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    let bus: EventBus
    let store: ActivityStore
    let diagnostics: DiagnosticsLog
    let shelf: FileShelf
    let systemMonitor: SystemMonitor
    let hookInstaller: ClaudeHookInstaller

    let claude: ClaudeCodeIntegration
    let codex: CodexIntegration
    let timer: TimerIntegration
    let media: MediaIntegration
    let battery: BatteryIntegration
    let network: NetworkIntegration
    let clipboard: ClipboardIntegration
    let integrations: IntegrationManager
    let keepAwake = KeepAwake()
    let hud = HUDMonitor()
    let ask = AskService()
    let updates = UpdateChecker()
    @ObservationIgnored private(set) lazy var mediaKeys = MediaKeyTap(hud: hud)
    @ObservationIgnored private var mediaKeysTask: Task<Void, Never>?

    var dashboardSection: DashboardSection? = .overview
    var socketStatus: SocketStatus = .starting
    private(set) var today = DayStats()
    private(set) var toast: Toast?
    /// Claude Code plan limits (5-hour and weekly), remembered across launches.
    private(set) var claudeUsage: ClaudeUsage?
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored weak var windows: (any WindowPresenting)?
    @ObservationIgnored var toggleIsland: () -> Void = {}
    /// Opens the island on a page and keeps it open (e.g. ⌃⌥V for the clipboard).
    @ObservationIgnored var openIsland: (IslandPage) -> Void = { _ in }
    /// Opens the island on a page and keeps it open until you close it (keyboard shortcuts).
    @ObservationIgnored var openIslandPinned: (IslandPage) -> Void = { _ in }
    @ObservationIgnored var floatingPlayer: FloatingPlayerController?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(database: EventDatabase?, defaults: UserDefaults = .standard, hookInstaller: ClaudeHookInstaller? = nil) {
        let preferences = Preferences(defaults: defaults)
        let bus = EventBus()
        let store = ActivityStore(database: database)
        let diagnostics = DiagnosticsLog()
        let claude = ClaudeCodeIntegration()
        let codex = CodexIntegration()
        let timer = TimerIntegration()
        let media = MediaIntegration()
        let battery = BatteryIntegration()
        let network = NetworkIntegration()
        let call = CallIntegration()
        call.onMicApp = { [weak diagnostics] text in diagnostics?.add(text) }
        let clipboard = ClipboardIntegration()

        self.preferences = preferences
        self.defaults = defaults
        self.bus = bus
        self.store = store
        self.diagnostics = diagnostics
        self.shelf = FileShelf(defaults: defaults)
        self.systemMonitor = SystemMonitor()
        self.hookInstaller = hookInstaller ?? ClaudeHookInstaller()
        self.claude = claude
        self.codex = codex
        self.timer = timer
        self.media = media
        self.battery = battery
        self.network = network
        self.clipboard = clipboard
        self.integrations = IntegrationManager(
            integrations: [claude, codex, timer, media, battery, network, clipboard, DownloadsIntegration(), call],
            defaults: defaults, bus: bus, store: store, log: diagnostics)

        claude.showsMessages = { [weak preferences] in preferences?.showAgentMessages ?? true }
        claudeUsage = defaults.data(forKey: Self.usageKey)
            .flatMap { try? JSONDecoder().decode(ClaudeUsage.self, from: $0) }?.current()
        media.onAutomationDenied = { [weak diagnostics] player in
            diagnostics?.add("macOS blocked control of \(player). Allow it in System Settings → Privacy & Security → Automation.", level: .warning)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }

        if database == nil {
            diagnostics.add("The history database couldn't be opened; history won't be saved.", level: .error)
        }
    }

    /// Wires everything up and starts the enabled integrations.
    func start() {
        _ = EnergyUsage.launchDate
        Task { // the Energy card's averages start once launching has settled
            try? await Task.sleep(for: .seconds(15))
            EnergyUsage.baseline = EnergyUsage.read()
        }
        bus.subscribe { [weak self] event in self?.didReceive(event) }
        integrations.onClaudeUsage = { [weak self] data in self?.updateClaudeUsage(data) }
        do {
            try HookScript.installStatusLine()
        } catch {
            diagnostics.add("Couldn't install the status line script: \(error.localizedDescription)", level: .error)
        }
        applyRetention()
        integrations.startEnabled()
        hud.start { [weak preferences] in preferences?.showHUDs ?? false }
        applyMediaKeys(askPermission: false)
        ask.refreshProviders()
        if Bundle.main.bundleIdentifier != nil {
            updates.start { [weak preferences] in preferences?.checkForUpdates ?? false }
        }
        do {
            try HookScript.install()
        } catch {
            diagnostics.add("Couldn't install the hook script: \(error.localizedDescription)", level: .error)
        }
        hookInstaller.refresh()
        refreshToday()
    }

    private func didReceive(_ event: ActivityEvent) {
        store.handle(event)
        if event.kind.isLogged { refreshToday() }
    }

    private static let usageKey = "claudeUsage"

    private func updateClaudeUsage(_ data: Data) {
        guard let usage = ClaudeCodeIntegration.usage(from: data), usage != claudeUsage else { return }
        claudeUsage = usage
        if let encoded = try? JSONEncoder().encode(usage) { defaults.set(encoded, forKey: Self.usageKey) }
    }

    /// Usage without windows that have reset since it was reported.
    var currentClaudeUsage: ClaudeUsage? { claudeUsage?.current() }

    func refreshToday() {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let events = store.database?.events(since: startOfDay) ?? store.history.filter { $0.timestamp >= startOfDay }
        today = ActivityStats.day(events)
    }

    // MARK: Actions

    /// Turns the volume/brightness key takeover on or off to match Settings.
    /// Asks for Accessibility when needed, then starts as soon as it's allowed.
    func applyMediaKeys(askPermission: Bool) {
        mediaKeysTask?.cancel()
        guard preferences.replaceSystemHUD, preferences.showHUDs else { mediaKeys.stop(); return }
        if mediaKeys.start() { return }
        if askPermission { clipboard.requestPastePermission() } // the same Accessibility prompt
        mediaKeysTask = Task { [weak self] in
            for _ in 0..<90 { // wait up to 3 minutes for the switch in System Settings
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if self.mediaKeys.start() { return }
            }
        }
    }

    func startFocus() {
        if !integrations.isEnabled(TimerIntegration.sourceID) {
            integrations.setEnabled(true, for: TimerIntegration.sourceID)
        }
        integrations.perform("focus", source: TimerIntegration.sourceID)
    }

    func perform(_ action: ActivityEvent.Action, source: String) {
        integrations.perform(action.id, source: source)
    }

    /// A sample event to try the island without any integration.
    func sendTestEvent() {
        let kinds: [ActivityEvent.Kind] = [.started, .update, .completed, .alert]
        let kind = kinds.randomElement() ?? .alert
        bus.publish(ActivityEvent(source: "test", kind: kind, title: "Test \(kind.rawValue)",
                                  detail: "Sent from DevIsland", symbol: "wand.and.stars", expiresAfter: 20))
    }

    func connectClaude() {
        do {
            try hookInstaller.install()
            diagnostics.add("Connected Claude Code (backup saved next to settings.json)")
            showToast("Claude Code connected")
        } catch {
            diagnostics.add("Couldn't connect Claude Code: \(error.localizedDescription)", level: .error)
        }
    }

    func disconnectClaude() {
        do {
            try hookInstaller.uninstall()
            diagnostics.add("Disconnected Claude Code")
            showToast("Claude Code disconnected", symbol: "link.badge.plus")
        } catch {
            diagnostics.add("Couldn't disconnect Claude Code: \(error.localizedDescription)", level: .error)
        }
    }

    func applyRetention() {
        guard let days = preferences.retention.days else { return }
        store.pruneHistory(olderThan: .now.addingTimeInterval(-Double(days) * 86_400))
    }

    func copy(_ text: String, message: String = "Copied to clipboard") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(message)
    }

    func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        toast = Toast(message: message, symbol: symbol)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DevIsland History.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let events = store.database?.allEvents() ?? store.history
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(events).write(to: url, options: .atomic)
            showToast("Exported \(events.count) events")
        } catch {
            showToast("Export failed", symbol: "exclamationmark.triangle.fill")
            diagnostics.add("Export failed: \(error.localizedDescription)", level: .error)
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.database])
    }
}
