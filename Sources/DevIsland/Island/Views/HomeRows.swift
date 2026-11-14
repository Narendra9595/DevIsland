import SwiftUI

// MARK: - Home: media hero + side widgets

/// Home: a big player on the left, small status widgets on the right, then the tool dock and Ask.
struct IslandHomeView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MediaHero(model: model)
                    .homeCard { if model.music != nil { model.show(.music) } }
                SideWidgets(model: model)
                    .frame(width: 176)
            }
            .frame(height: 118)
            HStack(spacing: 8) {
                ToolStrip(model: model)
                AskField(model: model).frame(height: 36)
            }
            .frame(height: 46)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

private extension View {
    /// A glass card; tapping empty space runs `open`.
    func homeCard(open: @escaping () -> Void = {}) -> some View {
        padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true, fallback: .white.opacity(0.07))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
    }
}

/// The player: a big cover, the song, a progress bar when the app shares it, and controls.
private struct MediaHero: View {
    let model: IslandViewModel

    var body: some View {
        if let event = model.music?.event {
            let playing = event.metadata["state"] == "playing"
            HStack(alignment: .top, spacing: 12) {
                Artwork(source: event.metadata["artwork"], player: event.metadata["player"], size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                            Text(event.detail ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        }
                        .lineLimit(1)
                        Spacer(minLength: 4)
                        EqualizerBars(isPlaying: playing, tint: SourceStyle.tint("media")).frame(width: 14, height: 12)
                    }
                    Spacer(minLength: 0)
                    TrackProgress(metadata: event.metadata, playing: playing) { seconds in
                        if let player = event.metadata["player"] { model.app.media.seek(player: player, to: seconds) }
                    }
                    HStack(spacing: 22) {
                        ForEach(event.actions) { action in
                            Button { model.app.perform(action, source: event.source) } label: {
                                Image(systemName: action.symbol)
                                    .font(.system(size: action.id.hasPrefix("playpause") ? 17 : 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(action.label)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            let player = MediaIntegration.lastPlayer
            HStack(spacing: 12) {
                PlayerIcon(player: player, size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    Text("Music, Spotify, YouTube and more show up here.")
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(2)
                    Button { model.app.integrations.perform("play:\(player)", source: "media") } label: {
                        Label("Play \(player)", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The right column: what's live, Claude's plan, and battery / Keep Awake.
private struct SideWidgets: View {
    let model: IslandViewModel

    var body: some View {
        let live = model.pages.contains(.activity) ? model.current : nil
        VStack(spacing: 6) {
            // What's live (or all quiet); tap for details.
            HStack(spacing: 7) {
                if let event = live?.event {
                    ActivityIcon(event: event).frame(width: 18)
                    Text(event.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 2)
                    if let start = event.startDate, event.kind != .completed {
                        Text(start, style: .timer).font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(event.tint)
                    }
                } else {
                    Circle().fill(Theme.success).frame(width: 7, height: 7).frame(width: 18)
                    Text("All quiet").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
            }
            .sideWidget { model.show(live == nil ? .usage : .activity) }

            // Claude's plan.
            HStack(spacing: 7) {
                ClaudeMark(size: 13).frame(width: 18)
                if model.app.currentClaudeUsage != nil {
                    UsageChips(model: model)
                } else {
                    Text("Plan: no data yet").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .sideWidget { model.show(.usage) }

            // Battery and Keep Awake.
            HStack(spacing: 6) {
                BatteryChip()
                if model.app.keepAwake.isOn {
                    StatusChip(symbol: "cup.and.saucer.fill", text: "Awake", tint: Color(red: 0.98, green: 0.62, blue: 0.22))
                }
                Spacer(minLength: 0)
            }
            .sideWidget { model.show(.tools) }
        }
    }
}

private extension View {
    func sideWidget(open: @escaping () -> Void) -> some View {
        padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true, fallback: .white.opacity(0.07))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
    }
}

/// A live activity's small icon: the agent orb, the call badge, or its symbol.
private struct ActivityIcon: View {
    let event: ActivityEvent

    var body: some View {
        switch ActivityPresentation(event) {
        case .agent(let state):
            AgentOrb(state: state, tint: SourceStyle.tint(event.source), symbol: event.displaySymbol, size: 16, source: event.source)
        case .call(let mic):
            CallGlyph(mic: mic, size: 16)
        default:
            Image(systemName: event.displaySymbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(event.tint)
        }
    }
}

/// Claude's 5-hour and weekly limits as two small pills; tap for the Usage page.
private struct UsageChips: View {
    let model: IslandViewModel

    var body: some View {
        if let usage = model.app.currentClaudeUsage {
            Button { model.show(.usage) } label: {
                HStack(spacing: 4) {
                    if let five = usage.fiveHour { chip("5h", five.leftFraction) }
                    if let week = usage.sevenDay { chip("wk", week.leftFraction) }
                }
            }
            .buttonStyle(.plain)
            .help("Claude Code plan left (5-hour · weekly)")
        }
    }

    private func chip(_ label: String, _ left: Double) -> some View {
        let tint = left < 0.15 ? Theme.danger : left < 0.35 ? Theme.attention : SourceStyle.tint("claude")
        return HStack(spacing: 3) {
            Text(label).foregroundStyle(.white.opacity(0.5))
            Text("\(Int((left * 100).rounded()))%").foregroundStyle(tint)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(.white.opacity(0.08), in: Capsule())
    }
}

/// Row 2: the song with its cover and controls, or a quiet hint.
private struct MusicRow: View {
    let model: IslandViewModel

    var body: some View {
        if let event = model.music?.event {
            HStack(spacing: 10) {
                Artwork(source: event.metadata["artwork"], player: event.metadata["player"], size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    Text(event.detail ?? "").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 14) {
                    ForEach(event.actions) { action in
                        Button { model.app.perform(action, source: event.source) } label: {
                            Image(systemName: action.symbol)
                                .font(.system(size: action.id.hasPrefix("playpause") ? 15 : 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(action.label)
                    }
                }
            }
        } else {
            let player = MediaIntegration.lastPlayer
            HStack(spacing: 10) {
                PlayerIcon(player: player, size: 26)
                Text("Nothing playing").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                // Opens the player if it's closed and resumes your music.
                Button { model.app.integrations.perform("play:\(player)", source: "media") } label: {
                    Label("Play \(player)", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }
}

/// Row 3, left: the first tools (same icons as the Tools page) plus "More".
private struct ToolStrip: View {
    let model: IslandViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IslandTool.all(model).prefix(6)) { IslandToolIcon(tool: $0) }
            IslandToolIcon(tool: IslandTool(id: "more", title: "More", symbol: "ellipsis", colors: [Color(white: 0.42), Color(white: 0.24)],
                                            help: "All tools") { model.show(.tools) })
        }
    }
}

/// A small pill with an icon and text, for the quiet row.
private struct StatusChip: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Battery level and charging, for the quiet row (read on demand; no background work).
private struct BatteryChip: View {
    var body: some View {
        if let battery = BatteryIntegration.read() {
            let percent = Int((battery.level * 100).rounded())
            let tint = battery.isLow ? Theme.danger : battery.isCharging ? Theme.success : Color.white.opacity(0.7)
            HStack(spacing: 3) {
                Image(systemName: battery.isCharging ? "battery.100percent.bolt" : percent > 60 ? "battery.75percent" : percent > 30 ? "battery.50percent" : "battery.25percent")
                Text("\(percent)%")
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(.white.opacity(0.08), in: Capsule())
        }
    }
}

/// Row 3, right: pick an AI (only the ones installed and signed in), type a question, press Return.
private struct AskField: View {
    let model: IslandViewModel
    @State private var text = ""

    var body: some View {
        let chosen = model.askProvider
        let inApp = !model.app.ask.providers.isEmpty
        // Without a signed-in app, both logos open the question in the browser instead.
        let choices = inApp ? model.app.ask.providers : AskProvider.allCases
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(choices) { provider in
                    Button { model.app.preferences.askProvider = provider.rawValue } label: {
                        AskLogo(provider: provider, size: 14)
                            .frame(width: 20, height: 20)
                            .opacity(provider == chosen ? 1 : 0.35)
                            .scaleEffect(provider == chosen ? 1.05 : 0.9)
                    }
                    .buttonStyle(.plain)
                    .help(inApp ? "Ask \(provider.name)" : "Ask in \(provider.webName) (opens your browser)")
                }
            }
            TextField(inApp ? "Ask \(chosen.name)…" : "Ask in \(chosen.webName)…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit {
                    if inApp {
                        model.ask(text)
                    } else if let url = chosen.webURL(for: text) {
                        NSWorkspace.shared.open(url)
                    }
                    text = ""
                }
            if !text.isEmpty {
                Image(systemName: "return").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

/// The logo of the AI answering: the Claude mascot, or the Codex app's icon.
struct AskLogo: View {
    let provider: AskProvider
    var size: CGFloat = 14

    var body: some View {
        provider == .claude ? AnyView(ClaudeMark(size: size)) : AnyView(AgentLogo(source: "codex", size: size))
    }
}

// MARK: - Ask chat

/// A small chat: your messages on the right, answers on the left, follow-ups remember the conversation.
struct AskClaudeView: View {
    let model: IslandViewModel
    @State private var draft = ""
    @Environment(\.highlight) private var highlight

    var body: some View {
        let ask = model.app.ask
        VStack(spacing: 8) {
            header(ask)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if ask.history.isEmpty && ask.question.isEmpty {
                            VStack(spacing: 6) {
                                AskLogo(provider: ask.provider, size: 26)
                                Text("Ask \(ask.provider.name) anything").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                                Text("It can't see your files from here. For your project, use Claude Code in your editor.")
                                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                        ForEach(ask.history) { turn in
                            UserBubble(text: turn.question, tint: highlight)
                            AnswerBubble(provider: turn.provider, text: turn.answer)
                        }
                        if !ask.question.isEmpty {
                            UserBubble(text: ask.question, tint: highlight)
                            if case .failed(let message) = ask.state {
                                AnswerBubble(provider: ask.provider, text: message, isError: true)
                            } else if ask.answer.isEmpty {
                                TypingBubble(provider: ask.provider)
                            } else {
                                AnswerBubble(provider: ask.provider, text: ask.answer)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .onChange(of: ask.answer) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: ask.question) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            composer(ask)
        }
        .padding(10)
        .islandPane(tint: (ask.provider == .claude ? SourceStyle.tint("claude") : SourceStyle.tint("codex")).opacity(0.1))
    }

    private func header(_ ask: AskService) -> some View {
        HStack(spacing: 8) {
            AskLogo(provider: ask.provider, size: 15)
            Text(ask.provider.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            if ask.state == .asking {
                Text("typing…").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if ask.state == .asking {
                headerButton("stop.fill", help: "Stop") { ask.cancel() }
            }
            if let url = ask.provider.webURL(for: ask.question) {
                headerButton("safari", help: "Continue in \(ask.provider.webName)") { NSWorkspace.shared.open(url) }
            }
            headerButton("square.and.pencil", help: "New chat") { ask.reset() }
            headerButton("xmark", help: "Close (the chat is kept)") { model.closeAnswer() }
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24, height: 22)
                .background(.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func composer(_ ask: AskService) -> some View {
        HStack(spacing: 8) {
            TextField("Message \(ask.provider.name)…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(draft.isEmpty ? .white.opacity(0.12) : highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Send")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.ask(draft)
        draft = ""
    }
}

private struct UserBubble: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(tint.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct AnswerBubble: View {
    let provider: AskProvider
    let text: String
    var isError = false
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AskLogo(provider: provider, size: 14).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(isError ? AttributedString(text) : Self.markdown(text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(isError ? Theme.attention : .white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !isError, hovering {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 24)
        }
        .onHover { hovering = $0 }
    }

    /// Bold, italics, code and links; anything else stays as plain text.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Three dots that pulse while the answer is on its way.
private struct TypingBubble: View {
    let provider: AskProvider
    @Environment(\.stillMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AskLogo(provider: provider, size: 14).frame(width: 18)
            TimelineView(.animation(minimumInterval: 1 / 8, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.35 + 0.5 * max(0, sin(time * 5 - Double(index) * 0.8))))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: Capsule())
            }
            Spacer()
        }
        .accessibilityLabel("\(provider.name) is typing")
    }
}

// MARK: - Notes page

/// A quick note that stays until you clear it.
struct IslandNotesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Note", systemImage: "note.text")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.8, blue: 0.3))
                Spacer()
                if !preferences.note.isEmpty {
                    Button("Clear") { preferences.note = "" }.buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                }
            }
            TextEditor(text: $preferences.note)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
        }
        .padding(12)
        .islandPane()
    }
}
