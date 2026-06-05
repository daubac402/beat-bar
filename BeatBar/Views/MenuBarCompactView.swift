import AppKit
import SwiftUI

/// Draws artwork into a fixed square bitmap so `MenuBarExtra` layout cannot read a huge `NSImage.size` from the stream.
private enum MenuBarArtworkThumbnail {
    static func square(source: NSImage, sidePoints: CGFloat) -> NSImage {
        let side = max(1, sidePoints)
        let s = source.size
        guard s.width > 0, s.height > 0 else {
            return empty(side: side)
        }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            NSGraphicsContext.current?.imageInterpolation = .high
            let scale = min(bounds.width / s.width, bounds.height / s.height)
            let dw = s.width * scale
            let dh = s.height * scale
            let x = bounds.midX - dw / 2
            let y = bounds.midY - dh / 2
            source.draw(
                in: NSRect(x: x, y: y, width: dw, height: dh),
                from: NSRect(origin: .zero, size: s),
                operation: .copy,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil)
            return true
        }
    }

    private static func empty(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            NSColor.clear.setFill()
            NSBezierPath(rect: bounds).fill()
            return true
        }
    }
}

struct MenuBarCompactView: View {
    @EnvironmentObject private var model: NowPlayingViewModel

    private var artworkSide: CGFloat {
        CGFloat(AppConstants.menuBarCompactArtworkMaxPointSize)
    }

    var body: some View {
        let _ = model.playbackUITick
        VStack(alignment: .leading, spacing: CGFloat(AppConstants.menuBarCompactProgressRowToBarSpacing)) {
            HStack(alignment: .center, spacing: 6) {
                artwork
                    .fixedSize(horizontal: true, vertical: true)
                Text(model.state.titleArtistLine)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(minWidth: 140, maxWidth: 160, alignment: .leading)
            }
            MenuBarBottomProgressView(progress: model.liveProgress)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: CGFloat(AppConstants.menuBarCompactProgressBarHeight))
        }
        .frame(minHeight: CGFloat(AppConstants.menuBarCompactLabelMinHeight), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // MenuBarExtra labels can ignore vertical subviews unless we assert intrinsic height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.state.title), \(model.state.artist)")
    }

    @ViewBuilder
    private var artwork: some View {
        let side = artworkSide
        if let image = model.state.artwork {
            MenuBarArtworkRasterCell(image: image, side: side)
                .id(ObjectIdentifier(image))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// One-off rasterize for menu bar: `NSImage.size` from stream art is often huge points-wise; SwiftUI uses that for layout.
private struct MenuBarArtworkRasterCell: View {
    let side: CGFloat
    private let thumbnail: NSImage

    init(image: NSImage, side: CGFloat) {
        self.side = side
        self.thumbnail = MenuBarArtworkThumbnail.square(source: image, sidePoints: side)
    }

    var body: some View {
        Image(nsImage: thumbnail)
            .interpolation(.high)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Full-width hairline: accent fill for `progress`, remainder a subtle track.
/// Avoids `GeometryReader` (often gets **zero width/height** inside `MenuBarExtra` label roots).
private struct MenuBarBottomProgressView: View {
    let progress: Double

    var body: some View {
        let clamped = max(0, min(1, progress))
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
            Rectangle()
                .fill(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(x: CGFloat(clamped), y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(AppConstants.menuBarCompactProgressBarHeight))
        .clipped()
        .compositingGroup()
    }
}
