import Foundation

/// Invokes `mediaremote-adapter` via `/usr/bin/perl` per upstream contract.
final class MediaRemoteAdapterClient: @unchecked Sendable {
    private let processLock = NSLock()
    private var streamProcess: Process?
    private var pipe: Pipe?
    private var lineBuffer = ""

    private static let perlExecutablePath = "/usr/bin/perl"
    private static let adapterSubdirectory = "Adapter"

    struct BundledPaths: Equatable {
        let scriptURL: URL
        let frameworkURL: URL
        let testClientURL: URL
    }

    static func bundledPaths() -> BundledPaths? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let adapterRoot = resourceURL.appendingPathComponent(adapterSubdirectory, isDirectory: true)
        let scriptURL = adapterRoot.appendingPathComponent("mediaremote-adapter.pl")
        let frameworkURL = adapterRoot.appendingPathComponent("MediaRemoteAdapter.framework")
        let testClientURL = adapterRoot.appendingPathComponent("MediaRemoteAdapterTestClient")
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              FileManager.default.fileExists(atPath: frameworkURL.path),
              FileManager.default.fileExists(atPath: testClientURL.path)
        else {
            return nil
        }
        return BundledPaths(scriptURL: scriptURL, frameworkURL: frameworkURL, testClientURL: testClientURL)
    }

    /// Runs `test` synchronously; returns true if exit code is 0.
    func runSelfTest(paths: BundledPaths) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            "test",
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// One-shot `get --now` JSON object or null.
    func fetchSnapshot(paths: BundledPaths) throws -> [String: Any]? {
        let process = Process()
        let output = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            "get",
            "--now",
        ]
        process.standardOutput = output
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "unknown"
            throw AdapterError.streamEndedUnexpectedly(message)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let outputText = String(data: data, encoding: .utf8) else { return nil }
        guard let firstLine = outputText.split(separator: "\n").first else {
            return nil
        }
        let lineString = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        if lineString == "null" { return nil }
        guard let jsonData = lineString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw AdapterError.invalidJSONLine(lineString)
        }
        return obj
    }

    func sendCommand(paths: BundledPaths, commandId: Int) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            "send",
            "\(commandId)",
        ]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "send failed"
            throw AdapterError.streamEndedUnexpectedly(message)
        }
    }

    func setShuffle(paths: BundledPaths, mode: Int) throws {
        try runSimpleCommand(paths: paths, name: "shuffle", value: "\(mode)")
    }

    func setRepeat(paths: BundledPaths, mode: Int) throws {
        try runSimpleCommand(paths: paths, name: "repeat", value: "\(mode)")
    }

    func seek(paths: BundledPaths, positionMicroseconds: Int64) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            "seek",
            "\(positionMicroseconds)",
        ]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "seek failed"
            throw AdapterError.streamEndedUnexpectedly(message)
        }
    }

    private func runSimpleCommand(paths: BundledPaths, name: String, value: String) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            name,
            value,
        ]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "\(name) failed"
            throw AdapterError.streamEndedUnexpectedly(message)
        }
    }

    /// Starts `stream` and calls handler for each JSON line on a background queue.
    func startStream(
        paths: BundledPaths,
        onLine: @escaping @Sendable (Result<[String: Any], Error>) -> Void
    ) throws {
        stopStream()
        let process = Process()
        let output = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = [
            paths.scriptURL.path,
            paths.frameworkURL.path,
            paths.testClientURL.path,
            "stream",
            "--debounce=\(AppConstants.mediaRemoteStreamDebounceMilliseconds)",
        ]
        process.standardOutput = output
        process.standardError = errorPipe

        processLock.lock()
        streamProcess = process
        pipe = output
        lineBuffer = ""
        processLock.unlock()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            var linesToEmit: [String] = []
            self.processLock.lock()
            self.lineBuffer.append(chunk)
            while let newlineIndex = self.lineBuffer.firstIndex(of: "\n") {
                let line = String(self.lineBuffer[..<newlineIndex])
                let afterNewline = self.lineBuffer.index(after: newlineIndex)
                self.lineBuffer = String(self.lineBuffer[afterNewline...])
                linesToEmit.append(line)
            }
            self.processLock.unlock()
            for raw in linesToEmit {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                onLine(Self.parseLine(trimmed))
            }
        }

        process.terminationHandler = { [weak self] proc in
            self?.processLock.lock()
            self?.pipe?.fileHandleForReading.readabilityHandler = nil
            self?.lineBuffer = ""
            self?.processLock.unlock()
            if proc.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
                onLine(.failure(AdapterError.streamEndedUnexpectedly(message)))
            }
        }

        try process.run()
    }

    private static func parseLine(_ line: String) -> Result<[String: Any], Error> {
        do {
            guard let jsonData = line.data(using: .utf8) else {
                throw AdapterError.invalidJSONLine(line)
            }
            let any = try JSONSerialization.jsonObject(with: jsonData)
            guard let dict = any as? [String: Any] else {
                throw AdapterError.invalidJSONLine(line)
            }
            return .success(dict)
        } catch {
            return .failure(error)
        }
    }

    func stopStream() {
        processLock.lock()
        lineBuffer = ""
        let process = streamProcess
        let currentPipe = pipe
        streamProcess = nil
        pipe = nil
        processLock.unlock()
        currentPipe?.fileHandleForReading.readabilityHandler = nil
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        stopStream()
    }
}
