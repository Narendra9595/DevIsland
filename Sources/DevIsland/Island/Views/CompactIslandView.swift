import SwiftUI

/// How an activity should look, decided from its source and state.
enum ActivityPresentation: Equatable {
    enum AgentState: Equatable {
        case working, attention, done, idle
    }

    case agent(AgentState)
    case timer(running: Bool)
    case media(playing: Bool, player: String?)
    case battery(charging: Bool)
    case call(mic: Bool)
    case generic

    init(_ event: ActivityEvent) {
        switch event.source {
        case "claude", "codex":
            switch event.metadata["state"] {
            case "working": self = .agent(.working)
            case "attention": self = .agent(.attention)
            case "done": self = .agent(.done)
            default: self = .agent(event.kind == .alert ? .attention : .idle)
            }
        case TimerIntegration.sourceID:
            self = .timer(running: event.endDate != nil)
        case "media":
            self = .media(playing: event.metadata["state"] == "playing", player: event.metadata["player"])
        case "battery":
            self = .battery(charging: event.metadata["charging"] == "true")
        case "call":
            self = .call(mic: event.metadata["kind"] == "mic")
        default:
            self = .generic
        }
    }
}

/// The compact island: an icon on the left "ear", a short value on the right "ear".
/// The middle is hidden behind the camera.
struct CompactIslandView: View {
    let activity: LiveActivity
    let geometry: IslandGeometry

    var body: some View {
        let event = activity.event
        let presentation = ActivityPresentation(event)
        HStack(spacing: 0) {
            leading(event, presentation)
                .frame(width: IslandGeometry.earWidth)
            Spacer(minLength: geometry.centerWidth)
            trailing(activity, presentation)
                .frame(width: IslandGeometry.earWidth)
        }
        .frame(height: geometry.topHeight)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private func leading(_ event: ActivityEvent, _ presentation: ActivityPresentation) -> some View {
        switch presentation {
        case .agent(let state):
            AgentOrb(state: state, tint: SourceStyle.tint(event.source), symbol: event.displaySymbol, size: 18, source: event.source)
        case .media(_, let player):
            Artwork(source: event.metadata["artwork"], player: player, size: 20)
        case .timer:
            Image(systemName: event.displaySymbol).foregroundStyle(SourceStyle.tint(event.source))
        case .call(let mic):
            CallGlyph(mic: mic, size: 20)
        default:
            Image(systemName: event.displaySymbol).foregroundStyle(event.tint)
        }
    }

    @ViewBuilder
    private func trailing(_ activity: LiveActivity, _ presentation: ActivityPresentation) -> some View {
        let event = activity.event
        switch presentation {
        case .agent(.working):
            Text(event.startDate ?? activity.startedAt, style: .timer)
                .foregroundStyle(.white.opacity(0.9))
        case .agent(.attention):
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(Theme.attention)
                .symbolEffect(.pulse)
        case .agent(.done):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        case .agent(.idle):
            PulseDot(color: SourceStyle.tint(event.source), active: false) // static: idle sessions last hours
                .frame(width: 7, height: 7)
        case .timer(running: true):
            if let end = event.endDate {
                Text(end, style: .timer).foregroundStyle(.white)
            }
        case .timer(running: false):
            Image(systemName: "pause.fill").foregroundStyle(.white.opacity(0.7))
        case .media(let playing, _):
            EqualizerBars(isPlaying: playing, tint: SourceStyle.tint("media"))
                .frame(width: 18, height: 12)
        case .battery:
            if let level = event.progress {
                Text(level, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(event.tint)
            }
        case .call(mic: false):
            if event.metadata["muted"] == "true" {
                Image(systemName: "mic.slash.fill").foregroundStyle(Theme.danger)
            } else {
                Text(event.startDate ?? activity.startedAt, style: .timer)
                    .foregroundStyle(CallGlyph.green)
            }
        case .call(mic: true):
            HStack(spacing: 4) {
                Circle().fill(CallGlyph.orange).frame(width: 6, height: 6)
                Image(systemName: "waveform")
                    .foregroundStyle(CallGlyph.orange)
            }
        case .generic:
            if let start = event.startDate, event.kind != .completed {
                // Calls and other running things: elapsed time.
                Text(start, style: .timer).foregroundStyle(event.tint)
            } else if let progress = event.progress, event.kind != .completed {
                // Downloads and other real progress: a small filling ring.
                RingProgress(progress: progress, tint: event.tint, lineWidth: 2.5, track: .white.opacity(0.15))
                    .frame(width: 14, height: 14)
            } else if event.kind == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            } else if event.kind == .alert {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(event.tint)
            } else {
                PulseDot(color: event.tint, active: false).frame(width: 7, height: 7)
            }
        }
    }
}

/// Apple-style call / mic badge: a white phone on green, or a white mic on orange, gently pulsing.
struct CallGlyph: View {
    nonisolated static let green = Color(red: 0.2, green: 0.82, blue: 0.4)
    nonisolated static let orange = Color(red: 1.0, green: 0.58, blue: 0.0)

    let mic: Bool
    var size: CGFloat = 20
    /// Pulse gently (only in the open island; a call can last an hour, so the closed notch stays still).
    var animated = false
    @Environment(\.stillMotion) private var reduceMotion

    var body: some View {
        Image(systemName: mic ? "mic.fill" : "phone.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.pulse, options: .repeating, isActive: animated && !reduceMotion)
            .frame(width: size, height: size)
            .background(Circle().fill(mic ? Self.orange : Self.green))
            .accessibilityLabel(mic ? "Microphone on" : "On a call")
    }
}
