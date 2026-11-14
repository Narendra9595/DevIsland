import SwiftUI

/// Flat top with concave "shoulders" and rounded bottom corners, like the MacBook notch.
/// With `topRadius` it becomes a floating capsule/card, rounded all round (iPhone Dynamic Island style).
/// All radii are animatable, so the island morphs smoothly between sizes.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(shoulder, bottomRadius), topRadius) }
        set {
            shoulder = newValue.first.first
            bottomRadius = newValue.first.second
            topRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if topRadius > 0.5 { return floatingPath(in: rect) }
        return notchPath(in: rect)
    }

    /// Rounded on all four corners (top and bottom radii can differ).
    private func floatingPath(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 2, rect.height / 2)
        let bottom = min(bottomRadius, rect.width / 2, rect.height / 2)
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom,
                                                                         bottomTrailing: bottom, topTrailing: top),
                    style: .continuous)
    }

    private func notchPath(in rect: CGRect) -> Path {
        let t = max(0, min(shoulder, rect.width / 4, rect.height / 2))
        let r = max(0, min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t))
        let k: CGFloat = 0.552 // cubic approximation of a quarter circle

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                          control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - r))
        path.addCurve(to: CGPoint(x: rect.minX + t + r, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + t, y: rect.maxY - r + r * k),
                      control2: CGPoint(x: rect.minX + t + r - r * k, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - r, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - r),
                      control1: CGPoint(x: rect.maxX - t - r + r * k, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - t, y: rect.maxY - r + r * k))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
