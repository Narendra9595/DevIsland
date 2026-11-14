import AppKit
import CoreAudio

/// Now playing + controls for Apple Music and Spotify.
/// Track changes come from the players' own notifications (no permission needed).
/// With Automation permission we also read artwork and position, and send controls.
final class MediaIntegration: Integration {
    let id = "media"
    let name = "Music"
    let summary = "Now playing and controls for Apple Music and Spotify."
    let symbol = "music.note"

    private static let players = [
        "com.apple.Music.playerInfo": "Music",
        "com.spotify.client.PlaybackStateChanged": "Spotify",
    ]
    private static let bundleIDs = ["Music": "com.apple.Music", "Spotify": "com.spotify.client", "TV": "com.apple.TV"]
    private static let commands = ["previous": "previous track", "playpause": "playpause", "next": "next track", "play": "play"]

    /// Whether DevIsland may control your music player (asks nothing; just checks).
    static func hasAccess() -> Bool {
        guard let bundleID = bundleIDs[lastPlayer] else { return false }
        return automationPermission(for: bundleID, ask: false) == noErr
    }

    /// The player you used last, so the island can start it even when it's closed.
    static var lastPlayer: String { UserDefaults.standard.string(forKey: "lastMusicPlayer") ?? "Music" }
    private nonisolated static let artFolder = URL.cachesDirectory.appending(path: "DevIsland/Artwork", directoryHint: .isDirectory)

    /// What a player reported: from its notification, or read with AppleScript.
    struct Track: Sendable {
        var state: String
        var name: String
        var artist = ""
        var album = ""
        var position: Double?
        var duration: Double?
        var artwork: String?
    }

    /// A song found in the Music library.
    struct Song: Sendable, Identifiable {
        let id: String
        let name: String
        let artist: String
    }

    /// A song from the whole Apple Music catalog (Apple's public search).
    struct CatalogSong: Sendable, Identifiable, Decodable {
        let id: Int
        let name: String
        let artist: String
        let artwork: URL?
        let link: URL?

        enum CodingKeys: String, CodingKey {
            case id = "trackId", name = "trackName", artist = "artistName", artwork = "artworkUrl60", link = "trackViewUrl"
        }
    }

    private var observers: [any NSObjectProtocol] = []
    private var publish: Publish?

    static func bundleID(for player: String) -> String? {
        bundleIDs[player] ?? BrowserMedia.browser(named: player)?.bundleID
    }

    // MARK: Browser tabs (YouTube and friends)

    private var browserTask: Task<Void, Never>?
    /// What's shown for the browser right now.
    private var browserNow: (browser: BrowserMedia.Browser, tab: BrowserMedia.Tab, playing: Bool)?
    private var browserChecked = Date.distantPast
    /// After you press play/pause in the notch: the state you chose, kept until the browser's sound agrees
    /// (it keeps reporting sound for a few seconds after a pause) or the wait runs out.
    private var browserExpect: (playing: Bool, until: Date)?
    /// Browser audio processes we're listening to, so a pause or play shows up immediately.
    private var browserListeners: Set<AudioObjectID> = []
    private var browserPublish: Publish?
    private var tvWasPlaying = false
    private var tvTitle: String?

    /// Every 2 s: is a browser playing sound? If so, which media tab? (The tab is re-read every 6 s for the next video.)
    private func pollBrowsers(publish: @escaping Publish) {
        browserPublish = publish
        listenToBrowserAudio()
        // The Apple TV app: read it like Music when it starts playing sound.
        let tvPlaying = AudioProcesses.all().contains { $0.playing && $0.bundleID == "com.apple.TV" }
        if tvPlaying != tvWasPlaying {
            tvWasPlaying = tvPlaying
            // Without permission to read it yet, at least show that Apple TV is playing.
            refresh(player: "TV", fallback: Track(state: tvPlaying ? "Playing" : "Paused", name: tvTitle ?? "Apple TV"), publish: publish)
        }
        let playing = BrowserMedia.playingBrowser()
        if let expect = browserExpect {
            if (playing != nil) == expect.playing || Date.now > expect.until {
                browserExpect = nil // the sound caught up (or we waited long enough): back to normal
            } else {
                return // keep showing what you chose
            }
        }
        if let browser = playing {
            let changed = browserNow?.browser != browser || browserNow?.playing != true
            guard changed || Date.now.timeIntervalSince(browserChecked) > 6 else { return }
            browserChecked = .now
            Task { [weak self] in
                // Asks for Automation the first time (macOS: "DevIsland wants to control Chrome").
                let allowed = browser.isApp ? true
                    : await Task.detached { Self.automationPermission(for: browser.bundleID, ask: true) == noErr }.value
                guard allowed, let tab = await Task.detached(operation: { BrowserMedia.mediaTab(in: browser) }).value else { return }
                guard let self else { return }
                if self.browserNow?.browser != browser || self.browserNow?.tab != tab || self.browserNow?.playing != true {
                    self.browserNow = (browser, tab, true)
                    self.publishBrowser(publish: publish)
                }
            }
        } else if let now = browserNow, now.playing {
            browserNow?.playing = false // sound stopped: show it as paused
            browserChecked = .now
            publishBrowser(publish: publish)
        } else if let now = browserNow, Date.now.timeIntervalSince(browserChecked) > 5 {
            // Paused: make sure the tab (or app) is still there; if it was closed, take it off the notch.
            browserChecked = .now
            Task { [weak self] in
                let stillThere = await Self.mediaStillOpen(now.browser)
                guard let self, !stillThere, self.browserNow?.browser == now.browser else { return }
                self.endBrowser(publish: publish)
            }
        }
    }

    /// Whether the paused browser tab or video app is still open.
    private static func mediaStillOpen(_ browser: BrowserMedia.Browser) async -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { return false }
        if browser.isApp { return true }
        return await Task.detached { BrowserMedia.mediaTab(in: browser) != nil }.value
    }

    private func endBrowser(publish: Publish) {
        guard let now = browserNow else { return }
        browserNow = nil
        browserExpect = nil
        publish(ActivityEvent(source: id, kind: .ended, sessionID: now.browser.name, title: "Stopped"))
    }

    /// macOS tells us the moment a browser's sound starts or stops; then we re-check right away.
    private func listenToBrowserAudio() {
        for process in BrowserMedia.browserProcesses() where !browserListeners.contains(process) {
            var address = AudioProcesses.runningOutput
            let status = AudioObjectAddPropertyListenerBlock(process, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let publish = self.browserPublish else { return }
                    self.pollBrowsers(publish: publish)
                }
            }
            if status == noErr { browserListeners.insert(process) }
        }
    }

    private func publishBrowser(publish: Publish) {
        guard let now = browserNow else { return }
        let player = now.browser.name
        var metadata = ["player": player, "state": now.playing ? "playing" : "paused", "browser": "true"]
        metadata["artwork"] = now.tab.artwork
        publish(ActivityEvent(
            source: id, kind: .update, sessionID: player, title: now.tab.title,
            detail: now.browser.isApp ? player : "\(now.tab.site) · \(player)", symbol: "play.rectangle.fill",
            expiresAfter: now.playing ? 2 * 3600 : 10 * 60, priority: .low,
            actions: [
                .init(id: "previous:\(player)", symbol: "backward.fill", label: "Previous"),
                .init(id: "playpause:\(player)", symbol: now.playing ? "pause.fill" : "play.fill", label: now.playing ? "Pause" : "Play"),
                .init(id: "next:\(player)", symbol: "forward.fill", label: "Next"),
            ],
            metadata: metadata))
    }

    func start(publish: @escaping Publish) {
        self.publish = publish
        try? FileManager.default.removeItem(at: Self.artFolder)
        try? FileManager.default.createDirectory(at: Self.artFolder, withIntermediateDirectories: true)
        let center = DistributedNotificationCenter.default()
        observers = Self.players.map { notification, player in
            center.addObserver(forName: Notification.Name(notification), object: nil, queue: .main) { [weak self] note in
                let track = Self.track(from: note.userInfo ?? [:])
                MainActor.assumeIsolated { self?.refresh(player: player, fallback: track, publish: publish) }
            }
        }
        browserTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollBrowsers(publish: publish)
                // Every second while a browser video is shown, every 2 s otherwise.
                try? await Task.sleep(for: .seconds(self?.browserNow == nil ? 2 : 1))
            }
        }
        // Players only announce changes, so read what's already playing once at start.
        for (player, bundleID) in Self.bundleIDs
        where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            refresh(player: player, fallback: nil, publish: publish)
        }
    }

    func stop() {
        browserTask?.cancel()
        browserTask = nil
        browserNow = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
    }

    /// Called when macOS refuses Automation permission for a player.
    var onAutomationDenied: (String) -> Void = { _ in }

    /// Actions look like "playpause:Spotify".
    /// Asks macOS for Automation permission first (shows the system prompt the first time),
    /// off the main thread so the island never freezes while the prompt is up.
    func perform(action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        // Browser tabs: media keys, which the browser sends to the playing tab (needs Accessibility).
        if parts.count == 2, BrowserMedia.browser(named: parts[1]) != nil {
            guard AXIsProcessTrusted() else {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                return
            }
            // Resuming a paused tab: check it's still open first, or the media key would start another app (e.g. Music).
            if parts[0] == "playpause", let now = browserNow, !now.playing, let publish = browserPublish {
                Task { [weak self] in
                    guard let self else { return }
                    guard await Self.mediaStillOpen(now.browser) else { self.endBrowser(publish: publish); return }
                    BrowserMedia.pressMediaKey("playpause")
                    self.browserNow?.playing = true
                    self.browserExpect = (true, .now.addingTimeInterval(5))
                    self.publishBrowser(publish: publish)
                }
                return
            }
            BrowserMedia.pressMediaKey(parts[0])
            // Flip the button right away; the browser's sound takes a few seconds to actually stop.
            if parts[0] == "playpause", let now = browserNow, let publish = browserPublish {
                let playing = !now.playing
                browserNow?.playing = playing
                // A pause can take Chrome ~10 s to go quiet; a play starts sound within a couple of seconds.
                browserExpect = (playing, .now.addingTimeInterval(playing ? 5 : 15))
                publishBrowser(publish: publish)
            }
            return
        }
        guard parts.count == 2, let command = Self.commands[parts[0]] else { return }
        let player = parts[1]
        guard Self.bundleIDs[player] != nil else { return }
        Task {
            guard await allowed(player) else { return }
            await Self.runDetached("tell application \"\(player)\" to \(command)")
        }
    }

    // MARK: Library and seeking (user actions, so macOS may ask for permission)

    /// Jumps to a time in the current track.
    func seek(player: String, to seconds: Double) {
        Task {
            guard await allowed(player) else { return }
            await Self.runDetached("on run argv\ntell application \"\(player)\" to set player position to (item 1 of argv as integer)\nend run",
                                   arguments: [String(Int(seconds))])
            refreshNow(player)
        }
    }

    /// Apple Music playlists (Spotify doesn't share its playlists with other apps).
    func playlists() async -> [String] {
        guard await allowed("Music"),
              let output = await Self.runDetached("""
                      tell application "Music" to set found to name of every user playlist whose special kind is none
                      set AppleScript's text item delimiters to linefeed
                      return found as text
                      """), !output.isEmpty else { return [] }
        return output.components(separatedBy: "\n")
    }

    /// Songs in the Apple Music library matching the text (up to 25).
    func search(_ text: String) async -> [Song] {
        guard await allowed("Music"),
              let output = await Self.runDetached("""
                      on run argv
                        set out to ""
                        tell application "Music"
                          set found to search library playlist 1 for (item 1 of argv) only songs
                          set n to 0
                          repeat with t in found
                            set out to out & (persistent ID of t) & tab & (name of t) & tab & (artist of t) & linefeed
                            set n to n + 1
                            if n ≥ 25 then exit repeat
                          end repeat
                        end tell
                        return out
                      end run
                      """, arguments: [text]) else { return [] }
        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            return parts.count == 3 ? Song(id: parts[0], name: parts[1], artist: parts[2]) : nil
        }
    }

    /// Searches the whole Apple Music catalog through Apple's public iTunes Search API (no account needed).
    func searchCatalog(_ text: String) async -> [CatalogSong] {
        struct Response: Decodable { let results: [CatalogSong] }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            .init(name: "term", value: text), .init(name: "media", value: "music"), .init(name: "entity", value: "song"),
            .init(name: "limit", value: "25"), .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.results
    }

    /// Catalog songs can't be played by other apps, so this opens the song in Music, ready to play.
    func open(_ song: CatalogSong) {
        guard let link = song.link, var components = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "music"
        NSWorkspace.shared.open(components.url ?? link)
    }

    func play(playlist name: String) {
        runInMusic("play (first user playlist whose name is (item 1 of argv))", argument: name)
    }

    func play(song: Song) {
        runInMusic("play (first track of library playlist 1 whose persistent ID is (item 1 of argv))", argument: song.id)
    }

    private func runInMusic(_ command: String, argument: String) {
        Task {
            guard await allowed("Music") else { return }
            await Self.runDetached("on run argv\ntell application \"Music\" to \(command)\nend run", arguments: [argument])
        }
    }

    /// Asks for Automation permission if needed (off the main thread); reports a refusal.
    private func allowed(_ player: String) async -> Bool {
        guard let bundleID = Self.bundleIDs[player] else { return false }
        let status = await Task.detached(priority: .userInitiated) {
            Self.automationPermission(for: bundleID, ask: true)
        }.value
        if status == OSStatus(errAEEventNotPermitted) { onAutomationDenied(player) }
        return status == noErr
    }

    private func refreshNow(_ player: String) {
        guard let publish else { return }
        refresh(player: player, fallback: nil, publish: publish)
    }

    // MARK: Reading

    /// Reads full details (art, position) when permitted, otherwise uses the notification. One event per change.
    private func refresh(player: String, fallback: Track?, publish: @escaping Publish) {
        guard let bundleID = Self.bundleIDs[player] else { return }
        Task.detached(priority: .utility) { [weak self] in
            let detailed = Self.automationPermission(for: bundleID, ask: false) == noErr ? Self.read(player) : nil
            await MainActor.run {
                guard let track = detailed ?? fallback else { return }
                self?.publish(player: player, track: track, publish: publish)
            }
        }
    }

    private nonisolated static func track(from info: [AnyHashable: Any]) -> Track {
        var track = Track(state: info["Player State"] as? String ?? "", name: info["Name"] as? String ?? "")
        track.artist = info["Artist"] as? String ?? ""
        track.album = info["Album"] as? String ?? ""
        // Music sends "Total Time", Spotify "Duration" (both ms); Spotify also sends its position (s).
        if let ms = (info["Total Time"] ?? info["Duration"]) as? Double { track.duration = ms / 1000 }
        track.position = info["Playback Position"] as? Double
        return track
    }

    private nonisolated static func read(_ player: String) -> Track? {
        // A new file per read so views notice the change; the previous one is removed.
        let old = (try? FileManager.default.contentsOfDirectory(at: artFolder, includingPropertiesForKeys: nil)) ?? []
        old.filter { $0.lastPathComponent.hasPrefix(player) }.forEach { try? FileManager.default.removeItem(at: $0) }
        let artPath = artFolder.appending(path: "\(player)-\(UUID().uuidString)").path
        let script = player == "Spotify" ? """
            tell application "Spotify"
              if player state is stopped then return ""
              set t to current track
              return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & ¬
                (album of t) & linefeed & (player position as text) & linefeed & ((duration of t) / 1000 as text) & ¬
                linefeed & (artwork url of t)
            end tell
            """ : """
            on run argv
              tell application "\(player)"
                if player state is stopped then return ""
                set t to current track
                set info to (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & ¬
                  (album of t) & linefeed & (player position as text) & linefeed & (duration of t as text)
                set art to missing value
                try
                  set art to raw data of artwork 1 of t
                end try
              end tell
              set f to ""
              if art is not missing value then
                set f to item 1 of argv
                set fh to open for access (POSIX file f) with write permission
                write art to fh
                close access fh
              end if
              return info & linefeed & f
            end run
            """
        guard let output = run(script, arguments: [artPath]) else { return nil }
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 6 else { return nil }
        func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
        return Track(state: lines[0].capitalized, name: lines[1], artist: lines[2], album: lines[3],
                     position: number(lines[4]), duration: number(lines[5]),
                     artwork: lines.count > 6 && !lines[6].isEmpty ? lines[6] : nil)
    }

    /// Runs a script off the main thread.
    @discardableResult
    private nonisolated static func runDetached(_ script: String, arguments: [String] = []) async -> String? {
        await Task.detached(priority: .userInitiated) { run(script, arguments: arguments) }.value
    }

    private nonisolated static func run(_ script: String, arguments: [String] = []) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func automationPermission(for bundleID: String, ask: Bool) -> OSStatus {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    // MARK: Publishing

    private func publish(player: String, track: Track, publish: Publish) {
        guard track.state != "Stopped", !track.name.isEmpty else {
            publish(ActivityEvent(source: id, kind: .ended, sessionID: player, title: "Stopped"))
            return
        }
        let playing = track.state == "Playing"
        if player != "TV" { UserDefaults.standard.set(player, forKey: "lastMusicPlayer") }
        var metadata = ["player": player, "state": playing ? "playing" : "paused"]
        if let position = track.position {
            metadata["position"] = String(position)
            metadata["positionAt"] = String(Date.now.timeIntervalSince1970)
        }
        metadata["duration"] = track.duration.map { String($0) }
        metadata["artwork"] = track.artwork
        publish(ActivityEvent(
            source: id,
            kind: .update,
            sessionID: player,
            title: track.name,
            detail: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "),
            symbol: "music.note",
            expiresAfter: playing ? 2 * 3600 : 15 * 60,
            priority: .low, // music is the background; agents and timers come first
            actions: [
                .init(id: "previous:\(player)", symbol: "backward.fill", label: "Previous"),
                .init(id: "playpause:\(player)", symbol: playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play"),
                .init(id: "next:\(player)", symbol: "forward.fill", label: "Next"),
            ],
            metadata: metadata))
    }
}
