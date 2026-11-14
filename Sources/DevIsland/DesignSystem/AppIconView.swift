import AppKit
import SwiftUI

/// The DevIsland app icon, drawn in code so it's crisp at every size: a dark glass tile with a black notch
/// hanging from its top edge, two tiny live lights in it, and a soft teal glow spilling down below.
/// Used for the Dock, About and onboarding.
struct AppIconView: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let tile = side * 0.805 // the macOS icon grid leaves a margin around the tile
            let corner = tile * 0.225
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

            ZStack(alignment: .top) {
                // Graphite glass.
                shape.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                // Light spilling down from under the notch.
                RadialGradient(colors: [Theme.accent.opacity(0.75), Theme.accent.opacity(0.18), .clear],
                               center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: tile * 0.62)
                    .blendMode(.screen)
                // Glass sheen across the top.
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0)], startPoint: .top, endPoint: .center)
                notch(tile: tile)
            }
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(1, side * 0.005)))
            .shadow(color: .black.opacity(0.4), radius: side * 0.03, y: side * 0.016)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The black notch with a live dot on the left and a progress ring on the right.
    private func notch(tile: CGFloat) -> some View {
        ZStack {
            NotchShape(shoulder: tile * 0.035, bottomRadius: tile * 0.075)
                .fill(.black)
                .shadow(color: Theme.accent.opacity(0.9), radius: tile * 0.06, y: tile * 0.03)
            HStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: tile * 0.055, height: tile * 0.055)
                    .shadow(color: Theme.accent, radius: tile * 0.02)
                Spacer()
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Theme.accent.mix(with: .white, by: 0.35), style: StrokeStyle(lineWidth: tile * 0.017, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: tile * 0.06, height: tile * 0.06)
            }
            .padding(.horizontal, tile * 0.1)
            .offset(y: -tile * 0.012)
        }
        .frame(width: tile * 0.56, height: tile * 0.17)
    }
}

@MainActor
enum AppIconRenderer {
    /// Writes an .iconset folder (every size macOS needs) for `iconutil` to turn into AppIcon.icns.
    static func exportIconset(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                guard let image = image(pixels: CGFloat(points * scale)),
                      let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try? png.write(to: folder.appending(path: name))
            }
        }
    }

    /// The icon as an image, e.g. for the Dock while running without an app bundle.
    static func image(pixels: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconView().frame(width: pixels, height: pixels))
        renderer.scale = 1
        return renderer.nsImage
    }
}

/// The small notch-shaped glyph in the menu bar: outlined when idle, filled when something is live.
@MainActor
enum MenuBarGlyph {
    static let idle = make(filled: false)
    static let active = make(filled: true)

    private static func make(filled: Bool) -> NSImage {
        let shape = NotchShape(shoulder: 0, bottomRadius: 4)
        let glyph = ZStack {
            if filled {
                shape.fill(.black)
            } else {
                shape.stroke(.black, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 8)
        .padding(.horizontal, 1)
        .padding(.vertical, 4)

        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "capsule", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
