import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            } footer: {
                if let loginError {
                    Text(loginError).foregroundStyle(Theme.danger)
                }
            }
            Section("Keyboard") {
                Picker("Toggle the island", selection: $preferences.shortcut) {
                    ForEach(HotKeyShortcut.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Open the clipboard with ⌃⌥V", isOn: $preferences.clipboardShortcut)
            }
            Section("Help") {
                LabeledContent("Welcome guide") {
                    Button("Show Again") { model.windows?.showOnboarding() }
                }
                LabeledContent("Data folder") {
                    Button("Show in Finder") { model.revealDataFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 330)
    }

    /// Only works in the bundled app (Scripts/build-app.sh), not with `swift run`.
    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Launch at login only works in the installed DevIsland.app."
            launchAtLogin = !enabled
        }
    }
}

struct IslandSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section("Behavior") {
                Toggle("Expand on hover", isOn: $preferences.expandOnHover)
                Picker("Hover delay", selection: $preferences.hoverDelay) {
                    ForEach(Preferences.HoverDelay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.expandOnHover)
                Toggle(isOn: $preferences.autoPresentAlerts) {
                    Text("Show alerts automatically")
                    Text("Briefly opens the island when an agent needs you or something finishes.")
                }
            }
            Section("Display") {
                Toggle(isOn: $preferences.hideInFullScreen) {
                    Text("Hide in full screen")
                    Text("While a video or app is full screen. Point at the top to bring it back; alerts still show.")
                }
                Toggle(isOn: $preferences.showHUDs) {
                    Text("Volume and brightness at the notch")
                    Text("A slim bar beside the notch when they change.")
                }
                .onChange(of: preferences.showHUDs) { model.applyMediaKeys(askPermission: false) }
                Toggle(isOn: $preferences.replaceSystemHUD) {
                    Text("Hide macOS's volume and brightness popup")
                    Text(model.mediaKeys.isRunning || !preferences.replaceSystemHUD
                         ? "DevIsland handles those keys so only the notch HUD shows. Needs Accessibility permission."
                         : "Waiting for Accessibility: turn DevIsland on in System Settings → Privacy & Security → Accessibility.")
                }
                .disabled(!preferences.showHUDs)
                .onChange(of: preferences.replaceSystemHUD) { model.applyMediaKeys(askPermission: true) }
            }
            Section {
                Toggle(isOn: $preferences.glassEffects) {
                    Text("Glass and activity light")
                    Text("Liquid Glass surfaces, and a soft glow in the color of what's happening.")
                }
                Toggle("Animations", isOn: $preferences.animations)
                Toggle("Haptic feedback", isOn: $preferences.hapticFeedback)
            } header: {
                Text("Look and feel")
            } footer: {
                Text("DevIsland also follows Reduce Motion and Reduce Transparency in Accessibility settings.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }
}

struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var preferences = model.preferences
        let clipboardEnabled = model.integrations.isEnabled(model.clipboard.id)
        Form {
            Section {
                Picker("Keep history for", selection: $preferences.retention) {
                    ForEach(Preferences.Retention.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: preferences.retention) { model.applyRetention() }
                LabeledContent("Saved events", value: "\(model.store.database?.totalCount() ?? model.store.history.count)")
                HStack {
                    Button("Export…") { model.exportHistory() }
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Stored only on this Mac, in ~/Library/Application Support/DevIsland.")
            }
            Section {
                Toggle(isOn: $preferences.showAgentMessages) {
                    Text("Show what Claude is saying")
                    Text("The island shows the first line of Claude's messages and its turn summaries.")
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Only the first line is used, and nothing leaves this Mac. Your prompts and code are never read.")
            }
            Section {
                Toggle("Clipboard history", isOn: Binding(
                    get: { clipboardEnabled },
                    set: { model.integrations.setEnabled($0, for: model.clipboard.id) }))
                Button("Clear Clipboard History") { model.clipboard.clear() }
                    .disabled(!clipboardEnabled)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Text, links, code, colors and images, kept in memory and never written to disk. Password-manager items are skipped.")
            }
            Section("Your data") {
                Label("No account, no analytics.", systemImage: "lock.shield")
                Label("Network only when you ask: Apple Music search, and Ask (sent to Claude or Codex through your own sign-in).", systemImage: "network")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.store.clearHistory() }
        } message: {
            Text("This permanently deletes every saved event from this Mac.")
        }
    }
}

struct AboutSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            AppIconView()
                .frame(width: 112, height: 112)
            Text("DevIsland")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The notch app for developers.\nLocal-first. No account. No tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Welcome Guide") { model.windows?.showOnboarding() }
                    .buttonStyle(.secondary)
                Button("Data Folder") { model.revealDataFolder() }
                    .buttonStyle(.secondary)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            Text("© 2026 DevIsland")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 520, height: 380)
    }
}

/// Settings → Customize: highlight color and island corners.
struct CustomizeSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var hexText = ""

    /// Twelve presets that read well on the black island.
    private static let presets = ["#2BC7B8", "#3B82F6", "#6366F1", "#8B5CF6", "#D946EF", "#EC4899",
                                  "#F43F5E", "#F97316", "#F59E0B", "#84CC16", "#22C55E", "#A1A1AA"]

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section("Highlight color") {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { hex in
                        let selected = hex.caseInsensitiveCompare(preferences.highlightHex) == .orderedSame
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.primary.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
                            .onTapGesture { preferences.highlightHex = hex }
                            .accessibilityLabel(hex)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Custom") {
                    TextField("#RRGGBB", text: $hexText)
                        .frame(width: 100)
                        .onSubmit { if Color(hex: hexText) != nil { preferences.highlightHex = hexText } }
                }
            }
            Section {
                Picker("Island style", selection: $preferences.islandStyle) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Corner roundness") {
                    Slider(value: $preferences.islandCorner, in: 16...34, step: 1).frame(width: 220)
                }
                Toggle("Glass and activity light", isOn: $preferences.glassEffects)
            } header: {
                Text("Island")
            } footer: {
                Text("Automatic: attached to the notch on Macs that have one, a floating iPhone-style island everywhere else.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .onAppear { hexText = preferences.highlightHex }
    }
}

/// Settings → AI: which AI tools can answer "Ask", with official sign-in and sign-out.
struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmInstall: AskProvider?

    var body: some View {
        let ask = model.ask
        Form {
            Section {
                ForEach(AskProvider.allCases) { provider in
                    HStack(spacing: 12) {
                        AskLogo(provider: provider, size: 22).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider == .claude ? "Claude Code" : "Codex (ChatGPT)")
                            Text(ask.installing.contains(provider) ? "Installing… this can take a minute."
                                 : ask.installErrors[provider] ?? caption(ask.statuses[provider] ?? .unknown))
                                .font(.caption)
                                .foregroundStyle(ask.installErrors[provider] == nil ? Color.secondary : Theme.attention)
                        }
                        Spacer()
                        if ask.installing.contains(provider) {
                            ProgressView().controlSize(.small)
                        } else {
                            switch ask.statuses[provider] ?? .unknown {
                            case .signedIn: Button("Sign Out") { ask.signOut(provider) }
                            case .signedOut: Button("Sign In…") { ask.signIn(provider) }.buttonStyle(.borderedProminent)
                            case .notInstalled:
                                if AskService.installCommand(for: provider) != nil {
                                    Button("Install") { confirmInstall = provider }.buttonStyle(.borderedProminent)
                                }
                                Button("How to Install") { NSWorkspace.shared.open(provider.installURL) }
                            case .unknown: ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
            } header: {
                Text("Ask in the island")
            } footer: {
                Text("Sign In opens the official sign-in page in your browser. DevIsland never sees your password; each tool keeps its own sign-in.")
            }
            Section {
                Label("No app signed in? The Ask box opens your question in claude.ai or ChatGPT in your browser, using the account you're already logged into there.", systemImage: "safari")
                    .font(.callout)
            }
            Section("Privacy") {
                Label("Questions go to Claude or ChatGPT through your own account. DevIsland keeps only the latest answer, in memory, and nothing is saved on this Mac.", systemImage: "lock.shield")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 430)
        .onAppear { ask.refreshProviders() }
        .confirmationDialog("Install \(confirmInstall == .claude ? "Claude Code" : "Codex")?",
                            isPresented: Binding(get: { confirmInstall != nil }, set: { if !$0 { confirmInstall = nil } }),
                            presenting: confirmInstall) { provider in
            Button("Install") { ask.install(provider) }
        } message: { provider in
            Text("DevIsland will run the official installer:\n\(AskService.installCommand(for: provider) ?? "")\n\nNo admin password needed. Afterwards your browser opens to sign in.")
        }
    }

    private func caption(_ status: AskProvider.Status) -> String {
        switch status {
        case .signedIn: "Signed in. Answers right in the island."
        case .signedOut: "Installed, not signed in."
        case .notInstalled: "Not installed on this Mac."
        case .unknown: "Checking…"
        }
    }
}
