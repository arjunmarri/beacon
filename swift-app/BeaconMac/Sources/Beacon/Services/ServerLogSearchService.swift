import Foundation

public struct ServerLogSearchOptions: Sendable, Equatable {
    public var useRegex: Bool
    public var caseSensitive: Bool
    public var includeContext: Bool
    public var maxMatches: Int

    public init(
        useRegex: Bool = true,
        caseSensitive: Bool = false,
        includeContext: Bool = false,
        maxMatches: Int = 500
    ) {
        self.useRegex = useRegex
        self.caseSensitive = caseSensitive
        self.includeContext = includeContext
        self.maxMatches = maxMatches
    }
}

public struct ServerLogSearchResult: Sendable {
    public let ok: Bool
    public let query: String
    public let logPath: String
    public let commandPreview: String
    public let preformattedOutput: String
    public let matchCount: Int
    public let truncated: Bool
    public let durationMs: Int
    public let errorMessage: String?

    public init(
        ok: Bool,
        query: String,
        logPath: String,
        commandPreview: String,
        preformattedOutput: String,
        matchCount: Int,
        truncated: Bool,
        durationMs: Int,
        errorMessage: String?
    ) {
        self.ok = ok
        self.query = query
        self.logPath = logPath
        self.commandPreview = commandPreview
        self.preformattedOutput = preformattedOutput
        self.matchCount = matchCount
        self.truncated = truncated
        self.durationMs = durationMs
        self.errorMessage = errorMessage
    }
}

/// Performs safe `grep` / regex searches against `~/beaconmac/server.log`.
/// - Outside App Sandbox (`swift run`, Xcode local run, Developer ID DMG): executes `/usr/bin/grep`
///   directly via `Foundation.Process` with an explicit argument array and `--` delimiter (zero shell injection).
/// - Inside Mac App Store App Sandbox: routes through `beacon-launchd.sh grep ...` via Apple's
///   App-Sandbox-compliant `NSUserUnixTask` API, with an in-memory `NSRegularExpression` fallback.
public final class ServerLogSearchService: Sendable {
    public init() {}

    public var resolvedServerLogPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("beaconmac/server.log")
    }

    public var displayServerLogPath: String {
        "~/beaconmac/server.log"
    }

    public func commandPreview(query: String, options: ServerLogSearchOptions) -> String {
        var parts = ["grep", "-n", "-m", String(options.maxMatches)]
        parts.append(options.useRegex ? "-E" : "-F")
        if !options.caseSensitive { parts.append("-i") }
        if options.includeContext { parts.append("-C 2") }
        let safeQuoted = query.replacingOccurrences(of: "'", with: "'\\''")
        parts.append("--")
        parts.append("'\(safeQuoted)'")
        parts.append(displayServerLogPath)
        return parts.joined(separator: " ")
    }

    public func search(
        query: String,
        options: ServerLogSearchOptions,
        deploymentService: AppDeploymentService
    ) async -> ServerLogSearchResult {
        let start = Date()
        let cleanedQuery = query.replacingOccurrences(of: "\0", with: "")
        let preview = commandPreview(query: cleanedQuery, options: options)
        let logPath = resolvedServerLogPath
        let clampedMax = max(1, min(2000, options.maxMatches))
        var safeOptions = options
        safeOptions.maxMatches = clampedMax

        guard !cleanedQuery.isEmpty else {
            return ServerLogSearchResult(
                ok: false,
                query: cleanedQuery,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: "",
                matchCount: 0,
                truncated: false,
                durationMs: 0,
                errorMessage: "Enter a grep or regex pattern to search ~/beaconmac/server.log."
            )
        }

        guard cleanedQuery.count <= 500 else {
            return ServerLogSearchResult(
                ok: false,
                query: cleanedQuery,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: "",
                matchCount: 0,
                truncated: false,
                durationMs: 0,
                errorMessage: "Search pattern is too long (maximum 500 characters)."
            )
        }

        // Inside Mac App Store App Sandbox, execute via NSUserUnixTask (`beacon-launchd.sh grep ...`).
        if EmbeddedScripts.isSandboxed {
            let res = await deploymentService.grepServerLog(
                pattern: cleanedQuery,
                useRegex: safeOptions.useRegex,
                caseSensitive: safeOptions.caseSensitive,
                includeContext: safeOptions.includeContext,
                maxMatches: safeOptions.maxMatches
            )
            let elapsed = max(1, Int(Date().timeIntervalSince(start) * 1000))
            if res.ok {
                let output = res.stdoutLines.joined(separator: "\n")
                let count = Self.countMatchedLines(in: res.stdoutLines, includeContext: safeOptions.includeContext)
                return ServerLogSearchResult(
                    ok: true,
                    query: cleanedQuery,
                    logPath: displayServerLogPath,
                    commandPreview: preview,
                    preformattedOutput: output,
                    matchCount: count,
                    truncated: count >= safeOptions.maxMatches,
                    durationMs: elapsed,
                    errorMessage: nil
                )
            }

            // Fallback to direct file read if the user granted access to ~/beaconmac/server.log
            if FileManager.default.isReadableFile(atPath: logPath) {
                return searchInMemory(
                    filePath: logPath,
                    query: cleanedQuery,
                    options: safeOptions,
                    preview: preview,
                    startedAt: start
                )
            }

            return ServerLogSearchResult(
                ok: false,
                query: cleanedQuery,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: "",
                matchCount: 0,
                truncated: false,
                durationMs: elapsed,
                errorMessage: res.stderrLines.joined(separator: "\n").isEmpty
                    ? res.summary
                    : res.stderrLines.joined(separator: "\n")
            )
        }

        // Outside App Sandbox: verify log exists first so we give a crystal-clear message.
        guard FileManager.default.fileExists(atPath: logPath) else {
            let elapsed = max(1, Int(Date().timeIntervalSince(start) * 1000))
            return ServerLogSearchResult(
                ok: false,
                query: cleanedQuery,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: "",
                matchCount: 0,
                truncated: false,
                durationMs: elapsed,
                errorMessage: "Log file not found at \(displayServerLogPath). Start the launchd supervisor or deploy an app to generate server logs."
            )
        }

        // Run native `/usr/bin/grep` directly with safe argument array (no shell).
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/grep") {
            return await runNativeGrep(
                filePath: logPath,
                query: cleanedQuery,
                options: safeOptions,
                preview: preview,
                startedAt: start
            )
        }

        return searchInMemory(
            filePath: logPath,
            query: cleanedQuery,
            options: safeOptions,
            preview: preview,
            startedAt: start
        )
    }

    private func runNativeGrep(
        filePath: String,
        query: String,
        options: ServerLogSearchOptions,
        preview: String,
        startedAt: Date
    ) async -> ServerLogSearchResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")

                var args = ["-n", "-m", String(options.maxMatches)]
                args.append(options.useRegex ? "-E" : "-F")
                if !options.caseSensitive {
                    args.append("-i")
                }
                if options.includeContext {
                    args.append(contentsOf: ["-C", "2"])
                }
                args.append("--")
                args.append(query)
                args.append(filePath)
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()

                    // Drain both pipes concurrently before waitUntilExit to avoid 64KB buffer deadlocks.
                    final class LockedDataBox: @unchecked Sendable {
                        private let lock = NSLock()
                        private var storage = Data()
                        func set(_ data: Data) {
                            lock.lock()
                            storage = data
                            lock.unlock()
                        }
                        func get() -> Data {
                            lock.lock()
                            defer { lock.unlock() }
                            return storage
                        }
                    }

                    let group = DispatchGroup()
                    let outBox = LockedDataBox()
                    let errBox = LockedDataBox()

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        outBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                        group.leave()
                    }

                    process.waitUntilExit()
                    group.wait()

                    let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
                    let rawOut = SecretMasker.redact(String(data: outBox.get(), encoding: .utf8) ?? "")
                    let rawErr = SecretMasker.redact(String(data: errBox.get(), encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // BSD grep exit codes: 0 = matches found, 1 = no matches, >=2 = error
                    if process.terminationStatus == 0 || process.terminationStatus == 1 {
                        let trimmedOut = rawOut.hasSuffix("\n") ? String(rawOut.dropLast()) : rawOut
                        let lines = trimmedOut.isEmpty ? [] : trimmedOut.components(separatedBy: "\n")
                        let count = Self.countMatchedLines(in: lines, includeContext: options.includeContext)
                        continuation.resume(returning: ServerLogSearchResult(
                            ok: true,
                            query: query,
                            logPath: self.displayServerLogPath,
                            commandPreview: preview,
                            preformattedOutput: trimmedOut,
                            matchCount: count,
                            truncated: count >= options.maxMatches,
                            durationMs: elapsed,
                            errorMessage: nil
                        ))
                    } else {
                        let msg = rawErr.isEmpty ? "grep exited with status \(process.terminationStatus)." : rawErr
                        continuation.resume(returning: ServerLogSearchResult(
                            ok: false,
                            query: query,
                            logPath: self.displayServerLogPath,
                            commandPreview: preview,
                            preformattedOutput: "",
                            matchCount: 0,
                            truncated: false,
                            durationMs: elapsed,
                            errorMessage: msg
                        ))
                    }
                } catch {
                    let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
                    continuation.resume(returning: ServerLogSearchResult(
                        ok: false,
                        query: query,
                        logPath: self.displayServerLogPath,
                        commandPreview: preview,
                        preformattedOutput: "",
                        matchCount: 0,
                        truncated: false,
                        durationMs: elapsed,
                        errorMessage: SecretMasker.redact(error.localizedDescription)
                    ))
                }
            }
        }
    }

    private func searchInMemory(
        filePath: String,
        query: String,
        options: ServerLogSearchOptions,
        preview: String,
        startedAt: Date
    ) -> ServerLogSearchResult {
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            let allLines = content.components(separatedBy: .newlines)

            var regex: NSRegularExpression?
            if options.useRegex {
                let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
                regex = try NSRegularExpression(pattern: query, options: regexOptions)
            }

            var matchedIndices: [Int] = []
            for (idx, line) in allLines.enumerated() {
                let isMatch: Bool
                if let regex {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    isMatch = regex.firstMatch(in: line, options: [], range: range) != nil
                } else {
                    let compareOpts: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
                    isMatch = line.range(of: query, options: compareOpts) != nil
                }
                if isMatch {
                    matchedIndices.append(idx)
                    if matchedIndices.count >= options.maxMatches {
                        break
                    }
                }
            }

            var outputLines: [String] = []
            if options.includeContext {
                let matchSet = Set(matchedIndices)
                var included = Set<Int>()
                for idx in matchedIndices {
                    let lo = max(0, idx - 2)
                    let hi = min(allLines.count - 1, idx + 2)
                    for i in lo...hi {
                        included.insert(i)
                    }
                }
                let sorted = included.sorted()
                var prev: Int?
                for idx in sorted {
                    if let prev, idx > prev + 1 {
                        outputLines.append("--")
                    }
                    let sep = matchSet.contains(idx) ? ":" : "-"
                    outputLines.append("\(idx + 1)\(sep)\(SecretMasker.redact(allLines[idx]))")
                    prev = idx
                }
            } else {
                for idx in matchedIndices {
                    outputLines.append("\(idx + 1):\(SecretMasker.redact(allLines[idx]))")
                }
            }

            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            return ServerLogSearchResult(
                ok: true,
                query: query,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: outputLines.joined(separator: "\n"),
                matchCount: matchedIndices.count,
                truncated: matchedIndices.count >= options.maxMatches,
                durationMs: elapsed,
                errorMessage: nil
            )
        } catch {
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            return ServerLogSearchResult(
                ok: false,
                query: query,
                logPath: displayServerLogPath,
                commandPreview: preview,
                preformattedOutput: "",
                matchCount: 0,
                truncated: false,
                durationMs: elapsed,
                errorMessage: SecretMasker.redact(error.localizedDescription)
            )
        }
    }

    private static func countMatchedLines(in lines: [String], includeContext: Bool) -> Int {
        guard !lines.isEmpty else { return 0 }
        if !includeContext {
            return lines.count
        }
        // With `grep -n -C 2`, match lines have `<digits>:` whereas context lines have `<digits>-` and group breaks are `--`.
        return lines.reduce(0) { acc, line in
            guard line != "--" else { return acc }
            var idx = line.startIndex
            while idx < line.endIndex, line[idx].isNumber {
                idx = line.index(after: idx)
            }
            if idx > line.startIndex, idx < line.endIndex, line[idx] == ":" {
                return acc + 1
            }
            return acc
        }
    }
}
