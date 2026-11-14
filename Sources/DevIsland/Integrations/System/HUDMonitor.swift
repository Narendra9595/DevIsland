import AppKit
import AudioToolbox
import SwiftUI

/// A short-lived notch HUD: volume, brightness or a new audio output.
struct HUD: Equatable {
    enum Kind { case volume, brightness, output }
    let kind: Kind
    var level: Double?
    var symbol: String
    var text: String?
}

/// Shows a HUD when the volume, audio output or brightness changes. Nothing runs on a timer:
/// macOS tells us about volume and output changes, and brightness is read only when a brightness key is pressed.
@MainActor
@Observable
final class HUDMonitor {
    private(set) var hud: HUD?

    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var isEnabled: () -> Bool = { false }
    @ObservationIgnored private var device = AudioDeviceID(0)
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var keyMonitor: Any?

    func start(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        // A new default output (AirPods connected, speakers switched).
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged(announce: true) }
        }
        outputChanged(announce: false)
        // Brightness keys: read brightness only when one is pressed (when DevIsland isn't handling the keys itself).
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let code = (event.data1 & 0xFFFF_0000) >> 16
            let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA
            guard isDown, code == 2 || code == 3 else { return } // brightness up / down
            MainActor.assumeIsolated { self?.brightnessKeyPressed() }
        }
    }

    /// Re-reads brightness just after a key press (the system fade has its target by then).
    func brightnessKeyPressed() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.showCurrent(.brightness)
        }
    }

    /// Moves the volume and mute listeners to the new output, and announces it.
    private func outputChanged(announce: Bool) {
        var volume = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, output: true)
        var mute = Self.address(kAudioDevicePropertyMute, output: true)
        if let deviceListener, device != 0 {
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, deviceListener)
        }
        device = Self.defaultOutput()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.showCurrent(.volume) }
        }
        deviceListener = listener
        if AudioObjectHasProperty(device, &volume) { AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener) }
        if AudioObjectHasProperty(device, &mute) { AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener) }

        guard announce, device != 0 else { return }
        let name = Self.deviceName(device) ?? "Speakers"
        let lower = name.lowercased()
        show(HUD(kind: .output, symbol: lower.contains("airpods") ? "airpods" : lower.contains("headphone") ? "headphones" : "hifispeaker.fill",
                 text: name))
    }

    func show(_ hud: HUD) {
        guard isEnabled() else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { self.hud = hud }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.35)) { self?.hud = nil }
        }
    }

    /// Shows the current volume or brightness.
    func showCurrent(_ kind: HUD.Kind) {
        switch kind {
        case .brightness:
            if let level = Brightness.read() {
                show(HUD(kind: .brightness, level: Double(level), symbol: level < 0.5 ? "sun.min.fill" : "sun.max.fill"))
            }
        default:
            let device = Self.defaultOutput()
            let volume = Self.volume(device) ?? 0
            let muted = Self.muted(device) || volume == 0
            show(HUD(kind: .volume, level: muted ? 0 : Double(volume),
                     symbol: muted ? "speaker.slash.fill" : volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        }
    }

    // MARK: Reading values

    private static func address(_ selector: AudioObjectPropertySelector, output: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: output ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutput() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static func volume(_ device: AudioDeviceID) -> Float? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, output: true)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    static func muted(_ device: AudioDeviceID) -> Bool {
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyMute, output: true)
        guard AudioObjectHasProperty(device, &address) else { return false }
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    /// False for outputs without a software volume (some HDMI and USB devices); macOS handles those.
    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, output: true)
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func setVolume(_ value: Float, on device: AudioDeviceID) {
        var volume = Float32(min(1, max(0, value)))
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, output: true)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        if volume > 0, muted(device) { setMuted(false, on: device) }
    }

    static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
        var value = UInt32(muted ? 1 : 0)
        var address = address(kAudioDevicePropertyMute, output: true)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func deviceName(_ device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// Built-in display brightness. macOS has no public API for it, so this uses the system's
/// DisplayServices library when present and simply returns nil otherwise.
enum Brightness {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32

    nonisolated(unsafe) private static let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getter: Getter? = {
        guard let library, let symbol = dlsym(library, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Getter.self)
    }()

    /// macOS's own brightness fade. It moves brightness *by* an amount (+/-), not *to* a level.
    private static let smoothStep: Setter? = {
        guard let library, let symbol = dlsym(library, "DisplayServicesSetBrightnessSmooth") else { return nil }
        return unsafeBitCast(symbol, to: Setter.self)
    }()

    /// Changes brightness by `delta` with the system's own fade; false when that isn't available.
    static func step(by delta: Float) -> Bool {
        guard let smoothStep, let display = builtInDisplay else { return false }
        return smoothStep(display, delta) == 0
    }

    private static let setter: Setter? = {
        guard let library, let symbol = dlsym(library, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Setter.self)
    }()

    /// False when this Mac can't set brightness this way (then macOS keeps handling the keys).
    static var canSet: Bool { setter != nil && builtInDisplay != nil && read() != nil }

    static func set(_ value: Float) {
        guard let setter, let display = builtInDisplay else { return }
        _ = setter(display, min(1, max(0, value)))
    }

    private static let builtInDisplay: CGDirectDisplayID? = {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count = UInt32(0)
        CGGetOnlineDisplayList(8, &displays, &count)
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }()

    static func read() -> Float? {
        guard let getter, let display = builtInDisplay else { return nil }
        var value = Float(0)
        return getter(display, &value) == 0 ? value : nil
    }
}
