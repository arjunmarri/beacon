import Foundation
import UniformTypeIdentifiers

public enum LogExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt
    case json

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .txt: return "Plain Text (.txt)"
        case .json: return "JSON (.json)"
        }
    }

    public var utType: UTType {
        switch self {
        case .txt: return .plainText
        case .json: return .json
        }
    }
}

public struct SessionLogExportBundle: Codable, Sendable {
    public struct Metadata: Codable, Sendable {
        public let exportedAt: Date
        public let appVersion: String
        public let appBuild: String
        public let macOSVersion: String
        public let architecture: String
        public let sandboxed: Bool
        public let aggregateStatus: String
        public let scope: String
        public let counts: Counts
    }

    public struct Counts: Codable, Sendable {
        public let totalActivityLogs: Int
        public let systemLogs: Int
        public let gitLogs: Int
        public let deploymentOutputLines: Int
        public let deploymentErrorLines: Int
        public let managedApps: Int
    }

    public struct ServicesSnapshot: Codable, Sendable {
        public let gitStatus: String
        public let gitAccount: String?
        public let gitRepoCount: Int
        public let gitLastError: String?
        public let ollamaEndpoint: String
        public let ollamaStatus: String
        public let ollamaActiveModel: String
        public let claudeStatus: String
        public let claudeConfigured: Bool
        public let launchdLoaded: Bool
        public let launchdStatus: String
    }

    public struct ToolSnapshot: Codable, Sendable {
        public let name: String
        public let available: Bool
        public let detail: String
        public let isOptional: Bool
    }

    public struct ManagedAppSnapshot: Codable, Sendable {
        public let name: String
        public let stackPreset: String
        public let branch: String
        public let port: Int
        public let monitorURL: String
        public let light: String
        public let statusLabel: String
        public let isHealthy: Bool
        public let httpStatus: Int?
        public let commitHash: String
        public let dependencySummary: String
        public let lastError: String?
    }

    public struct ExportedActivityLog: Codable, Sendable {
        public let id: String
        public let timestamp: Date
        public let source: String
        public let level: String
        public let message: String
    }

    public struct ExportedDeploymentLine: Codable, Sendable {
        public let id: String
        public let timestamp: Date
        public let appName: String
        public let stream: String
        public let isError: Bool
        public let text: String
    }

    public let metadata: Metadata
    public let services: ServicesSnapshot
    public let systemTools: [ToolSnapshot]
    public let managedApps: [ManagedAppSnapshot]
    public let activityLogs: [ExportedActivityLog]
    public let deploymentOutput: [ExportedDeploymentLine]
}

public enum LogExportService {
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    public static func suggestedFilename(format: LogExportFormat, filtered: Bool = false) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = df.string(from: Date())
        let prefix = filtered ? "beaconmac-filtered-logs" : "beaconmac-session-logs"
        return "\(prefix)-\(stamp).\(format.fileExtension)"
    }

    @MainActor
    public static func buildBundle(
        from controller: BeaconController,
        activityLogs: [LogEntry]? = nil,
        terminalLines: [TerminalOutputLine]? = nil,
        scopeDescription: String = "All Current Session Logs (System, Git, Services & Deployment Output)"
    ) -> SessionLogExportBundle {
        let sourceLogs = activityLogs ?? controller.logs
        let sourceTerminal = terminalLines ?? controller.terminalLines

        let exportedLogs = sourceLogs.map { entry in
            SessionLogExportBundle.ExportedActivityLog(
                id: entry.id,
                timestamp: entry.timestamp,
                source: entry.source.rawValue,
                level: entry.level.rawValue,
                message: SecretMasker.redact(entry.message)
            )
        }

        let exportedTerminal = sourceTerminal.map { line in
            SessionLogExportBundle.ExportedDeploymentLine(
                id: line.id,
                timestamp: line.timestamp,
                appName: line.appName,
                stream: line.isError ? "stderr" : "stdout",
                isError: line.isError,
                text: SecretMasker.redact(line.text)
            )
        }

        let systemCount = sourceLogs.filter { $0.source == .system }.count
        let gitCount = sourceLogs.filter { $0.source == .git }.count
        let deployErrorCount = sourceTerminal.filter { $0.isError }.count

        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appBuild = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let metadata = SessionLogExportBundle.Metadata(
            exportedAt: Date(),
            appVersion: (appVersion?.isEmpty == false) ? appVersion! : "1.1.0",
            appBuild: (appBuild?.isEmpty == false) ? appBuild! : "2",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            sandboxed: EmbeddedScripts.isSandboxed,
            aggregateStatus: controller.aggregateLight.rawValue,
            scope: scopeDescription,
            counts: SessionLogExportBundle.Counts(
                totalActivityLogs: exportedLogs.count,
                systemLogs: systemCount,
                gitLogs: gitCount,
                deploymentOutputLines: exportedTerminal.count,
                deploymentErrorLines: deployErrorCount,
                managedApps: controller.config.managedApps.count
            )
        )

        let services = SessionLogExportBundle.ServicesSnapshot(
            gitStatus: SecretMasker.redact(controller.git.statusLabel),
            gitAccount: controller.git.connectedUsername,
            gitRepoCount: controller.git.repos.count,
            gitLastError: controller.git.lastError.map { SecretMasker.redact($0) },
            ollamaEndpoint: controller.ollama.endpoint,
            ollamaStatus: SecretMasker.redact(controller.ollama.statusLabel),
            ollamaActiveModel: controller.ollama.activeModel,
            claudeStatus: SecretMasker.redact(controller.claude.statusLabel),
            claudeConfigured: controller.claude.keyHint != nil,
            launchdLoaded: controller.launchd.isLoaded,
            launchdStatus: controller.launchd.statusLabel
        )

        let tools = controller.systemTools.map { tool in
            SessionLogExportBundle.ToolSnapshot(
                name: tool.name,
                available: tool.available,
                detail: SecretMasker.redact(tool.detail),
                isOptional: tool.isOptional
            )
        }

        let apps = controller.config.managedApps.map { app in
            let state = controller.runtimeState(for: app.id)
            return SessionLogExportBundle.ManagedAppSnapshot(
                name: app.name,
                stackPreset: app.stackPreset.rawValue,
                branch: app.branch,
                port: app.port,
                monitorURL: app.monitorURL,
                light: state.light.rawValue,
                statusLabel: state.statusLabel,
                isHealthy: state.isHealthy,
                httpStatus: state.httpStatus,
                commitHash: state.commitHash,
                dependencySummary: SecretMasker.redact(state.dependencySummary),
                lastError: state.lastError.map { SecretMasker.redact($0) }
            )
        }

        return SessionLogExportBundle(
            metadata: metadata,
            services: services,
            systemTools: tools,
            managedApps: apps,
            activityLogs: exportedLogs,
            deploymentOutput: exportedTerminal
        )
    }

    public static func render(bundle: SessionLogExportBundle, format: LogExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(bundle)

        case .txt:
            let text = renderPlainText(bundle: bundle)
            return Data(text.utf8)
        }
    }

    public static func renderPlainText(bundle: SessionLogExportBundle) -> String {
        let iso = makeISOFormatter()
        var lines: [String] = []
        let rule = String(repeating: "=", count: 74)
        let subRule = String(repeating: "-", count: 74)

        lines.append(rule)
        lines.append("BeaconMac Session Debug Log Export")
        lines.append(rule)
        lines.append("Exported At  : \(iso.string(from: bundle.metadata.exportedAt))")
        lines.append("App Version  : \(bundle.metadata.appVersion) (build \(bundle.metadata.appBuild))")
        lines.append("macOS        : \(bundle.metadata.macOSVersion) (\(bundle.metadata.architecture))")
        lines.append("App Sandbox  : \(bundle.metadata.sandboxed ? "Enabled" : "Disabled (DMG / Local)")")
        lines.append("Status Light : \(bundle.metadata.aggregateStatus.uppercased())")
        lines.append("Scope        : \(bundle.metadata.scope)")
        lines.append(
            "Counts       : \(bundle.metadata.counts.totalActivityLogs) activity log(s) "
            + "(\(bundle.metadata.counts.systemLogs) system, \(bundle.metadata.counts.gitLogs) git) · "
            + "\(bundle.metadata.counts.deploymentOutputLines) deployment/terminal line(s) "
            + "(\(bundle.metadata.counts.deploymentErrorLines) error) · "
            + "\(bundle.metadata.counts.managedApps) managed app(s)"
        )
        lines.append("")

        lines.append(subRule)
        lines.append("SERVICES & ENVIRONMENT SNAPSHOT")
        lines.append(subRule)
        let gitAcct = bundle.services.gitAccount.map { " (@\($0))" } ?? ""
        lines.append("GitHub / Git : \(bundle.services.gitStatus)\(gitAcct) · \(bundle.services.gitRepoCount) repo(s)")
        if let gitErr = bundle.services.gitLastError, !gitErr.isEmpty {
            lines.append("  Last Error : \(gitErr)")
        }
        let modelNote = bundle.services.ollamaActiveModel.isEmpty ? "" : " · model: \(bundle.services.ollamaActiveModel)"
        lines.append("Ollama       : \(bundle.services.ollamaStatus) (\(bundle.services.ollamaEndpoint)\(modelNote))")
        lines.append("Claude API   : \(bundle.services.claudeStatus) (configured: \(bundle.services.claudeConfigured ? "yes" : "no"))")
        lines.append("launchd      : \(bundle.services.launchdStatus) (loaded: \(bundle.services.launchdLoaded ? "yes" : "no"))")

        if !bundle.systemTools.isEmpty {
            let toolSummary = bundle.systemTools.map { t in
                "\(t.name)=\(t.available ? "OK" : (t.isOptional ? "OPTIONAL" : "MISSING"))"
            }.joined(separator: ", ")
            lines.append("CLI Tools    : \(toolSummary)")
        }

        if !bundle.managedApps.isEmpty {
            lines.append("Managed Apps :")
            for app in bundle.managedApps {
                let httpPart = app.httpStatus.map { " HTTP \($0)" } ?? ""
                lines.append("  - \(app.name) [\(app.light.uppercased())] \(app.monitorURL) (preset: \(app.stackPreset), branch: \(app.branch), sha: \(app.commitHash)\(httpPart)) — \(app.statusLabel)")
                lines.append("    Deps: \(app.dependencySummary)")
                if let err = app.lastError, !err.isEmpty {
                    lines.append("    Last Error: \(err)")
                }
            }
        }
        lines.append("")

        lines.append(subRule)
        lines.append("ACTIVITY LOGS (System, Git, Local Apps, Services, Startup & Alerts)")
        lines.append(subRule)
        if bundle.activityLogs.isEmpty {
            lines.append("(No activity log entries in current session)")
        } else {
            for entry in bundle.activityLogs {
                let ts = iso.string(from: entry.timestamp)
                let lvl = entry.level.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)
                let src = entry.source.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
                lines.append("\(ts) [\(lvl)] [\(src)] \(entry.message)")
            }
        }
        lines.append("")

        lines.append(subRule)
        lines.append("DEPLOYMENT & TERMINAL OUTPUT (git clone/pull, installs, builds & deploys)")
        lines.append(subRule)
        if bundle.deploymentOutput.isEmpty {
            lines.append("(No deployment or terminal output captured in current session)")
        } else {
            for line in bundle.deploymentOutput {
                let ts = iso.string(from: line.timestamp)
                let streamTag = line.isError ? "STDERR" : "STDOUT"
                lines.append("\(ts) [\(streamTag)] [\(line.appName)] \(line.text)")
            }
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
