import AppKit

/// Starts the app: the hook socket, integrations, island, windows and keyboard shortcut.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(database: EventDatabase(path: AppPaths.database.path))
    private var windows: WindowManager?
    private var island: IslandPanelController?
    private var ipcServer: IPCServer?
    private let hotKey = GlobalHotKey()
    private let clipboardHotKey = GlobalHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar app: no Dock icon until a window opens
        if let icon = AppIconRenderer.image(pixels: 512) { NSApp.applicationIconImage = icon }

        guard startLocalBridge() else { return } // another DevIsland is running; it takes over

        model.start()

        let windows = WindowManager(model: model)
        self.windows = windows
        model.windows = windows
        model.integrations.onAppCommand = { [weak windows] command in
            if command == "open-dashboard" { windows?.showDashboard(nil) }
        }

        let island = IslandPanelController(model: IslandViewModel(app: model))
        island.show()
        self.island = island
        model.toggleIsland = { [weak island] in island?.model.togglePinned() }
        model.openIsland = { [weak island] page in island?.model.open(page) }
        model.openIslandPinned = { [weak island] page in island?.model.open(page, pinned: true) }
        model.floatingPlayer = FloatingPlayerController(model: model)
        model.bus.subscribe { [weak island] event in island?.model.handle(event) }

        observeShortcut()
        observeClipboardShortcut()

        if !model.preferences.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    /// Opening the app again (e.g. from Finder) shows the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showDashboard(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
        (model.integrations.integration("call") as? CallIntegration)?.restoreMic() // never leave the mic muted
    }

    /// Returns false when another instance is already running (and asks it to show its dashboard).
    private func startLocalBridge() -> Bool {
        let log = model.diagnostics
        let server = IPCServer(
            path: AppPaths.socket.path,
            onMessage: { [weak self] data in Task { @MainActor in self?.model.integrations.receive(data) } },
            onReject: { reason in Task { @MainActor in log.add(reason, level: .warning) } })

        switch server.start() {
        case .listening:
            ipcServer = server
            model.socketStatus = .listening
            log.add("Listening for hook events")
            return true
        case .alreadyRunning:
            IPCServer.send(Data(#"{"source":"devisland","payload":{"command":"open-dashboard"}}"#.utf8), to: AppPaths.socket.path)
            NSApp.terminate(nil)
            return false
        case .failed(let reason):
            model.socketStatus = .failed(reason)
            log.add("Couldn't open the hook socket: \(reason)", level: .error)
            return true
        }
    }

    /// Registers the island shortcut, and re-registers whenever the setting changes.
    private func observeShortcut() {
        let shortcut = withObservationTracking {
            model.preferences.shortcut
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeShortcut() }
        }
        hotKey.register(shortcut) { [weak self] in self?.model.toggleIsland() }
    }

    /// ⌃⌥V opens the clipboard in the island (can be turned off in Settings).
    private func observeClipboardShortcut() {
        let enabled = withObservationTracking {
            model.preferences.clipboardShortcut
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeClipboardShortcut() }
        }
        if enabled {
            let key = HotKeyShortcut.clipboard
            clipboardHotKey.register(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in
                self?.model.openIslandPinned(.clipboard)
            }
        } else {
            clipboardHotKey.unregister()
        }
    }
}
