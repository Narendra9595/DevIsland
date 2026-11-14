import Foundation

/// Human-friendly formatting used across the app.
enum Format {
    /// "45s", "12m", "1h 5m"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total == 0 { return "0m" }
        if total < 60 { return "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// "4:05", "1:02:03"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "45m", "2h 10m"
    static func minutes(_ minutes: Int) -> String {
        duration(TimeInterval(minutes * 60))
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .memory))
    }

    /// "Today", "Yesterday", "Monday, Nov 10"
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// Version info from the app bundle (with a fallback when run via `swift run`).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
}
