import SwiftUI

/// The expanded layout for one activity, chosen by its kind.
struct IslandActivityView: View {
    let activity: LiveActivity

    var body: some View {
        switch ActivityPresentation(activity.event) {
        case .agent(let state): AgentIslandView(activity: activity, state: state)
        case .timer: TimerIslandView(activity: activity)
        case .media(let playing, let player): MediaIslandView(activity: activity, playing: playing, player: player)
        case .battery(let charging): BatteryIslandView(event: activity.event, charging: charging)
        case .call(let mic): CallIslandView(activity: activity, mic: mic)
        case .generic: GenericIslandView(activity: activity)
        }
    }
}

private extension View {
    func islandTitle() -> some View {
        font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
    }

    func islandSubtitle() -> some View {
        font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
    }

    func islandBigValue() -> some View {
        font(.system(size: 24, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
    }

    func islandCaption() -> some View {
        font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.4))
    }
}

struct AgentIslandView: View {
    let activity: LiveActivity
    let state: ActivityPresentation.AgentState

    var body: some View {
        let event = activity.event
        HStack(spacing: 14) {
            AgentOrb(state: state, tint: SourceStyle.tint(event.source), symbol: event.displaySymbol, size: 44, source: event.source)
            VStack(alignment: .leading, spacing: 3) {
                // The step Claude is on, e.g. "Check app process, windows and socket" or "Editing IslandView.swift".
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
                    .animation(.smooth(duration: 0.25), value: event.title)
                if let detail = event.detail {
                    Text(detail).islandSubtitle().lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if state == .done {
                    Text(event.duration.map(Format.duration) ?? "—").islandBigValue()
                    Text("this turn").islandCaption()
                } else {
                    Text(event.startDate ?? activity.startedAt, style: .timer).islandBigValue()
                    Text(state == .idle ? "session" : "elapsed").islandCaption()
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct TimerIslandView: View {
    @Environment(AppModel.self) private var app
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        let tint = SourceStyle.tint(event.source)
        HStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RingProgress(progress: Self.progress(of: event, at: context.date), tint: tint, lineWidth: 5,
                             track: .white.opacity(0.12))
                    .overlay {
                        Image(systemName: event.displaySymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).islandTitle()
                Text(event.detail ?? "").islandSubtitle()
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Group {
                if let end = event.endDate {
                    Text(end, style: .timer)
                } else {
                    Text(Format.clock(Self.remaining(of: event)))
                }
            }
            .islandBigValue()

            HStack(spacing: 8) {
                ForEach(event.actions) { action in
                    Button { app.perform(action, source: event.source) } label: {
                        Image(systemName: action.symbol)
                    }
                    .buttonStyle(IslandIconButtonStyle(prominent: action.id == "pause" || action.id == "resume"))
                    .help(action.label)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    static func progress(of event: ActivityEvent, at date: Date) -> Double {
        guard let total = event.duration, total > 0 else { return event.progress ?? 0 }
        if let end = event.endDate {
            return min(1, max(0, 1 - end.timeIntervalSince(date) / total))
        }
        return event.progress ?? 0
    }

    static func remaining(of event: ActivityEvent) -> TimeInterval {
        (1 - (event.progress ?? 0)) * (event.duration ?? 0)
    }
}

struct MediaIslandView: View {
    @Environment(AppModel.self) private var app
    let activity: LiveActivity
    let playing: Bool
    let player: String?

    var body: some View {
        let event = activity.event
        HStack(spacing: 14) {
            PlayerIcon(player: player, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(event.title).islandTitle()
                    if playing {
                        EqualizerBars(isPlaying: true, tint: SourceStyle.tint("media"))
                            .frame(width: 14, height: 10)
                    }
                }
                Text(event.detail ?? player ?? "").islandSubtitle()
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(event.actions) { action in
                    Button { app.perform(action, source: event.source) } label: {
                        Image(systemName: action.symbol)
                    }
                    .buttonStyle(IslandIconButtonStyle(prominent: action.id.hasPrefix("playpause")))
                    .help(action.label)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct BatteryIslandView: View {
    let event: ActivityEvent
    let charging: Bool

    var body: some View {
        let isLow = event.metadata["low"] == "true"
        HStack(spacing: 16) {
            BatteryGlyph(level: event.progress ?? 0, charging: charging,
                         tint: isLow ? Theme.danger : charging ? Theme.success : .white)
                .frame(width: 54, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.progress ?? 0, format: .percent.precision(.fractionLength(0))).islandBigValue()
                Text(event.detail ?? "").islandSubtitle()
            }
            Spacer()
            if isLow {
                Text("Low")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.danger.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
    }
}

struct GenericIslandView: View {
    @Environment(AppModel.self) private var app
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(event.tint.opacity(0.2))
                Image(systemName: event.displaySymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(event.tint)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).islandTitle()
                if let detail = event.detail {
                    Text(detail).islandSubtitle()
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if event.actions.isEmpty {
                Text(event.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(event.actions) { action in
                    Button { app.perform(action, source: event.source) } label: { Image(systemName: action.symbol) }
                        .buttonStyle(IslandIconButtonStyle())
                        .help(action.label)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// A call or mic in use: the badge with soft ripples, who's using it, how long, and a button to jump there.
struct CallIslandView: View {
    @Environment(AppModel.self) private var app
    let activity: LiveActivity
    let mic: Bool
    @State private var ripple = false
    @Environment(\.stillMotion) private var reduceMotion

    var body: some View {
        let event = activity.event
        let tint = mic ? CallGlyph.orange : CallGlyph.green
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(ripple ? 0 : 0.5), lineWidth: 2)
                    .scaleEffect(ripple ? 1.6 : 1)
                CallGlyph(mic: mic, size: 40, animated: true)
            }
            .frame(width: 52, height: 52)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { ripple = true }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).islandTitle()
                Text(event.detail ?? "").islandSubtitle()
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(event.startDate ?? activity.startedAt, style: .timer)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            HStack(spacing: 6) {
                ForEach(event.actions) { action in
                    Button { app.perform(action, source: event.source) } label: {
                        Image(systemName: action.symbol)
                            .foregroundStyle(action.id == "hangup" || action.id == "unmute" ? .white : .primary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(action.id == "hangup" ? Theme.danger
                                                      : action.id == "unmute" ? Theme.danger.opacity(0.75) : .white.opacity(0.14)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .help(action.label)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
