import SwiftUI

extension EnvironmentValues {
    /// Off when the user turns glass off in Settings → Island.
    @Entry var glassEnabled = true
    /// True inside a glass surface, so controls in it stay flat (no glass on glass).
    @Entry var insideGlass = false
    /// Looping animations should stand still: Reduce Motion, Low Power Mode, or Animations off in Settings.
    @Entry var stillMotion = false
    /// The island highlight color chosen in Settings → Customize.
    @Entry var highlight: Color = Theme.accent
}

/// DevIsland's glass: Apple's Liquid Glass on macOS 26 and later, a frosted material with a lit edge
/// on earlier versions, and a plain surface when glass is off or Reduce Transparency is on.
private struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let fallback: Color
    @Environment(\.glassEnabled) private var glassEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let marked = content.environment(\.insideGlass, true)
        if !glassEnabled || reduceTransparency {
            marked
                .background(fallback, in: shape)
                .overlay(shape.stroke(Theme.cardStroke))
        } else if #available(macOS 26.0, *) {
            marked.glassEffect(liquidGlass, in: shape)
        } else {
            marked
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// Puts a glass surface of the given shape behind this view.
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false,
                         fallback: Color = Color.primary.opacity(0.06)) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }
}

/// Soft lagoon-colored light behind the dashboard, so the glass has something to catch.
/// Static, so it costs nothing after it's drawn.
/// The dashboard page background: a calm solid color.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Theme.pageFill(colorScheme)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// The shared environment for every SwiftUI root: app model, glass setting and accent color.
struct AppRoot<Content: View>: View {
    let model: AppModel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(model)
            .environment(\.glassEnabled, model.preferences.glassEffects)
            .environment(\.highlight, Color(hex: model.preferences.highlightHex) ?? Theme.accent)
            .modifier(StillWhenSaving(model: model))
            .tint(Theme.accent)
    }
}

/// In Low Power Mode, or with Animations off in Settings, looping animations stop (they all follow Reduce Motion).
private struct StillWhenSaving: ViewModifier {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.stillMotion, systemReduceMotion || lowPower || !model.preferences.animations)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
