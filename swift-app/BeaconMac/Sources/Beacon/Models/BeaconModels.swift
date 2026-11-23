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
    case email
    case system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vite: return "vite"
        case .git: return "git"
        case .ollama: return "ollama"
        case .claude: return "claude"
        case .email: return "email"
        case .system: return "system"
        }
    }
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

public struct ViteMonitorState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Checking"
    public var monitorURL: String = "http://localhost:5173"
    public var httpStatus: Int?
    public var responseTimeMs: Int?
    public var isHealthy: Bool = false
    public var restartCount: Int = 0
    public var consecutiveFailures: Int = 0
    public var autoRestart: Bool = true
    public var lastCheckedAt: Date?
    public var lastError: String?
    public var healthySince: Date?

    public var uptimeSeconds: Int {
        guard isHealthy, let since = healthySince else { return 0 }
        return max(0, Int(Date().timeIntervalSince(since)))
    }
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

public struct BeaconConfig: Codable, Sendable {
    public var workingDir: String
    public var monitorURL: String
    public var autoRestart: Bool
    public var maxRestarts: Int
    public var gitRepoFullName: String
    public var gitBranch: String
    public var gitAutoDeploy: Bool
    public var gitPollIntervalSec: Int
    public var ollamaEndpoint: String
    public var ollamaActiveModel: String
    public var emailEnabled: Bool
    public var recipientEmail: String
    public var smtpHost: String
    public var smtpPort: Int
    public var smtpUsername: String
    public var notifyOnCrash: Bool
    public var notifyOnDeploy: Bool
    public var notifyOnOllamaDown: Bool

    public static var defaults: BeaconConfig {
        BeaconConfig(
            workingDir: FileManager.default.homeDirectoryForCurrentUser.path,
            monitorURL: "http://localhost:5173",
            autoRestart: true,
            maxRestarts: 10,
            gitRepoFullName: "",
            gitBranch: "main",
            gitAutoDeploy: true,
            gitPollIntervalSec: 60,
            ollamaEndpoint: "http://127.0.0.1:11434",
            ollamaActiveModel: "",
            emailEnabled: true,
            recipientEmail: "",
            smtpHost: "smtp.gmail.com",
            smtpPort: 587,
            smtpUsername: "",
            notifyOnCrash: true,
            notifyOnDeploy: true,
            notifyOnOllamaDown: true
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
