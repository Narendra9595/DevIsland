import SwiftUI

/// Home: today's numbers on top; what's happening and what happened on the left; plan, setup and energy on the right.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScaffold(title: greeting, subtitle: summary) {
            HStack(spacing: 8) {
                Button { model.dashboardSection = .features } label: { Label("All features", systemImage: "sparkles.rectangle.stack") }
                    .buttonStyle(.secondary)
                Button { model.sendTestEvent() } label: { Label("Test event", systemImage: "wand.and.stars") }
                    .buttonStyle(.secondary)
                Button { model.startFocus() } label: { Label("Start focus", systemImage: "timer") }
                    .buttonStyle(.primary)
            }
        } content: {
            KPIRow()
            TwoColumn {
                NowCard()
                RecentCard()
                if !model.shelf.files.isEmpty { ShelfCard() }
            } side: {
                ClaudePlanCard()
                SetupCard()
                EnergyCard()
            }
        }
        .task { model.refreshToday() }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var summary: String {
        let live = model.store.live.count
        let liveText = live == 0 ? "All quiet right now" : "\(live) live \(live == 1 ? "activity" : "activities")"
        let agentTime = model.today.agentActiveTime
        return agentTime > 0 ? "\(liveText) · \(Format.duration(agentTime)) of agent time today" : liveText
    }
}

/// Today's four headline numbers.
private struct KPIRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.today
        let usage = model.currentClaudeUsage
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: "Agent time", value: Format.duration(stats.agentActiveTime), caption: "Claude & Codex today",
                     symbol: "sparkles", tint: SourceStyle.tint("claude"))
            StatTile(title: "Turns", value: "\(stats.agentTurns)", caption: "\(stats.agentAlerts) needed you",
                     symbol: "checkmark.circle", tint: Theme.accent)
            StatTile(title: "Plan left", value: usage?.fiveHour.map { "\(Int(($0.leftFraction * 100).rounded()))%" } ?? "—",
                     caption: usage?.sevenDay.map { "\(Int(($0.leftFraction * 100).rounded()))% of the week" } ?? "5-hour limit",
                     symbol: "gauge.with.dots.needle.33percent", tint: Theme.violet)
            StatTile(title: "Focus", value: Format.duration(stats.focusTime),
                     caption: "\(stats.focusSessions) \(stats.focusSessions == 1 ? "session" : "sessions")",
                     symbol: "timer", tint: Theme.attention)
        }
    }
}

/// Everything live right now, one row each.
private struct NowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let live = model.store.live
        ListCard(title: "Now", subtitle: live.isEmpty ? nil : "\(live.count) live") {
            if !live.isEmpty { StatusPill(text: "Live", tint: Theme.success, pulsing: true) }
        } content: {
            if live.isEmpty {
                EmptyRow(text: "All quiet. Claude, calls, timers, music and downloads show up here while they run.")
            } else {
                ForEach(Array(live.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { Divider().padding(.leading, 51) }
                    LiveActivityRow(activity: activity)
                }
            }
        }
    }
}

/// The latest saved events.
private struct RecentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recent = Array(model.store.history.prefix(6))
        ListCard(title: "Recent activity") {
            Button("View all") { model.dashboardSection = .activity }.buttonStyle(.link).font(.system(size: 11.5))
        } content: {
            if recent.isEmpty {
                EmptyRow(text: "Nothing yet. Events appear here as they happen.")
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().padding(.leading, 51) }
                    EventRow(event: event).padding(.horizontal, 14)
                }
            }
        }
    }
}

/// Claude Code's plan limits as two bars.
struct ClaudePlanCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let usage = model.currentClaudeUsage
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    ClaudeMark(size: 14)
                    Text("Claude plan").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if let usage {
                        Text(usage.updatedAt, format: .relative(presentation: .named)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                if usage == nil {
                    Text(model.hookInstaller.status == .installed
                         ? "Limits appear after your next Claude Code message in the terminal."
                         : "Connect Claude Code to see your 5-hour and weekly limits.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    UsageBar(title: "5-hour", window: usage?.fiveHour)
                    UsageBar(title: "Weekly", window: usage?.sevenDay)
                }
            }
        }
    }
}

/// What's set up, and one click to fix what isn't.
private struct SetupCard: View {
    @Environment(AppModel.self) private var model
    @State private var musicAccess = MediaIntegration.hasAccess()
    @State private var accessibility = AXIsProcessTrusted()

    var body: some View {
        let hooks = model.hookInstaller.status == .installed
        let ai = !model.ask.providers.isEmpty
        let done = [hooks, musicAccess, accessibility, ai].filter { $0 }.count
        ListCard(title: "Setup", subtitle: "\(done) of 4 done") {
            EmptyView()
        } content: {
            item("Claude Code connected", ok: hooks, fix: "Connect") { model.dashboardSection = .agents }
            Divider().padding(.leading, 40)
            item("Music controls", ok: musicAccess, fix: "Allow") { model.integrations.perform("play:\(MediaIntegration.lastPlayer)", source: "media") }
            Divider().padding(.leading, 40)
            item("Accessibility", ok: accessibility, fix: "Allow") { model.clipboard.requestPastePermission() }
            Divider().padding(.leading, 40)
            item("Ask AI signed in", ok: ai, fix: "Set up") { model.windows?.showSettings(tab: "AI") }
        }
        .task {
            // Re-check now and then while visible, since permissions are granted in System Settings.
            while !Task.isCancelled {
                musicAccess = MediaIntegration.hasAccess()
                accessibility = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func item(_ title: String, ok: Bool, fix: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(ok ? Theme.success : Color.secondary)
                .frame(width: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(ok ? .secondary : .primary)
            Spacer()
            if !ok { RowButton(title: fix, action: action) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct ShelfCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Shelf", subtitle: "Files you dropped on the island") {
                    Button("Clear") { model.shelf.clear() }.buttonStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(model.shelf.files, id: \.self) { FileTile(url: $0, shelf: model.shelf) }
                }
            }
        }
    }
}
