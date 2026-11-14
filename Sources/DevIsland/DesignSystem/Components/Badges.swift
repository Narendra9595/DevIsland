import SwiftUI

/// A quiet icon chip: the symbol in its color on a faint tint of the same color.
struct IconBadge: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// A small capsule label such as "Connected" or "3 active".
struct StatusPill: View {
    let text: String
    let tint: Color
    var pulsing = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(color: tint, active: pulsing)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(colorScheme == .dark ? tint : tint.mix(with: .black, by: 0.3))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A dot that can radiate a gentle ring to signal "live".
struct PulseDot: View {
    let color: Color
    var active = true

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                // Core Animation ripple: no per-frame work in DevIsland.
                if active { RippleRing(color: color) }
            }
    }
}
