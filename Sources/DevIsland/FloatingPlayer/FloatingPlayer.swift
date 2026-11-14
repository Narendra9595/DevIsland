import AppKit
import SwiftUI

/// A music player you can pull out of the notch and park anywhere on the desktop. Two sizes: mini and full.
@MainActor
final class FloatingPlayerController {
    private let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func toggle() {
        if let panel, panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSHostingView(rootView: AppRoot(model: model) {
            FloatingPlayerView(close: { [weak panel] in panel?.orderOut(nil) },
                               resize: { [weak panel] size in Self.resize(panel, to: size) })
        })
        view.sizingOptions = []
        panel.contentView = view
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: screen.maxX - 320, y: screen.minY + 20))
        }
        return panel
    }

    /// Changes size while keeping the top edge in place.
    private static func resize(_ panel: NSPanel?, to size: CGSize) {
        guard let panel else { return }
        let frame = panel.frame
        panel.setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                       display: true, animate: true)
    }
}

private struct FloatingPlayerView: View {
    @Environment(AppModel.self) private var app
    let close: () -> Void
    let resize: (CGSize) -> Void
    @State private var large = false
    @State private var hovering = false

    var body: some View {
        let music = app.store.live.filter { $0.event.source == "media" }
        let event = (music.first { $0.event.metadata["state"] == "playing" } ?? music.first)?.event
        ZStack(alignment: .topTrailing) {
            Group {
                if let event { large ? AnyView(full(event)) : AnyView(mini(event)) } else { empty }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.55))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))

            if hovering {
                HStack(spacing: 4) {
                    windowButton(large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 help: large ? "Smaller" : "Bigger") {
                        large.toggle()
                        resize(large ? CGSize(width: 300, height: 380) : CGSize(width: 300, height: 72))
                    }
                    windowButton("xmark", help: "Close", action: close)
                }
                .padding(7)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func mini(_ event: ActivityEvent) -> some View {
        HStack(spacing: 10) {
            Artwork(source: event.metadata["artwork"], player: event.metadata["player"], size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 13, weight: .semibold))
                Text(event.detail ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            controls(event, size: 15)
        }
        .padding(.horizontal, 13)
    }

    private func full(_ event: ActivityEvent) -> some View {
        VStack(spacing: 12) {
            Artwork(source: event.metadata["artwork"], player: event.metadata["player"], size: 240)
                .padding(.top, 18)
            VStack(spacing: 3) {
                Text(event.title).font(.system(size: 15, weight: .semibold))
                Text(event.detail ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 18)
            TrackProgress(metadata: event.metadata, playing: event.metadata["state"] == "playing") { seconds in
                if let player = event.metadata["player"] { app.media.seek(player: player, to: seconds) }
            }
            .padding(.horizontal, 18)
            controls(event, size: 19)
            Spacer(minLength: 0)
        }
    }

    private func controls(_ event: ActivityEvent, size: CGFloat) -> some View {
        HStack(spacing: size * 1.1) {
            ForEach(event.actions) { action in
                Button { app.perform(action, source: event.source) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: action.id.hasPrefix("playpause") ? size + 4 : size, weight: .bold))
                        .frame(width: size + 10, height: size + 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(action.label)
            }
        }
        .foregroundStyle(.white)
    }

    private var empty: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(SourceStyle.tint("media"))
            Text("Nothing playing").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func windowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
    }
}
