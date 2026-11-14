import SwiftUI

/// A pixel-style mascot for Claude, drawn on a 16 × 10 grid and centered in its frame.
/// Fill it with `FillStyle(eoFill: true)` so the eyes stay see-through.
struct ClaudeMascot: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width / 16, rect.height / 10)
        let origin = CGPoint(x: rect.midX - unit * 8, y: rect.midY - unit * 5)
        func cells(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit)
        }
        var path = Path()
        path.addRect(cells(2, 0, 12, 4))   // head
        path.addRect(cells(0, 4, 16, 2))   // arms
        path.addRect(cells(2, 6, 12, 2))   // body
        for leg: CGFloat in [3, 5, 10, 12] { path.addRect(cells(leg, 8, 1, 2)) }
        path.addRect(cells(4, 2, 1, 2))    // eyes (holes with even-odd fill)
        path.addRect(cells(11, 2, 1, 2))
        return path
    }
}

/// The Claude mark: the pixel mascot in Claude's terracotta.
struct ClaudeMark: View {
    var size: CGFloat = 28
    var color: Color = SourceStyle.tint("claude")

    var body: some View {
        ClaudeMascot()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

/// The agent's logo: the Claude mark for Claude, the installed app's icon for others
/// (e.g. Codex), otherwise our colored badge.
struct AgentLogo: View {
    let source: String
    var size: CGFloat = 28
    /// Badge style (mascot on a terracotta square) instead of the plain mascot.
    var badge = false

    private static let bundleIDs = ["codex": "com.openai.codex"]

    var body: some View {
        if source == "claude" {
            if badge { ClaudeBadge(size: size) } else { ClaudeMark(size: size) }
        } else if let bundleID = Self.bundleIDs[source], let image = AppIconCache.icon(bundleID: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.15, height: size * 1.15)
        } else {
            IconBadge(symbol: SourceStyle.symbol(source), tint: SourceStyle.tint(source), size: size)
        }
    }
}

/// A plan-limit ring: how much is left, with the agent's logo in the middle.
struct UsageRing: View {
    let source: String
    let title: String
    let window: UsageWindow?
    var size: CGFloat = 92
    var dark = false

    var body: some View {
        let tint = color
        VStack(spacing: 8) {
            ZStack {
                RingProgress(progress: window?.leftFraction ?? 0, tint: tint, lineWidth: size * 0.075,
                             track: dark ? .white.opacity(0.1) : Color.primary.opacity(0.08))
                AgentLogo(source: source, size: size * 0.38)
            }
            .frame(width: size, height: size)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: max(11, size * 0.15), weight: .semibold))
                    .foregroundStyle(dark ? .white : .primary)
                Text(window.map { "\(Int(($0.leftFraction * 100).rounded()))% left" } ?? "No data yet")
                    .font(.system(size: max(10.5, size * 0.13), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dark ? .white.opacity(0.6) : .secondary)
                if let window {
                    Text(Self.resetText(window.resetsAt))
                        .font(.system(size: max(9.5, size * 0.11)))
                        .foregroundStyle(dark ? .white.opacity(0.4) : Color.secondary.opacity(0.8))
                }
            }
        }
    }

    /// Green when plenty is left, amber when getting low, red when nearly out.
    private var color: Color {
        guard let left = window?.leftFraction else { return .gray }
        if left < 0.15 { return Theme.danger }
        if left < 0.35 { return Theme.attention }
        return SourceStyle.tint(source)
    }

    static func resetText(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 24 * 3600 { return "Resets in \(Format.duration(seconds))" }
        return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}

/// An event's icon: the Claude mark for Claude events, otherwise its colored badge.
struct EventIcon: View {
    let event: ActivityEvent
    var size: CGFloat = 28

    var body: some View {
        if event.source == "claude" {
            ClaudeMark(size: size)
        } else {
            IconBadge(symbol: event.displaySymbol, tint: event.tint, size: size)
        }
    }
}

/// The mascot in white on a terracotta rounded square, matching our other icon badges.
struct ClaudeBadge: View {
    var size: CGFloat = 28

    var body: some View {
        ClaudeMark(size: size * 0.72, color: .white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [SourceStyle.tint("claude"), SourceStyle.tint("claude").mix(with: .black, by: 0.22)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
