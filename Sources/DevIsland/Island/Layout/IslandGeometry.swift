import AppKit

/// Island sizes for one screen, measured from the real notch when there is one.
struct IslandGeometry: Equatable {
    var hasNotch: Bool
    var notchSize: CGSize
    /// Height of the band at the top of the island (notch or menu bar; the capsule height when floating).
    var topHeight: CGFloat
    /// A detached capsule below the top edge (iPhone Dynamic Island style) instead of hanging from the notch.
    var floating = false

    static let earWidth: CGFloat = 62
    static let fallback = IslandGeometry(hasNotch: true, notchSize: CGSize(width: 180, height: 32), topHeight: 32)
    static let capsuleHeight: CGFloat = 30

    /// Concave "shoulders" that blend the island into the menu bar beside the notch.
    var shoulder: CGFloat { hasNotch && !floating ? 6 : 0 }
    /// Space above a floating island: just below the camera on notch Macs, a few points from the top otherwise.
    var topGap: CGFloat { floating ? (hasNotch ? notchSize.height + 6 : 6) : 0 }
    /// The part hidden behind the camera (a small gap between the two sides when there's no camera in the way).
    var centerWidth: CGFloat { hasNotch && !floating ? notchSize.width : floating ? 40 : 84 }
    var idleSize: CGSize {
        if floating { return CGSize(width: 118, height: topHeight) } // a small capsule, always there like the iPhone's
        return hasNotch ? notchSize : CGSize(width: 120, height: topHeight)
    }
    var expandedWidth: CGFloat { floating ? 500 : max(540, centerWidth + 340) }
    var compactRadius: CGFloat { hasNotch && !floating ? 10 : topHeight / 2 }

    func compactSize(isLive: Bool) -> CGSize {
        isLive ? CGSize(width: centerWidth + Self.earWidth * 2, height: topHeight) : idleSize
    }

    /// A volume / brightness HUD: wider ears for the icon and the level bar.
    var hudSize: CGSize { CGSize(width: centerWidth + 100 * 2, height: topHeight) }

    func expandedSize(contentHeight: CGFloat) -> CGSize {
        CGSize(width: expandedWidth, height: topHeight + contentHeight)
    }

    /// The fixed panel size: room for the largest island plus a margin.
    var canvasSize: CGSize {
        CGSize(width: expandedWidth + shoulder * 2 + 40,
               height: topGap + topHeight + IslandMetrics.maxContentHeight + IslandMetrics.tabBarHeight + 40)
    }
}

/// Where the island sits: hanging from the notch, or floating below the top edge.
enum IslandStyle: String, CaseIterable, Identifiable {
    case automatic, notch, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .notch: "Notch"
        case .floating: "Floating island"
        }
    }
}

extension IslandGeometry {
    init(screen: NSScreen, style: IslandStyle = .automatic) {
        let notch = screen.notchSize
        // Automatic: the notch style where there is a notch, a floating island everywhere else.
        let floating = style == .floating || (style == .automatic && notch == nil)
        if floating {
            self.init(hasNotch: notch != nil, notchSize: notch ?? .zero, topHeight: Self.capsuleHeight, floating: true)
        } else if let notch {
            self.init(hasNotch: true, notchSize: notch, topHeight: notch.height)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            self.init(hasNotch: false, notchSize: .zero, topHeight: menuBar > 0 ? menuBar : 24)
        }
    }
}

/// The tallest expanded content (music with its library open), for the panel size.
enum IslandMetrics {
    static let activityHeight: CGFloat = 88
    static let maxContentHeight: CGFloat = 290
    /// The labelled page tabs along the bottom of the open island.
    static let tabBarHeight: CGFloat = 32
}

extension NSScreen {
    /// Size of the camera notch, or `nil` when this screen has no notch.
    /// macOS reports the usable areas left and right of the notch; the notch is what's in between.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}
