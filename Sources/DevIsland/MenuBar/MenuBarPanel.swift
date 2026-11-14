import SwiftUI

/// The panel that opens from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)
            Divider()
            live
                .padding(.vertical, 6)
            Divider()
            actions
                .padding(12)
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 330)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("DevIsland").font(.system(size: 14, weight: .semibold))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.store.live.isEmpty {
                StatusPill(text: "Live", tint: Theme.accent, pulsing: true)
            }
        }
    }

    private var statusText: String {
        let count = model.store.live.count
        return count == 0 ? "All quiet" : "\(count) live \(count == 1 ? "activity" : "activities")"
    }

    @ViewBuilder
    private var live: some View {
        if model.store.live.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text("Nothing running right now")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } else {
            ForEach(model.store.live.prefix(4)) { activity in
                MenuLiveRow(activity: activity)
            }
        }
    }

    private var actions: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                QuickActionButton(title: "Focus 25m", symbol: "brain.head.profile", tint: Theme.violet) { model.startFocus() }
                QuickActionButton(title: "Clipboard", symbol: "doc.on.clipboard.fill", tint: SourceStyle.tint("clipboard")) {
                    model.windows?.showDashboard(.clipboard)
                }
            }
            GridRow {
                QuickActionButton(title: "Toggle Island", symbol: "capsule.fill", tint: .gray) { model.toggleIsland() }
                QuickActionButton(title: "Dashboard", symbol: "square.grid.2x2.fill", tint: SourceStyle.tint("network")) {
                    model.windows?.showDashboard(nil)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { model.windows?.showSettings() }
            Button("Test Event") { model.sendTestEvent() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

private struct MenuLiveRow: View {
    @Environment(AppModel.self) private var model
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        HStack(spacing: 10) {
            EventIcon(event: event, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(event.detail ?? SourceStyle.name(event.source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            LiveValueText(activity: activity, size: 13)
            ForEach(event.actions.prefix(2)) { action in
                Button { model.perform(action, source: event.source) } label: {
                    Image(systemName: action.symbol)
                }
                .buttonStyle(.borderless)
                .help(action.label)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct QuickActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color.primary.opacity(hovering ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
