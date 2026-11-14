import SwiftUI

/// Health of DevIsland's local services, file locations and the in-app log.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScaffold(title: "Diagnostics", subtitle: "Health of DevIsland's local services.") {
            Button { model.copy(report, message: "Diagnostics copied") } label: {
                Label("Copy Report", systemImage: "doc.on.doc")
            }
            .buttonStyle(.secondary)
        } content: {
            TwoColumn {
                ListCard(title: "Health") {
                    VStack(spacing: 0) {
                        socketRow
                        Divider()
                        databaseRow
                        Divider()
                        hooksRow
                        Divider()
                        HealthRow(level: .info, title: "Last hook message",
                                  detail: model.integrations.lastHookMessage.map {
                                      $0.formatted(.relative(presentation: .named))
                                  } ?? "None received yet")
                    }
                    .padding(.horizontal, 14)
                }
                ListCard(title: "Log", subtitle: "This session only") {
                    Button("Clear") { model.diagnostics.clear() }.buttonStyle(.secondary).controlSize(.small)
                } content: {
                    if model.diagnostics.entries.isEmpty {
                        EmptyRow(text: "No entries")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(model.diagnostics.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.date, format: .dateTime.hour().minute().second())
                                        .foregroundStyle(.tertiary)
                                    Circle().fill(color(for: entry.level)).frame(width: 5, height: 5)
                                    Text(entry.message).textSelection(.enabled)
                                }
                                .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
            } side: {
                SystemPanel()
                ListCard(title: "Storage") {
                    Button("Show") { model.revealDataFolder() }.buttonStyle(.secondary).controlSize(.small)
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        PathRow(title: "Database", path: AppPaths.database.path)
                        PathRow(title: "Hook socket", path: AppPaths.socket.path)
                        PathRow(title: "Hook script", path: AppPaths.hookScript.path)
                    }
                    .padding(14)
                }
            }
        }
    }

    @ViewBuilder
    private var socketRow: some View {
        switch model.socketStatus {
        case .listening:
            HealthRow(level: .ok, title: "Hook socket", detail: "Listening for Claude Code and Codex events")
        case .starting:
            HealthRow(level: .info, title: "Hook socket", detail: "Starting…")
        case .failed(let reason):
            HealthRow(level: .error, title: "Hook socket", detail: "Unavailable: \(reason)")
        }
    }

    @ViewBuilder
    private var databaseRow: some View {
        if let database = model.store.database {
            HealthRow(level: .ok, title: "History database",
                      detail: "\(database.totalCount()) events · \(Format.bytes(database.fileSize))")
        } else {
            HealthRow(level: .error, title: "History database", detail: "Couldn't be opened; history isn't being saved")
        }
    }

    @ViewBuilder
    private var hooksRow: some View {
        switch model.hookInstaller.status {
        case .installed:
            HealthRow(level: .ok, title: "Claude Code hooks", detail: "Installed in ~/.claude/settings.json")
        case .outdated:
            HealthRow(level: .warning, title: "Claude Code hooks", detail: "Point to an old location") {
                Button("Fix") { model.dashboardSection = .agents }.buttonStyle(.secondary)
            }
        case .notInstalled:
            HealthRow(level: .warning, title: "Claude Code hooks", detail: "Not connected") {
                Button("Set Up") { model.dashboardSection = .agents }.buttonStyle(.secondary)
            }
        }
    }

    private var report: String {
        """
        DevIsland \(AppInfo.version) (\(AppInfo.build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Socket: \(model.socketStatus)
        Database: \(model.store.database.map { "\($0.totalCount()) events" } ?? "unavailable")
        Claude hooks: \(model.hookInstaller.status)
        Enabled integrations: \(model.integrations.enabledIDs.sorted().joined(separator: ", "))

        \(model.diagnostics.report)
        """
    }

    private func color(for level: DiagnosticsLog.Level) -> Color {
        switch level {
        case .info: Theme.accent
        case .warning: Theme.attention
        case .error: Theme.danger
        }
    }
}

struct HealthRow<Action: View>: View {
    enum Level { case ok, warning, error, info }

    let level: Level
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 8)
    }

    private var symbol: String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch level {
        case .ok: Theme.success
        case .warning: Theme.attention
        case .error: Theme.danger
        case .info: .secondary
        }
    }
}

extension HealthRow where Action == EmptyView {
    init(level: Level, title: String, detail: String) {
        self.init(level: level, title: title, detail: detail, action: { EmptyView() })
    }
}

private struct PathRow: View {
    let title: String
    let path: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 110, alignment: .leading)
            Text(path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

/// CPU and memory of the whole Mac, sampled only while this page is open.
private struct SystemPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let monitor = model.systemMonitor
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "This Mac", subtitle: "Live while this page is open")
                row("CPU", value: monitor.cpu, values: monitor.samples.map(\.cpu), tint: Theme.accent)
                row("Memory", value: monitor.memoryUsed > 0 ? monitor.memoryFraction : nil,
                    values: monitor.samples.map(\.memory), tint: Theme.violet)
            }
        }
        .task { await model.systemMonitor.observe() }
    }

    private func row(_ title: String, value: Double?, values: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Sparkline(values: values, tint: tint, maxValue: 1).frame(height: 26)
        }
    }
}
