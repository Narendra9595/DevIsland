import SwiftUI

/// Brand colors and shared metrics.
enum Theme {
    static let accent = Color(red: 0.16, green: 0.78, blue: 0.72)
    static let violet = Color(red: 0.47, green: 0.42, blue: 0.98)
    static let attention = Color(red: 1.0, green: 0.69, blue: 0.20)
    static let success = Color(red: 0.25, green: 0.80, blue: 0.48)
    static let danger = Color(red: 1.0, green: 0.37, blue: 0.35)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardStroke = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.05)

    /// Solid, quiet surfaces: white cards on light gray, or lifted charcoal on near-black.
    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.115) : .white
    }

    static func pageFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.075) : Color(white: 0.965)
    }

    enum Radius {
        static let card: CGFloat = 12
        static let tile: CGFloat = 8
    }
}

/// Name, icon and color for each event source. Used everywhere events are shown.
enum SourceStyle {
    static func name(_ source: String) -> String {
        switch source {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "timer": "Focus Timer"
        case "media": "Music"
        case "battery": "Battery"
        case "network": "Network"
        case "downloads": "Downloads"
        case "call": "Calls & Mic"
        case "clipboard": "Clipboard"
        case "test": "Test"
        default: source.capitalized
        }
    }

    static func symbol(_ source: String) -> String {
        switch source {
        case "claude": "sparkles"
        case "codex": "terminal"
        case "timer": "timer"
        case "media": "music.note"
        case "battery": "battery.75percent"
        case "network": "wifi"
        case "downloads": "arrow.down.circle.fill"
        case "call": "phone.fill"
        case "clipboard": "doc.on.clipboard"
        case "test": "wand.and.stars"
        default: "circle.dotted"
        }
    }

    static func tint(_ source: String) -> Color {
        switch source {
        case "claude": Color(red: 0.85, green: 0.47, blue: 0.34)
        case "codex": Color(red: 0.30, green: 0.75, blue: 0.56)
        case "timer": Theme.violet
        case "media": Color(red: 0.98, green: 0.36, blue: 0.53)
        case "battery": Theme.success
        case "network": Color(red: 0.25, green: 0.56, blue: 1.0)
        case "downloads": Color(red: 0.3, green: 0.7, blue: 1.0)
        case "call": Color(red: 0.2, green: 0.82, blue: 0.4)
        case "clipboard": Color(red: 0.30, green: 0.62, blue: 1.0)
        case "test": Theme.accent
        default: .gray
        }
    }
}

extension ActivityEvent {
    var displaySymbol: String { symbol ?? SourceStyle.symbol(source) }

    /// Source color, overridden by state: alerts stand out and finished work turns green.
    var tint: Color {
        switch kind {
        case .alert: ActivityStats.agentSources.contains(source) ? Theme.attention : Theme.danger
        case .completed: Theme.success
        default:
            if metadata["low"] == "true" { Theme.danger }
            else if metadata["kind"] == "mic" { CallGlyph.orange } // mic glows orange, calls green
            else { SourceStyle.tint(source) }
        }
    }
}

extension Color {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
