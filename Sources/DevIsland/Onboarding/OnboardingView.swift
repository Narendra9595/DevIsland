import SwiftUI

/// First-launch welcome: what DevIsland does, connecting Claude Code, and how to use the island.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Int
    @State private var forward = true
    let onFinish: () -> Void
    private let lastStep = 4

    init(step: Int = 0, onFinish: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: WelcomePage().transition(pageTransition)
                case 1: FeaturesPage().transition(pageTransition)
                case 2: ConnectPage().transition(pageTransition)
                case 3: HUDPage().transition(pageTransition)
                default: ReadyPage(shortcut: model.preferences.shortcut).transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 720, height: 520)
        .background(OnboardingBackground())
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.5, bounce: 0.12), value: step)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.white : Color.white.opacity(0.25))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") {
                    forward = false
                    step -= 1
                }
                .buttonStyle(.secondary)
            }
            Button(step == lastStep ? "Get Started" : "Continue") {
                if step == lastStep {
                    model.preferences.hasCompletedOnboarding = true
                    onFinish()
                } else {
                    forward = true
                    step += 1
                }
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
    }
}

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.15), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.3), .clear], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear], center: UnitPoint(x: 0.95, y: 1), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 26) {
            IslandShowcase()
                .frame(width: 560, height: 210)
            PageTitle(title: "Welcome to DevIsland",
                      subtitle: "Your MacBook notch becomes a live view of your work — agents, timers, music and more.")
        }
        .padding(.top, 30)
    }
}

private struct FeaturesPage: View {
    var body: some View {
        VStack(spacing: 22) {
            PageTitle(title: "Everything at a glance", subtitle: "One calm place for what's happening on your Mac.")
            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(symbol: "claude", tint: SourceStyle.tint("claude"), title: "Agents in your notch",
                           text: "See what Claude Code and Codex are doing, and when they need you.")
                FeatureRow(symbol: "brain.head.profile", tint: Theme.violet, title: "Focus timer",
                           text: "Start a focus session from the menu bar and watch it count down in the notch.")
                FeatureRow(symbol: "tray.and.arrow.down.fill", tint: Theme.accent, title: "Shelf and clipboard",
                           text: "Drop files on the notch to keep them handy. Copy history stays in memory.")
                FeatureRow(symbol: "lock.shield.fill", tint: Theme.success, title: "Private by design",
                           text: "No account, no cloud, no tracking. Everything stays on this Mac.")
            }
            .frame(maxWidth: 500, alignment: .leading)
        }
        .padding(.top, 24)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            if symbol == "claude" { ClaudeBadge(size: 36) } else { IconBadge(symbol: symbol, tint: tint, size: 36) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), fallback: .white.opacity(0.06))
    }
}

private struct ConnectPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let installer = model.hookInstaller
        VStack(spacing: 22) {
            AgentLogo(source: "claude", size: 76, badge: true)
            PageTitle(title: "Connect Claude Code",
                      subtitle: "DevIsland adds small hooks to Claude Code's settings so sessions show what they're doing. Your prompts and code are never read.")
            VStack(spacing: 10) {
                Group {
                    if installer.status == .installed {
                        Label("Connected — new sessions will report to DevIsland", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.success)
                    } else {
                        Button { model.connectClaude() } label: {
                            Label("Connect Claude Code", systemImage: "link")
                        }
                        .buttonStyle(.primary)
                    }
                }
                .frame(height: 32)
                if let error = installer.lastError {
                    Text(error).font(.callout).foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), fallback: .white.opacity(0.06))
            Text("A backup of your settings is saved first. You can disconnect anytime in Dashboard → Agents.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 36)
    }
}

/// Volume and brightness: macOS shows its own popup too until you let DevIsland handle those keys.
private struct HUDPage: View {
    @Environment(AppModel.self) private var model
    @State private var running = false

    var body: some View {
        let preferences = model.preferences
        let replacing = preferences.replaceSystemHUD
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "speaker.wave.2.fill")
                Image(systemName: "sun.max.fill")
            }
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(height: 76)
            PageTitle(title: "Volume and brightness",
                      subtitle: "DevIsland shows a slim bar at the notch when you change them. Until you turn on the switch below, macOS keeps showing its own popup too, so you'll see two.")
            VStack(spacing: 10) {
                Group {
                    if replacing && running {
                        Label("Done: only DevIsland's bar will show", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.success)
                    } else if replacing {
                        Label("Allow DevIsland in System Settings → Privacy & Security → Accessibility", systemImage: "hand.raised.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.attention)
                    } else {
                        Button {
                            preferences.showHUDs = true
                            preferences.replaceSystemHUD = true
                            model.applyMediaKeys(askPermission: true)
                        } label: {
                            Label("Show only DevIsland's bar", systemImage: "rectangle.on.rectangle.slash")
                        }
                        .buttonStyle(.primary)
                    }
                }
                .frame(height: 32)
                Text("Needs Accessibility permission. Only the volume, mute and brightness keys are handled; everything else stays with macOS.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), fallback: .white.opacity(0.06))
            Text("Change it anytime: Settings → Island → \"Hide macOS's volume and brightness popup\". You can skip this step.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 36)
        .task {
            // Accessibility is granted in System Settings; notice it while this page is open.
            while !Task.isCancelled {
                running = model.mediaKeys.isRunning
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct ReadyPage: View {
    let shortcut: HotKeyShortcut

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 84, height: 84)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            PageTitle(title: "You're all set", subtitle: "A few things to know:")
            VStack(alignment: .leading, spacing: 14) {
                TipRow(symbol: "cursorarrow.motionlines", text: "Hover over your notch to open the island; move away to close it.")
                TipRow(symbol: "hand.draw.fill", text: "Swipe with two fingers: down to open, up to close, left/right for pages.")
                if shortcut != .off {
                    TipRow(symbol: "keyboard", text: "Press \(shortcut.title) to keep it open, ⌃⌥V for your clipboard.")
                }
                TipRow(symbol: "sparkles.rectangle.stack", text: "Dashboard → Features shows everything DevIsland can do.")
            }
            .padding(20)
            .frame(maxWidth: 440, alignment: .leading)
            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), fallback: .white.opacity(0.06))
        }
        .padding(.top, 36)
    }
}

private struct TipRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
