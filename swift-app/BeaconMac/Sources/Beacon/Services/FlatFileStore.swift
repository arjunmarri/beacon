import Foundation

/// Flat-file storage for activity.log and config.json inside the app's
/// sandboxed Application Support container (zero database).
public final class FlatFileStore {
    public let dataDirectoryURL: URL
    public let logFileURL: URL
    public let configFileURL: URL

    private let maxLogBytes: UInt64 = 2 * 1024 * 1024
    private let isoFormatter: ISO8601DateFormatter

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.dataDirectoryURL = appSupport.appendingPathComponent("Beacon", isDirectory: true)
        self.logFileURL = dataDirectoryURL.appendingPathComponent("activity.log")
        self.configFileURL = dataDirectoryURL.appendingPathComponent("config.json")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter

        try? FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: Data())
        }
    }

    public func loadConfig() -> BeaconConfig {
        guard let data = try? Data(contentsOf: configFileURL),
              let decoded = try? JSONDecoder().decode(BeaconConfig.self, from: data) else {
            let defaults = BeaconConfig.defaults
            saveConfig(defaults)
            return defaults
        }
        return decoded
    }

    public func saveConfig(_ config: BeaconConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configFileURL, options: .atomic)
    }

    public func loadRecentLogs(limit: Int = 400) -> [LogEntry] {
        guard let raw = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        let tail = lines.suffix(limit)
        return tail.enumerated().map { idx, line in
            parseLine(String(line), index: idx)
        }
    }

    @discardableResult
    public func appendLog(source: LogSource, level: LogLevel, message: String) -> LogEntry {
        let sanitized = SecretMasker.redact(message)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let clipped = String(sanitized.prefix(1200))
        let entry = LogEntry(source: source, level: level, message: clipped)

        let line = "\(isoFormatter.string(from: entry.timestamp)) [\(level.rawValue.uppercased())] [\(source.rawValue.uppercased())] \(clipped)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
        rotateLogIfNeeded()
        return entry
    }

    public func clearLogs() {
        try? Data().write(to: logFileURL, options: .atomic)
    }

    public func logFileByteCount() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private func rotateLogIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxLogBytes,
              let raw = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return
        }
        let kept = raw.split(separator: "\n", omittingEmptySubsequences: true).suffix(500).joined(separator: "\n") + "\n"
        try? kept.data(using: .utf8)?.write(to: logFileURL, options: .atomic)
    }

    private func parseLine(_ line: String, index: Int) -> LogEntry {
        // Format: <ISO8601> [LEVEL] [SOURCE] Message
        let pattern = #"^(\S+)\s+\[(INFO|WARN|ERROR)\]\s+\[(VITE|GIT|OLLAMA|CLAUDE|TERMINAL|STARTUP|EMAIL|SYSTEM)\]\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              match.numberOfRanges == 5,
              let tsRange = Range(match.range(at: 1), in: line),
              let lvlRange = Range(match.range(at: 2), in: line),
              let srcRange = Range(match.range(at: 3), in: line),
              let msgRange = Range(match.range(at: 4), in: line) else {
            return LogEntry(id: "line-\(index)", source: .system, level: .info, message: line)
        }

        let timestamp = isoFormatter.date(from: String(line[tsRange])) ?? Date()
        let level = LogLevel(rawValue: String(line[lvlRange]).lowercased()) ?? .info
        let source = LogSource(rawValue: String(line[srcRange]).lowercased()) ?? .system
        let message = String(line[msgRange])
        return LogEntry(id: "\(line[tsRange])-\(index)", timestamp: timestamp, source: source, level: level, message: message)
    }
}
