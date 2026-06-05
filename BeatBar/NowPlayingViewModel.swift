import AppKit
import Combine
import Foundation

/// MediaRemote `send` command IDs (mediaremote-adapter README).
enum MediaRemoteSendCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case toggleShuffle = 6
    case toggleRepeat = 7
}

/// Mode IDs for mediaremote-adapter `shuffle` / `repeat` CLI (see upstream README).
private enum MediaRemoteShuffleCommandMode: Int {
    case off = 1
    case shuffleAlbums = 2
    case shuffleTracks = 3
}

private enum MediaRemoteRepeatCommandMode: Int {
    case off = 1
    case repeatOne = 2
    case repeatAll = 3
}

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var state: NowPlayingDisplayState = .empty
    @Published private(set) var adapterError: AdapterError?
    @Published private(set) var adapterPaths: MediaRemoteAdapterClient.BundledPaths?
    @Published var panelVolume: Double = 0.5
    /// Bumps on a short interval while playing so views can read `liveProgress` / `liveElapsedSeconds`.
    @Published private(set) var playbackUITick: UInt = 0

    /// Elapsed playback extrapolated to “now” (for smooth progress UI between adapter ticks).
    var liveElapsedSeconds: Double {
        let duration = Self.durationSeconds(from: mergedPayload)
        guard duration > 0 else { return 0 }
        return Self.resolveElapsedSeconds(payload: mergedPayload, duration: duration)
    }

    /// 0...1 progress using `liveElapsedSeconds` (use with `TimelineView` while playing).
    var liveProgress: Double {
        let duration = Self.durationSeconds(from: mergedPayload)
        guard duration > 0 else { return 0 }
        return min(1, max(0, liveElapsedSeconds / duration))
    }

    /// Total duration from the same merged adapter payload as `liveProgress` (some apps omit it in partial diffs).
    var liveDurationSeconds: Double {
        Self.durationSeconds(from: mergedPayload)
    }

    private let client = MediaRemoteAdapterClient()
    private let volumeController = SystemVolumeController()
    private var mergedPayload: [String: Any] = [:]
    private var recheckTask: Task<Void, Never>?
    private var volumeRefreshTimer: Timer?
    private var playbackUITimer: Timer?

    init() {
        start()
    }

    func start() {
        client.stopStream()
        recheckTask?.cancel()
        adapterError = nil
        if let paths = MediaRemoteAdapterClient.bundledPaths() {
            adapterPaths = paths
            Task { await self.bootstrapAdapter(paths: paths) }
        } else {
            adapterPaths = nil
            adapterError = .missingBundledResources
            state = Self.idlePlaceholder()
            scheduleRecheck()
        }
        startVolumeObservation()
    }

    func stop() {
        recheckTask?.cancel()
        recheckTask = nil
        volumeRefreshTimer?.invalidate()
        volumeRefreshTimer = nil
        stopPlaybackUITimer()
        client.stopStream()
    }

    deinit {
        playbackUITimer?.invalidate()
        playbackUITimer = nil
        // `stop()` is MainActor; deinit cannot hop. Stop stream synchronously.
        client.stopStream()
    }

    private static func idlePlaceholder() -> NowPlayingDisplayState {
        NowPlayingDisplayState(
            title: "Nothing playing",
            artist: "",
            album: "",
            releaseYear: nil,
            isPlaying: false,
            durationSeconds: 0,
            elapsedSeconds: 0,
            artwork: nil
        )
    }

    private func scheduleRecheck() {
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.adapterMissingRecheckSeconds * 1_000_000_000))
                await MainActor.run {
                    guard let self else { return }
                    if let paths = MediaRemoteAdapterClient.bundledPaths() {
                        self.adapterError = nil
                        self.adapterPaths = paths
                        Task { await self.bootstrapAdapter(paths: paths) }
                        self.recheckTask?.cancel()
                    }
                }
            }
        }
    }

    private func bootstrapAdapter(paths: MediaRemoteAdapterClient.BundledPaths) async {
        let mediaClient = client
        let ok = await Task.detached {
            mediaClient.runSelfTest(paths: paths)
        }.value
        if !ok {
            adapterError = .streamEndedUnexpectedly("Adapter self-test failed. Rebuild the helper (see README).")
        }
        startStream(paths: paths)
    }

    private func startStream(paths: MediaRemoteAdapterClient.BundledPaths) {
        mergedPayload = [:]
        let mediaClient = client
        Task.detached {
            do {
                try mediaClient.startStream(paths: paths) { result in
                    Task { @MainActor [weak self] in
                        self?.handleStreamResult(result)
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.adapterError = .streamEndedUnexpectedly(error.localizedDescription)
                }
            }
        }
    }

    private func handleStreamResult(_ result: Result<[String: Any], Error>) {
        switch result {
        case let .failure(error):
            stopPlaybackUITimer()
            if let known = error as? AdapterError {
                self.adapterError = known
            } else {
                self.adapterError = .streamEndedUnexpectedly(error.localizedDescription)
            }
        case let .success(dict):
            adapterError = nil
            guard let type = dict["type"] as? String, type == "data" else { return }
            let diff = (dict["diff"] as? Bool) ?? false
            guard let payload = dict["payload"] as? [String: Any] else {
                mergedPayload = [:]
                state = Self.idlePlaceholder()
                syncPlaybackUITimer()
                return
            }
            Self.mergePayload(into: &mergedPayload, diff: diff, payload: payload)
            state = Self.mapDisplayState(from: mergedPayload)
            syncPlaybackUITimer()
        }
    }

    private func syncPlaybackUITimer() {
        stopPlaybackUITimer()
        guard state.isPlaying, state.durationSeconds > 0 else { return }
        let interval = AppConstants.playbackProgressTimelineIntervalSeconds
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playbackUITick &+= 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackUITimer = timer
        playbackUITick &+= 1
    }

    private func stopPlaybackUITimer() {
        playbackUITimer?.invalidate()
        playbackUITimer = nil
    }

    private static func mergePayload(into base: inout [String: Any], diff: Bool, payload: [String: Any]) {
        if !diff {
            base = payload
            return
        }
        for (key, value) in payload {
            if value is NSNull {
                base.removeValue(forKey: key)
            } else {
                base[key] = value
            }
        }
    }

    private static func mapDisplayState(from payload: [String: Any]) -> NowPlayingDisplayState {
        let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            return idlePlaceholder()
        }
        let artist = (payload["artist"] as? String) ?? ""
        let album = (payload["album"] as? String) ?? ""
        let year = releaseYear(from: payload)
        let playing = payloadBool(payload["playing"])
        let duration = durationSeconds(from: payload)
        let elapsed = resolveElapsedSeconds(payload: payload, duration: duration)
        let artwork = decodeArtwork(mime: payload["artworkMimeType"] as? String, base64: payload["artworkData"] as? String)
        return NowPlayingDisplayState(
            title: title,
            artist: artist,
            album: album,
            releaseYear: year,
            isPlaying: playing,
            durationSeconds: duration,
            elapsedSeconds: elapsed,
            artwork: artwork
        )
    }

    /// Best-effort year from adapter keys / ISO-like date strings.
    private static func releaseYear(from payload: [String: Any]) -> Int? {
        if let y = payload["year"] as? Int, y > 0 { return y }
        if let n = payload["year"] as? NSNumber {
            let y = n.intValue
            return y > 0 ? y : nil
        }
        if let s = payload["year"] as? String, let y = Int(s), y > 0 { return y }
        for key in ["releaseYear", "albumYear"] {
            if let y = payload[key] as? Int, y > 0 { return y }
            if let n = payload[key] as? NSNumber {
                let y = n.intValue
                if y > 0 { return y }
            }
            if let s = payload[key] as? String, let y = Int(s), y > 0 { return y }
        }
        for key in ["releaseDate", "albumReleaseDate", "date"] {
            if let s = payload[key] as? String, let y = yearPrefix(from: s) {
                return y
            }
        }
        return nil
    }

    private static func yearPrefix(from string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        guard let y = Int(trimmed.prefix(4)), y >= 1000, y <= 2999 else { return nil }
        return y
    }

    private static func numberToDouble(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return 0
    }

    /// `mediaremote-adapter` JSON booleans may bridge as `Bool` or `NSNumber` (0/1).
    private static func payloadBool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool:
            return b
        case let n as NSNumber:
            return n.boolValue
        case let i as Int:
            return i != 0
        default:
            return false
        }
    }

    /// Matches `sanitizeValueForJsonEncoding` in the adapter: `NSDate` → UTC `yyyy-MM-dd'T'HH:mm:ss'Z'`.
    private static let adapterTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Epoch seconds for `timestamp` (number) or adapter ISO string; `nil` if unknown.
    private static func timestampEpochSeconds(from value: Any?) -> Double? {
        switch value {
        case let d as Double:
            return d.isFinite ? d : nil
        case let i as Int:
            return Double(i)
        case let n as NSNumber:
            let d = n.doubleValue
            return d.isFinite ? d : nil
        case let s as String:
            if let d = Double(s), d.isFinite { return d }
            if let date = adapterTimestampFormatter.date(from: s) {
                return date.timeIntervalSince1970
            }
            if let date = iso8601FallbackFormatter.date(from: s) {
                return date.timeIntervalSince1970
            }
            return nil
        default:
            return nil
        }
    }

    private static func durationSeconds(from payload: [String: Any]) -> Double {
        if payload["durationMicros"] != nil {
            return numberToDouble(payload["durationMicros"]) / 1_000_000
        }
        return numberToDouble(payload["duration"])
    }

    private static func resolveElapsedSeconds(payload: [String: Any], duration: Double) -> Double {
        if payload["elapsedTimeNow"] != nil {
            return max(0, min(duration, numberToDouble(payload["elapsedTimeNow"])))
        }
        if payload["elapsedTimeNowMicros"] != nil {
            return max(0, min(duration, numberToDouble(payload["elapsedTimeNowMicros"]) / 1_000_000))
        }
        let elapsed: Double
        if payload["elapsedTimeMicros"] != nil {
            elapsed = numberToDouble(payload["elapsedTimeMicros"]) / 1_000_000
        } else {
            elapsed = numberToDouble(payload["elapsedTime"])
        }
        let playing = payloadBool(payload["playing"])
        let rate = max(0, numberToDouble(payload["playbackRate"]))
        if playing, let stamp = timestampEpochSeconds(from: payload["timestamp"]) {
            let wall = Date().timeIntervalSince1970 - stamp
            let delta = wall * (rate > 0 ? rate : 1)
            return max(0, min(duration, elapsed + delta))
        }
        if playing, payload["timestampEpochMicros"] != nil {
            let stampMicros = numberToDouble(payload["timestampEpochMicros"])
            let stamp = stampMicros / 1_000_000
            let wall = Date().timeIntervalSince1970 - stamp
            let delta = wall * (rate > 0 ? rate : 1)
            return max(0, min(duration, elapsed + delta))
        }
        return max(0, min(duration, elapsed))
    }

    private static func decodeArtwork(mime: String?, base64: String?) -> NSImage? {
        guard let base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return NSImage(data: data)
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let paths = adapterPaths else { return }
        let mediaClient = client
        Task.detached {
            try? mediaClient.sendCommand(paths: paths, commandId: MediaRemoteSendCommand.togglePlayPause.rawValue)
        }
    }

    func nextTrack() {
        sendCommandId(MediaRemoteSendCommand.nextTrack.rawValue)
    }

    func previousTrack() {
        sendCommandId(MediaRemoteSendCommand.previousTrack.rawValue)
    }

    /// Cycles shuffle off ↔ “shuffle tracks” using explicit `shuffle` modes (toggle `send 6` is unreliable for many players).
    func toggleShuffle() {
        guard let paths = adapterPaths else { return }
        let current = Self.normalizedShuffleMode(from: mergedPayload)
        let next: Int
        switch current {
        case MediaRemoteShuffleCommandMode.shuffleAlbums.rawValue,
             MediaRemoteShuffleCommandMode.shuffleTracks.rawValue:
            next = MediaRemoteShuffleCommandMode.off.rawValue
        default:
            next = MediaRemoteShuffleCommandMode.shuffleTracks.rawValue
        }
        runSetShuffle(paths: paths, mode: next)
    }

    /// Cycles repeat off ↔ “repeat playlist” using explicit `repeat` modes (toggle `send 7` is unreliable for many players).
    func toggleRepeat() {
        guard let paths = adapterPaths else { return }
        let current = Self.normalizedRepeatMode(from: mergedPayload)
        let next: Int
        switch current {
        case MediaRemoteRepeatCommandMode.repeatOne.rawValue,
             MediaRemoteRepeatCommandMode.repeatAll.rawValue:
            next = MediaRemoteRepeatCommandMode.off.rawValue
        default:
            next = MediaRemoteRepeatCommandMode.repeatAll.rawValue
        }
        runSetRepeat(paths: paths, mode: next)
    }

    func seekToProgress(_ progress: Double) {
        guard let paths = adapterPaths else { return }
        let duration = Self.durationSeconds(from: mergedPayload)
        guard duration > 0 else { return }
        let clamped = max(0, min(1, progress))
        let micros = Int64(clamped * duration * AppConstants.microsecondsPerSecond)
        let mediaClient = client
        Task.detached {
            try? mediaClient.seek(paths: paths, positionMicroseconds: micros)
        }
    }

    private func sendCommandId(_ id: Int) {
        guard let paths = adapterPaths else { return }
        let mediaClient = client
        Task.detached {
            try? mediaClient.sendCommand(paths: paths, commandId: id)
        }
    }

    private func runSetShuffle(paths: MediaRemoteAdapterClient.BundledPaths, mode: Int) {
        let mediaClient = client
        Task.detached {
            do {
                try mediaClient.setShuffle(paths: paths, mode: mode)
            } catch {
                try? mediaClient.sendCommand(paths: paths, commandId: MediaRemoteSendCommand.toggleShuffle.rawValue)
            }
        }
    }

    private func runSetRepeat(paths: MediaRemoteAdapterClient.BundledPaths, mode: Int) {
        let mediaClient = client
        Task.detached {
            do {
                try mediaClient.setRepeat(paths: paths, mode: mode)
            } catch {
                try? mediaClient.sendCommand(paths: paths, commandId: MediaRemoteSendCommand.toggleRepeat.rawValue)
            }
        }
    }

    private static func mediaRemoteModeInt(_ value: Any?) -> Int? {
        switch value {
        case let i as Int:
            return i
        case let n as NSNumber:
            return n.intValue
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }

    /// Maps `shuffleMode` from the adapter payload to command mode IDs (treats `0` / missing as off).
    private static func normalizedShuffleMode(from payload: [String: Any]) -> Int {
        guard let raw = mediaRemoteModeInt(payload["shuffleMode"]) else {
            return MediaRemoteShuffleCommandMode.off.rawValue
        }
        if raw == 0 { return MediaRemoteShuffleCommandMode.off.rawValue }
        return raw
    }

    /// Maps `repeatMode` from the adapter payload to command mode IDs (treats `0` / missing as off).
    private static func normalizedRepeatMode(from payload: [String: Any]) -> Int {
        guard let raw = mediaRemoteModeInt(payload["repeatMode"]) else {
            return MediaRemoteRepeatCommandMode.off.rawValue
        }
        if raw == 0 { return MediaRemoteRepeatCommandMode.off.rawValue }
        return raw
    }

    func applyPanelVolumeFromSystem() {
        volumeController.refreshDefaultOutputDevice()
        if let v = volumeController.readVolumeScalar() {
            panelVolume = Double(v)
        }
    }

    func setPanelVolume(_ value: Double) {
        let clamped = max(Double(AppConstants.outputVolumeMin), min(Double(AppConstants.outputVolumeMax), value))
        panelVolume = clamped
        volumeController.setVolumeScalar(Float32(clamped))
    }

    private func startVolumeObservation() {
        volumeRefreshTimer?.invalidate()
        applyPanelVolumeFromSystem()
        volumeRefreshTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.volumePollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyPanelVolumeFromSystem()
            }
        }
    }
}
