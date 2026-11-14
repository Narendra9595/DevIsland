import SwiftUI

/// One saved event in a list.
struct EventRow: View {
    let event: ActivityEvent
    var showsSource = true

    var body: some View {
        HStack(spacing: 12) {
            EventIcon(event: event, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let duration = event.duration, duration > 0 {
                Text(Format.duration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.subtleFill, in: Capsule())
            }
            Text(event.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private var subtitle: String {
        [showsSource ? SourceStyle.name(event.source) : nil, event.detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// The headline value of a live activity: countdown, elapsed time, percent, or bars.
struct LiveValueText: View {
    let activity: LiveActivity
    var size: CGFloat = 20

    var body: some View {
        let event = activity.event
        Group {
            switch ActivityPresentation(event) {
            case .timer(running: true):
                if let end = event.endDate { Text(end, style: .timer) }
            case .timer(running: false):
                Text(Format.clock(TimerIslandView.remaining(of: event)))
            case .agent(.done):
                Text(event.duration.map(Format.duration) ?? "Done")
            case .agent:
                Text(event.startDate ?? activity.startedAt, style: .timer)
            case .battery:
                if let level = event.progress {
                    Text(level, format: .percent.precision(.fractionLength(0)))
                }
            case .media(let playing, _):
                EqualizerBars(isPlaying: playing, tint: SourceStyle.tint("media"))
                    .frame(width: size, height: size * 0.7)
            case .call:
                Text(event.startDate ?? activity.startedAt, style: .timer)
            case .generic:
                Text(event.timestamp, format: .dateTime.hour().minute())
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// A rich card for something happening right now.
struct LiveActivityCard: View {
    @Environment(AppModel.self) private var model
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        let presentation = ActivityPresentation(event)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    glyph(event, presentation)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SourceStyle.name(event.source).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    LiveValueText(activity: activity)
                }
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                progress(event, presentation)
                if !event.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(event.actions) { action in
                            Button { model.perform(action, source: event.source) } label: {
                                Label(action.label, systemImage: action.symbol)
                            }
                            .buttonStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func glyph(_ event: ActivityEvent, _ presentation: ActivityPresentation) -> some View {
        switch presentation {
        case .agent(let state):
            AgentOrb(state: state, tint: SourceStyle.tint(event.source), symbol: event.displaySymbol, size: 30, source: event.source)
        case .media(_, let player):
            PlayerIcon(player: player, size: 30)
        default:
            IconBadge(symbol: event.displaySymbol, tint: event.tint, size: 30)
        }
    }

    @ViewBuilder
    private func progress(_ event: ActivityEvent, _ presentation: ActivityPresentation) -> some View {
        switch presentation {
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressBar(value: TimerIslandView.progress(of: event, at: context.date), tint: SourceStyle.tint(event.source))
            }
        case .battery:
            if let level = event.progress {
                ProgressBar(value: level, tint: event.tint)
            }
        default:
            EmptyView()
        }
    }
}

/// A file on the shelf, shown in the dashboard.
struct FileTile: View {
    let url: URL
    let shelf: FileShelf
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(hovering ? Theme.subtleFill : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .help(url.path)
        .draggable(url)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
    }
}

/// A list of rows inside a card, separated by inset dividers.
struct CardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var dividerInset: CGFloat = 56
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, dividerInset)
                    }
                    row(item)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
