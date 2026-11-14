import SwiftUI

/// The main call to action: a solid accent button.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.accent.mix(with: .black, by: configuration.isPressed ? 0.2 : hovering ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Secondary actions: a quiet bordered button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButton(configuration: configuration)
    }

    private struct SecondaryButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.08 : 0.04),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.cardStroke))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
