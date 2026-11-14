import AppKit
import SwiftUI

/// A colored orb for an AI agent: a spinning ring while working, a pulse when it needs you,
/// a checkmark when done.
struct AgentOrb: View {
    let state: ActivityPresentation.AgentState
    let tint: Color
    let symbol: String
    var size: CGFloat = 44
    /// "claude" draws the Claude spark instead of the symbol.
    var source: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if source == "claude" {
                ClaudeMark(size: size * 0.62, color: .white)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }

            switch state {
            case .working:
                OrbRing(mode: .spin, color: .white, lineWidth: max(1.5, size * 0.07))
                    .padding(-size * 0.13)
            case .attention:
                OrbRing(mode: .pulse, color: Theme.attention, lineWidth: max(1.5, size * 0.06))
                    .padding(-size * 0.13)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.success)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .offset(x: size * 0.36, y: size * 0.36)
            case .idle:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

struct AgentStateChip: View {
    let state: ActivityPresentation.AgentState

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var label: String {
        switch state {
        case .working: "Working"
        case .attention: "Needs you"
        case .done: "Done"
        case .idle: "Ready"
        }
    }

    private var color: Color {
        switch state {
        case .working: Theme.accent
        case .attention: Theme.attention
        case .done: Theme.success
        case .idle: .gray
        }
    }
}

/// The music app's own icon (Music or Spotify), or a note if it can't be found.
struct PlayerIcon: View {
    let player: String?
    var size: CGFloat = 44

    var body: some View {
        if let image = AppIconCache.icon(for: player) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(SourceStyle.tint("media"), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        }
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for player: String?) -> NSImage? {
        guard let player, let bundleID = MediaIntegration.bundleID(for: player) else { return nil }
        return icon(bundleID: bundleID)
    }

    /// The installed app's own icon, or nil if the app isn't installed.
    static func icon(bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

/// Little bouncing bars while music plays.
/// A battery outline filled to the current level.
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    var tint: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            HStack(spacing: width * 0.03) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                        .stroke(.white.opacity(0.45), lineWidth: max(1, height * 0.07))
                    RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                        .fill(tint)
                        .frame(width: max(height * 0.3, (width * 0.9 - height * 0.28) * min(max(level, 0), 1)))
                        .padding(height * 0.14)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: height * 0.55, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: width * 0.9)
                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: width * 0.06, height: height * 0.36)
            }
        }
    }
}

/// Round buttons for the dark island. `prominent` = white with a black symbol.
struct IslandIconButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        IslandIconButton(configuration: configuration, prominent: prominent)
    }

    private struct IslandIconButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: 32, height: 32)
                .background(
                    prominent ? Color.white.opacity(hovering ? 0.85 : 1) : Color.white.opacity(hovering ? 0.22 : 0.12),
                    in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(prominent ? 0 : 0.12), lineWidth: 0.5))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
