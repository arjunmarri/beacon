import Foundation

public struct ScriptExecutionResult: Sendable {
    public let ok: Bool
    public let stdoutLines: [String]
    public let stderrLines: [String]
    public let summary: String
}

/// Executes App-Sandbox-compliant NSUserUnixTask deployment, dependency-audit,
/// restart, and stop scripts while streaming stdout/stderr back to BeaconMac's
/// integrated terminal console.
public final class AppDeploymentService: Sendable {
    public init() {}

    public static func isValidRepoURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5, trimmed.count <= 300, !trimmed.hasPrefix("-") else {
            return false
        }
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("git@") {
            return !trimmed.contains(where: \.isWhitespace)
        }
        return false
    }

    public static func isValidBranch(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.hasPrefix("-"), !trimmed.contains("..") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public func deployApp(_ app: ManagedApp) async -> ScriptExecutionResult {
        let trimmedPath = app.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: ["Local folder path is required before cloning or deploying."],
                summary: "Local folder path missing."
            )
        }
        if !app.repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.isValidRepoURL(app.repoURL) {
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: ["Invalid Git repository URL. Use https://... or git@..."],
                summary: "Invalid repository URL."
            )
        }
        guard Self.isValidBranch(app.branch) else {
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: ["Invalid Git branch name."],
                summary: "Invalid branch name."
            )
        }

        let args = [
            app.repoURL.trimmingCharacters(in: .whitespacesAndNewlines),
            app.branch.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmedPath,
            String(app.port),
            app.installCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : app.installCommand,
            app.buildCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            app.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        return await runUnixScript(named: "beacon-deploy.sh", arguments: args)
    }

    public func checkDependencies(for workingDir: String?) async -> (result: ScriptExecutionResult, tools: [DependencyToolStatus], appSummary: String) {
        let args = workingDir.map { [$0] } ?? []
        let res = await runUnixScript(named: "beacon-check-deps.sh", arguments: args)
        var tools: [DependencyToolStatus] = []
        var appNotes: [String] = []

        let optionalToolNames: Set<String> = ["pnpm", "yarn", "bun", "python3", "uv", "go", "cloudflared"]

        for line in res.stdoutLines {
            let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 4 && parts[0] == "TOOL" {
                let name = parts[1]
                let status = parts[2]
                tools.append(DependencyToolStatus(
                    name: name,
                    available: status == "OK",
                    detail: parts[3],
                    isOptional: status == "OPTIONAL" || optionalToolNames.contains(name)
                ))
            } else if parts.count == 4 && parts[0] == "APP" {
                appNotes.append("\(parts[1].lowercased()): \(parts[3])")
            }
        }

        let summary = appNotes.isEmpty
            ? (res.ok ? "Environment audited" : res.summary)
            : appNotes.joined(separator: " · ")
        return (res, tools, summary)
    }

    public func installPrerequisitesAndDependencies(
        workingDir: String?,
        requestedTools: [String],
        strategy: DependencyInstallStrategy = .auto
    ) async -> ScriptExecutionResult {
        let allowedTools: Set<String> = ["node", "npm", "pnpm", "yarn", "bun", "python3", "uv", "go", "cargo", "rust", "git", "cloudflared"]
        let safeTools = requestedTools
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { allowedTools.contains($0) }
        let toolsArg = safeTools.isEmpty ? "auto" : safeTools.joined(separator: ",")
        let dirArg = workingDir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await runUnixScript(
            named: "beacon-check-deps.sh",
            arguments: ["--install", dirArg, toolsArg, strategy.rawValue]
        )
    }

    public func restartApp(_ app: ManagedApp) async -> ScriptExecutionResult {
        let trimmedPath = app.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: ["Set Local Folder for \(app.name) before restarting."],
                summary: "Local folder missing."
            )
        }
        var args = [trimmedPath, String(app.port)]
        let start = app.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !start.isEmpty {
            args.append(start)
        }
        return await runUnixScript(named: "beacon-restart.sh", arguments: args)
    }

    public func stopApp(port: Int, workingDir: String = "") async -> ScriptExecutionResult {
        var args = [String(port)]
        let trimmed = workingDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            args.append(trimmed)
        }
        return await runUnixScript(named: "beacon-stop.sh", arguments: args)
    }

    public struct LaunchdProbeResult: Sendable {
        public let result: ScriptExecutionResult
        public let isInstalled: Bool?
        public let isLoaded: Bool?
        public let pidText: String?
        public let caffeinateActive: Bool?
        public let plistPath: String?
        public let serverLogPath: String?
    }

    public func runLaunchdAction(
        _ action: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.beaconmac.app",
        preventSleep: Bool = true
    ) async -> LaunchdProbeResult {
        let res = await runUnixScript(
            named: "beacon-launchd.sh",
            arguments: [action, bundleID, preventSleep ? "1" : "0"]
        )
        var installed: Bool?
        var loaded: Bool?
        var pidText: String?
        var caffeinateActive: Bool?
        var plistPath: String?
        var serverLogPath: String?

        for line in res.stdoutLines {
            let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, parts[0] == "LAUNCHD" else { continue }
            switch parts[1] {
            case "INSTALLED":
                installed = (parts[2] == "YES")
                plistPath = parts[3]
            case "LOADED":
                loaded = (parts[2] == "YES")
                pidText = parts[3]
            case "CAFFEINATE":
                caffeinateActive = (parts[2] == "YES")
            case "LOG":
                serverLogPath = parts[3]
            default:
                break
            }
        }

        return LaunchdProbeResult(
            result: res,
            isInstalled: installed,
            isLoaded: loaded,
            pidText: pidText,
            caffeinateActive: caffeinateActive,
            plistPath: plistPath,
            serverLogPath: serverLogPath
        )
    }

    public func grepServerLog(
        pattern: String,
        useRegex: Bool,
        caseSensitive: Bool,
        includeContext: Bool,
        maxMatches: Int
    ) async -> ScriptExecutionResult {
        await runUnixScript(
            named: "beacon-launchd.sh",
            arguments: [
                "grep",
                pattern,
                useRegex ? "E" : "F",
                caseSensitive ? "s" : "i",
                includeContext ? "2" : "0",
                String(maxMatches)
            ]
        )
    }

    public func runBuiltInNodeServerAction(
        _ action: String,
        port: Int,
        registryPath: String
    ) async -> ScriptExecutionResult {
        await runUnixScript(
            named: "beacon-node-server.sh",
            arguments: [action, String(port), registryPath]
        )
    }

    public struct CloudflareTunnelScriptEntry: Sendable {
        public let tunnelID: String
        public let pid: Int
        public let publicURL: String?
        public let targetURL: String?
        public let mode: CloudflareTunnelMode
    }

    public struct CloudflareTunnelProbeResult: Sendable {
        public let result: ScriptExecutionResult
        public let isInstalled: Bool?
        public let version: String?
        public let isRunning: Bool?
        public let pid: Int?
        public let publicURL: String?
        public let entries: [CloudflareTunnelScriptEntry]
    }

    public func runCloudflaredAction(
        _ action: String,
        tunnelID: String = "all",
        extraArgs: [String] = []
    ) async -> CloudflareTunnelProbeResult {
        var args: [String] = [action, tunnelID]
        args.append(contentsOf: extraArgs)
        let res = await runUnixScript(
            named: "beacon-cloudflared.sh",
            arguments: args
        )

        var installed: Bool?
        var version: String?
        var running: Bool?
        var pid: Int?
        var publicURL: String?
        var entries: [CloudflareTunnelScriptEntry] = []

        for line in res.stdoutLines {
            if line.hasPrefix("CLOUDFLARED:INSTALLED:") {
                let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                if parts.count == 4 {
                    installed = (parts[2] == "YES")
                    if parts[2] == "YES" {
                        version = parts[3]
                    }
                }
            } else if line.hasPrefix("TUNNEL:RUNNING:") {
                let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                if parts.count >= 4 {
                    running = (parts[2] == "YES")
                    if parts[2] == "YES" {
                        pid = Int(parts[3].trimmingCharacters(in: .whitespacesAndNewlines))
                        if parts.count >= 5 {
                            let urlCandidate = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
                            if urlCandidate.hasPrefix("https://") {
                                publicURL = urlCandidate
                            }
                        }
                    }
                }
            } else if line.hasPrefix("TUNNEL:ENTRY:") {
                // Format: TUNNEL:ENTRY:<tid>:<pid>:<pub_url>|<tgt_url>|<mode>
                let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                if parts.count == 5, let parsedPID = Int(parts[3].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let tid = parts[2]
                    let payload = parts[4].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    let pub = payload.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let tgt = payload.count > 1 ? payload[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    let rawMode = payload.count > 2 ? payload[2].trimmingCharacters(in: .whitespacesAndNewlines) : "quick"
                    let mode: CloudflareTunnelMode = (rawMode == "api") ? .apiManaged : .quickTunnel
                    entries.append(CloudflareTunnelScriptEntry(
                        tunnelID: tid,
                        pid: parsedPID,
                        publicURL: (pub?.hasPrefix("https://") == true) ? pub : nil,
                        targetURL: (tgt?.isEmpty == false) ? tgt : nil,
                        mode: mode
                    ))
                }
            }
        }

        return CloudflareTunnelProbeResult(
            result: res,
            isInstalled: installed,
            version: version,
            isRunning: running,
            pid: pid,
            publicURL: publicURL,
            entries: entries
        )
    }

    private func runUnixScript(named scriptName: String, arguments: [String]) async -> ScriptExecutionResult {
        let primaryDir = EmbeddedScripts.targetScriptsDirectoryURL()

        // Outside the App Sandbox (swift run, local builds, Developer ID DMG), auto-install embedded
        // scripts and execute directly via Foundation.Process.
        if !EmbeddedScripts.isSandboxed {
            EmbeddedScripts.autoInstallIfNotSandboxed()

            let primaryScript = primaryDir.appendingPathComponent(scriptName)
            let fallbackScript = EmbeddedScripts.fallbackScriptsDirectoryURL().appendingPathComponent(scriptName)
            let appSupportScript = EmbeddedScripts.appSupportScriptsDirectoryURL().appendingPathComponent(scriptName)

            let resolvedScript: URL?
            if FileManager.default.fileExists(atPath: primaryScript.path) {
                resolvedScript = primaryScript
            } else if FileManager.default.fileExists(atPath: fallbackScript.path) {
                resolvedScript = fallbackScript
            } else if FileManager.default.fileExists(atPath: appSupportScript.path) {
                resolvedScript = appSupportScript
            } else {
                resolvedScript = nil
            }

            guard let scriptURL = resolvedScript else {
                let hint = "Missing \(scriptName) in \(primaryDir.path). Click \"Install Hook Scripts\" at the top of BeaconMac or run: \(EmbeddedScripts.terminalInstallOneLiner)"
                return ScriptExecutionResult(
                    ok: false,
                    stdoutLines: [],
                    stderrLines: [hint],
                    summary: hint
                )
            }

            return await runViaProcess(scriptURL: scriptURL, scriptName: scriptName, arguments: arguments)
        }

        // Inside the Mac App Store App Sandbox:
        // 1. NEVER gate on FileManager.fileExists(atPath:) — App Sandbox denies POSIX stat() on
        //    ~/Library/Application Scripts/<bundle-id>/. Pass the URL directly to NSUserUnixTask.
        // 2. Capture stdout/stderr via real temporary FileHandles inside the app container's
        //    temporaryDirectory instead of Pipe() — prevents macOS XPC UserScriptService
        //    "Bad file descriptor" (EBADF) errors and avoids 64KB pipe buffer deadlocks.
        let scriptURL = primaryDir.appendingPathComponent(scriptName)
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: scriptURL)
        } catch {
            let nsErr = error as NSError
            let isMissing = nsErr.domain == NSCocoaErrorDomain && (
                nsErr.code == NSFileReadNoSuchFileError ||
                nsErr.code == NSFileNoSuchFileError
            )
            let msg = isMissing
                ? "Missing \(scriptName) in \(primaryDir.path). Click \"Install Hook Scripts\" at the top of BeaconMac or run: \(EmbeddedScripts.terminalInstallOneLiner)"
                : "\(scriptName) could not be prepared: \(SecretMasker.redact(error.localizedDescription))"
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: [msg],
                summary: msg
            )
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let runID = UUID().uuidString
        let outURL = tmpDir.appendingPathComponent("beacon-stdout-\(runID).log")
        let errURL = tmpDir.appendingPathComponent("beacon-stderr-\(runID).log")

        guard FileManager.default.createFile(atPath: outURL.path, contents: Data()),
              FileManager.default.createFile(atPath: errURL.path, contents: Data()) else {
            let msg = "Unable to create temporary output files for \(scriptName)."
            return ScriptExecutionResult(ok: false, stdoutLines: [], stderrLines: [msg], summary: msg)
        }
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        do {
            let outHandle = try FileHandle(forWritingTo: outURL)
            let errHandle = try FileHandle(forWritingTo: errURL)

            task.standardOutput = outHandle
            task.standardError = errHandle

            let executionError: Error? = await withCheckedContinuation { continuation in
                task.execute(withArguments: arguments) { error in
                    continuation.resume(returning: error)
                }
            }

            // Flush & close handles only AFTER UserScriptService finishes executing.
            try? outHandle.synchronize()
            try? errHandle.synchronize()
            try? outHandle.close()
            try? errHandle.close()

            let outData = (try? Data(contentsOf: outURL)) ?? Data()
            let errData = (try? Data(contentsOf: errURL)) ?? Data()
            let stdoutLines = (String(data: outData, encoding: .utf8) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { SecretMasker.redact(String($0)) }
            var stderrLines = (String(data: errData, encoding: .utf8) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { SecretMasker.redact(String($0)) }

            if let executionError {
                let errMsg = SecretMasker.redact(executionError.localizedDescription)
                if stderrLines.isEmpty {
                    stderrLines.append(errMsg)
                }
                return ScriptExecutionResult(
                    ok: false,
                    stdoutLines: stdoutLines,
                    stderrLines: stderrLines,
                    summary: stderrLines.last ?? "\(scriptName) failed: \(errMsg)"
                )
            }

            return ScriptExecutionResult(
                ok: true,
                stdoutLines: stdoutLines,
                stderrLines: stderrLines,
                summary: stdoutLines.last ?? "\(scriptName) completed."
            )
        } catch {
            let errMsg = SecretMasker.redact(error.localizedDescription)
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: [errMsg],
                summary: "\(scriptName) failed: \(errMsg)"
            )
        }
    }

    private func runViaProcess(scriptURL: URL, scriptName: String, arguments: [String]) async -> ScriptExecutionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptURL.path] + arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()

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

                    let stdoutLines = (String(data: outBox.get(), encoding: .utf8) ?? "")
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .map { SecretMasker.redact(String($0)) }
                    var stderrLines = (String(data: errBox.get(), encoding: .utf8) ?? "")
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .map { SecretMasker.redact(String($0)) }

                    if process.terminationStatus != 0 {
                        if stderrLines.isEmpty {
                            stderrLines.append("\(scriptName) exited with code \(process.terminationStatus).")
                        }
                        continuation.resume(returning: ScriptExecutionResult(
                            ok: false,
                            stdoutLines: stdoutLines,
                            stderrLines: stderrLines,
                            summary: stderrLines.last ?? "\(scriptName) failed (exit \(process.terminationStatus))."
                        ))
                    } else {
                        continuation.resume(returning: ScriptExecutionResult(
                            ok: true,
                            stdoutLines: stdoutLines,
                            stderrLines: stderrLines,
                            summary: stdoutLines.last ?? "\(scriptName) completed."
                        ))
                    }
                } catch {
                    let errMsg = SecretMasker.redact(error.localizedDescription)
                    continuation.resume(returning: ScriptExecutionResult(
                        ok: false,
                        stdoutLines: [],
                        stderrLines: [errMsg],
                        summary: "\(scriptName) failed: \(errMsg)"
                    ))
                }
            }
        }
    }
}
