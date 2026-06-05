import Foundation

/// Centralized tunables (no scattered magic numbers).
enum AppConstants {
    /// How often the UI samples extrapolated playback position while playing (for progress bars).
    static let playbackProgressTimelineIntervalSeconds: Double = 0.25

    /// Menu bar extra label: artwork thumbnail **maximum** width and height (points).
    static let menuBarCompactArtworkMaxPointSize: Double = 20

    /// Height of the full-width progress strip under the menu bar title row (points). Values below ~2 often disappear in `MenuBarExtra` labels.
    static let menuBarCompactProgressBarHeight: Double = 2

    /// Vertical gap between the title row and the progress strip (points).
    static let menuBarCompactProgressRowToBarSpacing: Double = 3

    /// Minimum height for the compact label so the progress strip is not clipped by the status item host.
    static let menuBarCompactLabelMinHeight: Double = 26

    /// Retries while SwiftUI registers `MenuBarExtra` with `NSStatusBar` before attaching the right-click Quit handler.
    static let menuBarExtraQuitMenuInstallMaxAttempts: Int = 40
    /// Delay between retries when the status item is not yet available (seconds).
    static let menuBarExtraQuitMenuInstallRetryDelaySeconds: TimeInterval = 0.05
    /// `String(format:titleFormat, appName)` for the status-item context menu (include a `%@` placeholder for the app name).
    static let menuBarExtraQuitMenuItemTitleFormat: String = "Quit %@"
    /// Menu item keyboard shortcut (Cmd+Q when used with `keyEquivalentModifierMask: .command` in the delegate).
    static let menuBarExtraQuitMenuKeyEquivalent: String = "q"

    /// Minimum width for elapsed / remaining labels under the panel progress bar (points).
    static let playerPanelTimeLabelMinWidth: Double = 48

    /// Compact “Now Playing” panel (horizontal card).
    static let playerPanelCompactWidth: Double = 448
    static let playerPanelInnerPadding: Double = 12
    /// Horizontal gap between album art and the metadata column (points).
    static let playerPanelArtworkToTextSpacing: Double = 14
    /// Top and bottom padding inside the metadata / controls column (points).
    static let playerPanelRightColumnVerticalInset: Double = 10
    /// Inner row height between panel paddings: album art is a square of this side; right column matches this height (inset applied inside).
    static let playerPanelContentRailHeightPoints: Double = 148
    /// Total panel height: content rail + inner padding on top and bottom.
    static var playerPanelCompactHeight: Double {
        playerPanelContentRailHeightPoints + 2 * playerPanelInnerPadding
    }

    static let playerPanelChromeCornerRadius: Double = 14
    static let playerPanelArtworkCornerRadius: Double = 10
    /// Track title (line 1) — was `.subheadline` (~15pt); +2pt.
    static let playerPanelTitleFontPoints: Double = 17
    /// Artist (line 2) — +1pt vs a 13pt secondary baseline.
    static let playerPanelArtistFontPoints: Double = 14
    /// Album + year (line 3).
    static let playerPanelAlbumYearFontPoints: Double = 13
    /// Vertical spacing between metadata lines (points).
    static let playerPanelMetadataLineSpacing: Double = 4
    /// Space between error / metadata / transport / progress blocks in the right column (points).
    static let playerPanelRightColumnSectionSpacing: Double = 10
    /// Vertical padding around the transport button row (points).
    static let playerPanelTransportVerticalPadding: Double = 6
    /// Horizontal padding around the play/pause button (points).
    static let playerPanelPlayButtonHorizontalPadding: Double = 14
    /// Spacing inside the progress + time labels stack (points).
    static let playerPanelProgressSectionSpacing: Double = 6
    /// Minimum space between elapsed and remaining time labels (points).
    static let playerPanelTimeRowInnerSpacing: Double = 12
    /// Solid fill for panel chrome (`Color(white: …)`).
    static let playerPanelChromeFillWhite: Double = 0.11
    /// Hairline border on the outer rounded rect.
    static let playerPanelBorderOpacity: Double = 0.22

    /// Debounce passed through to mediaremote-adapter `stream` (milliseconds).
    static let mediaRemoteStreamDebounceMilliseconds: UInt32 = 200

    /// When adapter is missing, how often to re-check for bundled files (seconds).
    static let adapterMissingRecheckSeconds: TimeInterval = 2.0

    /// CoreAudio scalar volume bounds.
    static let outputVolumeMin: Float32 = 0
    static let outputVolumeMax: Float32 = 1

    /// `seek` argument unit (mediaremote-adapter).
    static let microsecondsPerSecond: Double = 1_000_000

    /// How often to sync the volume slider with system output volume.
    static let volumePollIntervalSeconds: TimeInterval = 1.0
}
