import AppKit
import Foundation

struct NowPlayingDisplayState: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Release year when reported by the adapter (optional).
    var releaseYear: Int?
    var isPlaying: Bool
    var durationSeconds: Double
    var elapsedSeconds: Double
    var artwork: NSImage?

    static let empty = NowPlayingDisplayState(
        title: "BeatBar",
        artist: "",
        album: "",
        releaseYear: nil,
        isPlaying: false,
        durationSeconds: 0,
        elapsedSeconds: 0,
        artwork: nil
    )

    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, elapsedSeconds / durationSeconds))
    }

    var titleArtistLine: String {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedArtist.isEmpty { return title }
        return "\(title) - \(trimmedArtist)"
    }

    /// Third line: `Album (YYYY)` or fallbacks when album or year is missing.
    var albumYearLine: String {
        let a = album.trimmingCharacters(in: .whitespacesAndNewlines)
        if let y = releaseYear {
            if a.isEmpty { return "(\(y))" }
            return "\(a) (\(y))"
        }
        return a.isEmpty ? " " : a
    }
}

enum AdapterError: LocalizedError, Equatable {
    case missingBundledResources
    case streamEndedUnexpectedly(String)
    case invalidJSONLine(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledResources:
            return "MediaRemote adapter files are not bundled. Run ./scripts/build-adapter.sh (see README)."
        case let .streamEndedUnexpectedly(message):
            return "Media stream stopped: \(message)"
        case let .invalidJSONLine(message):
            return "Invalid adapter output: \(message)"
        }
    }
}
