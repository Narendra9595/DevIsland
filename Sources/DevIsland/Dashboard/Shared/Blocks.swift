import SwiftUI

// Building blocks for the dashboard's SaaS-style pages.

/// Main content on the left, a fixed-width column of side panels on the right.
struct TwoColumn<Main: View, Side: View>: View {
    @ViewBuilder var main: Main
    @ViewBuilder var side: Side

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) { main }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(spacing: 14) { side }
                .frame(width: 290, alignment: .top)
        }
    }
}

/// A card with a header row, a hairline, then rows.
struct ListCard<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                        if let subtitle {
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                Divider()
                VStack(spacing: 0) { content }
                    .padding(.vertical, 4)
            }
        }
    }
}

extension ListCard where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// One row in a ListCard: icon, title and subtitle, then whatever goes on the right.
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 11) {
            leading.frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A placeholder line inside a ListCard.
struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

/// A plan limit as a slim bar: how much is left, and when it resets.
struct UsageBar: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        let left = window?.leftFraction
        let tint = left.map { $0 < 0.15 ? Theme.danger : $0 < 0.35 ? Theme.attention : SourceStyle.tint("claude") } ?? .gray
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(left.map { "\(Int(($0 * 100).rounded()))% left" } ?? "No data")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(left == nil ? Color.secondary : tint)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.subtleFill)
                    Capsule().fill(tint).frame(width: proxy.size.width * (left ?? 0))
                }
            }
            .frame(height: 6)
            if let window {
                Text(UsageRing.resetText(window.resetsAt)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// A small "Fix" style button used in checklist rows.
struct RowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action).buttonStyle(.secondary).controlSize(.small)
    }
}

/// An activity's icon: the agent orb, the call badge, the player or a tinted chip.
struct ActivityGlyph: View {
    let event: ActivityEvent
    var size: CGFloat = 26

    var body: some View {
        switch ActivityPresentation(event) {
        case .agent(let state):
            AgentOrb(state: state, tint: SourceStyle.tint(event.source), symbol: event.displaySymbol, size: size, source: event.source)
        case .media(_, let player):
            Artwork(source: event.metadata["artwork"], player: player, size: size)
        case .call(let mic):
            CallGlyph(mic: mic, size: size)
        default:
            IconBadge(symbol: event.displaySymbol, tint: event.tint, size: size)
        }
    }
}

/// A live activity as one dashboard row: what it is, what it's doing, its live value and its buttons.
struct LiveActivityRow: View {
    @Environment(AppModel.self) private var model
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        ListRow(title: event.title,
                subtitle: [SourceStyle.name(event.source), event.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")) {
            ActivityGlyph(event: event)
        } trailing: {
            HStack(spacing: 6) {
                LiveValueText(activity: activity, size: 12.5)
                ForEach(event.actions.prefix(3)) { action in
                    Button { model.perform(action, source: event.source) } label: {
                        Image(systemName: action.symbol).font(.system(size: 10.5, weight: .semibold)).frame(width: 24, height: 22)
                    }
                    .buttonStyle(.secondary)
                    .help(action.label)
                }
            }
        }
    }
}
