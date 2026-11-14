import SwiftUI

/// Every integration as a row, grouped: what it is, its status and an on/off switch.
struct IntegrationsView: View {
    @Environment(AppModel.self) private var model

    private static let groups: [(title: String, ids: [String])] = [
        ("Agents", ["claude", "codex"]),
        ("Live activities", ["timer", "media", "call", "downloads"]),
        ("System", ["battery", "network", "clipboard"]),
    ]

    var body: some View {
        PageScaffold(title: "Integrations", subtitle: "Turn each source on or off. Everything runs on this Mac.") {
            ForEach(Self.groups, id: \.title) { group in
                let items = group.ids.compactMap { model.integrations.integration($0) }
                ListCard(title: group.title, subtitle: "\(items.filter { model.integrations.isEnabled($0.id) }.count) of \(items.count) on") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, integration in
                        if index > 0 { Divider().padding(.leading, 51) }
                        IntegrationRow(integration: integration)
                    }
                }
            }
        }
    }
}

private struct IntegrationRow: View {
    @Environment(AppModel.self) private var model
    let integration: any Integration

    var body: some View {
        let enabled = model.integrations.isEnabled(integration.id)
        let status = self.status(enabled: enabled)
        ListRow(title: integration.name, subtitle: integration.summary) {
            AgentLogo(source: integration.id, size: 24, badge: true)
        } trailing: {
            HStack(spacing: 10) {
                if let last = model.store.lastSeen[integration.id], enabled {
                    Text(last, format: .relative(presentation: .named))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                if enabled && (integration.id == "claude" || integration.id == "codex") {
                    RowButton(title: "Set up") { model.dashboardSection = .agents }
                }
                StatusPill(text: status.text, tint: status.tint)
                Toggle(integration.name, isOn: Binding(
                    get: { enabled },
                    set: { model.integrations.setEnabled($0, for: integration.id) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    private func status(enabled: Bool) -> (text: String, tint: Color) {
        guard enabled else { return ("Off", .gray) }
        switch integration.id {
        case "claude":
            return model.hookInstaller.status == .installed ? ("Connected", Theme.success) : ("Needs setup", Theme.attention)
        case "codex":
            return model.store.lastSeen["codex"] != nil ? ("Receiving", Theme.success) : ("Manual setup", Theme.attention)
        case "battery":
            return BatteryIntegration.isAvailable ? ("Active", Theme.success) : ("No battery", .gray)
        default:
            return ("Active", Theme.success)
        }
    }
}
