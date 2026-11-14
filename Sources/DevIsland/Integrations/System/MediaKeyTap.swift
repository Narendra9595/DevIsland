import AppKit
import AudioToolbox

/// Takes over the volume, mute and brightness keys so macOS's own popup doesn't appear and only
/// the notch HUD shows. Needs Accessibility permission; keys DevIsland can't handle are passed on to macOS.
@MainActor
final class MediaKeyTap {
    private let hud: HUDMonitor
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Where brightness is heading, and the fade getting it there (so it never jumps and flickers).
    private var brightnessTarget: Float?
    private var fade: Task<Void, Never>?

    // Key types from macOS's system-defined media key events.
    private enum Key: Int { case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }

    init(hud: HUDMonitor) {
        self.hud = hud
    }

    var isRunning: Bool { tap != nil }

    /// Starts if Accessibility is allowed; returns false otherwise.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
            // Pull plain values out of the event; the tap runs on the main run loop.
            let ns = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput ? nil : NSEvent(cgEvent: event)
            let info = ns.map { (subtype: Int($0.subtype.rawValue), data1: $0.data1, fine: $0.modifierFlags.contains([.option, .shift])) }
            let disabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
            let consumed = MainActor.assumeIsolated { owner.handle(disabled: disabled, subtype: info?.subtype, data1: info?.data1, fine: info?.fine ?? false) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Returns true when DevIsland handled the key (so macOS doesn't see it and shows no popup).
    private func handle(disabled: Bool, subtype: Int?, data1: Int?, fine: Bool) -> Bool {
        // macOS switches a slow tap off; switch it back on.
        if disabled {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard subtype == 8, let data1 else { return false }
        let isDown = ((data1 & 0xFF00) >> 8) == 0xA
        guard let key = Key(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return false }
        // Anything DevIsland can't change goes back to macOS untouched.
        if (key == .brightnessUp || key == .brightnessDown) && !Brightness.canSet { return false }
        if [.volumeUp, .volumeDown, .mute].contains(key) && !HUDMonitor.canSetVolume(HUDMonitor.defaultOutput()) { return false }
        if isDown { press(key, fine: fine) }
        return true
    }

    /// Fades to the new brightness over ~0.2 s at 120 steps a second, easing out like macOS.
    private func fadeBrightness(to target: Float) {
        fade?.cancel()
        let start = Brightness.read() ?? target
        fade = Task { [weak self] in
            let frames = 24
            for frame in 1...frames {
                guard !Task.isCancelled else { return }
                let t = Float(frame) / Float(frames)
                let eased = 1 - (1 - t) * (1 - t) * (1 - t)
                Brightness.set(start + (target - start) * eased)
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled else { return }
            self?.brightnessTarget = nil
        }
    }

    /// One step is 1/16, like macOS; ⌥⇧ gives quarter steps.
    private func press(_ key: Key, fine: Bool) {
        let step: Float = fine ? 1 / 64 : 1 / 16
        let device = HUDMonitor.defaultOutput()
        switch key {
        case .volumeUp, .volumeDown:
            let current = HUDMonitor.volume(device) ?? 0
            let next = ((current + (key == .volumeUp ? step : -step)) / step).rounded() * step
            HUDMonitor.setVolume(next, on: device)
            hud.showCurrent(.volume) // shows even at 0% / 100%, where the volume doesn't change
        case .mute:
            HUDMonitor.setMuted(!HUDMonitor.muted(device), on: device)
            hud.showCurrent(.volume)
        case .brightnessUp, .brightnessDown:
            // Quick presses build on the level we're heading to, not the half-faded one.
            let base = brightnessTarget ?? Brightness.read() ?? 0.5
            let target = min(1, max(0, ((base + (key == .brightnessUp ? step : -step)) / step).rounded() * step))
            brightnessTarget = target
            // Prefer macOS's own fade (identical to the normal keys); otherwise fade it ourselves.
            if Brightness.step(by: target - (Brightness.read() ?? base)) {
                brightnessTarget = nil
            } else {
                fadeBrightness(to: target)
            }
            hud.show(HUD(kind: .brightness, level: Double(target), symbol: target < 0.5 ? "sun.min.fill" : "sun.max.fill"))
        }
    }
}
