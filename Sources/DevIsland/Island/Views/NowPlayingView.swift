import SwiftUI

/// The island's Music page: artwork, track, a seek bar, big controls, and the library (search + playlists).
struct NowPlayingView: View {
    @Environment(AppModel.self) private var app
    let model: IslandViewModel
    let activity: LiveActivity

    var body: some View {
        let event = activity.event
        let playing = event.metadata["state"] == "playing"
        let player = event.metadata["player"]
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Artwork(source: event.metadata["artwork"], player: player, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(event.detail ?? player ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                EqualizerBars(isPlaying: playing, tint: SourceStyle.tint("media"))
                    .frame(width: 16, height: 14)
            }
            TrackProgress(metadata: event.metadata, playing: playing) { seconds in
                if let player { app.media.seek(player: player, to: seconds) }
            }
            HStack {
                Button { model.toggleLibrary() } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.libraryOpen ? SourceStyle.tint("media") : .white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(model.libraryOpen ? "Hide library" : "Search and playlists")
                Button { app.floatingPlayer?.show() } label: {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Pop out the player")
                Spacer()
                HStack(spacing: 26) {
                    ForEach(event.actions) { action in
                        Button { app.perform(action, source: event.source) } label: {
                            Image(systemName: action.symbol)
                                .font(.system(size: action.id.hasPrefix("playpause") ? 20 : 15, weight: .bold))
                                .frame(width: 30, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .help(action.label)
                    }
                }
                Spacer()
                Color.clear.frame(width: 22, height: 22) // balances the two buttons on the left
                Button { openPlayer(player) } label: { PlayerIcon(player: player, size: 20) }
                    .buttonStyle(PressableStyle())
                    .help("Open \(player ?? "player")")
            }
            if model.libraryOpen {
                Divider().overlay(.white.opacity(0.1))
                MusicLibrary(media: app.media)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func openPlayer(_ player: String?) {
        guard let player, let bundleID = MediaIntegration.bundleID(for: player),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Elapsed / bar / remaining, ticking every second. Click or drag the bar to jump.
struct TrackProgress: View {
    let metadata: [String: String]
    let playing: Bool
    let seek: (Double) -> Void
    /// 0...1 while dragging, and until the player confirms the new position.
    @State private var scrub: Double?
    @State private var dragging = false
    @Environment(\.highlight) private var highlight

    var body: some View {
        if let duration = metadata["duration"].flatMap(Double.init), duration > 0,
           let position = metadata["position"].flatMap(Double.init) {
            let since = metadata["positionAt"].flatMap(Double.init) ?? Date.now.timeIntervalSince1970
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let running = playing ? context.date.timeIntervalSince1970 - since : 0
                let elapsed = scrub.map { $0 * duration } ?? min(duration, max(0, position + running))
                HStack(spacing: 10) {
                    Text(Format.clock(elapsed))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(dragging ? highlight : .white.opacity(0.9))
                                .frame(width: proxy.size.width * elapsed / duration)
                        }
                        .frame(height: dragging ? 7 : 4)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragging = true
                                scrub = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                            }
                            .onEnded { _ in
                                dragging = false
                                if let scrub { seek(scrub * duration) }
                            })
                    }
                    .frame(height: 14)
                    Text("-" + Format.clock(duration - elapsed))
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(dragging ? 0.85 : 0.55))
                .animation(dragging ? nil : .linear(duration: 1), value: elapsed)
                .animation(.spring(duration: 0.2), value: dragging)
            }
            .onChange(of: metadata["positionAt"]) { if !dragging { scrub = nil } }
        } else if metadata["browser"] == "true" {
            EmptyView() // browser tabs don't share progress
        } else {
            Text("Use a control once and allow access to see artwork and progress")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .frame(height: 14)
        }
    }
}

/// Search the Apple Music library, or pick a playlist.
private struct MusicLibrary: View {
    let media: MediaIntegration
    @State private var query = ""
    @State private var playlists: [String] = []
    @State private var songs: [MediaIntegration.Song] = []
    @State private var catalog: [MediaIntegration.CatalogSong] = []
    @State private var loading = true
    @State private var searching = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search Apple Music", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.white.opacity(0.08), in: Capsule())

            ScrollView {
                LazyVStack(spacing: 1) {
                    if query.isEmpty {
                        ForEach(playlists, id: \.self) { name in
                            LibraryRow(symbol: "music.note.list", title: name) { media.play(playlist: name) }
                        }
                    } else {
                        if !songs.isEmpty { SectionTitle(text: "In your library · plays now") }
                        ForEach(songs) { song in
                            LibraryRow(symbol: "music.note", title: song.name, subtitle: song.artist) { media.play(song: song) }
                        }
                        if !catalog.isEmpty { SectionTitle(text: "Apple Music · opens in Music") }
                        ForEach(catalog) { song in
                            LibraryRow(symbol: "music.note", title: song.name, subtitle: song.artist,
                                       artwork: song.artwork, hoverSymbol: "arrow.up.forward") { media.open(song) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if !loading, !searching, query.isEmpty ? playlists.isEmpty : songs.isEmpty && catalog.isEmpty {
                    Text(query.isEmpty ? "No playlists in Apple Music" : "No songs found")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .task {
            playlists = await media.playlists()
            loading = false
        }
        .task(id: query) {
            guard !query.isEmpty else { songs = []; catalog = []; return }
            try? await Task.sleep(for: .milliseconds(350)) // wait until typing pauses
            guard !Task.isCancelled else { return }
            searching = true
            async let library = media.search(query)
            async let store = media.searchCatalog(query)
            let (foundSongs, foundCatalog) = await (library, store)
            guard !Task.isCancelled else { return }
            songs = foundSongs
            catalog = foundCatalog
            searching = false
        }
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct LibraryRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var artwork: URL?
    var hoverSymbol = "play.fill"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let artwork {
                    AsyncImage(url: artwork) { image in image.resizable() } placeholder: { Color.white.opacity(0.1) }
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SourceStyle.tint("media"))
                        .frame(width: 18)
                }
                Text(title).foregroundStyle(.white)
                if let subtitle { Text(subtitle).foregroundStyle(.white.opacity(0.45)) }
                Spacer(minLength: 4)
                if hovering { Image(systemName: hoverSymbol).foregroundStyle(.white.opacity(0.8)) }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Album art from a file (Music) or a URL (Spotify); the player's icon until it loads.
struct Artwork: View {
    let source: String?
    let player: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let source, source.hasPrefix("http"), let url = URL(string: source) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else if let source, let image = ArtworkCache.image(at: source) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    private var placeholder: some View {
        PlayerIcon(player: player, size: size)
    }
}

@MainActor
private enum ArtworkCache {
    private static var images: [String: NSImage] = [:]

    static func image(at path: String) -> NSImage? {
        if let image = images[path] { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        if images.count > 6 { images.removeAll() }
        images[path] = image
        return image
    }
}

/// White icon that dims and shrinks a little when pressed.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 1))
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
