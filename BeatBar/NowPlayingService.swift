import Foundation

/// Facade boundary for future alternative backends (AppleScript-only, etc.).
protocol NowPlayingService: AnyObject {
    var displayState: NowPlayingDisplayState { get }
}

extension NowPlayingViewModel: NowPlayingService {
    var displayState: NowPlayingDisplayState { state }
}
