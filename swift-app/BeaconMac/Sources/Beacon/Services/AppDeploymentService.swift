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

        for line in res.stdoutLines {
            let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 4 && parts[0] == "TOOL" {
                tools.append(DependencyToolStatus(
                    name: parts[1],
                    available: parts[2] == "OK",
                    detail: parts[3]
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

    public func stopApp(port: Int) async -> ScriptExecutionResult {
        await runUnixScript(named: "beacon-stop.sh", arguments: [String(port)])
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

    private func runUnixScript(named scriptName: String, arguments: [String]) async -> ScriptExecutionResult {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.beaconmac.app"
        guard let scriptsDir = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: ["Application Scripts directory unavailable."],
                summary: "Application Scripts directory unavailable."
            )
        }

        let scriptURL = scriptsDir.appendingPathComponent(scriptName)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            let hint = "Missing \(scriptName). Run ./Scripts/install-sandbox-scripts.sh \(bundleID) in Terminal to install BeaconMac's App Sandbox hook scripts."
            return ScriptExecutionResult(
                ok: false,
                stdoutLines: [],
                stderrLines: [hint],
                summary: hint
            )
        }

        do {
            let task = try NSUserUnixTask(url: scriptURL)
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe.fileHandleForWriting
            task.standardError = stderrPipe.fileHandleForWriting

            let executionError: Error? = await withCheckedContinuation { continuation in
                task.execute(withArguments: arguments) { error in
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    continuation.resume(returning: error)
                }
            }

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
}
