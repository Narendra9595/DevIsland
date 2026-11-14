import SwiftUI

/// Everything DevIsland can do, grouped, with how to use it, whether it's on, and a button to try it.
struct FeaturesView: View {
    @Environment(AppModel.self) private var model
    @State private var musicAccess = MediaIntegration.hasAccess()
    @State private var accessibility = AXIsProcessTrusted()

    var body: some View {
        PageScaffold(title: "Features", subtitle: "Everything DevIsland can do, and how to use it.") {
            ForEach(groups, id: \.title) { group in
                ListCard(title: group.title, subtitle: group.subtitle) {
                    ForEach(Array(group.items.enumerated()), id: \.element.title) { index, feature in
                        if index > 0 { Divider().padding(.leading, 51) }
                        FeatureRow(feature: feature)
                    }
                }
            }
        }
        .task {
            // Permissions change in System Settings; re-check now and then while this page is open.
            while !Task.isCancelled {
                musicAccess = MediaIntegration.hasAccess()
                accessibility = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: The catalog

    private var groups: [FeatureGroup] {
        let prefs = model.preferences
        let integrations = model.integrations
        let hooks = model.hookInstaller.status
        return [
            FeatureGroup(title: "The island", subtitle: "Your notch, made useful", items: [
                Feature(title: "Notch island", symbol: "capsule.portrait.fill", tint: Theme.accent,
                        summary: "Shows what's happening beside the camera, and opens into pages.",
                        howTo: "Hover · click · swipe down · ⌃⌥I", status: .on,
                        action: ("Open", { model.toggleIsland() })),
                Feature(title: "Pages and gestures", symbol: "hand.draw.fill", tint: Theme.accent,
                        summary: "Home, Music, Files and Tools tabs; swipe left or right to switch, up to close.",
                        howTo: "Two-finger swipe on the notch", status: .on, action: nil),
                Feature(title: "Volume and brightness", symbol: "speaker.wave.2.fill", tint: Theme.violet,
                        summary: prefs.replaceSystemHUD ? "A slim bar at the notch replaces macOS's popup."
                                                        : "A slim bar at the notch when they change.",
                        howTo: "Use your volume or brightness keys",
                        status: prefs.showHUDs ? .on : .off,
                        action: prefs.showHUDs ? nil : ("Turn on", { prefs.showHUDs = true })),
                Feature(title: "Customize", symbol: "paintbrush.fill", tint: Theme.violet,
                        summary: "Highlight color, corner roundness and glass.",
                        howTo: "Settings → Customize", status: .on,
                        action: ("Open", { model.windows?.showSettings(tab: "Customize") })),
            ]),
            FeatureGroup(title: "AI agents", subtitle: "Claude Code and Codex", items: [
                Feature(title: "Claude Code live", symbol: "sparkles", tint: SourceStyle.tint("claude"),
                        summary: "What Claude is doing, step by step, and when it needs you.",
                        howTo: "Works in any Claude Code session",
                        status: hooks == .installed ? .on : .setup,
                        action: hooks == .installed ? nil : ("Connect", { model.dashboardSection = .agents })),
                Feature(title: "Plan limits", symbol: "gauge.with.dots.needle.33percent", tint: SourceStyle.tint("claude"),
                        summary: "Your 5-hour and weekly Claude limits in the notch and on Home.",
                        howTo: "Updates as you use Claude Code in the terminal",
                        status: model.currentClaudeUsage != nil ? .on : .waiting, action: nil),
                Feature(title: "Ask AI", symbol: "bubble.left.and.text.bubble.right.fill", tint: SourceStyle.tint("claude"),
                        summary: "Chat with Claude or Codex right in the island, using your own sign-in.",
                        howTo: "Type in Home's Ask box",
                        status: model.ask.providers.isEmpty ? .setup : .on,
                        action: model.ask.providers.isEmpty ? ("Set up", { model.windows?.showSettings(tab: "AI") })
                                                            : ("Try", { model.openIsland(.ask) })),
                Feature(title: "Codex", symbol: "terminal.fill", tint: SourceStyle.tint("codex"),
                        summary: "Know the moment a Codex turn finishes.",
                        howTo: "One line in ~/.codex/config.toml",
                        status: model.store.lastSeen["codex"] != nil ? .on : .setup,
                        action: ("Set up", { model.dashboardSection = .agents })),
            ]),
            FeatureGroup(title: "Music and calls", subtitle: nil, items: [
                Feature(title: "Now playing", symbol: "music.note", tint: SourceStyle.tint("media"),
                        summary: "Album art, a seek bar, controls, playlists and Apple Music search.",
                        howTo: "Music tab in the island",
                        status: musicAccess ? .on : .permission,
                        action: musicAccess ? ("Open", { model.openIsland(.music) })
                                            : ("Allow", { model.integrations.perform("play:\(MediaIntegration.lastPlayer)", source: "media") })),
                Feature(title: "Floating player", symbol: "pip.fill", tint: SourceStyle.tint("media"),
                        summary: "A mini player you can put anywhere, in two sizes.",
                        howTo: "Pop-out button on the Music page", status: .on,
                        action: ("Pop out", { model.floatingPlayer?.show() })),
                Feature(title: "Calls and microphone", symbol: "phone.fill", tint: CallGlyph.green,
                        summary: "Green call timer with the caller's name, mute and leave; orange when another app records.",
                        howTo: "Starts by itself on any call",
                        status: integrations.isEnabled("call") ? (accessibility ? .on : .partial) : .off,
                        action: !integrations.isEnabled("call") ? ("Turn on", { integrations.setEnabled(true, for: "call") })
                              : accessibility ? nil : ("Allow names", { model.clipboard.requestPastePermission() })),
            ]),
            FeatureGroup(title: "Productivity", subtitle: nil, items: [
                Feature(title: "Clipboard history", symbol: "doc.on.clipboard.fill", tint: SourceStyle.tint("clipboard"),
                        summary: "Text, links, code, colors and images; search and paste back.",
                        howTo: "⌃⌥V anywhere",
                        status: integrations.isEnabled("clipboard") ? .on : .off,
                        action: integrations.isEnabled("clipboard") ? ("Open", { model.openIsland(.clipboard) })
                                                                   : ("Turn on", { integrations.setEnabled(true, for: "clipboard") })),
                Feature(title: "File shelf", symbol: "tray.full.fill", tint: Theme.accent,
                        summary: "Drop files on the notch to keep them handy; drag out, copy path, AirDrop.",
                        howTo: "Drag files onto the notch", status: .on,
                        action: ("Open", { model.openIsland(.files) })),
                Feature(title: "Notes", symbol: "note.text", tint: Theme.attention,
                        summary: "A quick note that stays until you clear it.",
                        howTo: "Notes in the tools row", status: .on,
                        action: ("Open", { model.openIsland(.notes) })),
                Feature(title: "Focus timer", symbol: "timer", tint: Theme.violet,
                        summary: "25 minutes of focus with a countdown in the notch.",
                        howTo: "Tools row or menu bar", status: .on,
                        action: ("Start", { model.startFocus() })),
                Feature(title: "Keep Awake", symbol: "cup.and.saucer.fill", tint: Theme.attention,
                        summary: "Stops your Mac and screen from sleeping until you turn it off.",
                        howTo: "Tools row", status: model.keepAwake.isOn ? .on : .off,
                        action: (model.keepAwake.isOn ? "Turn off" : "Turn on", { model.keepAwake.toggle() })),
                Feature(title: "Mirror", symbol: "web.camera.fill", tint: Color(red: 0.35, green: 0.6, blue: 1),
                        summary: "Check yourself before a call; the camera runs only while it's open.",
                        howTo: "Tools row", status: .on,
                        action: ("Open", { model.openIsland(.camera) })),
            ]),
            FeatureGroup(title: "Live activities", subtitle: "Show up by themselves while they matter", items: [
                Feature(title: "Downloads", symbol: "arrow.down.circle.fill", tint: SourceStyle.tint("downloads"),
                        summary: "Progress for Safari, Chrome, Firefox and Edge, then Show in Finder.",
                        howTo: "Starts with any browser download",
                        status: integrations.isEnabled("downloads") ? .on : .off,
                        action: integrations.isEnabled("downloads") ? nil : ("Turn on", { integrations.setEnabled(true, for: "downloads") })),
                Feature(title: "Battery and network", symbol: "battery.75percent", tint: Theme.success,
                        summary: "Plug-in and low battery, offline and back online.",
                        howTo: "Automatic", status: integrations.isEnabled("battery") ? .on : .off, action: nil),
                Feature(title: "Battery friendly", symbol: "leaf.fill", tint: Theme.success,
                        summary: "Animations run in macOS's renderer and stop in Low Power Mode; see Energy on Home.",
                        howTo: "Automatic", status: .on,
                        action: ("Energy", { model.dashboardSection = .overview })),
            ]),
        ]
    }
}

struct FeatureGroup {
    let title: String
    let subtitle: String?
    let items: [Feature]
}

struct Feature {
    enum Status { case on, off, setup, permission, partial, waiting }
    let title: String
    let symbol: String
    let tint: Color
    let summary: String
    let howTo: String
    let status: Status
    let action: (title: String, run: () -> Void)?
}

private struct FeatureRow: View {
    let feature: Feature

    var body: some View {
        HStack(spacing: 11) {
            IconBadge(symbol: feature.symbol, tint: feature.tint, size: 26).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.system(size: 12.5, weight: .semibold))
                Text(feature.summary).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                Label(feature.howTo, systemImage: "hand.point.up.left")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 10)
            StatusPill(text: statusText, tint: statusTint)
            if let action = feature.action {
                Button(action.title, action: action.run).buttonStyle(.secondary).controlSize(.small)
                    .frame(minWidth: 70)
            } else {
                Color.clear.frame(width: 70, height: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var statusText: String {
        switch feature.status {
        case .on: "On"
        case .off: "Off"
        case .setup: "Set up"
        case .permission: "Needs access"
        case .partial: "On · no names"
        case .waiting: "Waiting"
        }
    }

    private var statusTint: Color {
        switch feature.status {
        case .on: Theme.success
        case .off, .waiting: .gray
        case .setup, .permission, .partial: Theme.attention
        }
    }
}
