import Charts
import SwiftUI

/// A circular progress ring.
struct RingProgress: View {
    let progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 6
    var track: Color = Color.primary.opacity(0.08)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(.smooth(duration: 0.5), value: progress)
    }
}

/// A thin horizontal progress bar.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.smooth(duration: 0.4), value: value)
    }
}

/// A tiny line chart without axes.
struct Sparkline: View {
    let values: [Double]
    let tint: Color
    var maxValue: Double?

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("Time", point.offset), y: .value("Value", point.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", point.offset), y: .value("Value", point.element))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(maxValue ?? max(values.max() ?? 1, 0.01)))
        .chartXScale(domain: 0...max(values.count - 1, 1))
    }
}
