import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class BeaconController {
    public var config: BeaconConfig
    public var vite = ViteMonitorState()
    public var git = GitDeployState()
    public var ollama = OllamaState()
    public var claude = ClaudeState()
    public var logs: [LogEntry] = []
    public var logFileBytes: Int64 = 0
    public var busyAction: String?
    public var bannerError: String?

    public let flatFileStore = FlatFileStore()
    public let keychain = KeychainStore()

    private let processService = LocalProcessService()
    private let gitService = GitDeployService()
    private let ollamaService = OllamaService()
    private let claudeService = ClaudeService()
    private let alertService = AlertService()

    private var pollingTask: Task<Void, Never>?
    private var tickCount = 0

    public var aggregateLight: TrafficLightColor {
        let lights = [vite.light, git.light, ollama.light, claude.light]
        if lights.contains(.red) { return .red }
        if lights.contains(.amber) { return .amber }
        return .green
    }

    public init() {
        let loaded = flatFileStore.loadConfig()
        self.config = loaded
        self.vite.monitorURL = loaded.monitorURL
        self.vite.autoRestart = loaded.autoRestart
        self.git.repoFullName = loaded.gitRepoFullName
        self.git.branch = loaded.gitBranch
        self.git.autoDeploy = loaded.gitAutoDeploy
        self.git.pollIntervalSec = loaded.gitPollIntervalSec
        self.ollama.endpoint = loaded.ollamaEndpoint
        self.ollama.activeModel = loaded.ollamaActiveModel
        self.logs = flatFileStore.loadRecentLogs()
        self.logFileBytes = flatFileStore.logFileByteCount()

        alertService.requestPermission()
        log(.system, .info, "Beacon SwiftUI monitor initialized (flat-file log: \(flatFileStore.logFileURL.path))")

        Task {
            await restoreSavedKeysAndBoot()
        }
        startPollingLoop()
    }

    public func log(_ source: LogSource, _ level: LogLevel, _ message: String) {
        let entry = flatFileStore.appendLog(source: source, level: level, message: message)
        logs.append(entry)
        if logs.count > 400 {
            logs = Array(logs.suffix(400))
        }
        logFileBytes = flatFileStore.logFileByteCount()
    }

    private func restoreSavedKeysAndBoot() async {
        await probeVite(logTransition: true)
        await probeOllama(logResult: true)

        if let savedGitToken = keychain.read(.githubToken), !savedGitToken.isEmpty {
            git.keyHint = SecretMasker.mask(savedGitToken)
            await connectGitToken(savedGitToken, persistToKeychain: false)
        }

        if let savedClaudeKey = keychain.read(.claudeAPIKey), !savedClaudeKey.isEmpty {
            claude.keyHint = SecretMasker.mask(savedClaudeKey)
            await probeClaude(logResult: true)
        }
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { break }
                self.tickCount += 1

                await self.probeVite(logTransition: true)

                if self.tickCount % 5 == 0 {
                    await self.probeOllama(logResult: false)
                }

                let gitIntervalTicks = max(5, self.config.gitPollIntervalSec / 3)
                if self.config.gitAutoDeploy && !self.config.gitRepoFullName.isEmpty && self.tickCount % gitIntervalTicks == 0 {
                    await self.checkAndDeployGit(forcePull: false, trigger: "poll")
                }

                if self.tickCount % 20 == 0 && self.keychain.read(.claudeAPIKey) != nil {
                    await self.probeClaude(logResult: false)
                }
            }
        }
    }

    // MARK: - Vite / Localhost Watchdog

    public func updateMonitorURL(_ rawURL: String) async {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LocalProcessService.isValidLocalhostURL(trimmed) else {
            bannerError = "Monitor URL must be a localhost or 127.0.0.1 HTTP(S) URL (e.g. http://localhost:5173)."
            return
        }
        bannerError = nil
        config.monitorURL = trimmed
        vite.monitorURL = trimmed
        vite.consecutiveFailures = 0
        vite.healthySince = nil
        flatFileStore.saveConfig(config)
        log(.vite, .info, "Switched monitored localhost URL to \(trimmed)")
        await probeVite(logTransition: true)
    }

    public func probeVite(logTransition: Bool) async {
        let wasHealthy = vite.isHealthy
        let result = await processService.probe(urlString: config.monitorURL)
        vite.lastCheckedAt = Date()
        vite.httpStatus = result.httpStatus
        vite.responseTimeMs = result.responseTimeMs
        vite.isHealthy = result.healthy
        vite.lastError = result.error

        if result.healthy {
            vite.consecutiveFailures = 0
            vite.light = .green
            vite.statusLabel = "Running"
            if vite.healthySince == nil {
                vite.healthySince = Date()
            }
            if logTransition && !wasHealthy {
                log(.vite, .info, "Localhost app reachable at \(config.monitorURL) (HTTP \(result.httpStatus ?? 200), \(result.responseTimeMs ?? 1) ms)")
            }
        } else {
            vite.healthySince = nil
            vite.consecutiveFailures += 1
            vite.light = .red
            vite.statusLabel = "Unreachable"

            if vite.consecutiveFailures == 3 {
                log(.vite, .error, "Monitored app \(config.monitorURL) failed 3 consecutive health checks")
                if config.notifyOnCrash {
                    let note = await alertService.sendAlert(
                        title: "Localhost Server Down",
                        body: "\(config.monitorURL) stopped responding.",
                        recipientEmail: config.recipientEmail,
                        emailEnabled: config.emailEnabled
                    )
                    log(.email, .info, note)
                }
                if config.autoRestart && vite.restartCount < config.maxRestarts {
                    await triggerViteRestart(reason: "auto-recovery #\(vite.restartCount + 1)")
                }
            }
        }
    }

    public func triggerViteRestart(reason: String = "manual restart") async {
        busyAction = "vite-restart"
        defer { busyAction = nil }

        vite.light = .amber
        vite.statusLabel = "Restarting"
        let port = LocalProcessService.extractPort(from: config.monitorURL)
        log(.vite, .info, "Invoking App Sandbox restart script for \(config.workingDir) on port \(port) (\(reason))...")

        let outcome = await processService.runSandboxRestartScript(workingDir: config.workingDir, port: port)
        if outcome.ok {
            vite.restartCount += 1
            log(.vite, .info, outcome.detail)
            try? await Task.sleep(for: .seconds(2))
            await probeVite(logTransition: true)
        } else {
            vite.light = .red
            vite.statusLabel = "Script Missing"
            vite.lastError = outcome.detail
            log(.vite, .warn, outcome.detail)
        }
    }

    public func toggleViteAutoRestart() {
        config.autoRestart.toggle()
        vite.autoRestart = config.autoRestart
        flatFileStore.saveConfig(config)
        log(.vite, .info, "Auto-restart watchdog \(config.autoRestart ? "enabled" : "disabled")")
    }

    // MARK: - Git Auto-Deploy & Keychain Token

    @discardableResult
    public func connectGitToken(_ rawToken: String, persistToKeychain: Bool = true) async -> Bool {
        busyAction = "git-connect"
        bannerError = nil
        defer { busyAction = nil }

        do {
            let verified = try await gitService.verifyTokenAndFetchRepos(token: rawToken)
            if persistToKeychain {
                keychain.save(rawToken, for: .githubToken)
            }
            git.connectedUsername = verified.username
            git.keyHint = SecretMasker.mask(rawToken)
            git.repos = verified.repos
            git.lastError = nil
            git.light = config.gitAutoDeploy ? .green : .amber
            git.statusLabel = config.gitAutoDeploy ? "Synced" : "Paused"

            if config.gitRepoFullName.isEmpty, let first = verified.repos.first {
                config.gitRepoFullName = first.fullName
                config.gitBranch = first.defaultBranch
                git.repoFullName = first.fullName
                git.branch = first.defaultBranch
                flatFileStore.saveConfig(config)
            }

            log(.git, .info, "Connected GitHub account @\(verified.username) via Keychain token (\(verified.repos.count) repos accessible)")
            if !config.gitRepoFullName.isEmpty {
                await checkAndDeployGit(forcePull: false, trigger: "token connect")
            }
            return true
        } catch {
            let msg = SecretMasker.redact(error.localizedDescription)
            git.light = .red
            git.statusLabel = "Auth Error"
            git.lastError = msg
            bannerError = msg
            log(.git, .error, "GitHub token verification failed: \(msg)")
            return false
        }
    }

    public func disconnectGitToken() {
        let prevUser = git.connectedUsername
        keychain.delete(.githubToken)
        git.connectedUsername = nil
        git.keyHint = nil
        git.repos = []
        git.light = .amber
        git.statusLabel = "Idle"
        log(.git, .info, "Removed GitHub token from macOS Keychain\(prevUser.map { " (@\($0))" } ?? "")")
    }

    public func selectGitRepo(_ repoFullName: String, branch: String) async {
        config.gitRepoFullName = repoFullName
        config.gitBranch = branch
        git.repoFullName = repoFullName
        git.branch = branch
        flatFileStore.saveConfig(config)
        log(.git, .info, "Selected GitHub repository \(repoFullName) (\(branch))")
        await checkAndDeployGit(forcePull: false, trigger: "repo switch")
    }

    public func checkAndDeployGit(forcePull: Bool, trigger: String) async {
        guard !config.gitRepoFullName.isEmpty else {
            bannerError = "Paste your GitHub token and pick a repository first."
            return
        }
        busyAction = "git-deploy"
        defer { busyAction = nil }

        git.light = .amber
        git.statusLabel = "Checking"
        git.lastCheckedAt = Date()

        do {
            let token = keychain.read(.githubToken)
            let commit = try await gitService.fetchLatestCommit(
                repoFullName: config.gitRepoFullName,
                branch: config.gitBranch,
                token: token
            )
            let changed = commit.shaShort != git.commitHash && git.commitHash != "—"
            git.commitHash = commit.shaShort
            git.commitMessage = commit.message
            git.lastError = nil

            if forcePull || changed {
                log(.git, .info, "Detected commit \(commit.shaShort) on \(config.gitRepoFullName)@\(config.gitBranch) (\(trigger)): \"\(commit.message)\"")
                let pullResult = await gitService.runSandboxGitPullScript(workingDir: config.workingDir, branch: config.gitBranch)
                if pullResult.ok {
                    git.deployCount += 1
                    git.lastDeployedAt = Date()
                    log(.git, .info, pullResult.detail)
                    await triggerViteRestart(reason: "git deploy \(commit.shaShort)")
                    if config.notifyOnDeploy {
                        let note = await alertService.sendAlert(
                            title: "Git Auto-Deploy (\(commit.shaShort))",
                            body: "\(config.gitRepoFullName)@\(config.gitBranch): \(commit.message)",
                            recipientEmail: config.recipientEmail,
                            emailEnabled: config.emailEnabled
                        )
                        log(.email, .info, note)
                    }
                } else {
                    log(.git, .warn, pullResult.detail)
                }
            }

            git.light = config.gitAutoDeploy ? .green : .amber
            git.statusLabel = config.gitAutoDeploy ? "Synced" : "Paused"
        } catch {
            let msg = SecretMasker.redact(error.localizedDescription)
            git.light = .red
            git.statusLabel = "Error"
            git.lastError = msg
            log(.git, .error, "Git check failed: \(msg)")
        }
    }

    public func toggleGitAutoDeploy() {
        config.gitAutoDeploy.toggle()
        git.autoDeploy = config.gitAutoDeploy
        git.light = config.gitAutoDeploy ? .green : .amber
        git.statusLabel = config.gitAutoDeploy ? "Synced" : "Paused"
        flatFileStore.saveConfig(config)
        log(.git, .info, "Git auto-deploy polling \(config.gitAutoDeploy ? "enabled" : "paused")")
    }

    // MARK: - Ollama Local LLM

    public func probeOllama(logResult: Bool) async {
        let wasConnected = ollama.isConnected
        let res = await ollamaService.probeHealth(endpoint: config.ollamaEndpoint, preferredModel: config.ollamaActiveModel)
        ollama.lastCheckedAt = Date()
        ollama.isConnected = res.connected
        ollama.latencyMs = res.latencyMs
        ollama.models = res.models
        ollama.activeModel = res.activeModel
        ollama.vramUsedGB = res.vramUsedGB
        ollama.lastError = res.error

        if res.connected {
            ollama.light = .green
            ollama.statusLabel = "Connected"
            if logResult || !wasConnected {
                log(.ollama, .info, "Ollama healthy at \(config.ollamaEndpoint) (\(res.latencyMs ?? 1) ms, \(res.models.count) local models)")
            }
        } else {
            ollama.light = .red
            ollama.statusLabel = "Offline"
            if logResult || wasConnected {
                log(.ollama, .warn, res.error ?? "Ollama unreachable at \(config.ollamaEndpoint)")
                if wasConnected && config.notifyOnOllamaDown {
                    let note = await alertService.sendAlert(
                        title: "Ollama Offline",
                        body: "Local Ollama daemon at \(config.ollamaEndpoint) stopped responding.",
                        recipientEmail: config.recipientEmail,
                        emailEnabled: config.emailEnabled
                    )
                    log(.email, .info, note)
                }
            }
        }
    }

    public func switchOllamaModel(_ model: String) async {
        busyAction = "ollama-model"
        defer { busyAction = nil }
        ollama.light = .amber
        ollama.statusLabel = "Switching"
        config.ollamaActiveModel = model
        flatFileStore.saveConfig(config)

        do {
            let ms = try await ollamaService.switchModel(endpoint: config.ollamaEndpoint, model: model)
            ollama.activeModel = model
            ollama.latencyMs = ms
            ollama.light = .green
            ollama.statusLabel = "Connected"
            log(.ollama, .info, "Switched active local Ollama model to \(model) (\(ms) ms)")
        } catch {
            let msg = error.localizedDescription
            ollama.light = .red
            ollama.statusLabel = "Error"
            ollama.lastError = msg
            bannerError = msg
            log(.ollama, .error, "Failed to switch Ollama model: \(msg)")
        }
    }

    // MARK: - Claude API Health Checker

    @discardableResult
    public func connectClaudeKey(_ rawKey: String) async -> Bool {
        busyAction = "claude-connect"
        bannerError = nil
        defer { busyAction = nil }

        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.contains(where: \.isWhitespace) else {
            bannerError = "Paste a valid Anthropic Claude API key (starts with sk-ant-...)."
            return false
        }

        keychain.save(trimmed, for: .claudeAPIKey)
        claude.keyHint = SecretMasker.mask(trimmed)
        return await probeClaude(logResult: true)
    }

    @discardableResult
    public func probeClaude(logResult: Bool) async -> Bool {
        guard let apiKey = keychain.read(.claudeAPIKey), !apiKey.isEmpty else {
            claude.light = .amber
            claude.statusLabel = "No Key"
            claude.isConnected = false
            claude.keyHint = nil
            claude.httpStatus = nil
            claude.latencyMs = nil
            claude.models = []
            claude.activeModel = ""
            claude.lastError = nil
            return false
        }

        claude.light = .amber
        claude.statusLabel = "Checking"
        let res = await claudeService.probeHealth(apiKey: apiKey)
        claude.lastCheckedAt = Date()
        claude.httpStatus = res.httpStatus
        claude.latencyMs = res.latencyMs
        claude.isConnected = res.connected
        claude.lastError = res.error

        if res.connected {
            claude.light = .green
            claude.statusLabel = "Healthy"
            claude.models = res.models
            if claude.activeModel.isEmpty || !res.models.contains(where: { $0.id == claude.activeModel }) {
                claude.activeModel = res.models.first(where: { $0.id.contains("sonnet") })?.id ?? res.models.first?.id ?? ""
            }
            if logResult {
                log(.claude, .info, "Claude API healthy (HTTP \(res.httpStatus ?? 200), \(res.latencyMs) ms, \(res.models.count) models, key \(claude.keyHint ?? "stored"))")
            }
            return true
        } else {
            claude.light = .red
            claude.statusLabel = "Error"
            bannerError = res.error
            log(.claude, .error, "Claude API check failed (\(res.error ?? "Unknown error"))")
            return false
        }
    }

    public func disconnectClaudeKey() {
        keychain.delete(.claudeAPIKey)
        claude = ClaudeState()
        log(.claude, .info, "Cleared Claude API key from macOS Keychain")
    }

    // MARK: - Batch & Utility Controls

    public func refreshAllServices() async {
        busyAction = "refresh-all"
        defer { busyAction = nil }
        await probeVite(logTransition: true)
        await probeOllama(logResult: true)
        if !config.gitRepoFullName.isEmpty {
            await checkAndDeployGit(forcePull: false, trigger: "refresh all")
        }
        if keychain.read(.claudeAPIKey) != nil {
            await probeClaude(logResult: true)
        }
    }

    public func saveConfiguration(_ updated: BeaconConfig) async {
        config = updated
        vite.monitorURL = updated.monitorURL
        vite.autoRestart = updated.autoRestart
        git.repoFullName = updated.gitRepoFullName
        git.branch = updated.gitBranch
        git.autoDeploy = updated.gitAutoDeploy
        git.pollIntervalSec = updated.gitPollIntervalSec
        ollama.endpoint = updated.ollamaEndpoint
        flatFileStore.saveConfig(updated)
        log(.system, .info, "Saved flat-file configuration to \(flatFileStore.configFileURL.lastPathComponent)")
        await probeVite(logTransition: true)
        await probeOllama(logResult: false)
    }

    public func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Folder"
        if panel.runModal() == .OK, let url = panel.url {
            config.workingDir = url.path
            flatFileStore.saveConfig(config)
            log(.system, .info, "Updated local project folder to \(url.path)")
        }
    }

    public func exportActivityLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "beacon-activity.log"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: flatFileStore.logFileURL, to: dest)
            log(.system, .info, "Exported flat-file activity log to \(dest.lastPathComponent)")
        }
    }

    public func clearLogs() {
        flatFileStore.clearLogs()
        logs = []
        log(.system, .info, "Flat-file activity log cleared")
    }

    public func sendTestAlert() async {
        let note = await alertService.sendAlert(
            title: "Test Notification",
            body: "Beacon native macOS alerts are active.",
            recipientEmail: config.recipientEmail,
            emailEnabled: config.emailEnabled
        )
        log(.email, .info, note)
    }
}
