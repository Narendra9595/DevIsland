import SwiftUI

/// The island: solid black where it meets the notch, glowing softly in the color of whatever is
/// happening, with its content on glass panes lit from inside.
struct IslandView: View {
    let model: IslandViewModel
    @Environment(\.glassEnabled) private var glassEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var lighting: Bool { glassEnabled && !reduceTransparency }

    var body: some View {
        let size = model.size
        let shoulder = model.geometry.shoulder
        let shape = NotchShape(shoulder: shoulder, bottomRadius: model.bottomRadius, topRadius: model.topRadius)
        let width = size.width + shoulder * 2
        // Colored light only for what's in front: the activity, or music on its page.
        let tint: Color? = !model.isExpanded ? model.current?.event.tint
            : model.page == .activity ? model.current?.event.tint
            : model.page == .music ? model.music?.event.tint : nil

        ZStack(alignment: .top) {
            // Activity light: a soft halo in the activity's color around the island.
            if lighting, let tint {
                shape.fill(tint)
                    .frame(width: width, height: size.height)
                    .blur(radius: model.isExpanded ? 24 : 12)
                    .opacity(model.isExpanded ? 0.5 : 0.32)
                    .offset(y: model.isExpanded ? 8 : 3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            ZStack(alignment: .top) {
                shape.fill(.black)
                // The same color glowing inside the black, picked up by the glass panes.
                if lighting, model.isExpanded, let tint {
                    RadialGradient(colors: [tint.opacity(0.3), .clear], center: UnitPoint(x: 0.2, y: 0.65),
                                   startRadius: 0, endRadius: width * 0.6)
                        .transition(.opacity)
                }
                content
                    .padding(.horizontal, shoulder)
            }
            .frame(width: width, height: size.height, alignment: .top)
            .overlay {
                // A lit lower edge, like light catching polished glass.
                if lighting, tint != nil {
                    shape.stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.2)],
                                                startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }
            }
            .clipShape(shape)
            // A floating island casts a soft shadow, like the iPhone's over content.
            .shadow(color: .black.opacity(model.geometry.floating ? (model.isExpanded ? 0.45 : 0.25) : 0),
                    radius: model.isExpanded ? 16 : 6, y: model.isExpanded ? 8 : 2)
            .overlay { IslandGlow(event: model.current?.event, shape: shape) }
            .contentShape(shape)
            // A click opens it like hovering does; it still closes when the pointer leaves.
            .onTapGesture { model.openFromGesture() }
            .dropDestination(for: URL.self) { urls, _ in
                model.app.shelf.add(urls)
                return true
            } isTargeted: { model.setDropTargeted($0) }
        }
        .padding(.top, model.geometry.topGap)
        .animation(model.animation, value: size)
        .animation(model.animation, value: model.current?.key)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DevIsland")
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded {
            ExpandedIslandView(model: model)
                // No delay: the content arrives with the shape, so it never gets stuck invisible
                // (e.g. when a screenshot pauses animations mid-opening).
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(.smooth(duration: 0.22)),
                    removal: .opacity.animation(.easeOut(duration: 0.1))))
        } else if let hud = model.app.hud.hud {
            HUDView(hud: hud, geometry: model.geometry)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
        } else if let activity = model.current {
            CompactIslandView(activity: activity, geometry: model.geometry)
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
        }
    }
}

/// A soft pulsing outline while something needs attention.
struct IslandGlow: View {
    let event: ActivityEvent?
    let shape: NotchShape
    @Environment(\.stillMotion) private var reduceMotion

    var body: some View {
        if let event, event.kind == .alert || event.metadata["state"] == "attention" {
            // 8 frames a second is plenty for a slow glow.
            TimelineView(.animation(minimumInterval: 1 / 8, paused: reduceMotion)) { context in
                let wave = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * .pi / 0.9)
                shape
                    .stroke(event.tint.opacity(reduceMotion ? 0.8 : 0.4 + 0.55 * wave), lineWidth: 1.5)
                    .mask(LinearGradient(colors: [.clear, .white, .white], startPoint: .top, endPoint: .bottom))
            }
            .allowsHitTesting(false)
        }
    }
}

/// The HUD beside the notch: the icon on the left ear, a slim level bar (or a short label) on the right.
struct HUDView: View {
    let hud: HUD
    let geometry: IslandGeometry
    @Environment(\.highlight) private var highlight

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: hud.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 100)
            Spacer(minLength: geometry.centerWidth)
            Group {
                if let level = hud.level {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(hud.kind == .brightness ? .white : highlight)
                                .frame(width: max(5, proxy.size.width * level))
                        }
                    }
                    .frame(width: 64, height: 5)
                    .animation(.spring(duration: 0.2), value: level)
                } else if let text = hud.text {
                    Text(text)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: 100)
        }
        .frame(height: geometry.topHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.text ?? "\(Int((hud.level ?? 0) * 100)) percent")
    }
}
