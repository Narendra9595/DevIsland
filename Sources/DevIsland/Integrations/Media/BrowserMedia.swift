import AppKit
import CoreAudio

/// Media playing in a browser tab (YouTube and friends), found without any extension:
/// macOS says which app is playing sound, the browser says which tab is a media site,
/// and media keys control it. Only media-site tabs are kept; other tabs are ignored.
enum BrowserMedia {
    struct Browser: Equatable {
        let name: String
        let bundleID: String
        let safari: Bool
        /// A video app (Prime Video, VLC…) rather than a browser: its window title is the title.
        var isApp = false
    }

    struct Tab: Equatable {
        let title: String
        let site: String
        let artwork: String?
    }

    /// Browsers (matched by bundle ID prefix, so their audio helpers count too).
    static let browsers: [(prefix: String, browser: Browser)] = [
        ("com.google.Chrome", Browser(name: "Chrome", bundleID: "com.google.Chrome", safari: false)),
        ("company.thebrowser", Browser(name: "Arc", bundleID: "company.thebrowser.Browser", safari: false)),
        ("com.brave.Browser", Browser(name: "Brave", bundleID: "com.brave.Browser", safari: false)),
        ("com.microsoft.edgemac", Browser(name: "Edge", bundleID: "com.microsoft.edgemac", safari: false)),
        ("com.apple.Safari", Browser(name: "Safari", bundleID: "com.apple.Safari", safari: true)),
        ("com.apple.WebKit", Browser(name: "Safari", bundleID: "com.apple.Safari", safari: true)),
        // Video apps without their own scripting: shown with their window title and controlled with media keys.
        ("com.amazon.aiv.AIVApp", Browser(name: "Prime Video", bundleID: "com.amazon.aiv.AIVApp", safari: false, isApp: true)),
        ("org.videolan.vlc", Browser(name: "VLC", bundleID: "org.videolan.vlc", safari: false, isApp: true)),
        ("com.colliderli.iina", Browser(name: "IINA", bundleID: "com.colliderli.iina", safari: false, isApp: true)),
        ("com.apple.QuickTimePlayerX", Browser(name: "QuickTime", bundleID: "com.apple.QuickTimePlayerX", safari: false, isApp: true)),
        ("com.firecore.infuse", Browser(name: "Infuse", bundleID: "com.firecore.infuse", safari: false, isApp: true)),
    ]

    static func browser(named name: String) -> Browser? {
        browsers.first { $0.browser.name == name }?.browser
    }

    /// The browser that's playing sound right now, if any.
    static func playingBrowser() -> Browser? {
        for process in AudioProcesses.all() where process.playing {
            if let match = browsers.first(where: { process.bundleID.hasPrefix($0.prefix) }) { return match.browser }
        }
        return nil
    }

    /// Audio process objects that belong to a browser (to be told the moment their sound starts or stops).
    static func browserProcesses() -> [AudioObjectID] {
        AudioProcesses.all().filter { process in browsers.contains { process.bundleID.hasPrefix($0.prefix) } }.map(\.id)
    }

    /// The media tab: the front tab if it's a media site, otherwise the first media-site tab.
    nonisolated static func mediaTab(in browser: Browser) -> Tab? {
        if browser.isApp { return appTitle(browser) }
        let tabsVar = browser.safari ? "current tab" : "active tab"
        let titleVar = browser.safari ? "name" : "title"
        let script = """
            on run
              set sep to character id 9
              set out to ""
              tell application id "\(browser.bundleID)"
                try
                  set t to \(tabsVar) of front window
                  set out to "A" & sep & (URL of t) & sep & (\(titleVar) of t) & linefeed
                end try
                repeat with w in windows
                  repeat with t in tabs of w
                    set out to out & "T" & sep & (URL of t) & sep & (\(titleVar) of t) & linefeed
                  end repeat
                end repeat
              end tell
              return out
            end run
            """
        guard let output = run(script, arguments: []) else { return nil }
        let rows = output.components(separatedBy: "\n").map { $0.components(separatedBy: "\t") }.filter { $0.count >= 3 }
        let candidates = rows.filter { $0[0] == "A" } + rows.filter { $0[0] == "T" }
        for row in candidates {
            guard let url = URL(string: row[1]), let site = site(of: url) else { continue }
            return Tab(title: clean(row[2...].joined(separator: " ")), site: site, artwork: thumbnail(for: url))
        }
        return nil
    }

    /// Presses a media key (play/pause, next, previous). The browser passes it to the playing tab.
    static func pressMediaKey(_ action: String) {
        let key: Int = action == "next" ? 17 : action == "previous" ? 18 : 16 // NX_KEYTYPE_NEXT / PREVIOUS / PLAY
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// A video app's front window title (Accessibility), or just the app's name.
    private static func appTitle(_ app: Browser) -> Tab {
        var title = app.name
        if AXIsProcessTrusted(),
           let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.processIdentifier {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &value)
                if let text = (value as? String)?.trimmingCharacters(in: .whitespaces),
                   !text.isEmpty, text.lowercased() != app.name.lowercased(), text.count <= 80 {
                    title = clean(text)
                }
            }
        }
        return Tab(title: title, site: app.name, artwork: nil)
    }

    // MARK: Helpers

    private static func site(of url: URL) -> String? {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path()
        if host.hasSuffix("music.youtube.com") { return "YouTube Music" }
        if host.hasSuffix("youtube.com"), path.hasPrefix("/watch") || path.hasPrefix("/shorts") || path.hasPrefix("/live") { return "YouTube" }
        if host == "youtu.be" { return "YouTube" }
        if host.hasSuffix("soundcloud.com") { return "SoundCloud" }
        if host == "open.spotify.com" { return "Spotify" }
        if host.hasSuffix("twitch.tv") { return "Twitch" }
        if host.hasSuffix("vimeo.com") { return "Vimeo" }
        // Streaming services (video pages only, so browsing their catalog doesn't count).
        if host.hasSuffix("netflix.com"), path.hasPrefix("/watch") { return "Netflix" }
        if host.hasSuffix("primevideo.com") || (host.contains("amazon.") && path.contains("/gp/video")) { return "Prime Video" }
        if host.hasSuffix("hotstar.com") || host.hasSuffix("jiohotstar.com") { return "JioHotstar" }
        if host.hasSuffix("disneyplus.com"), path.contains("/play") || path.contains("/video") { return "Disney+" }
        if host.hasSuffix("hulu.com"), path.hasPrefix("/watch") { return "Hulu" }
        if host.hasSuffix("max.com"), path.contains("/video") { return "Max" }
        if host == "tv.apple.com" { return "Apple TV" }
        if host.hasSuffix("sonyliv.com") { return "SonyLIV" }
        if host.hasSuffix("zee5.com") { return "ZEE5" }
        return nil
    }

    /// YouTube's own thumbnail for the video.
    private static func thumbnail(for url: URL) -> String? {
        let host = url.host()?.lowercased() ?? ""
        var id: String?
        if host == "youtu.be" {
            id = url.pathComponents.dropFirst().first
        } else if host.hasSuffix("youtube.com") {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            if id == nil, url.path().hasPrefix("/shorts/") { id = url.pathComponents.dropFirst(2).first }
        }
        return id.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }
    }

    /// "(3) Song name - YouTube" → "Song name".
    private static func clean(_ title: String) -> String {
        var result = title.replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
        for suffix in [" - YouTube Music", " - YouTube", " | Spotify", " | Free Listening on SoundCloud", " - Twitch", " on Vimeo",
                       " | Netflix", " - Netflix", " | Prime Video", " - Prime Video", " - JioHotstar", " | Disney+", " | Hulu",
                       " | Max", " - Apple TV+", " - SonyLIV", " - ZEE5"] where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
        }
        if result.hasPrefix("Watch ") { result = String(result.dropFirst(6)) }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func run(_ script: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Which apps are playing or recording audio right now (macOS reports apps, never the audio itself).
enum AudioProcesses {
    struct Process {
        let id: AudioObjectID
        let bundleID: String
        let playing: Bool
    }

    static let runningOutput = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)

    /// Every app with an audio connection, and whether it's playing right now.
    static func all() -> [Process] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &list) == noErr else { return [] }
        return list.compactMap { process in
            var running = runningOutput
            var value = UInt32(0)
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(process, &running, 0, nil, &valueSize, &value)
            var bundle = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &bundle, 0, nil, &nameSize, &name) == noErr,
                  let bundleID = name?.takeRetainedValue() as String?, !bundleID.isEmpty else { return nil }
            return Process(id: process, bundleID: bundleID, playing: value != 0)
        }
    }
}
