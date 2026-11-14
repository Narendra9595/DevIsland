import SwiftUI

/// One DevIsland tool: the same icon, colors and action everywhere it appears.
struct IslandTool: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let colors: [Color]
    let help: String
    var badge = 0
    var active = false
    let action: () -> Void

    /// Every tool, in order. Home shows the first few plus "More"; the Tools page shows them all.
    @MainActor
    static func all(_ model: IslandViewModel) -> [IslandTool] {
        let app = model.app
        return [
            IslandTool(id: "clipboard", title: "Clipboard", symbol: "list.clipboard.fill",
                       colors: [.init(red: 0.35, green: 0.62, blue: 1), .init(red: 0.18, green: 0.38, blue: 0.95)],
                       help: "Clipboard history  ⌃⌥V") { model.show(.clipboard) },
            IslandTool(id: "files", title: "Files", symbol: "folder.fill",
                       colors: [.init(red: 0.2, green: 0.83, blue: 0.75), .init(red: 0.05, green: 0.58, blue: 0.55)],
                       help: "Files you dropped on the notch", badge: app.shelf.files.count) { model.show(.files) },
            IslandTool(id: "notes", title: "Notes", symbol: "square.and.pencil",
                       colors: [.init(red: 1, green: 0.84, blue: 0.3), .init(red: 0.96, green: 0.63, blue: 0.1)],
                       help: "Quick note") { model.show(.notes) },
            IslandTool(id: "focus", title: "Focus", symbol: "timer",
                       colors: [.init(red: 0.66, green: 0.5, blue: 1), .init(red: 0.45, green: 0.3, blue: 0.95)],
                       help: "Start a 25-minute focus timer") { app.startFocus() },
            IslandTool(id: "awake", title: "Awake", symbol: "cup.and.saucer.fill",
                       colors: [.init(red: 1, green: 0.66, blue: 0.3), .init(red: 0.93, green: 0.42, blue: 0.12)],
                       help: app.keepAwake.isOn ? "Keep Awake is on (tap to turn off)" : "Keep your Mac awake",
                       active: app.keepAwake.isOn) { app.keepAwake.toggle() },
            IslandTool(id: "mirror", title: "Mirror", symbol: "web.camera.fill",
                       colors: [.init(red: 0.45, green: 0.55, blue: 1), .init(red: 0.3, green: 0.3, blue: 0.85)],
                       help: "Camera mirror") { model.show(.camera) },
            IslandTool(id: "player", title: "Player", symbol: "pip.fill",
                       colors: [.init(red: 1, green: 0.42, blue: 0.62), .init(red: 0.86, green: 0.2, blue: 0.45)],
                       help: "Pop out the music player") { app.floatingPlayer?.toggle() },
            IslandTool(id: "usage", title: "Usage", symbol: "gauge.with.dots.needle.67percent",
                       colors: [.init(red: 0.92, green: 0.55, blue: 0.4), .init(red: 0.78, green: 0.36, blue: 0.24)],
                       help: "Claude plan limits") { model.show(.usage) },
        ]
    }
}

/// An app-style icon (glossy gradient tile, white symbol) with its name underneath. Active adds a glowing ring.
struct IslandToolIcon: View {
    let tool: IslandTool
    var size: CGFloat = 30
    @State private var hovering = false

    var body: some View {
        Button(action: tool.action) {
            VStack(spacing: size * 0.12) {
                let corner = size * 0.28
                Image(systemName: tool.symbol)
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: tool.colors, startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: 0.75))
                    .overlay(RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                        .strokeBorder(tool.active ? tool.colors[0] : .clear, lineWidth: 1.5).padding(-3))
                    .shadow(color: tool.colors[0].opacity(hovering || tool.active ? 0.55 : 0), radius: size * 0.27)
                    .overlay(alignment: .topTrailing) {
                        if tool.badge > 0 {
                            Text("\(tool.badge)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 13)
                                .background(Theme.danger, in: Capsule()).offset(x: 4, y: -4)
                        }
                    }
                    .scaleEffect(hovering ? 1.08 : 1)
                Text(tool.title)
                    .font(.system(size: max(9, size * 0.23), weight: .medium))
                    .foregroundStyle(.white.opacity(hovering || tool.active ? 0.95 : 0.65))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: size + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.22, bounce: 0.35), value: hovering)
        .help(tool.help)
        .accessibilityLabel(tool.help)
    }
}

/// The Tools page: every tool, the same icons as on Home, just bigger.
struct IslandToolsView: View {
    let model: IslandViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(IslandTool.all(model)) { tool in
                IslandToolIcon(tool: tool, size: 44).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
