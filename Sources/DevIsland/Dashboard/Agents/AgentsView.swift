import Charts
import SwiftUI

struct AgentsView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [AgentSessionSummary] = []
    @State private var hourly: [HourCount] = []

    var body: some View {
        PageScaffold(title: "Agents", subtitle: "Claude Code and Codex, live from your terminal.") {
            kpis
            TwoColumn {
                liveCard
                chartCard
                sessionsCard
            } side: {
                ClaudeConnectionCard()
                CodexConnectionCard()
                ClaudePlanCard()
            }
        }
        .task(id: model.store.revision) { load() }
    }

    private var agentActivities: [LiveActivity] {
        model.store.live.filter { ActivityStats.agentSources.contains($0.event.source) }
    }

    private var kpis: some View {
        let stats = model.today
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatTile(title: "Agent time", value: Format.duration(stats.agentActiveTime), caption: "actively working today",
                     symbol: "clock", tint: SourceStyle.tint("claude"))
            StatTile(title: "Turns", value: "\(stats.agentTurns)", caption: "finished today",
                     symbol: "arrow.triangle.2.circlepath", tint: Theme.accent)
            StatTile(title: "Sessions", value: "\(stats.agentSessions)", caption: "\(agentActivities.count) live now",
                     symbol: "rectangle.stack", tint: Theme.violet)
            StatTile(title: "Needed you", value: "\(stats.agentAlerts)", caption: "permission or input",
                     symbol: "hand.raised", tint: Theme.attention)
        }
    }

    private var liveCard: some View {
        ListCard(title: "Live sessions") {
            if !agentActivities.isEmpty { StatusPill(text: "\(agentActivities.count) live", tint: Theme.success, pulsing: true) }
        } content: {
            if agentActivities.isEmpty {
                EmptyRow(text: "No agents running. Start Claude Code in your terminal and it shows up here and in your notch.")
            } else {
                ForEach(Array(agentActivities.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { Divider().padding(.leading, 51) }
                    LiveActivityRow(activity: activity)
                }
            }
        }
    }

    private var chartCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Turns by hour", subtitle: "Finished agent turns today")
                Chart(hourly) { item in
                    BarMark(x: .value("Hour", item.hour), y: .value("Turns", item.count), width: .ratio(0.65))
                        .foregroundStyle(SourceStyle.tint("claude"))
                        .cornerRadius(2)
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) { Text(Self.hourLabel(hour)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 140)
            }
        }
    }

    private var sessionsCard: some View {
        ListCard(title: "Recent sessions", subtitle: "Last 7 days") {
            if sessions.isEmpty {
                EmptyRow(text: "Sessions appear here after Claude Code reports through its hooks.")
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider().padding(.leading, 51) }
                    SessionRow(session: session).padding(.horizontal, 14)
                }
            }
        }
    }

    private func load() {
        model.refreshToday()
        guard let database = model.store.database else { return }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let events = database.events(since: weekAgo)
        sessions = Array(ActivityStats.agentSessions(events).prefix(12))
        hourly = ActivityStats.agentTurnsByHour(events.filter { Calendar.current.isDateInToday($0.timestamp) })
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

private struct ClaudeConnectionCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let installer = model.hookInstaller
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AgentLogo(source: "claude", size: 24, badge: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claude Code").font(.system(size: 12.5, weight: .semibold))
                        Text("Hooks").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: statusText(installer.status), tint: statusTint(installer.status),
                               pulsing: installer.status == .installed && model.store.lastSeen["claude"] != nil)
                }
                Text(explanation(installer.status))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = installer.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                }
                HStack(spacing: 8) {
                    if installer.status == .installed {
                        Button("Disconnect") { model.disconnectClaude() }
                            .buttonStyle(.secondary)
                    } else {
                        Button { confirming = true } label: {
                            Label(installer.status == .outdated ? "Update Hooks" : "Connect", systemImage: "link")
                        }
                        .buttonStyle(.primary)
                    }
                    Spacer()
                    if let last = model.store.lastSeen["claude"] {
                        Text(last, format: .relative(presentation: .named))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Connect Claude Code?", isPresented: $confirming) {
            Button("Connect") { model.connectClaude() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("DevIsland will add a few small hooks to ~/.claude/settings.json and save a backup next to it first. Claude Code then sends its status to DevIsland on this Mac: the step it's on, file names and the first line of its messages. Your prompts and code are never read.")
        }
    }

    private func statusText(_ status: ClaudeHookInstaller.Status) -> String {
        switch status {
        case .installed: "Connected"
        case .outdated: "Needs update"
        case .notInstalled: "Not connected"
        }
    }

    private func statusTint(_ status: ClaudeHookInstaller.Status) -> Color {
        switch status {
        case .installed: Theme.success
        case .outdated: Theme.attention
        case .notInstalled: .gray
        }
    }

    private func explanation(_ status: ClaudeHookInstaller.Status) -> String {
        switch status {
        case .installed: "New Claude Code sessions report their status, current tool and turn time to your notch."
        case .outdated: "DevIsland's hooks need an update to show more of what Claude is doing. Your settings are backed up first."
        case .notInstalled: "Connect once and every new Claude Code session shows up in your notch and here."
        }
    }
}

private struct CodexConnectionCard: View {
    @Environment(AppModel.self) private var model

    private var line: String {
        #"notify = ["\#(AppPaths.hookScript.path)", "codex"]"#
    }

    var body: some View {
        let receiving = model.store.lastSeen["codex"] != nil
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AgentLogo(source: "codex", size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Codex").font(.system(size: 12.5, weight: .semibold))
                        Text("notify").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: receiving ? "Receiving" : "Manual setup",
                               tint: receiving ? Theme.success : .gray, pulsing: receiving)
                }
                Text("Add this line to ~/.codex/config.toml so Codex reports finished turns:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.copy(line) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                }
                .padding(10)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSessionSummary

    var body: some View {
        HStack(spacing: 12) {
            AgentLogo(source: session.source, size: 26, badge: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project ?? "Session").font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            metric("\(session.turns)", "turns")
            metric(Format.duration(session.activeTime), "active")
            if session.alerts > 0 {
                Label("\(session.alerts)", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.attention)
            }
        }
        .padding(.vertical, 9)
    }

    private var subtitle: String {
        let when = "\(Format.dayTitle(session.start)), \(session.start.formatted(date: .omitted, time: .shortened))"
        return [when, session.branch].compactMap { $0 }.joined(separator: " · ")
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 48, alignment: .trailing)
    }
}
