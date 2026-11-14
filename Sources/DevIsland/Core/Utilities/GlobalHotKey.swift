import Carbon.HIToolbox

/// Shortcut choices for toggling the island from anywhere.
enum HotKeyShortcut: String, CaseIterable, Identifiable {
    case off, controlOptionI, controlOptionSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .controlOptionI: "⌃⌥I"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .controlOptionI: UInt32(kVK_ANSI_I)
        case .controlOptionSpace: UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 { UInt32(controlKey | optionKey) }

    /// The fixed clipboard shortcut, ⌃⌥V.
    static let clipboard = (keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey))
}

/// Registers one system-wide shortcut through Carbon (no Accessibility permission needed).
/// Several can exist; each reacts only to its own key.
@MainActor
final class GlobalHotKey {
    private static var nextID: UInt32 = 1
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    func register(_ shortcut: HotKeyShortcut, action: @escaping () -> Void) {
        guard let keyCode = shortcut.keyCode else { unregister(); return }
        register(keyCode: keyCode, modifiers: shortcut.modifiers, action: action)
    }

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            let mine = MainActor.assumeIsolated { pressed.id == hotKey.id }
            guard mine else { return OSStatus(eventNotHandledErr) } // let the other shortcut's handler see it
            MainActor.assumeIsolated { hotKey.action?() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4456_4953), id: id) // "DVIS"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
    }
}
