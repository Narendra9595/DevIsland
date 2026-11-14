import AppKit
import SwiftUI

/// Island state: compact or expanded, pinned, and the size for each state.
@MainActor
@Observable
final class IslandViewModel {
    let app: AppModel
    var geometry = IslandGeometry.fallback
    private(set) var isExpanded = false
    private(set) var isPinned = false

    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private var isDropTargeted = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var presentTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    var current: LiveActivity? { app.store.current }

    /// Size of the island body (without the shoulders).
    var size: CGSize {
        if isExpanded { return geometry.expandedSize(contentHeight: expandedContentHeight + IslandMetrics.tabBarHeight) }
        return app.hud.hud != nil ? geometry.hudSize : geometry.compactSize(isLive: current != nil)
    }

    var bottomRadius: CGFloat {
        isExpanded ? app.preferences.islandCorner + (geometry.floating ? 6 : 0) : geometry.compactRadius
    }
    /// Rounded top corners only for the floating island.
    var topRadius: CGFloat { geometry.floating ? bottomRadius : 0 }

    /// The page chosen with the tabs or a swipe; nil = automatic.
    private(set) var chosenPage: IslandPage?

    /// What's playing (the playing player first), if anything.
    var music: LiveActivity? {
        let players = app.store.live.filter { $0.event.source == "media" }
        return players.first { $0.event.metadata["state"] == "playing" } ?? players.first
    }

    /// The current activity, unless it's music (music has its own page).
    private var activity: LiveActivity? {
        current?.event.source == "media" ? nil : current
    }

    /// What the expanded island shows. Automatic: an activity that matters, then music, then Home.
    var page: IslandPage {
        // The camera is never in the swipe order, so it only turns on when you open it.
        if let chosenPage, [.camera, .ask, .notes].contains(chosenPage) || pages.contains(chosenPage) { return chosenPage }
        if app.ask.isFresh { return .ask } // an answer on its way, or just arrived, comes first
        if let activity, activity.event.priority > .low || app.store.selectedKey == activity.key { return .activity }
        if music?.event.metadata["state"] == "playing" { return .music }
        return .home
    }

    /// Tabs in the order a swipe moves through them.
    var pages: [IslandPage] {
        (activity == nil ? [] : [.activity]) + [.home] + (music == nil ? [] : [.music]) + [.files, .clipboard, .tools, .usage]
    }

    func show(_ page: IslandPage) {
        guard page != self.page else { return }
        withAnimation(animation) { chosenPage = page }
    }

    /// From the switcher: music opens its page, anything else the activity page.
    func showActivity(_ key: String) {
        withAnimation(animation) {
            app.store.select(key)
            chosenPage = current?.event.source == "media" ? .music : .activity
        }
    }

    /// Two-finger swipe: next page (fingers move left) or previous (fingers move right).
    /// The pages with their own tab (and the swipe order). Pages opened from Tools count as Tools.
    var tabPages: [IslandPage] {
        (activity == nil ? [] : [.activity]) + [.home] + (music == nil ? [] : [.music]) + [.files, .tools]
    }

    /// Pages opened from the Tools page; they show a "‹ Tools" back button.
    var isToolSubpage: Bool { [.clipboard, .usage, .notes, .camera].contains(page) }

    func swipePage(forward: Bool) {
        let current = isToolSubpage ? .tools : page
        guard let index = tabPages.firstIndex(of: current) else { return }
        let next = index + (forward ? 1 : -1)
        guard tabPages.indices.contains(next) else { return }
        show(tabPages[next])
        if app.preferences.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Opens the island on a page and keeps it open (shortcut, Tools tile).
    /// Opens the island on a page. Pinned (shortcuts) stays until closed; otherwise it closes by itself
    /// after a few seconds unless the pointer is on it.
    func open(_ page: IslandPage, pinned: Bool = false) {
        presentTask?.cancel()
        isPinned = pinned
        expand(haptic: false)
        withAnimation(animation) { chosenPage = page }
        guard !pinned else { return }
        presentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, !self.isHovering, !self.isPinned else { return }
            self.collapse()
        }
    }

    /// A click outside the open island (or Esc) closes it, pinned or not.
    func dismiss() {
        guard isExpanded else { return }
        collapse()
    }

    /// Pages with their own scrolling list, where a vertical swipe shouldn't close the island.
    var scrollsVertically: Bool { libraryOpen || page == .clipboard || page == .ask }

    /// The AI chosen for Ask, falling back to whichever is installed and signed in.
    var askProvider: AskProvider {
        let available = app.ask.providers
        let saved = AskProvider(rawValue: app.preferences.askProvider) ?? .claude
        if available.isEmpty || available.contains(saved) { return saved } // with no app signed in, any choice opens the web
        return available.first ?? .claude
    }

    /// Closes the chat (keeping it, so asking from Home continues it) and goes back to Home.
    func closeAnswer() {
        app.ask.dismiss()
        withAnimation(animation) { chosenPage = .home }
    }

    /// Sends a question to Claude and shows the answer page.
    func ask(_ question: String) {
        app.ask.ask(question, using: askProvider)
        withAnimation(animation) { chosenPage = .ask } // stays on the answer until you leave it
    }

    /// Closes the island, hands the keyboard back to your app, then pastes the clip there.
    func paste(_ item: ClipItem) {
        collapse()
        if let panel = NSApp.windows.first(where: { $0 is IslandPanel }), panel.isKeyWindow {
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
        Task { [app] in
            try? await Task.sleep(for: .milliseconds(150))
            app.clipboard.paste(item)
        }
    }

    /// Two-finger swipe down on the notch.
    func openFromGesture() {
        expand(haptic: true)
    }

    /// Two-finger swipe up on the open island.
    func closeFromGesture() {
        collapse()
    }

    /// The music page's library (search + playlists) is open.
    private(set) var libraryOpen = false

    func toggleLibrary() {
        withAnimation(animation) { libraryOpen.toggle() }
    }

    /// Each page gets the height its content needs, so the island grows and shrinks with it.
    var expandedContentHeight: CGFloat {
        let files = app.shelf.files.count
        return switch page {
        case .activity: IslandMetrics.activityHeight
        case .home: 182
        case .music: libraryOpen ? IslandMetrics.maxContentHeight : 132
        case .files: files == 0 ? 104 : files <= 4 ? 106 : 154
        case .usage: 132
        case .tools: 104
        case .clipboard: 250
        case .camera: 200
        case .ask: IslandMetrics.maxContentHeight
        case .notes: 130
        }
    }

    /// nil when the user turned animations off or enabled Reduce Motion.
    var animation: Animation? {
        guard app.preferences.animations, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return nil }
        return .spring(duration: 0.45, bounce: 0.22)
    }

    /// The screen area that reacts to the mouse, with a little tolerance.
    func hitRect(in panelFrame: CGRect) -> CGRect {
        // A HUD makes the island wider for a moment, but shouldn't make it catch the pointer.
        let size = isExpanded ? size : geometry.compactSize(isLive: current != nil)
        let tolerance: CGFloat = isExpanded ? 8 : 3
        return CGRect(x: panelFrame.midX - size.width / 2 - tolerance,
                      y: panelFrame.maxY - geometry.topGap - size.height - tolerance,
                      width: size.width + tolerance * 2,
                      height: size.height + tolerance * 2)
    }

    // MARK: Input

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverTask?.cancel()

        if hovering {
            presentTask?.cancel()
            guard app.preferences.expandOnHover, !isExpanded else { return }
            let delay = app.preferences.hoverDelay.seconds
            hoverTask = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard let self, !Task.isCancelled, self.isHovering else { return }
                self.expand(haptic: true)
            }
        } else {
            scheduleCollapse()
        }
    }

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted {
            expand(haptic: true)
        } else {
            scheduleCollapse()
        }
    }

    /// Click, keyboard shortcut or menu: keep the island open until toggled again.
    func togglePinned() {
        if isExpanded && isPinned {
            collapse()
        } else {
            isPinned = true
            expand(haptic: false)
        }
    }

    /// Briefly opens the island for alerts and finished work.
    func handle(_ event: ActivityEvent) {
        guard event.kind == .alert || event.kind == .completed,
              app.preferences.autoPresentAlerts, !isExpanded else { return }
        app.store.select(event.activityKey)
        expand(haptic: false)
        presentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, !self.isHovering, !self.isPinned else { return }
            self.collapse()
        }
    }

    // MARK: State changes

    private func scheduleCollapse() {
        guard isExpanded, !isPinned else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.35))
            // Don't collapse in the middle of dragging a file out of the shelf.
            while NSEvent.pressedMouseButtons != 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard let self, !Task.isCancelled, !self.isHovering, !self.isDropTargeted, !self.isPinned else { return }
            self.collapse()
        }
    }

    /// Told when the island opens or closes (the panel only watches the pointer closely while open).
    @ObservationIgnored var onExpandedChange: (Bool) -> Void = { _ in }

    private func expand(haptic: Bool) {
        guard !isExpanded else { return }
        withAnimation(animation) { isExpanded = true }
        onExpandedChange(true)
        if haptic && app.preferences.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func collapse() {
        presentTask?.cancel()
        // A finished item you just saw is done: the notch goes straight back to what was there before (e.g. music).
        if isExpanded, page == .activity, let shown = current, shown.event.kind == .completed {
            app.store.dismiss(shown.key)
        }
        isPinned = false
        withAnimation(animation) { isExpanded = false }
        onExpandedChange(false)
        // A pick from the switcher or Home lasts until the island closes; next time it opens on what matters most.
        app.store.clearSelection()
        chosenPage = nil
        libraryOpen = false
    }
}

/// The pages of the expanded island.
enum IslandPage: Equatable {
    case activity, home, music, files, clipboard, tools, usage, camera, ask, notes
}
