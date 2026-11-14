import SwiftUI

/// A quiet card: solid surface, hairline border, small radius.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .environment(\.insideGlass, true) // buttons inside stay flat
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFill(colorScheme), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.cardStroke))
    }
}

/// The standard dashboard page: large title, optional actions, scrolling content.
struct PageScaffold<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

extension PageScaffold where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.cardFill(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.8) : Theme.cardStroke, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A transient confirmation shown at the bottom of the dashboard.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
}

struct ToastView: View {
    let toast: Toast?

    var body: some View {
        if let toast {
            Label(toast.message, systemImage: toast.symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glass(in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
        }
    }
}
