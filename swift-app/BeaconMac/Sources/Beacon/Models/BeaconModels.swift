import Foundation

public enum TrafficLightColor: String, Codable, Sendable {
    case green
    case amber
    case red
}

public enum LogSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case vite
    case git
    case ollama
    case claude
    case terminal
    case startup
    case email
    case system

    public var id: String { rawValue }

    public var label: String { rawValue }
}

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case info
    case warn
    case error
}

public struct LogEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let source: LogSource
    public let level: LogLevel
    public let message: String

    public init(id: String = UUID().uuidString, timestamp: Date = Date(), source: LogSource, level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.message = message
    }
}

public enum AppStackPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case vite = "Vite + Node"
    case nodeServer = "Node.js Server"
    case nextjs = "Next.js"
    case custom = "Custom"

    public var id: String { rawValue }

    public var defaultInstallCommand: String { "auto" }

    public var defaultBuildCommand: String {
        switch self {
        case .vite: return "npm run build"
        case .nodeServer: return ""
        case .nextjs: return "npm run build"
        case .custom: return ""
        }
    }

    public func defaultStartCommand(port: Int) -> String {
        switch self {
        case .vite: return "npm run dev -- --port \(port)"
        case .nodeServer: return "npm start"
        case .nextjs: return "npm run dev -- -p \(port)"
        case .custom: return ""
        }
    }
}

public struct ManagedApp: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var stackPreset: AppStackPreset
    public var repoURL: String
    public var branch: String
    public var localPath: String
    public var monitorURL: String
    public var port: Int
    public var installCommand: String
    public var buildCommand: String
    public var startCommand: String
    public var autoRestart: Bool
    public var autoDeploy: Bool
    public var runOnStartup: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        stackPreset: AppStackPreset = .vite,
        repoURL: String = "",
        branch: String = "main",
        localPath: String = "",
        monitorURL: String = "http://localhost:5173",
        port: Int = 5173,
        installCommand: String = "auto",
        buildCommand: String = "npm run build",
        startCommand: String = "npm run dev -- --port 5173",
        autoRestart: Bool = true,
        autoDeploy: Bool = true,
        runOnStartup: Bool = false
    ) {
        self.id = id
        self.name = name
        self.stackPreset = stackPreset
        self.repoURL = repoURL
        self.branch = branch
        self.localPath = localPath
        self.monitorURL = monitorURL
        self.port = port
        self.installCommand = installCommand
        self.buildCommand = buildCommand
        self.startCommand = startCommand
        self.autoRestart = autoRestart
        self.autoDeploy = autoDeploy
        self.runOnStartup = runOnStartup
    }

    /// Extracts `owner/repo` from GitHub HTTPS or SSH URLs when available.
    public var githubFullName: String? {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: "github.com/") {
            let suffix = String(trimmed[range.upperBound...])
            return suffix.hasSuffix(".git") ? String(suffix.dropLast(4)) : suffix
        }
        if let range = trimmed.range(of: "github.com:") {
            let suffix = String(trimmed[range.upperBound...])
            return suffix.hasSuffix(".git") ? String(suffix.dropLast(4)) : suffix
        }
        return nil
    }
}

public struct ManagedAppRuntimeState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Idle"
    public var httpStatus: Int?
    public var responseTimeMs: Int?
    public var isHealthy: Bool = false
    public var isDeploying: Bool = false
    public var restartCount: Int = 0
    public var consecutiveFailures: Int = 0
    public var commitHash: String = "—"
    public var commitMessage: String = ""
    public var dependencySummary: String = "Not checked"
    public var lastCheckedAt: Date?
    public var lastDeployedAt: Date?
    public var lastError: String?
    public var healthySince: Date?

    public var uptimeSeconds: Int {
        guard isHealthy, let since = healthySince else { return 0 }
        return max(0, Int(Date().timeIntervalSince(since)))
    }
}

public struct DependencyToolStatus: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let available: Bool
    public let detail: String
}

public struct TerminalOutputLine: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let appName: String
    public let text: String
    public let isError: Bool

    public init(appName: String, text: String, isError: Bool = false) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.appName = appName
        self.text = SecretMasker.redact(text)
        self.isError = isError
    }
}

public struct StartupScheduleConfig: Codable, Sendable {
    public var launchAtLogin: Bool = false
    public var autoDeployOnStartup: Bool = false
    public var preventSleep: Bool = true
    public var cronEnabled: Bool = false
    public var cronExpression: String = "@reboot"

    public init(
        launchAtLogin: Bool = false,
        autoDeployOnStartup: Bool = false,
        preventSleep: Bool = true,
        cronEnabled: Bool = false,
        cronExpression: String = "@reboot"
    ) {
        self.launchAtLogin = launchAtLogin
        self.autoDeployOnStartup = autoDeployOnStartup
        self.preventSleep = preventSleep
        self.cronEnabled = cronEnabled
        self.cronExpression = cronExpression
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.autoDeployOnStartup = try container.decodeIfPresent(Bool.self, forKey: .autoDeployOnStartup) ?? false
        self.preventSleep = try container.decodeIfPresent(Bool.self, forKey: .preventSleep) ?? true
        self.cronEnabled = try container.decodeIfPresent(Bool.self, forKey: .cronEnabled) ?? false
        self.cronExpression = try container.decodeIfPresent(String.self, forKey: .cronExpression) ?? "@reboot"
    }
}

public struct LaunchdDaemonState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Not Loaded"
    public var isInstalled: Bool = false
    public var isLoaded: Bool = false
    public var pidText: String = "—"
    public var plistPath: String = "~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist"
    public var serverLogPath: String = "~/beaconmac/server.log"
    public var sleepAssertionActive: Bool = false
    public var caffeinateActive: Bool = false
}

public struct GitRepoSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { fullName }
    public let fullName: String
    public let cloneURL: String
    public let defaultBranch: String
    public let isPrivate: Bool
}

public struct GitDeployState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Idle"
    public var repoFullName: String = ""
    public var branch: String = "main"
    public var commitHash: String = "—"
    public var commitMessage: String = "Connect GitHub token or configure repository"
    public var lastCheckedAt: Date?
    public var lastDeployedAt: Date?
    public var autoDeploy: Bool = true
    public var pollIntervalSec: Int = 60
    public var deployCount: Int = 0
    public var connectedUsername: String?
    public var keyHint: String?
    public var repos: [GitRepoSummary] = []
    public var lastError: String?
}

public struct OllamaModelInfo: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let parameterSize: String
    public let quantization: String
    public let sizeGB: Double
}

public struct OllamaState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Checking"
    public var endpoint: String = "http://127.0.0.1:11434"
    public var isConnected: Bool = false
    public var activeModel: String = ""
    public var models: [OllamaModelInfo] = []
    public var latencyMs: Int?
    public var vramUsedGB: Double = 0
    public var totalMemoryGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000.0
    public var lastCheckedAt: Date?
    public var lastError: String?
}

public struct ClaudeModelInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let createdAt: String?
}

public struct ClaudeState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "No Key"
    public var isConnected: Bool = false
    public var keyHint: String?
    public var httpStatus: Int?
    public var latencyMs: Int?
    public var activeModel: String = ""
    public var models: [ClaudeModelInfo] = []
    public var lastCheckedAt: Date?
    public var lastError: String?
}

public enum UpdateStatus: String, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable
    case downloading
    case installing
    case readyToRelaunch
    case failed
}

public struct AppUpdateRelease: Sendable, Equatable {
    public let version: String
    public let tagName: String
    public let releaseNotes: String
    public let dmgDownloadURL: URL?
    public let htmlReleaseURL: URL
    public let publishedAt: String?
}

public struct AppUpdateState: Sendable {
    public var currentVersion: String = AppUpdateService.currentAppVersion()
    public var currentBuild: String = AppUpdateService.currentAppBuild()
    public var status: UpdateStatus = .idle
    public var latestRelease: AppUpdateRelease?
    public var lastCheckedAt: Date?
    public var downloadProgress: Double = 0
    public var statusMessage: String = "Automatic updates ready"
    public var lastError: String?
}

public struct BeaconConfig: Codable, Sendable {
    public var managedApps: [ManagedApp]
    public var startupSchedule: StartupScheduleConfig
    public var maxRestarts: Int
    public var gitPollIntervalSec: Int
    public var ollamaEndpoint: String
    public var ollamaActiveModel: String
    public var emailEnabled: Bool
    public var recipientEmail: String
    public var notifyOnCrash: Bool
    public var notifyOnDeploy: Bool
    public var notifyOnOllamaDown: Bool
    public var autoCheckForUpdates: Bool
    public var autoInstallUpdates: Bool
    public var updateFeedRepo: String

    public init(
        managedApps: [ManagedApp],
        startupSchedule: StartupScheduleConfig,
        maxRestarts: Int,
        gitPollIntervalSec: Int,
        ollamaEndpoint: String,
        ollamaActiveModel: String,
        emailEnabled: Bool,
        recipientEmail: String,
        notifyOnCrash: Bool,
        notifyOnDeploy: Bool,
        notifyOnOllamaDown: Bool,
        autoCheckForUpdates: Bool = true,
        autoInstallUpdates: Bool = false,
        updateFeedRepo: String = AppUpdateService.defaultRepo
    ) {
        self.managedApps = managedApps
        self.startupSchedule = startupSchedule
        self.maxRestarts = maxRestarts
        self.gitPollIntervalSec = gitPollIntervalSec
        self.ollamaEndpoint = ollamaEndpoint
        self.ollamaActiveModel = ollamaActiveModel
        self.emailEnabled = emailEnabled
        self.recipientEmail = recipientEmail
        self.notifyOnCrash = notifyOnCrash
        self.notifyOnDeploy = notifyOnDeploy
        self.notifyOnOllamaDown = notifyOnOllamaDown
        self.autoCheckForUpdates = autoCheckForUpdates
        self.autoInstallUpdates = autoInstallUpdates
        self.updateFeedRepo = updateFeedRepo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.managedApps = try container.decodeIfPresent([ManagedApp].self, forKey: .managedApps) ?? []
        self.startupSchedule = try container.decodeIfPresent(StartupScheduleConfig.self, forKey: .startupSchedule) ?? StartupScheduleConfig()
        self.maxRestarts = try container.decodeIfPresent(Int.self, forKey: .maxRestarts) ?? 10
        self.gitPollIntervalSec = try container.decodeIfPresent(Int.self, forKey: .gitPollIntervalSec) ?? 60
        self.ollamaEndpoint = try container.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://127.0.0.1:11434"
        self.ollamaActiveModel = try container.decodeIfPresent(String.self, forKey: .ollamaActiveModel) ?? ""
        self.emailEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailEnabled) ?? true
        self.recipientEmail = try container.decodeIfPresent(String.self, forKey: .recipientEmail) ?? ""
        self.notifyOnCrash = try container.decodeIfPresent(Bool.self, forKey: .notifyOnCrash) ?? true
        self.notifyOnDeploy = try container.decodeIfPresent(Bool.self, forKey: .notifyOnDeploy) ?? true
        self.notifyOnOllamaDown = try container.decodeIfPresent(Bool.self, forKey: .notifyOnOllamaDown) ?? true
        self.autoCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates) ?? true
        self.autoInstallUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoInstallUpdates) ?? false
        self.updateFeedRepo = try container.decodeIfPresent(String.self, forKey: .updateFeedRepo) ?? AppUpdateService.defaultRepo
    }

    public static var defaults: BeaconConfig {
        BeaconConfig(
            managedApps: [],
            startupSchedule: StartupScheduleConfig(),
            maxRestarts: 10,
            gitPollIntervalSec: 60,
            ollamaEndpoint: "http://127.0.0.1:11434",
            ollamaActiveModel: "",
            emailEnabled: true,
            recipientEmail: "",
            notifyOnCrash: true,
            notifyOnDeploy: true,
            notifyOnOllamaDown: true,
            autoCheckForUpdates: true,
            autoInstallUpdates: false,
            updateFeedRepo: AppUpdateService.defaultRepo
        )
    }
}

public enum SecretMasker {
    public static func mask(_ rawKey: String) -> String {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "••••••••" }
        let suffix = String(trimmed.suffix(4))
        if trimmed.hasPrefix("sk-ant-") {
            return "sk-ant-••••\(suffix)"
        }
        if trimmed.hasPrefix("github_pat_") {
            return "github_pat_••••\(suffix)"
        }
        if let idx = trimmed.firstIndex(of: "_"), trimmed.distance(from: trimmed.startIndex, to: idx) <= 4 {
            let prefix = String(trimmed[...idx])
            return "\(prefix)••••\(suffix)"
        }
        return "\(String(trimmed.prefix(4)))••••\(suffix)"
    }

    public static func redact(_ input: String) -> String {
        let patterns = [
            "\\b(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]+\\b",
            "\\bsk-ant-[A-Za-z0-9_-]+\\b"
        ]
        var result = input
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[REDACTED_KEY]")
            }
        }
        return result
    }
}
