import SwiftUI

/// Compact horizontal “Now Playing” card: artwork left, metadata + transport + progress on the right.
struct PlayerPanelView: View {
    @EnvironmentObject private var model: NowPlayingViewModel

    private var panelWidth: CGFloat { CGFloat(AppConstants.playerPanelCompactWidth) }
    private var panelHeight: CGFloat { CGFloat(AppConstants.playerPanelCompactHeight) }
    private var innerPadding: CGFloat { CGFloat(AppConstants.playerPanelInnerPadding) }
    private var outerCorner: CGFloat { CGFloat(AppConstants.playerPanelChromeCornerRadius) }
    private var artCorner: CGFloat { CGFloat(AppConstants.playerPanelArtworkCornerRadius) }

    /// Height of the inner HStack row (art + right column); art is a square with this edge length.
    private var contentRailHeight: CGFloat {
        panelHeight - 2 * innerPadding
    }

    private var artworkSide: CGFloat { contentRailHeight }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                .fill(Color(white: AppConstants.playerPanelChromeFillWhite))
                .overlay(
                    RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                        .strokeBorder(Color.white.opacity(AppConstants.playerPanelBorderOpacity), lineWidth: 1)
                )

            HStack(alignment: .center, spacing: CGFloat(AppConstants.playerPanelArtworkToTextSpacing)) {
                artworkSquare
                    .frame(height: contentRailHeight, alignment: .center)
                rightColumn
                    .frame(maxHeight: contentRailHeight, alignment: .center)
            }
            .padding(innerPadding)
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: outerCorner, style: .continuous))
        .onAppear {
            model.applyPanelVolumeFromSystem()
        }
    }

    private var artworkSquare: some View {
        Group {
            if let image = model.state.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artworkSide, height: artworkSide)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: artCorner, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: artworkSide, height: artworkSide)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: artworkSide * 0.28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: CGFloat(AppConstants.playerPanelRightColumnSectionSpacing)) {
            if let error = model.adapterError {
                Text(error.localizedDescription)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            titleRow
            transportRowCompact
            progressSection
        }
        .padding(.vertical, CGFloat(AppConstants.playerPanelRightColumnVerticalInset))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: CGFloat(AppConstants.playerPanelMetadataLineSpacing)) {
            Text(model.state.title)
                .font(.system(size: CGFloat(AppConstants.playerPanelTitleFontPoints), weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Text(artistLine)
                .font(.system(size: CGFloat(AppConstants.playerPanelArtistFontPoints), weight: .regular))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(model.state.albumYearLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : model.state.albumYearLine)
                .font(.system(size: CGFloat(AppConstants.playerPanelAlbumYearFontPoints), weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artistLine: String {
        let a = model.state.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? "—" : a
    }

    private var transportRowCompact: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: { model.previousTrack() }) {
                Image(systemName: "backward.end.fill")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))

            Button(action: { model.togglePlayPause() }) {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, CGFloat(AppConstants.playerPanelPlayButtonHorizontalPadding))

            Button(action: { model.nextTrack() }) {
                Image(systemName: "forward.end.fill")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
        .padding(.vertical, CGFloat(AppConstants.playerPanelTransportVerticalPadding))
    }

    private var progressSection: some View {
        let _ = model.playbackUITick
        return VStack(alignment: .leading, spacing: CGFloat(AppConstants.playerPanelProgressSectionSpacing)) {
            Slider(
                value: Binding(
                    get: { model.liveProgress },
                    set: { model.seekToProgress($0) }
                ),
                in: 0...1
            )
            .tint(Color.accentColor)
            .disabled(model.liveDurationSeconds <= 0)
            .controlSize(.regular)

            HStack {
                Text(formatMinutesSeconds(model.liveElapsedSeconds))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: CGFloat(AppConstants.playerPanelTimeLabelMinWidth), alignment: .leading)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: CGFloat(AppConstants.playerPanelTimeRowInnerSpacing))
                Text(formatNegativeRemaining(elapsed: model.liveElapsedSeconds, duration: model.liveDurationSeconds))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: CGFloat(AppConstants.playerPanelTimeLabelMinWidth), alignment: .trailing)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .id(model.playbackUITick)
    }

    /// `mm:ss` elapsed (e.g. `00:44`).
    private func formatMinutesSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Remaining time like macOS mini player: `-02:11`.
    private func formatNegativeRemaining(elapsed: Double, duration: Double) -> String {
        guard duration > 0, elapsed.isFinite, duration.isFinite else { return "-00:00" }
        let rem = max(0, duration - elapsed)
        let total = Int(rem.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "-%02d:%02d", m, s)
    }
}
