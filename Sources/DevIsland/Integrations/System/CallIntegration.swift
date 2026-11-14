import AppKit
import CoreAudio

/// Microphone use, the Apple way: a green "On a call" for call apps, an orange "Microphone on"
/// for anything else (Wispr Flow, Voice Memos…). macOS tells us which apps are recording, never what
/// they record. Siri's "Hey Siri" listening and system services are ignored.
final class CallIntegration: Integration {
    let id = "call"
    let name = "Calls & Microphone"
    let summary = "A green call timer for call apps, an orange mic for anything else that's recording."
    let symbol = "phone.fill"

    /// Call apps and browsers (matched by bundle ID prefix, so helpers count too).
    private static let callApps: [(prefix: String, name: String)] = [
        ("com.apple.mobilephone", "Phone"), ("com.apple.TelephonyUtilities", "Phone"), ("com.apple.avconference", "Phone"),
        ("us.zoom", "Zoom"), ("com.microsoft.teams", "Teams"), ("com.apple.FaceTime", "FaceTime"),
("com.tinyspeck.slackmacgap", "Slack"), ("com.hnc.Discord", "Discord"),
        ("com.cisco.webex", "Webex"), ("net.whatsapp", "WhatsApp"), ("ru.keepcoder.Telegram", "Telegram"),
        ("com.apple.Safari", "Safari"), ("com.apple.WebKit", "Safari"), ("com.google.Chrome", "Chrome"),
        ("company.thebrowser", "Arc"), ("com.microsoft.edgemac", "Edge"), ("org.mozilla.firefox", "Firefox"),
        ("com.brave.Browser", "Brave"),
    ]
    private static let browsers: Set<String> = ["Safari", "Chrome", "Arc", "Edge", "Firefox", "Brave"]
    /// macOS services that carry phone and FaceTime audio (they have no bundle ID).
    private static let callServices = ["avconferenced", "callservicesd", "telephonyutilitiesd"]
    /// Words in the bundle ID or name of Apple's calling services.
    private static let appleCallWords = ["phone", "facetime", "call", "telephony", "conference", "continuity"]
    /// Always-listening system features that aren't you using the mic.
    private static let ignored = ["corespeech", "siri", "assistant", "devisland"]

    private struct User: Equatable {
        let isCall: Bool
        let name: String
        let pid: pid_t?
        var bundleID = ""
    }

    /// Reports which app is on the mic (bundle ID only, never audio), for Diagnostics.
    var onMicApp: (String) -> Void = { _ in }

    private var task: Task<Void, Never>?
    private var current: User?
    private var start: Date?
    private var offSeconds = 0
    private var onSeconds = 0
    private var publish: Publish?
    /// Who you're talking to, from the call window's title (needs Accessibility); nil when unknown.
    private var caller: String?
    /// The call app's own controls, when its call window exposes them (needs Accessibility).
    private var controls = CallControls()
    /// The mic DevIsland muted, so it's always unmuted again (call ended, turned off, app quit).
    private var mutedMic: MicMute?

    /// Apps whose own "leave call" shortcut we can press. Zoom asks you to confirm.
    private static let hangUpKeys: [String: CGKeyCode] = ["Teams": 4, "Slack": 4, "Zoom": 13] // ⌘⇧H, ⌘⇧H, ⌘W

    func start(publish: @escaping Publish) {
        self.publish = publish
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.check(publish: publish)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        current = nil
        start = nil
        restoreMic()
    }

    /// "open:<pid>", "mute", "unmute", "hangup".
    func perform(action: String) {
        switch action {
        case "mute", "unmute":
            if controls.hasMute, let pid = current?.pid {
                // Press the app's own mute button, so the app and the notch always agree.
                CallControls.press(.mute, pid: pid)
                controls.muted = action == "mute"
            } else if action == "mute" {
                mutedMic = MicMute.muteDefaultInput()
            } else {
                restoreMic()
            }
            republish()
        case "hangup":
            if controls.hasLeave, let pid = current?.pid { CallControls.press(.leave, pid: pid) } else { hangUp() }
        default:
            guard action.hasPrefix("open:"), let pid = pid_t(action.dropFirst(5)) else { return }
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// Unmutes the mic if DevIsland muted it.
    func restoreMic() {
        mutedMic?.restore()
        mutedMic = nil
    }

    /// Brings the call app forward and presses its own "leave" shortcut (needs Accessibility).
    private func hangUp() {
        guard let user = current, let key = Self.hangUpKeys[user.name], let pid = user.pid,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        app.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(250)) // let the app come to the front first
            let flags: CGEventFlags = key == 13 ? .maskCommand : [.maskCommand, .maskShift]
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func republish() {
        guard let publish, let user = current, let begin = start else { return }
        send(user, kind: .update, begin: begin, publish: publish)
    }

    private func send(_ user: User, kind: ActivityEvent.Kind, begin: Date, publish: Publish) {
        let browser = Self.browsers.contains(user.name)
        let muted = mutedMic != nil || controls.muted
        var actions: [ActivityEvent.Action] = []
        if user.isCall {
            actions.append(muted ? .init(id: "unmute", symbol: "mic.slash.fill", label: "Unmute")
                                 : .init(id: "mute", symbol: "mic.fill", label: "Mute"))
            if controls.hasLeave || Self.hangUpKeys[user.name] != nil {
                actions.append(.init(id: "hangup", symbol: "phone.down.fill", label: "Leave call"))
            }
        }
        if let pid = user.pid {
            actions.append(.init(id: "open:\(pid)", symbol: "arrow.up.forward.app", label: "Show \(user.name)"))
        }
        publish(ActivityEvent(
            source: id, kind: kind, sessionID: "call",
            title: user.isCall ? (muted ? "On a call · muted" : "On a call") : "Microphone on",
            detail: [caller, browser ? "In \(user.name)" : user.name].compactMap { $0 }.joined(separator: " · "),
            symbol: user.isCall ? "phone.fill" : "mic.fill", startDate: begin, expiresAfter: 12 * 3600,
            actions: actions,
            metadata: ["kind": user.isCall ? "call" : "mic", "muted": muted ? "true" : "false"]))
    }

    private func check(publish: Publish) {
        let user = Self.micUser()
        onSeconds = user == nil ? 0 : onSeconds + 1
        offSeconds = user == nil ? offSeconds + 1 : 0

        if let user {
            // Checked every 2 s: seen twice in a row for a call (skips blips), once for the mic.
            guard onSeconds >= (user.isCall ? 2 : 1) else { return }
            // Every few seconds, refresh the caller's name from the call window.
            if user == current {
                if user.isCall, let pid = user.pid {
                    let name = Self.callerName(pid: pid, app: user.name)
                    let found = CallControls.find(pid: pid)
                    if name != caller || found != controls { caller = name; controls = found; republish() }
                }
                return
            }
            caller = user.isCall ? user.pid.flatMap { Self.callerName(pid: $0, app: user.name) } : nil
            controls = user.isCall ? user.pid.map { CallControls.find(pid: $0) } ?? CallControls() : CallControls()
            let begin = start ?? Date.now.addingTimeInterval(-Double(onSeconds) * 2)
            let kind: ActivityEvent.Kind = current == nil ? .started : .update
            current = user
            start = begin
            onMicApp("\(user.isCall ? "Call" : "Microphone"): \(user.bundleID.isEmpty ? user.name : user.bundleID)")
            send(user, kind: kind, begin: begin, publish: publish)
        } else if let begin = start, offSeconds >= 1 {
            let wasCall = current?.isCall ?? false
            current = nil
            start = nil
            caller = nil
            controls = CallControls()
            restoreMic() // never leave the mic muted after a call
            publish(ActivityEvent(source: id, kind: .ended, sessionID: "call", title: wasCall ? "Call ended" : "Microphone off",
                                  duration: Date.now.timeIntervalSince(begin)))
        }
    }

    /// Who's recording right now: a call app wins over anything else.
    private static func micUser() -> User? {
        var found: [User] = []
        for process in objects(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID(kAudioObjectSystemObject)) {
            guard uint32(kAudioProcessPropertyIsRunningInput, of: process) != 0 else { continue }
            let pid = pid_t(uint32(kAudioProcessPropertyPID, of: process))
            guard let bundleID = string(kAudioProcessPropertyBundleID, of: process), !bundleID.isEmpty else {
                // A service without a bundle ID: a phone/FaceTime call, or something like historicalaudiod (ignored).
                if callServices.contains(processName(pid)) { found.append(User(isCall: true, name: "Phone", pid: nil)) }
                continue
            }
            let app = NSRunningApplication(processIdentifier: pid)
            let haystack = (bundleID + " " + (app?.localizedName ?? "")).lowercased()
            guard !ignored.contains(where: haystack.contains) else { continue }

            if let call = callApps.first(where: { bundleID.hasPrefix($0.prefix) }) {
                // Helpers (e.g. "Google Chrome Helper") point to their main app.
                let owner = NSWorkspace.shared.runningApplications.first {
                    $0.bundleIdentifier?.hasPrefix(call.prefix) == true && $0.activationPolicy == .regular
                }
                found.append(User(isCall: true, name: call.name, pid: (owner ?? app)?.processIdentifier, bundleID: bundleID))
            } else if bundleID.hasPrefix("com.apple."), appleCallWords.contains(where: haystack.contains) {
                // Apple's calling pieces (Phone, FaceTime, Continuity) under any of their names.
                found.append(User(isCall: true, name: haystack.contains("facetime") ? "FaceTime" : "Phone", pid: app?.processIdentifier,
                                  bundleID: bundleID))
            } else {
                found.append(User(isCall: false, name: app?.localizedName ?? "An app", pid: app?.processIdentifier, bundleID: bundleID))
            }
        }
        return found.first { $0.isCall } ?? found.first
    }

    /// Generic window titles that aren't a person or meeting name.
    private static let genericTitles: Set<String> = ["", "zoom", "zoom meeting", "zoom workplace", "whatsapp", "facetime", "phone",
                                                     "slack", "microsoft teams", "teams", "discord", "telegram", "webex", "meet"]
    /// App names browsers and call apps add to window titles.
    private static let titleSuffixes = ["microsoft teams", "google chrome", "safari", "arc", "microsoft edge", "firefox", "brave",
                                        "zoom", "slack", "whatsapp", "discord", "telegram", "webex"]

    /// The call window's title, cleaned up ("Jane Doe", "Design review"). Reads window titles only,
    /// through Accessibility; returns nil without permission or when there's no useful title.
    private static func callerName(pid: pid_t, app: String) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25) // never hang on a busy app
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) // wakes up lazy apps
        var focused: CFTypeRef?
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused)
        AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
        var candidates: [AXUIElement] = []
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() { candidates.append(focused as! AXUIElement) }
        candidates += (windows as? [AXUIElement]) ?? []

        for window in candidates {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            guard let raw = title as? String else { continue }
            // Apps like WhatsApp wrap names in invisible direction marks; remove them.
            let visible = String(raw.unicodeScalars.filter { !(0x200B...0x200F).contains($0.value) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) })
            // "Manvish - WhatsApp voice call" → "Manvish"; "Meeting with Jane | Microsoft Teams" → "Meeting with Jane".
            let parts = visible.components(separatedBy: CharacterSet(charactersIn: "|—–")).flatMap { $0.components(separatedBy: " - ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { part in !part.isEmpty && !titleSuffixes.contains { part.lowercased().contains($0) } }
            let cleaned = parts.joined(separator: " - ")
            if !genericTitles.contains(cleaned.lowercased()), cleaned.lowercased() != app.lowercased(), cleaned.count <= 60 {
                return cleaned
            }
        }
        return nil
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return String(decoding: buffer.prefix(Int(max(0, length))), as: UTF8.self)
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> [AudioObjectID] {
        var address = address(selector)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }

    private static func uint32(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32 {
        var address = address(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

/// Mutes the current microphone for every app, remembering how to undo it.
/// Uses the mic's mute switch, or its input level when it has no mute switch.
struct MicMute {
    private let device: AudioDeviceID
    private let previousVolume: Float32?

    static func muteDefaultInput() -> MicMute? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }

        if setMute(true, on: device) { return MicMute(device: device, previousVolume: nil) }
        var volumeAddress = inputAddress(kAudioDevicePropertyVolumeScalar)
        var volume = Float32(1)
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr else { return nil }
        var zero = Float32(0)
        guard AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, volumeSize, &zero) == noErr else { return nil }
        return MicMute(device: device, previousVolume: volume)
    }

    func restore() {
        if var volume = previousVolume {
            var address = Self.inputAddress(kAudioDevicePropertyVolumeScalar)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        } else {
            _ = Self.setMute(false, on: device)
        }
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func setMute(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = inputAddress(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// A call app's own Mute and Leave buttons, found through Accessibility in its call window,
/// so DevIsland presses the same buttons you would and reads whether you're muted.
struct CallControls: Equatable {
    enum Button { case mute, leave }

    var hasMute = false
    var hasLeave = false
    /// From the mute button's label ("Unmute" means you're muted).
    var muted = false

    private static let leaveWords = ["leave call", "end call", "hang up", "leave meeting", "end meeting", "leave"]

    static func find(pid: pid_t) -> CallControls {
        var controls = CallControls()
        for (label, _) in buttons(pid: pid) {
            if isMute(label) {
                controls.hasMute = true
                controls.muted = isMutedLabel(label)
            }
            if leaveWords.contains(where: label.contains) { controls.hasLeave = true }
        }
        return controls
    }

    static func press(_ button: Button, pid: pid_t) {
        guard let match = buttons(pid: pid).first(where: { label, _ in
            button == .mute ? isMute(label) : leaveWords.contains(where: label.contains)
        }) else { return }
        AXUIElementPerformAction(match.1, kAXPressAction as CFString)
    }

    private static func isMute(_ label: String) -> Bool {
        (label.contains("mute") || label.contains("microphone")) && !label.contains("notification") && !label.contains("speaker")
    }

    private static func isMutedLabel(_ label: String) -> Bool {
        label.contains("unmute") || label.contains("turn on microphone") || label.contains("microphone off")
    }

    /// Buttons (lowercased label, element) in the app's call windows only, never its other windows.
    private static func buttons(pid: pid_t) -> [(String, AXUIElement)] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        let windows = (value as? [AXUIElement]) ?? []
        let callWindows = windows.filter { window in
            let title = (text(window, kAXTitleAttribute) ?? "").lowercased()
            return ["call", "meeting", "meet", "facetime", "huddle", "zoom"].contains(where: title.contains)
        }
        var found: [(String, AXUIElement)] = []
        for window in callWindows { collect(window, depth: 0, into: &found) }
        return found
    }

    private static func collect(_ element: AXUIElement, depth: Int, into found: inout [(String, AXUIElement)]) {
        guard depth < 14, found.count < 60 else { return }
        if text(element, kAXRoleAttribute) == kAXButtonRole as String || text(element, kAXRoleAttribute) == kAXCheckBoxRole as String {
            let label = [text(element, kAXTitleAttribute), text(element, kAXDescriptionAttribute), text(element, kAXHelpAttribute)]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            if !label.isEmpty { found.append((label, element)) }
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] { collect(child, depth: depth + 1, into: &found) }
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }
}
