import AppKit
import SwiftUI

/// Opens and reuses the app's windows. While any window is open, DevIsland shows in the Dock
/// and gets a normal menu bar; when the last one closes it goes back to being menu-bar only.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate, WindowPresenting {
    private let model: AppModel
    private var dashboard: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func showDashboard(_ section: DashboardSection?) {
        if let section { model.dashboardSection = section }
        if dashboard == nil { dashboard = Self.makeDashboardWindow(model: model, delegate: self) }
        present(dashboard)
    }

    func showSettings(tab: String?) {
        if settings == nil { settings = Self.makeSettingsWindow(model: model, delegate: self) }
        if let tab, let tabs = settings?.contentViewController as? NSTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = index
        }
        present(settings)
    }

    func showOnboarding() {
        if onboarding == nil { onboarding = makeOnboardingWindow() }
        present(onboarding)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboarding {
            model.preferences.hasCompletedOnboarding = true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let anyVisible = [self.dashboard, self.settings, self.onboarding].contains { $0?.isVisible == true }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: Window factories

    /// A native sidebar window: SwiftUI sidebar and detail inside an AppKit split view.
    static func makeDashboardWindow(model: AppModel, delegate: (any NSWindowDelegate)?) -> NSWindow {
        let sidebar = NSHostingController(rootView: AnyView(AppRoot(model: model) { DashboardSidebar() }))
        sidebar.sizingOptions = []
        let detail = NSHostingController(rootView: AnyView(AppRoot(model: model) { DashboardDetail() }))
        detail.sizingOptions = []

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = false
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: detail))

        let window = AppWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = split
        window.title = "DevIsland"
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "DevIslandDashboard")
        window.toolbarStyle = .unified
        window.minSize = CGSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.setContentSize(CGSize(width: 1120, height: 760))
        window.center()
        window.setFrameAutosaveName("DevIslandDashboard")
        window.setFrameUsingName("DevIslandDashboard") // restore the last size and position, if any
        return window
    }

    /// Classic macOS preferences: toolbar tabs, each a SwiftUI form.
    static func makeSettingsWindow(model: AppModel, delegate: (any NSWindowDelegate)?) -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTab("General", symbol: "gearshape", view: GeneralSettingsView(), model: model)
        tabs.addTab("Island", symbol: "capsule.fill", view: IslandSettingsView(), model: model)
        tabs.addTab("Customize", symbol: "paintbrush.fill", view: CustomizeSettingsView(), model: model)
        tabs.addTab("AI", symbol: "sparkles", view: AISettingsView(), model: model)
        tabs.addTab("Privacy", symbol: "hand.raised", view: PrivacySettingsView(), model: model)
        tabs.addTab("About", symbol: "info.circle", view: AboutSettingsView(), model: model)

        let window = AppWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()
        return window
    }

    private func makeOnboardingWindow() -> NSWindow {
        let view = AppRoot(model: model) {
            OnboardingView { [weak self] in self?.onboarding?.close() }
        }
        let host = NSHostingController(rootView: AnyView(view))
        host.sizingOptions = []

        let window = AppWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = host
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(CGSize(width: 720, height: 520))
        window.center()
        return window
    }
}

/// A window that closes with ⌘W even though DevIsland has no File menu.
final class AppWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Toolbar-style tabs that resize the window to fit each tab.
final class SettingsTabViewController: NSTabViewController {
    func addTab(_ title: String, symbol: String, view: some View, model: AppModel) {
        let host = NSHostingController(rootView: AnyView(AppRoot(model: model) { view }))
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        resizeWindow(to: tabView.selectedTabViewItem, animate: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        resizeWindow(to: tabViewItem, animate: true)
    }

    private func resizeWindow(to item: NSTabViewItem?, animate: Bool) {
        guard let view = item?.viewController?.view, let window = view.window else { return }
        let size = view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let chrome = window.frame.height - window.contentLayoutRect.height
        let height = size.height + chrome
        let frame = CGRect(x: window.frame.minX, y: window.frame.maxY - height, width: size.width, height: height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}
