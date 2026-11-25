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
    case auto = "Auto-Detect"
    case vite = "Vite + Node"
    case nodeServer = "Node.js Server"
    case nextjs = "Next.js"
    case custom = "Custom"

    public var id: String { rawValue }

    public var defaultInstallCommand: String { "auto" }

    public var defaultBuildCommand: String {
        switch self {
        case .auto: return "auto"
        case .vite: return "auto"
        case .nodeServer: return ""
        case .nextjs: return "auto"
        case .custom: return ""
        }
    }

    public func defaultStartCommand(port: Int) -> String {
        switch self {
        case .auto: return "auto"
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
        stackPreset: AppStackPreset = .auto,
        repoURL: String = "",
        branch: String = "main",
        localPath: String = "",
        monitorURL: String = "http://localhost:5173",
        port: Int = 5173,
        installCommand: String = "auto",
        buildCommand: String = "auto",
        startCommand: String = "auto",
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
    public var isManuallyStopped: Bool = false
    public var hasEverBeenHealthy: Bool = false
    public var startupGraceUntil: Date?
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
    public let isOptional: Bool

    public init(name: String, available: Bool, detail: String, isOptional: Bool = false) {
        self.name = name
        self.available = available
        self.detail = detail
        self.isOptional = isOptional
    }
}

public enum DependencyProjectType: String, CaseIterable, Identifiable, Sendable {
    case nodejsNpm = "Node.js (npm)"
    case nodejsPnpm = "Node.js + pnpm"
    case nodejsYarn = "Node.js + Yarn"
    case bun = "Bun"
    case jsAll = "Full JS / TS (Node, pnpm, Yarn, Bun)"
    case python = "Python (python3 + uv)"
    case golang = "Go"
    case custom = "Custom Selection"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .nodejsNpm: return "Node.js LTS, npm, and Git"
        case .nodejsPnpm: return "Node.js LTS, pnpm, and Git"
        case .nodejsYarn: return "Node.js LTS, Yarn, and Git"
        case .bun: return "Bun runtime/bundler and Git"
        case .jsAll: return "Node.js, pnpm, Yarn, Bun, and Git"
        case .python: return "Python 3, uv package manager, and Git"
        case .golang: return "Go toolchain and Git"
        case .custom: return "Choose individual tools below"
        }
    }

    public var requiredTools: [String] {
        switch self {
        case .nodejsNpm: return ["git", "node"]
        case .nodejsPnpm: return ["git", "node", "pnpm"]
        case .nodejsYarn: return ["git", "node", "yarn"]
        case .bun: return ["git", "bun"]
        case .jsAll: return ["git", "node", "pnpm", "yarn", "bun"]
        case .python: return ["git", "python3", "uv"]
        case .golang: return ["git", "go"]
        case .custom: return []
        }
    }

    public static func defaultType(for preset: AppStackPreset?) -> DependencyProjectType {
        switch preset {
        case .vite, .nextjs: return .nodejsPnpm
        case .auto, .nodeServer, .custom, .none: return .nodejsNpm
        }
    }
}

public enum DependencyInstallStrategy: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case homebrew = "homebrew"
    case direct = "direct"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto (Homebrew, fallback to Direct Download)"
        case .homebrew: return "Homebrew (silent)"
        case .direct: return "Direct Official Download (no Homebrew)"
        }
    }
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
    public let sha256: String?
    public let sha256DownloadURL: URL?
    public let htmlReleaseURL: URL
    public let publishedAt: String?

    public init(
        version: String,
        tagName: String,
        releaseNotes: String,
        dmgDownloadURL: URL?,
        sha256: String? = nil,
        sha256DownloadURL: URL? = nil,
        htmlReleaseURL: URL,
        publishedAt: String?
    ) {
        self.version = version
        self.tagName = tagName
        self.releaseNotes = releaseNotes
        self.dmgDownloadURL = dmgDownloadURL
        self.sha256 = sha256
        self.sha256DownloadURL = sha256DownloadURL
        self.htmlReleaseURL = htmlReleaseURL
        self.publishedAt = publishedAt
    }
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

public enum BuiltInNodeAppMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case staticFolder = "static"
    case localProxy = "proxy"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .staticFolder: return "Static / Built App Folder"
        case .localProxy: return "Local Port Proxy (127.0.0.1)"
        }
    }
}

public struct BuiltInMountedApp: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var slug: String
    public var mode: BuiltInNodeAppMode
    public var folderPath: String
    public var proxyPort: Int?
    public var spaFallback: Bool
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        mode: BuiltInNodeAppMode = .staticFolder,
        folderPath: String = "",
        proxyPort: Int? = nil,
        spaFallback: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.mode = mode
        self.folderPath = folderPath
        self.proxyPort = proxyPort
        self.spaFallback = spaFallback
        self.addedAt = addedAt
    }
}

public struct BuiltInServerConfig: Codable, Sendable {
    public var port: Int = 4173
    public var autoStart: Bool = false
    public var activeRootAppID: UUID? = nil
    public var mountedApps: [BuiltInMountedApp] = []

    public init(
        port: Int = 4173,
        autoStart: Bool = false,
        activeRootAppID: UUID? = nil,
        mountedApps: [BuiltInMountedApp] = []
    ) {
        self.port = port
        self.autoStart = autoStart
        self.activeRootAppID = activeRootAppID
        self.mountedApps = mountedApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPort = try container.decodeIfPresent(Int.self, forKey: .port) ?? 4173
        self.port = (1024...65535).contains(decodedPort) ? decodedPort : 4173
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        self.activeRootAppID = try container.decodeIfPresent(UUID.self, forKey: .activeRootAppID)
        self.mountedApps = try container.decodeIfPresent([BuiltInMountedApp].self, forKey: .mountedApps) ?? []
    }
}

public struct BuiltInServerState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Stopped"
    public var isRunning: Bool = false
    public var pid: Int?
    public var port: Int = 4173
    public var nodeVersion: String?
    public var uptimeSec: Int?
    public var lastCheckedAt: Date?
    public var lastError: String?

    public var baseURL: String {
        "http://127.0.0.1:\(port)"
    }
}

public struct NginxProxyRoute: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// URL path prefix (e.g. "/my-app") when serving via path-based reverse proxy.
    public var pathPrefix: String
    /// Optional virtual-host domain (e.g. "myapp.localhost"). When non-empty, NGINX exposes a dedicated `server_name` block.
    public var serverName: String
    /// Target local host (strictly loopback by default: 127.0.0.1).
    public var targetHost: String
    /// Target local app port (e.g. 3000, 5173).
    public var targetPort: Int
    /// Enables Upgrade/Connection headers for WebSockets and Vite HMR.
    public var webSocketsEnabled: Bool
    /// Strips the pathPrefix before forwarding to upstream (proxy_pass trailing slash).
    public var stripPrefix: Bool
    /// Whether this route is currently active in generated nginx.conf.
    public var enabled: Bool
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        pathPrefix: String,
        serverName: String = "",
        targetHost: String = "127.0.0.1",
        targetPort: Int,
        webSocketsEnabled: Bool = true,
        stripPrefix: Bool = true,
        enabled: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.pathPrefix = pathPrefix
        self.serverName = serverName
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.webSocketsEnabled = webSocketsEnabled
        self.stripPrefix = stripPrefix
        self.enabled = enabled
        self.addedAt = addedAt
    }
}

public struct NginxProxyConfig: Codable, Sendable {
    public var listenPort: Int = 8080
    public var exposeOnLAN: Bool = false
    public var autoStart: Bool = false
    public var activeRootRouteID: UUID? = nil
    public var routes: [NginxProxyRoute] = []

    public init(
        listenPort: Int = 8080,
        exposeOnLAN: Bool = false,
        autoStart: Bool = false,
        activeRootRouteID: UUID? = nil,
        routes: [NginxProxyRoute] = []
    ) {
        self.listenPort = listenPort
        self.exposeOnLAN = exposeOnLAN
        self.autoStart = autoStart
        self.activeRootRouteID = activeRootRouteID
        self.routes = routes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPort = try container.decodeIfPresent(Int.self, forKey: .listenPort) ?? 8080
        self.listenPort = (80...65535).contains(decodedPort) ? decodedPort : 8080
        self.exposeOnLAN = try container.decodeIfPresent(Bool.self, forKey: .exposeOnLAN) ?? false
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        self.activeRootRouteID = try container.decodeIfPresent(UUID.self, forKey: .activeRootRouteID)
        self.routes = try container.decodeIfPresent([NginxProxyRoute].self, forKey: .routes) ?? []
    }
}

public struct NginxProxyState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Stopped"
    public var isInstalled: Bool = false
    public var isRunning: Bool = false
    public var pid: Int?
    public var listenPort: Int = 8080
    public var nginxVersion: String?
    public var lanAddress: String?
    public var configPath: String = ""
    public var lastCheckedAt: Date?
    public var lastError: String?

    public var baseURL: String {
        listenPort == 80 ? "http://localhost" : "http://localhost:\(listenPort)"
    }

    public var lanBaseURL: String? {
        guard let ip = lanAddress, !ip.isEmpty else { return nil }
        return listenPort == 80 ? "http://\(ip)" : "http://\(ip):\(listenPort)"
    }
}

public enum CloudflareTunnelTargetKind: String, Codable, Sendable {
    case managedApp
    case nginxProxy
    case builtInNode
    case customPort
}

public enum CloudflareTunnelProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case http2 = "http2"
    case quic = "quic"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto (QUIC / HTTP2)"
        case .http2: return "HTTP/2 (Firewall Friendly)"
        case .quic: return "QUIC (UDP)"
        }
    }
}

public enum CloudflareTunnelMode: String, Codable, Sendable {
    case apiManaged = "api"
    case quickTunnel = "quick"

    public var badgeLabel: String {
        switch self {
        case .apiManaged: return "Cloudflare API · Named Tunnel"
        case .quickTunnel: return "Quick Tunnel"
        }
    }
}

public struct CloudflareTunnelConfig: Codable, Sendable {
    public var preferredProtocol: CloudflareTunnelProtocol = .auto
    public var autoInstallCloudflared: Bool = true
    public var autoCopyURLOnStart: Bool = true
    public var preferCloudflareAPI: Bool = true
    public var customBaseDomain: String = ""

    public init(
        preferredProtocol: CloudflareTunnelProtocol = .auto,
        autoInstallCloudflared: Bool = true,
        autoCopyURLOnStart: Bool = true,
        preferCloudflareAPI: Bool = true,
        customBaseDomain: String = ""
    ) {
        self.preferredProtocol = preferredProtocol
        self.autoInstallCloudflared = autoInstallCloudflared
        self.autoCopyURLOnStart = autoCopyURLOnStart
        self.preferCloudflareAPI = preferCloudflareAPI
        self.customBaseDomain = customBaseDomain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preferredProtocol = try container.decodeIfPresent(CloudflareTunnelProtocol.self, forKey: .preferredProtocol) ?? .auto
        self.autoInstallCloudflared = try container.decodeIfPresent(Bool.self, forKey: .autoInstallCloudflared) ?? true
        self.autoCopyURLOnStart = try container.decodeIfPresent(Bool.self, forKey: .autoCopyURLOnStart) ?? true
        self.preferCloudflareAPI = try container.decodeIfPresent(Bool.self, forKey: .preferCloudflareAPI) ?? true
        self.customBaseDomain = try container.decodeIfPresent(String.self, forKey: .customBaseDomain) ?? ""
    }
}

public struct CloudflareTunnelEntry: Identifiable, Sendable {
    public var id: String
    public var label: String
    public var targetKind: CloudflareTunnelTargetKind
    public var appID: UUID?
    public var targetPort: Int
    public var targetURL: String
    public var publicURL: String?
    public var mode: CloudflareTunnelMode
    public var configFilePath: String?
    public var cloudflareTunnelID: String?
    public var isRunning: Bool
    public var isStarting: Bool
    public var pid: Int?
    public var startedAt: Date?
    public var lastError: String?
    public var light: TrafficLightColor
    public var statusLabel: String

    public init(
        id: String,
        label: String,
        targetKind: CloudflareTunnelTargetKind,
        appID: UUID? = nil,
        targetPort: Int,
        targetURL: String,
        publicURL: String? = nil,
        mode: CloudflareTunnelMode = .quickTunnel,
        configFilePath: String? = nil,
        cloudflareTunnelID: String? = nil,
        isRunning: Bool = false,
        isStarting: Bool = false,
        pid: Int? = nil,
        startedAt: Date? = nil,
        lastError: String? = nil,
        light: TrafficLightColor = .amber,
        statusLabel: String = "Stopped"
    ) {
        self.id = id
        self.label = label
        self.targetKind = targetKind
        self.appID = appID
        self.targetPort = targetPort
        self.targetURL = targetURL
        self.publicURL = publicURL
        self.mode = mode
        self.configFilePath = configFilePath
        self.cloudflareTunnelID = cloudflareTunnelID
        self.isRunning = isRunning
        self.isStarting = isStarting
        self.pid = pid
        self.startedAt = startedAt
        self.lastError = lastError
        self.light = light
        self.statusLabel = statusLabel
    }
}

public struct CloudflareTunnelState: Sendable {
    public var isInstalled: Bool = false
    public var version: String?
    public var isInstalling: Bool = false
    public var tunnels: [String: CloudflareTunnelEntry] = [:]
    public var lastCheckedAt: Date?
    public var lastError: String?

    public var activeTunnels: [CloudflareTunnelEntry] {
        tunnels.values
            .filter { $0.isRunning || $0.isStarting }
            .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    public var activeCount: Int {
        tunnels.values.filter(\.isRunning).count
    }

    public var light: TrafficLightColor {
        if tunnels.values.contains(where: { $0.isRunning }) {
            return .green
        }
        if isInstalling || tunnels.values.contains(where: { $0.isStarting }) {
            return .amber
        }
        if lastError != nil {
            return .red
        }
        return .amber
    }

    public var statusLabel: String {
        if isInstalling {
            return "Installing…"
        }
        let running = activeCount
        if running > 0 {
            return running == 1 ? "1 Live Tunnel" : "\(running) Live Tunnels"
        }
        if tunnels.values.contains(where: { $0.isStarting }) {
            return "Connecting…"
        }
        return isInstalled ? "Ready" : "Auto-Install Ready"
    }
}

public enum BeaconAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark = "dark"
    case light = "light"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "White"
        }
    }
}

public enum CloudProviderCategory: String, CaseIterable, Sendable {
    case ai = "Cloud AI APIs"
    case cloud = "Cloud & Edge Platforms"
}

public enum CloudProviderKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case openai = "openai"
    case gemini = "gemini"
    case openrouter = "openrouter"
    case groq = "groq"
    case customOpenAI = "custom_openai"
    case cloudflare = "cloudflare"
    case vercel = "vercel"
    case supabase = "supabase"

    public var id: String { rawValue }

    public var category: CloudProviderCategory {
        switch self {
        case .openai, .gemini, .openrouter, .groq, .customOpenAI:
            return .ai
        case .cloudflare, .vercel, .supabase:
            return .cloud
        }
    }

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI (ChatGPT)"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        case .customOpenAI: return "Custom OpenAI-Compatible"
        case .cloudflare: return "Cloudflare (API & Workers AI)"
        case .vercel: return "Vercel"
        case .supabase: return "Supabase"
        }
    }

    public var subtitle: String {
        switch self {
        case .openai: return "api.openai.com · GPT-4o / o3 / GPT-4.1 · powers AI Log Help"
        case .gemini: return "generativelanguage.googleapis.com · Gemini 2.5 Flash/Pro · powers AI Log Help"
        case .openrouter: return "openrouter.ai/api/v1 · Multi-model router · powers AI Log Help"
        case .groq: return "api.groq.com/openai/v1 · Ultra-fast Llama/Qwen · powers AI Log Help"
        case .customOpenAI: return "DeepSeek, xAI Grok, Together, Mistral, or Azure OpenAI-compatible endpoint"
        case .cloudflare: return "api.cloudflare.com · Verify API token & optionally enable Workers AI log help"
        case .vercel: return "api.vercel.com · Verify personal or team deployment token"
        case .supabase: return "Project REST URL + anon/service key · Verify database API reachability"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-proj-..."
        case .gemini: return "AIzaSy..."
        case .openrouter: return "sk-or-v1-..."
        case .groq: return "gsk_..."
        case .customOpenAI: return "sk-..."
        case .cloudflare: return "Cloudflare API Token..."
        case .vercel: return "Vercel Access Token..."
        case .supabase: return "eyJhbGciOi... or sb_..."
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.5-flash"
        case .openrouter: return "openai/gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .customOpenAI: return "deepseek-chat"
        case .cloudflare: return "@cf/meta/llama-3.1-8b-instruct"
        case .vercel, .supabase: return ""
        }
    }

    public var supportsBaseURL: Bool {
        self == .customOpenAI || self == .supabase
    }

    public var baseURLPlaceholder: String {
        switch self {
        case .customOpenAI: return "https://api.deepseek.com/v1"
        case .supabase: return "https://your-project.supabase.co"
        default: return ""
        }
    }

    public var supportsAccountID: Bool {
        self == .cloudflare
    }

    public var supportsAIHelp: Bool {
        switch self {
        case .openai, .gemini, .openrouter, .groq, .customOpenAI, .cloudflare:
            return true
        case .vercel, .supabase:
            return false
        }
    }

    public var keychainAccount: KeychainAccount {
        switch self {
        case .openai: return .openaiAPIKey
        case .gemini: return .geminiAPIKey
        case .openrouter: return .openrouterAPIKey
        case .groq: return .groqAPIKey
        case .customOpenAI: return .customAIAPIKey
        case .cloudflare: return .cloudflareAPIToken
        case .vercel: return .vercelAPIToken
        case .supabase: return .supabaseAPIKey
        }
    }
}

public struct CloudProviderConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var accountID: String
    public var selectedModel: String

    public init(baseURL: String = "", accountID: String = "", selectedModel: String = "") {
        self.baseURL = baseURL
        self.accountID = accountID
        self.selectedModel = selectedModel
    }
}

public struct CloudProviderRuntimeState: Sendable {
    public var light: TrafficLightColor = .amber
    public var statusLabel: String = "Not Connected"
    public var isConnected: Bool = false
    public var keyHint: String?
    public var httpStatus: Int?
    public var latencyMs: Int?
    public var accountLabel: String?
    public var models: [String] = []
    public var lastCheckedAt: Date?
    public var lastError: String?
}

public struct BeaconConfig: Codable, Sendable {
    public var managedApps: [ManagedApp]
    public var builtInServer: BuiltInServerConfig
    public var nginxProxy: NginxProxyConfig
    public var cloudflareTunnel: CloudflareTunnelConfig
    public var startupSchedule: StartupScheduleConfig
    public var appearanceMode: BeaconAppearanceMode
    public var cloudProviders: [String: CloudProviderConfig]
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
    /// Pinned to the official BeaconMac release repository; cannot be overridden via config.json.
    public var updateFeedRepo: String

    public init(
        managedApps: [ManagedApp],
        builtInServer: BuiltInServerConfig = BuiltInServerConfig(),
        nginxProxy: NginxProxyConfig = NginxProxyConfig(),
        cloudflareTunnel: CloudflareTunnelConfig = CloudflareTunnelConfig(),
        startupSchedule: StartupScheduleConfig,
        appearanceMode: BeaconAppearanceMode = .dark,
        cloudProviders: [String: CloudProviderConfig] = [:],
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
        updateFeedRepo: String = AppUpdateService.pinnedRepo
    ) {
        self.managedApps = managedApps
        self.builtInServer = builtInServer
        self.nginxProxy = nginxProxy
        self.cloudflareTunnel = cloudflareTunnel
        self.startupSchedule = startupSchedule
        self.appearanceMode = appearanceMode
        self.cloudProviders = cloudProviders
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
        self.updateFeedRepo = AppUpdateService.pinnedRepo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.managedApps = try container.decodeIfPresent([ManagedApp].self, forKey: .managedApps) ?? []
        self.builtInServer = try container.decodeIfPresent(BuiltInServerConfig.self, forKey: .builtInServer) ?? BuiltInServerConfig()
        self.nginxProxy = try container.decodeIfPresent(NginxProxyConfig.self, forKey: .nginxProxy) ?? NginxProxyConfig()
        self.cloudflareTunnel = try container.decodeIfPresent(CloudflareTunnelConfig.self, forKey: .cloudflareTunnel) ?? CloudflareTunnelConfig()
        self.startupSchedule = try container.decodeIfPresent(StartupScheduleConfig.self, forKey: .startupSchedule) ?? StartupScheduleConfig()
        self.appearanceMode = try container.decodeIfPresent(BeaconAppearanceMode.self, forKey: .appearanceMode) ?? .dark
        self.cloudProviders = try container.decodeIfPresent([String: CloudProviderConfig].self, forKey: .cloudProviders) ?? [:]
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
        // Always ignore any mutable updateFeedRepo value from config.json to prevent update feed hijacking.
        _ = try? container.decodeIfPresent(String.self, forKey: .updateFeedRepo)
        self.updateFeedRepo = AppUpdateService.pinnedRepo
    }

    public static var defaults: BeaconConfig {
        BeaconConfig(
            managedApps: [],
            builtInServer: BuiltInServerConfig(),
            nginxProxy: NginxProxyConfig(),
            cloudflareTunnel: CloudflareTunnelConfig(),
            startupSchedule: StartupScheduleConfig(),
            appearanceMode: .dark,
            cloudProviders: [:],
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
            updateFeedRepo: AppUpdateService.pinnedRepo
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
        if trimmed.hasPrefix("sk-proj-") {
            return "sk-proj-••••\(suffix)"
        }
        if trimmed.hasPrefix("sk-or-") {
            return "sk-or-••••\(suffix)"
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
            "\\bsk-ant-[A-Za-z0-9_-]+\\b",
            "\\bsk-(proj|or-v1)?-?[A-Za-z0-9_-]{20,}\\b",
            "\\bAIza[0-9A-Za-z_-]{20,}\\b",
            "\\bgsk_[A-Za-z0-9_-]{20,}\\b"
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
