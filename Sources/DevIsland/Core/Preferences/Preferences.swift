import Foundation
import Observation

/// Typed, observable settings. Each change is saved to UserDefaults immediately.
@MainActor
@Observable
final class Preferences {
    enum HoverDelay: String, CaseIterable, Identifiable {
        case instant, short, long
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var seconds: Double {
            switch self {
            case .instant: 0
            case .short: 0.15
            case .long: 0.4
            }
        }
    }

    enum Retention: String, CaseIterable, Identifiable {
        case week, month, quarter, forever
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .forever: nil
            }
        }
        var title: String {
            switch self {
            case .week: "1 week"
            case .month: "1 month"
            case .quarter: "3 months"
            case .forever: "Forever"
            }
        }
    }

    var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover) } }
    var hoverDelay: HoverDelay { didSet { defaults.set(hoverDelay.rawValue, forKey: Key.hoverDelay) } }
    var autoPresentAlerts: Bool { didSet { defaults.set(autoPresentAlerts, forKey: Key.autoPresentAlerts) } }
    var hapticFeedback: Bool { didSet { defaults.set(hapticFeedback, forKey: Key.hapticFeedback) } }
    var animations: Bool { didSet { defaults.set(animations, forKey: Key.animations) } }
    var glassEffects: Bool { didSet { defaults.set(glassEffects, forKey: Key.glassEffects) } }
    var showAgentMessages: Bool { didSet { defaults.set(showAgentMessages, forKey: Key.showAgentMessages) } }
    var retention: Retention { didSet { defaults.set(retention.rawValue, forKey: Key.retention) } }
    var shortcut: HotKeyShortcut { didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut) } }
    /// Highlight color for the island (hex, e.g. "#2BC7B8").
    var highlightHex: String { didSet { defaults.set(highlightHex, forKey: Key.highlight) } }
    /// Hide the island while an app is full screen (it comes back when you point at the top, and for alerts).
    var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen) } }
    /// Notch, floating island, or automatic (`IslandStyle` raw value).
    var islandStyle: String { didSet { defaults.set(islandStyle, forKey: Key.islandStyle) } }
    /// Corner roundness of the open island, 16...34.
    var islandCorner: Double { didSet { defaults.set(islandCorner, forKey: Key.islandCorner) } }
    /// Volume, brightness and Caps Lock shown at the notch.
    var showHUDs: Bool { didSet { defaults.set(showHUDs, forKey: Key.showHUDs) } }
    /// DevIsland handles the volume/brightness keys so macOS's own popup doesn't show (needs Accessibility).
    var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD) } }
    /// ⌃⌥V opens the clipboard in the island.
    var clipboardShortcut: Bool { didSet { defaults.set(clipboardShortcut, forKey: Key.clipboardShortcut) } }
    /// Which AI answers "Ask" in the island (`AskProvider` raw value).
    var askProvider: String { didSet { defaults.set(askProvider, forKey: Key.askProvider) } }
    /// The note on the island's Notes page.
    var note: String { didSet { defaults.set(note, forKey: Key.note) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? true
        hoverDelay = defaults.string(forKey: Key.hoverDelay).flatMap { HoverDelay(rawValue: $0) } ?? .short
        autoPresentAlerts = defaults.object(forKey: Key.autoPresentAlerts) as? Bool ?? true
        hapticFeedback = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? true
        animations = defaults.object(forKey: Key.animations) as? Bool ?? true
        glassEffects = defaults.object(forKey: Key.glassEffects) as? Bool ?? true
        showAgentMessages = defaults.object(forKey: Key.showAgentMessages) as? Bool ?? true
        retention = defaults.string(forKey: Key.retention).flatMap { Retention(rawValue: $0) } ?? .quarter
        shortcut = defaults.string(forKey: Key.shortcut).flatMap { HotKeyShortcut(rawValue: $0) } ?? .controlOptionI
        highlightHex = defaults.string(forKey: Key.highlight) ?? "#2BC7B8"
        islandCorner = defaults.object(forKey: Key.islandCorner) as? Double ?? 26
        islandStyle = defaults.string(forKey: Key.islandStyle) ?? "automatic"
        hideInFullScreen = defaults.object(forKey: Key.hideInFullScreen) as? Bool ?? true
        showHUDs = defaults.object(forKey: Key.showHUDs) as? Bool ?? true
        replaceSystemHUD = defaults.bool(forKey: Key.replaceSystemHUD)
        clipboardShortcut = defaults.object(forKey: Key.clipboardShortcut) as? Bool ?? true
        note = defaults.string(forKey: Key.note) ?? ""
        askProvider = defaults.string(forKey: Key.askProvider) ?? "claude"
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
    }

    private enum Key {
        static let expandOnHover = "expandOnHover"
        static let hoverDelay = "hoverDelay"
        static let autoPresentAlerts = "autoPresentAlerts"
        static let hapticFeedback = "hapticFeedback"
        static let animations = "animations"
        static let glassEffects = "glassEffects"
        static let showAgentMessages = "showAgentMessages"
        static let retention = "historyRetention"
        static let shortcut = "toggleShortcut"
        static let onboarding = "hasCompletedOnboarding"
        static let highlight = "highlightColor"
        static let islandCorner = "islandCorner"
        static let islandStyle = "islandStyle"
        static let hideInFullScreen = "hideInFullScreen"
        static let showHUDs = "showHUDs"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let clipboardShortcut = "clipboardShortcut"
        static let note = "widgetNote"
        static let askProvider = "askProvider"
    }
}
