import AppKit
import SwiftUI

/// Owns the island window. The panel has a fixed size and lets clicks pass through,
/// except while the mouse is over the island itself — so it never blocks the menu bar or apps.
@MainActor
final class IslandPanelController {
    let model: IslandViewModel
    private let panel = IslandPanel()
    private var monitors: [Any] = []
    /// Finger travel in the current two-finger swipe; one action per swipe.
    private var swipe = CGSize.zero
    private var swipeHandled = false

    init(model: IslandViewModel) {
        self.model = model
        let hostingView = IslandHostingView(rootView: AnyView(AppRoot(model: model.app) { IslandView(model: model) }))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        installMouseMonitors()
        observeStyle()
        observeHUD()
        // Full screen: re-check when Spaces or the front app change (a full-screen video gets its own Space).
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreen() }
            }
        }
    }

    // MARK: Full screen

    /// Shows the island for a volume or brightness HUD even in full screen.
    private func observeHUD() {
        _ = withObservationTracking {
            model.app.hud.hud
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateVisibility()
                self?.observeHUD()
            }
        }
    }

    private var fullScreen = false
    private var pointerInside = false

    /// True when the front app has a window covering the whole screen (full-screen video, full-screen apps).
    private func checkFullScreen() {
        // Spaces animate for a moment; check once it has settled.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, let screen = Self.targetScreen() else { return }
            let front = NSWorkspace.shared.frontmostApplication
            var covering = false
            if let pid = front?.processIdentifier, pid != getpid() {
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                covering = windows.contains { window in
                    guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                          (window[kCGWindowLayer as String] as? Int) == 0,
                          let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                          let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                    return rect.width >= screen.frame.width && rect.height >= screen.frame.height
                }
            }
            self.fullScreen = covering
            self.updateVisibility()
        }
    }

    /// In full screen the island fades away, unless it's open, you point at it, or an alert opened it.
    private func updateVisibility() {
        let hide = fullScreen && model.app.preferences.hideInFullScreen && !model.isExpanded && !pointerInside
            && model.app.hud.hud == nil // volume / brightness still show in full screen
        guard panel.alphaValue != (hide ? 0 : 1) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = hide ? 0 : 1
        }
    }

    /// Re-lays out the island when you switch between notch and floating in Settings.
    private func observeStyle() {
        _ = withObservationTracking {
            model.app.preferences.islandStyle
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.layout()
                self?.observeStyle()
            }
        }
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
    }

    private func layout() {
        guard let screen = Self.targetScreen() else { return }
        model.geometry = IslandGeometry(screen: screen, style: IslandStyle(rawValue: model.app.preferences.islandStyle) ?? .automatic)
        let canvas = model.geometry.canvasSize
        panel.setFrame(CGRect(x: screen.frame.midX - canvas.width / 2,
                              y: screen.frame.maxY - canvas.height,
                              width: canvas.width,
                              height: canvas.height), display: true)
    }

    /// Mouse-moved events from other apps (global) and from ours (local).
    /// No permission is needed to observe mouse movement.
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.trackMouse() }
            return event
        }) {
            monitors.append(local)
        }
        // A click outside the open island closes it, like a popover (in other apps and in our own windows).
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfClickedOutside() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated { if event.window !== self?.panel { self?.closeIfClickedOutside() } }
            return event
        }) {
            monitors.append(local)
        }
        // Esc closes it while it has the keyboard (e.g. after typing in Ask or a search field).
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, event.window === self?.panel else { return event }
            MainActor.assumeIsolated { self?.model.dismiss() }
            return nil
        }) {
            monitors.append(escape)
        }
        // Scrolls reach us only while the pointer is over the island (the panel ignores mouse events otherwise).
        // Safety net, only while open: mouse-move events can stop arriving (e.g. while one of our windows
        // is active), so check the pointer a few times a second and close when it has left.
        model.onExpandedChange = { [weak self] open in
            self?.setSafetyTimer(open)
            self?.updateVisibility()
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleSwipe(event) }
            return event
        }) {
            monitors.append(scroll)
        }
    }

    /// Two-finger trackpad swipes: down opens, up closes, left/right changes page.
    private func handleSwipe(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) { swipe = .zero; swipeHandled = false }
        guard !swipeHandled, model.hitRect(in: panel.frame).contains(NSEvent.mouseLocation) else { return }

        // Physical finger direction, the same with or without natural scrolling.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        swipe.width += event.scrollingDeltaX * sign
        swipe.height += event.scrollingDeltaY * sign

        let threshold: CGFloat = 28
        let horizontal = abs(swipe.width) > abs(swipe.height)
        if model.isExpanded, horizontal, abs(swipe.width) > threshold {
            model.swipePage(forward: swipe.width < 0)
        } else if !horizontal, swipe.height > threshold, !model.isExpanded {
            model.openFromGesture()
        } else if !horizontal, swipe.height < -threshold, model.isExpanded, !model.scrollsVertically {
            model.closeFromGesture()
        } else {
            return
        }
        swipeHandled = true
    }

    private var safetyTimer: Timer?

    private func setSafetyTimer(_ on: Bool) {
        safetyTimer?.invalidate()
        safetyTimer = nil
        if !on {
            // Typing went to the island's search field; give the keyboard back to the app you were in.
            if panel.isKeyWindow {
                panel.resignKey()
                NSWorkspace.shared.frontmostApplication?.activate()
            }
            return
        }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    private func closeIfClickedOutside() {
        guard model.isExpanded, !model.hitRect(in: panel.frame).contains(NSEvent.mouseLocation) else { return }
        model.dismiss()
    }

    private func trackMouse() {
        let inside = model.hitRect(in: panel.frame).contains(NSEvent.mouseLocation)
        if inside != pointerInside {
            pointerInside = inside
            if fullScreen { updateVisibility() } // pointing at the top brings it back in full screen
        }
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        model.setHovering(inside)
    }

    /// Prefer the built-in screen with a notch; otherwise the main screen.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main
    }
}

/// A borderless, transparent panel that floats above the menu bar on every Space.
final class IslandPanel: NSPanel {
    convenience init() {
        self.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Takes the keyboard only when a text field is clicked (music search), never for buttons.
    override var canBecomeKey: Bool { true }

    // Let the panel sit at the very top instead of below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Accepts the first click even when DevIsland isn't the active app.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
