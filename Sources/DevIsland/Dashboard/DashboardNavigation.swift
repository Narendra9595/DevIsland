import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, features, agents, activity, clipboard, integrations, diagnostics

    var id: String { rawValue }
    var title: String { self == .overview ? "Home" : rawValue.capitalized }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .features: "sparkles.rectangle.stack"
        case .agents: "sparkles"
        case .activity: "chart.bar.xaxis"
        case .clipboard: "doc.on.clipboard"
        case .integrations: "puzzlepiece.extension"
        case .diagnostics: "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .overview: Theme.accent
        case .features: Theme.violet
        case .agents: SourceStyle.tint("claude")
        case .activity: Theme.violet
        case .clipboard: SourceStyle.tint("clipboard")
        case .integrations: Color(red: 0.98, green: 0.62, blue: 0.22)
        case .diagnostics: Color(white: 0.55)
        }
    }
}

struct DashboardSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.dashboardSection) {
            Section {
                item(.overview)
                item(.features)
                item(.agents)
                item(.activity)
            }
            Section("Tools") {
                item(.clipboard)
            }
            Section("System") {
                item(.integrations)
                item(.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 9) {
                AppIconView().frame(width: 22, height: 22)
                Text("DevIsland").font(.system(size: 13.5, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }

    private func item(_ section: DashboardSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            // Plain monochrome icons, like a modern SaaS sidebar; color is kept for content.
            if section == .agents {
                ClaudeMark(size: 15, color: model.dashboardSection == section ? Theme.accent : Color.secondary)
            } else {
                Image(systemName: section.symbol)
                    .foregroundStyle(model.dashboardSection == section ? Theme.accent : Color.secondary)
            }
        }
        .badge(badge(for: section))
        .tag(section)
    }

    private func badge(for section: DashboardSection) -> Int {
        switch section {
        case .agents: model.store.live.filter { ActivityStats.agentSources.contains($0.event.source) }.count
        case .clipboard: model.integrations.isEnabled(model.clipboard.id) ? model.clipboard.items.count : 0
        default: 0
        }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                PulseDot(color: dotColor, active: !model.store.live.isEmpty)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.store.live.isEmpty ? "All quiet" : "\(model.store.live.count) live")
                        .font(.caption.weight(.semibold))
                    Text(socketText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { model.windows?.showSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var dotColor: Color {
        if case .failed = model.socketStatus { return Theme.danger }
        return model.store.live.isEmpty ? Theme.success : Theme.accent
    }

    private var socketText: String {
        switch model.socketStatus {
        case .starting: "Starting…"
        case .listening: "Listening for agents"
        case .failed: "Hook socket unavailable"
        }
    }
}

struct DashboardDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.dashboardSection ?? .overview {
            case .overview: OverviewView()
            case .features: FeaturesView()
            case .agents: AgentsView()
            case .activity: ActivityView()
            case .clipboard: ClipboardView()
            case .integrations: IntegrationsView()
            case .diagnostics: DiagnosticsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraBackground())
        .overlay(alignment: .bottom) { ToastView(toast: model.toast) }
        .animation(.easeOut(duration: 0.18), value: model.dashboardSection)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: model.toast)
    }
}
