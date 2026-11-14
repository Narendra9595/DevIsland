import AppKit
import SwiftUI

// Looping animations handed to Core Animation: they run in macOS's render server, so DevIsland's
// own code does no work per frame (SwiftUI animations would re-render the island 60 times a second).

/// Equalizer bars that bounce while music plays and rest when paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    var tint: Color = .white
    @Environment(\.stillMotion) private var still

    var body: some View {
        LoopLayerView(kind: .bars, active: isPlaying && !still, color: NSColor(tint))
    }
}

/// A ring that grows and fades from a dot, like a radar ping.
struct RippleRing: View {
    let color: Color
    @Environment(\.stillMotion) private var still

    var body: some View {
        LoopLayerView(kind: .ripple, active: !still, color: NSColor(color))
    }
}

/// The ring around an agent's orb: spinning while it works, pulsing when it needs you.
struct OrbRing: View {
    enum Mode { case spin, pulse }
    let mode: Mode
    let color: Color
    let lineWidth: CGFloat
    @Environment(\.stillMotion) private var still

    var body: some View {
        LoopLayerView(kind: mode == .spin ? .spinner(lineWidth) : .pulse(lineWidth), active: !still, color: NSColor(color))
    }
}

private struct LoopLayerView: NSViewRepresentable {
    enum Kind: Equatable { case bars, spinner(CGFloat), pulse(CGFloat), ripple }
    let kind: Kind
    let active: Bool
    let color: NSColor

    func makeNSView(context: Context) -> LoopView { LoopView(kind: kind) }

    func updateNSView(_ view: LoopView, context: Context) {
        view.update(active: active, color: color)
    }
}

private final class LoopView: NSView {
    private let kind: LoopLayerView.Kind
    private let bars = (0..<4).map { _ in CALayer() }
    private let ring = CAShapeLayer()
    private var active = false
    private var color = NSColor.white

    init(kind: LoopLayerView.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        if case .bars = kind {
            for bar in bars {
                bar.anchorPoint = CGPoint(x: 0.5, y: 0) // grow up from the bottom
                layer?.addSublayer(bar)
            }
        } else {
            ring.fillColor = nil
            ring.lineCap = .round
            layer?.addSublayer(ring)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // purely decorative

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch kind {
        case .bars:
            let width: CGFloat = 2.5
            let gap = max(1.5, (bounds.width - width * 4) / 3)
            for (index, bar) in bars.enumerated() {
                bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
                bar.position = CGPoint(x: width / 2 + CGFloat(index) * (width + gap), y: 0)
                bar.cornerRadius = width / 2
            }
        case .ripple:
            ring.frame = bounds
            ring.lineWidth = 1.5
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        case .spinner(let lineWidth), .pulse(let lineWidth):
            ring.frame = bounds
            ring.lineWidth = lineWidth
            let inset = lineWidth / 2
            let circle = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
            ring.path = circle
            if case .spinner = kind { ring.strokeEnd = 0.3 }
        }
        CATransaction.commit()
        restart()
    }

    func update(active: Bool, color: NSColor) {
        guard active != self.active || color != self.color else { return }
        self.active = active
        self.color = color
        bars.forEach { $0.backgroundColor = color.cgColor }
        ring.strokeColor = color.cgColor
        restart()
    }

    private func restart() {
        bars.forEach { $0.removeAllAnimations() }
        ring.removeAllAnimations()
        switch kind {
        case .bars:
            for (index, bar) in bars.enumerated() {
                bar.transform = CATransform3DMakeScale(1, 0.3, 1)
                guard active else { continue }
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.3
                bounce.toValue = 1.0
                bounce.duration = [0.42, 0.55, 0.37, 0.61][index]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bounce.beginTime = CACurrentMediaTime() - Double(index) * 0.13
                bar.add(bounce, forKey: "bounce")
            }
        case .spinner:
            guard active else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi // clockwise in a y-up layer
            spin.duration = 1.1
            spin.repeatCount = .infinity
            ring.add(spin, forKey: "spin")
        case .ripple:
            ring.opacity = 0
            guard active else { return }
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 2.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 1.5
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "ripple")
        case .pulse:
            guard active else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(pulse, forKey: "pulse")
        }
    }
}
