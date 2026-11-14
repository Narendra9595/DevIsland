import SwiftUI

/// A headline number with an icon, used for "Today" stats.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    let symbol: String
    let tint: Color

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A friendly placeholder for empty lists, with optional actions.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 8) { actions }
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message, actions: { EmptyView() })
    }
}
