import SwiftUI

/// A looping demo of the island on a mock screen: idle → compact → expanded → compact.
struct IslandShowcase: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let geometry = IslandGeometry.fallback

    var body: some View {
        let activity = SampleActivities.claudeWorking()
        let live = phase >= 1
        let expanded = phase == 2
        let size = expanded
            ? geometry.expandedSize(contentHeight: IslandMetrics.activityHeight)
            : geometry.compactSize(isLive: live)
        let shape = NotchShape(shoulder: geometry.shoulder, bottomRadius: expanded ? 26 : geometry.compactRadius)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.30, blue: 0.58), Color(red: 0.55, green: 0.33, blue: 0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.16)).frame(height: geometry.topHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))

            ZStack(alignment: .top) {
                shape.fill(.black)
                Group {
                    if expanded {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: geometry.topHeight)
                            IslandActivityView(activity: activity)
                                .frame(height: IslandMetrics.activityHeight)
                        }
                        .transition(.opacity.animation(.easeOut(duration: 0.3).delay(0.1)))
                    } else if live {
                        CompactIslandView(activity: activity, geometry: geometry)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, geometry.shoulder)
            }
            .frame(width: size.width + geometry.shoulder * 2, height: size.height, alignment: .top)
            .clipShape(shape)
            .environment(\.colorScheme, .dark)
            .scaleEffect(0.92, anchor: .top)
        }
        .animation(.spring(duration: 0.55, bounce: 0.2), value: phase)
        .task {
            guard !reduceMotion else {
                phase = 2
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(phase == 2 ? 2.6 : 1.4))
                phase = (phase + 1) % 4
            }
        }
    }
}

/// Example activities for the welcome screen and previews.
enum SampleActivities {
    static func claudeWorking(now: Date = .now) -> LiveActivity {
        let event = ActivityEvent(
            source: "claude", kind: .update, sessionID: "demo", title: "Editing files",
            detail: "DevIsland · main", symbol: "sparkles", startDate: now.addingTimeInterval(-252),
            metadata: ["state": "working", "project": "DevIsland", "branch": "main", "tool": "Edit"],
            timestamp: now)
        return LiveActivity(key: event.activityKey, event: event, startedAt: now.addingTimeInterval(-1260))
    }
}
