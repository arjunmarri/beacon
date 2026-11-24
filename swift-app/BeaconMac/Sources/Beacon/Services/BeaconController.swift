import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
public final class BeaconController {
    public var config: BeaconConfig
    public var appStates: [UUID: ManagedAppRuntimeState] = [:]
    public var systemTools: [DependencyToolStatus] = []
    public var terminalLines: [TerminalOutputLine] = []
    public var git = GitDeployState()
    public var ollama = OllamaState()
    public var claude = ClaudeState()
    public var launchd = LaunchdDaemonState()
    public var builtInServer = BuiltInServerState()
    public var update = AppUpdateState()
    public var scriptsInstalled: Bool = false
    public var serverLogSearchResult: ServerLogSearchResult?
    public var isSearchingServerLog: Bool = false
    public var aiHelpContext: AILogContext?
    public var aiHelpResult: AITroubleshootingResult?
    public var isAnalyzingLogs: Bool = false
    public var showingDependencyInstaller: Bool = false
    public var dependencyInstallerAppID: UUID?
    public var logs: [LogEntry] = []
    public var logFileBytes: Int64 = 0
    public var busyAction: String?
    public var bannerError: String?

    public let flatFileStore = FlatFileStore()
    public let keychain = KeychainStore()
    public let terminalService = TerminalIntegrationService()
    public let startupService = StartupSchedulerService()
    public let sleepService = SleepPreventionService()

    private let processService = LocalProcessService()
    private let deploymentService = AppDeploymentService()
    private let builtInServerService: BuiltInNodeServerService
    private let serverLogSearchService = ServerLogSearchService()
    private let aiTroubleshootingService = LogTroubleshootingService()
    private let updateService = AppUpdateService()
    private let gitService = GitDeployService()
    private let ollamaService = OllamaService()
    private let claudeService = ClaudeService()
    private let alertService = AlertService()

    private var pollingTask: Task<Void, Never>?
    private var updateLoopTask: Task<Void, Never>?
    private var tickCount = 0

    public var aggregateLight: TrafficLightColor {
        var lights: [TrafficLightColor] = [git.light, ollama.light, claude.light]
        lights.append(contentsOf: config.managedApps.map { runtimeState(for: $0.id).light })
        if lights.contains(.red) { return .red }
        if lights.contains(.amber) { return .amber }
        return .green
    }

    public init() {
        let loaded = flatFileStore.loadConfig()
        self.builtInServerService = BuiltInNodeServerService(dataDirectoryURL: flatFileStore.dataDirectoryURL)
        self.config = loaded
        self.config.startupSchedule.launchAtLogin = startupService.isLaunchAtLoginEnabled
        self.builtInServer.port = loaded.builtInServer.port
        self.ollama.endpoint = loaded.ollamaEndpoint
        self.ollama.activeModel = loaded.ollamaActiveModel
        self.logs = flatFileStore.loadRecentLogs()
        self.logFileBytes = flatFileStore.logFileByteCount()

        for app in loaded.managedApps {
            self.appStates[app.id] = ManagedAppRuntimeState()
        }

        self.builtInServerService.writeRegistry(from: loaded.builtInServer)
        self.launchd.plistPath = startupService.launchdPlistTildePath
        self.launchd.serverLogPath = startupService.serverLogTildePath
        self.scriptsInstalled = EmbeddedScripts.autoInstallIfNotSandboxed()

        if loaded.startupSchedule.preventSleep {
            let sleepRes = sleepService.setPreventSystemSleep(true)
            self.launchd.sleepAssertionActive = sleepService.isAssertionActive
            log(.startup, sleepRes.ok ? .info : .warn, sleepRes.detail)
        }

        alertService.requestPermission()
        log(.system, .info, "BeaconMac initialized with \(loaded.managedApps.count) managed app(s) (flat-file log: \(flatFileStore.logFileURL.path))")

        Task {
            await bootServices()
        }
        startPollingLoop()
        startAutoUpdateLoop()
    }

    public func runtimeState(for appID: UUID) -> ManagedAppRuntimeState {
        appStates[appID] ?? ManagedAppRuntimeState()
    }

    public func log(_ source: LogSource, _ level: LogLevel, _ message: String) {
        let entry = flatFileStore.appendLog(source: source, level: level, message: message)
        logs.append(entry)
        if logs.count > 400 {
            logs = Array(logs.suffix(400))
        }
        logFileBytes = flatFileStore.logFileByteCount()
    }

    public func appendTerminal(appName: String, text: String, isError: Bool = false) {
        terminalLines.append(TerminalOutputLine(appName: appName, text: text, isError: isError))
        if terminalLines.count > 500 {
            terminalLines = Array(terminalLines.suffix(500))
        }
    }

    public func clearTerminal() {
        terminalLines = []
    }

    private func bootServices() async {
        scriptsInstalled = EmbeddedScripts.areScriptsInstalled()
        if scriptsInstalled {
            await auditSystemDependencies()
            await refreshLaunchdStatus()
        }
        await probeAllManagedApps(logTransitions: true)
        await probeBuiltInNodeServer(logTransitions: false)
        if config.builtInServer.autoStart && !builtInServer.isRunning {
            await startBuiltInNodeServer()
        }
        await probeOllama(logResult: true)

        if let savedGitToken = keychain.read(.githubToken), !savedGitToken.isEmpty {
            git.keyHint = SecretMasker.mask(savedGitToken)
            await connectGitToken(savedGitToken, persistToKeychain: false)
        }

        if let savedClaudeKey = keychain.read(.claudeAPIKey), !savedClaudeKey.isEmpty {
            claude.keyHint = SecretMasker.mask(savedClaudeKey)
            await probeClaude(logResult: true)
        }

        // Automatically start or deploy any app marked runOnStartup
        let startupApps = config.managedApps.filter(\.runOnStartup)
        if !startupApps.isEmpty {
            log(.startup, .info, "Running startup sequence for \(startupApps.count) app(s)...")
            for app in startupApps {
                let state = runtimeState(for: app.id)
                if !state.isHealthy {
                    if config.startupSchedule.autoDeployOnStartup && !app.repoURL.isEmpty {
                        await cloneBuildAndDeploy(app: app, trigger: "startup")
                    } else if !app.localPath.isEmpty {
                        await restartManagedApp(app, reason: "startup")
                    }
                }
            }
        }
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { break }
                self.tickCount += 1

                await self.probeAllManagedApps(logTransitions: true)

                if self.tickCount % 3 == 0 {
                    await self.probeBuiltInNodeServer(logTransitions: true)
                }

                if self.tickCount % 5 == 0 {
                    await self.probeOllama(logResult: false)
                }

                let gitIntervalTicks = max(5, self.config.gitPollIntervalSec / 3)
                if self.tickCount % gitIntervalTicks == 0 {
                    await self.pollAutoDeployApps()
                }

                if self.tickCount % 20 == 0 && self.keychain.read(.claudeAPIKey) != nil {
                    await self.probeClaude(logResult: false)
                }
            }
        }
    }

    private func startAutoUpdateLoop() {
        updateLoopTask?.cancel()
        updateLoopTask = Task { [weak self] in
            // Short delay so initial launch stays snappy
            try? await Task.sleep(for: .seconds(4))
            while !Task.isCancelled {
                guard let self else { break }
                if self.config.autoCheckForUpdates {
                    await self.checkForUpdates(userInitiated: false)
                }
                // Re-check every 6 hours automatically
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    // MARK: - Multi-App CRUD, Probe, Dependency Audit & Clone/Build/Deploy

    public func upsertManagedApp(_ app: ManagedApp) async {
        let normalizedURL = LocalProcessService.normalizeLocalAppURL(app.monitorURL)
        guard LocalProcessService.isValidLocalAppURL(normalizedURL) else {
            bannerError = "Monitor URL for \(app.name) must use a local host (localhost, 127.0.0.1, ::1, *.localhost, or *.local)."
            return
        }

        var normalized = app
        normalized.monitorURL = normalizedURL
        normalized.port = LocalProcessService.extractPort(from: normalizedURL, fallback: app.port)

        bannerError = nil
        if let idx = config.managedApps.firstIndex(where: { $0.id == normalized.id }) {
            config.managedApps[idx] = normalized
            log(.vite, .info, "Updated managed app \"\(normalized.name)\" (\(normalized.monitorURL))")
        } else {
            config.managedApps.append(normalized)
            appStates[normalized.id] = ManagedAppRuntimeState()
            log(.vite, .info, "Added managed app \"\(normalized.name)\" (\(normalized.monitorURL))")
        }
        flatFileStore.saveConfig(config)
        await probeManagedApp(normalized, logTransition: true)
        if !normalized.localPath.isEmpty {
            await checkDependencies(for: normalized)
        }
    }

    public func deleteManagedApp(_ app: ManagedApp) {
        config.managedApps.removeAll { $0.id == app.id }
        appStates.removeValue(forKey: app.id)
        flatFileStore.saveConfig(config)
        log(.vite, .info, "Removed managed app \"\(app.name)\"")
    }

    public func toggleAppStartup(_ app: ManagedApp) {
        guard let idx = config.managedApps.firstIndex(where: { $0.id == app.id }) else { return }
        config.managedApps[idx].runOnStartup.toggle()
        let enabled = config.managedApps[idx].runOnStartup
        flatFileStore.saveConfig(config)
        log(.startup, .info, "Startup launch \(enabled ? "enabled" : "disabled") for \(app.name)")
    }

    public func probeAllManagedApps(logTransitions: Bool) async {
        for app in config.managedApps {
            await probeManagedApp(app, logTransition: logTransitions)
        }
    }

    public func probeManagedApp(_ app: ManagedApp, logTransition: Bool) async {
        var state = runtimeState(for: app.id)
        if state.isDeploying { return }

        let wasHealthy = state.isHealthy
        let result = await processService.probe(urlString: app.monitorURL)
        state.lastCheckedAt = Date()
        state.httpStatus = result.httpStatus
        state.responseTimeMs = result.responseTimeMs
        state.isHealthy = result.healthy
        state.lastError = result.error

        if result.healthy {
            state.consecutiveFailures = 0
            state.light = .green
            state.statusLabel = "Healthy"
            if state.healthySince == nil {
                state.healthySince = Date()
            }
            if logTransition && !wasHealthy {
                log(.vite, .info, "[\(app.name)] Reachable at \(app.monitorURL) (HTTP \(result.httpStatus ?? 200), \(result.responseTimeMs ?? 1) ms)")
            }
            appStates[app.id] = state
        } else {
            state.healthySince = nil
            state.consecutiveFailures += 1
            state.light = .red
            state.statusLabel = "Down"
            appStates[app.id] = state

            if state.consecutiveFailures == 3 {
                log(.vite, .error, "[\(app.name)] Failed 3 consecutive health checks at \(app.monitorURL)")
                if config.notifyOnCrash {
                    let note = await alertService.sendAlert(
                        title: "\(app.name) Down",
                        body: "\(app.monitorURL) stopped responding.",
                        recipientEmail: config.recipientEmail,
                        emailEnabled: config.emailEnabled
                    )
                    log(.email, .info, note)
                }
                if app.autoRestart && !app.localPath.isEmpty && state.restartCount < config.maxRestarts {
                    await restartManagedApp(app, reason: "auto-recovery #\(state.restartCount + 1)")
                }
            }
        }
    }

    public func auditSystemDependencies() async {
        let audit = await deploymentService.checkDependencies(for: nil)
        if !audit.tools.isEmpty {
            systemTools = audit.tools
            let installed = audit.tools
                .filter(\.available)
                .map { "\($0.name) (\($0.detail))" }
            let missingRequired = audit.tools
                .filter { !$0.available && !$0.isOptional }
                .map(\.name)
            if !installed.isEmpty {
                appendTerminal(appName: "system", text: "Runtime tools ready: \(installed.joined(separator: ", "))")
            }
            if !missingRequired.isEmpty {
                appendTerminal(
                    appName: "system",
                    text: "Missing required tools: \(missingRequired.joined(separator: ", "))",
                    isError: true
                )
            }
        }
        for line in audit.result.stderrLines {
            appendTerminal(appName: "system", text: line, isError: true)
        }
    }

    public func checkDependencies(for app: ManagedApp) async {
        busyAction = "deps-\(app.id.uuidString)"
        defer { busyAction = nil }

        appendTerminal(appName: app.name, text: "$ beacon-check-deps.sh \"\(app.localPath)\"")
        let audit = await deploymentService.checkDependencies(for: app.localPath)
        if !audit.tools.isEmpty {
            systemTools = audit.tools
        }
        if !audit.appSummary.isEmpty {
            appendTerminal(appName: app.name, text: audit.appSummary)
        }
        for line in audit.result.stderrLines {
            appendTerminal(appName: app.name, text: line, isError: true)
        }

        var state = runtimeState(for: app.id)
        state.dependencySummary = audit.appSummary
        appStates[app.id] = state
        log(.terminal, audit.result.ok ? .info : .warn, "[\(app.name)] Dependency check: \(audit.appSummary)")
    }

    public func openDependencyInstaller(for app: ManagedApp? = nil) {
        dependencyInstallerAppID = app?.id ?? config.managedApps.first?.id
        showingDependencyInstaller = true
    }

    public func installPrerequisitesAndDependencies(
        for app: ManagedApp?,
        requestedTools: [String],
        strategy: DependencyInstallStrategy = .auto
    ) async -> ScriptExecutionResult {
        busyAction = "install-deps-\(app?.id.uuidString ?? "system")"
        defer { busyAction = nil }

        let targetLabel = app?.name ?? "system"
        let dirArg = app?.localPath ?? ""
        let toolsDesc = requestedTools.isEmpty ? "auto" : requestedTools.joined(separator: ",")
        appendTerminal(appName: targetLabel, text: "$ beacon-check-deps.sh --install \"\(dirArg)\" \(toolsDesc) \(strategy.rawValue)")

        let res = await deploymentService.installPrerequisitesAndDependencies(
            workingDir: dirArg.isEmpty ? nil : dirArg,
            requestedTools: requestedTools,
            strategy: strategy
        )

        for line in res.stdoutLines {
            appendTerminal(appName: targetLabel, text: line)
        }
        for line in res.stderrLines {
            appendTerminal(appName: targetLabel, text: line, isError: true)
        }

        if res.ok {
            log(.terminal, .info, "[\(targetLabel)] Installed dependencies (\(toolsDesc), mode: \(strategy.rawValue))")
        } else {
            bannerError = "[\(targetLabel)] \(res.summary)"
            log(.terminal, .error, "[\(targetLabel)] Dependency install failed: \(res.summary)")
        }

        await auditSystemDependencies()
        if let app, !app.localPath.isEmpty {
            await checkDependencies(for: app)
        }
        return res
    }

    // MARK: - AI Log Troubleshooting

    public func openAIHelp(title: String, logText: String, appName: String? = nil) {
        aiHelpResult = nil
        aiHelpContext = AILogContext(title: title, logText: logText, appName: appName)
    }

    public func buildAITroubleshootingPrompt(context: AILogContext, followUp: String? = nil) -> String {
        aiTroubleshootingService.buildPrompt(context: context, followUp: followUp)
    }

    public func analyzeLogsWithAI(
        context: AILogContext,
        followUp: String?,
        provider: AIHelpProvider
    ) async {
        isAnalyzingLogs = true
        defer { isAnalyzingLogs = false }

        let result = await aiTroubleshootingService.analyze(
            context: context,
            followUp: followUp,
            provider: provider,
            claudeAPIKey: keychain.read(.claudeAPIKey),
            claudeModel: claude.activeModel,
            ollamaEndpoint: config.ollamaEndpoint,
            ollamaModel: ollama.activeModel,
            ollamaConnected: ollama.isConnected,
            claudeConnected: claude.isConnected
        )

        aiHelpResult = result
        if result.ok {
            log(.system, .info, "AI Help analyzed \"\(context.title)\" via \(result.providerLabel) (\(result.durationMs) ms)")
        } else if let err = result.error {
            log(.system, .warn, "AI Help (\(result.providerLabel)): \(err)")
        }
    }

    public func cloneBuildAndDeploy(app: ManagedApp, trigger: String = "manual") async {
        busyAction = "deploy-\(app.id.uuidString)"
        defer { busyAction = nil }

        var state = runtimeState(for: app.id)
        state.isDeploying = true
        state.light = .amber
        state.statusLabel = "Deploying"
        state.lastError = nil
        appStates[app.id] = state

        log(.git, .info, "[\(app.name)] Starting clone/pull, dependency check, build & local deploy (\(trigger))...")
        appendTerminal(appName: app.name, text: "$ beacon-deploy.sh \(app.repoURL) \(app.branch) \(app.localPath) \(app.port)")

        let res = await deploymentService.deployApp(app)
        for line in res.stdoutLines {
            appendTerminal(appName: app.name, text: line)
        }
        for line in res.stderrLines {
            appendTerminal(appName: app.name, text: line, isError: true)
        }

        state = runtimeState(for: app.id)
        state.isDeploying = false

        if res.ok {
            state.lastDeployedAt = Date()
            state.lastError = nil
            state.dependencySummary = "Deps verified & built"
            appStates[app.id] = state
            log(.git, .info, "[\(app.name)] \(res.summary)")
            if config.notifyOnDeploy {
                let note = await alertService.sendAlert(
                    title: "Deployed \(app.name)",
                    body: res.summary,
                    recipientEmail: config.recipientEmail,
                    emailEnabled: config.emailEnabled
                )
                log(.email, .info, note)
            }
            try? await Task.sleep(for: .seconds(2))
            await probeManagedApp(app, logTransition: true)
        } else {
            state.light = .red
            state.statusLabel = "Deploy Failed"
            state.lastError = res.summary
            appStates[app.id] = state
            bannerError = "[\(app.name)] \(res.summary)"
            log(.git, .error, "[\(app.name)] \(res.summary)")
        }
    }

    public func restartManagedApp(_ app: ManagedApp, reason: String = "manual") async {
        busyAction = "restart-\(app.id.uuidString)"
        defer { busyAction = nil }

        var state = runtimeState(for: app.id)
        state.light = .amber
        state.statusLabel = "Restarting"
        appStates[app.id] = state

        appendTerminal(appName: app.name, text: "$ beacon-restart.sh \"\(app.localPath)\" \(app.port) (\(reason))")
        let res = await deploymentService.restartApp(app)
        for line in res.stdoutLines { appendTerminal(appName: app.name, text: line) }
        for line in res.stderrLines { appendTerminal(appName: app.name, text: line, isError: true) }

        if res.ok {
            state.restartCount += 1
            state.lastError = nil
            appStates[app.id] = state
            log(.vite, .info, "[\(app.name)] Restarted on port \(app.port) (\(reason))")
            try? await Task.sleep(for: .seconds(2))
            await probeManagedApp(app, logTransition: true)
        } else {
            state.light = .red
            state.statusLabel = "Action Needed"
            state.lastError = res.summary
            appStates[app.id] = state
            log(.vite, .warn, "[\(app.name)] \(res.summary)")
        }
    }

    public func stopManagedApp(_ app: ManagedApp) async {
        busyAction = "stop-\(app.id.uuidString)"
        defer { busyAction = nil }

        appendTerminal(appName: app.name, text: "$ beacon-stop.sh \(app.port)")
        let res = await deploymentService.stopApp(port: app.port)
        for line in res.stdoutLines { appendTerminal(appName: app.name, text: line) }
        for line in res.stderrLines { appendTerminal(appName: app.name, text: line, isError: true) }

        var state = runtimeState(for: app.id)
        state.light = .amber
        state.statusLabel = "Stopped"
        state.isHealthy = false
        state.healthySince = nil
        appStates[app.id] = state
        log(.vite, .info, "[\(app.name)] \(res.summary)")
    }

    private func pollAutoDeployApps() async {
        let token = keychain.read(.githubToken)
        for app in config.managedApps where app.autoDeploy {
            guard let fullName = app.githubFullName else { continue }
            var state = runtimeState(for: app.id)
            if state.isDeploying { continue }

            if let commit = try? await gitService.fetchLatestCommit(repoFullName: fullName, branch: app.branch, token: token) {
                let previous = state.commitHash
                state.commitHash = commit.shaShort
                state.commitMessage = commit.message
                appStates[app.id] = state

                if previous != "—" && previous != commit.shaShort {
                    log(.git, .info, "[\(app.name)] New commit \(commit.shaShort) detected on \(fullName)@\(app.branch); triggering auto-deploy")
                    await cloneBuildAndDeploy(app: app, trigger: "git poll \(commit.shaShort)")
                }
            }
        }
    }

    // MARK: - Terminal & Startup / Cron Integration

    public func openInTerminal(app: ManagedApp) {
        let res = terminalService.openFolderInTerminal(app.localPath)
        log(.terminal, res.ok ? .info : .warn, "[\(app.name)] \(res.detail)")
        if !res.ok { bannerError = res.detail }
    }

    public func tailLogsInTerminal(app: ManagedApp) {
        let res = terminalService.openAppLogInTerminal(app: app)
        log(.terminal, .info, "[\(app.name)] \(res.detail)")
    }

    public func copyDeployCommand(for app: ManagedApp) {
        let cmd = terminalService.copyDeployCommand(for: app)
        appendTerminal(appName: app.name, text: "Copied deploy command: \(cmd)")
        log(.terminal, .info, "[\(app.name)] Copied terminal deploy command to clipboard")
    }

    public func toggleLaunchAtLogin(_ enabled: Bool) {
        let res = startupService.setLaunchAtLogin(enabled)
        config.startupSchedule.launchAtLogin = startupService.isLaunchAtLoginEnabled
        flatFileStore.saveConfig(config)
        log(.startup, res.ok ? .info : .warn, res.detail)
        if !res.ok { bannerError = res.detail }
    }

    public func updateStartupSchedule(autoDeploy: Bool, cronEnabled: Bool, cronExpression: String) {
        config.startupSchedule.autoDeployOnStartup = autoDeploy
        config.startupSchedule.cronEnabled = cronEnabled
        config.startupSchedule.cronExpression = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "@reboot"
            : cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        flatFileStore.saveConfig(config)
        log(.startup, .info, "Saved startup schedule (cron: \(config.startupSchedule.cronExpression), auto-deploy on boot: \(autoDeploy))")
    }

    public func copyCrontabInstallCommand() {
        let cmd = startupService.copyCrontabCommand(cronExpression: config.startupSchedule.cronExpression)
        appendTerminal(appName: "cron", text: "Copied crontab command: \(cmd)")
        log(.startup, .info, "Copied macOS crontab install command to clipboard")
    }

    public func exportLaunchAgentPlist() {
        let res = startupService.exportLaunchAgentPlist(preventSleep: config.startupSchedule.preventSleep)
        log(.startup, res.ok ? .info : .warn, res.detail)
    }

    public func refreshLaunchdStatus() async {
        let probe = await deploymentService.runLaunchdAction(
            "status",
            bundleID: startupService.bundleID,
            preventSleep: config.startupSchedule.preventSleep
        )
        applyLaunchdProbe(probe)
    }

    public func installAndLoadLaunchdAgent() async {
        busyAction = "launchd-install"
        defer { busyAction = nil }

        appendTerminal(appName: "launchd", text: "$ beacon-launchd.sh install \(startupService.bundleID) \(config.startupSchedule.preventSleep ? "1" : "0")")
        let probe = await deploymentService.runLaunchdAction(
            "install",
            bundleID: startupService.bundleID,
            preventSleep: config.startupSchedule.preventSleep
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "launchd", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "launchd", text: line, isError: true) }

        applyLaunchdProbe(probe)
        if probe.result.ok {
            log(.startup, .info, "Installed and loaded macOS launchd supervisor (\(startupService.launchdPlistTildePath))")
            await refreshLaunchdStatus()
        } else {
            bannerError = probe.result.summary
            log(.startup, .error, "Failed to load launchd supervisor: \(probe.result.summary)")
        }
    }

    public func unloadLaunchdAgent() async {
        busyAction = "launchd-stop"
        defer { busyAction = nil }

        appendTerminal(appName: "launchd", text: "$ launchctl unload \(startupService.launchdPlistTildePath)")
        let probe = await deploymentService.runLaunchdAction(
            "stop",
            bundleID: startupService.bundleID,
            preventSleep: config.startupSchedule.preventSleep
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "launchd", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "launchd", text: line, isError: true) }

        applyLaunchdProbe(probe)
        if probe.result.ok {
            log(.startup, .info, "Stopped macOS launchd background service (\(startupService.launchdLabel))")
        } else {
            bannerError = probe.result.summary
            log(.startup, .warn, probe.result.summary)
        }
    }

    private func applyLaunchdProbe(_ probe: AppDeploymentService.LaunchdProbeResult) {
        if let installed = probe.isInstalled { launchd.isInstalled = installed }
        if let loaded = probe.isLoaded { launchd.isLoaded = loaded }
        if let pid = probe.pidText { launchd.pidText = pid }
        if let caff = probe.caffeinateActive { launchd.caffeinateActive = caff }
        if let plist = probe.plistPath { launchd.plistPath = plist }
        if let logPath = probe.serverLogPath { launchd.serverLogPath = logPath }
        launchd.sleepAssertionActive = sleepService.isAssertionActive

        if launchd.isLoaded {
            launchd.light = .green
            launchd.statusLabel = (launchd.pidText != "-" && launchd.pidText != "running" && launchd.pidText != "—")
                ? "Loaded · PID \(launchd.pidText)"
                : "Loaded"
        } else if launchd.isInstalled {
            launchd.light = .amber
            launchd.statusLabel = "Unloaded"
        } else {
            launchd.light = .amber
            launchd.statusLabel = "Not Installed"
        }
    }

    public func togglePreventSleep(_ enabled: Bool) {
        config.startupSchedule.preventSleep = enabled
        flatFileStore.saveConfig(config)
        let res = sleepService.setPreventSystemSleep(enabled)
        launchd.sleepAssertionActive = sleepService.isAssertionActive
        log(.startup, res.ok ? .info : .warn, res.detail)
        if !res.ok { bannerError = res.detail }
    }

    public func watchSupervisorLiveLogs() {
        let res = terminalService.watchSupervisorLogInTerminal()
        appendTerminal(appName: "logs", text: "$ \(startupService.tailServerLogCommand)")
        log(.terminal, res.ok ? .info : .warn, res.detail)
    }

    public func searchServerLog(query: String, options: ServerLogSearchOptions) async {
        let cleaned = query.trimmingCharacters(in: .newlines)
        guard !cleaned.isEmpty else {
            serverLogSearchResult = nil
            return
        }
        isSearchingServerLog = true
        defer { isSearchingServerLog = false }

        let result = await serverLogSearchService.search(
            query: cleaned,
            options: options,
            deploymentService: deploymentService
        )
        serverLogSearchResult = result

        if result.ok {
            log(.terminal, .info, "Searched \(result.logPath) for \"\(cleaned)\": \(result.matchCount) match(es) in \(result.durationMs) ms")
        } else if let err = result.errorMessage {
            log(.terminal, .warn, "Server log search failed: \(err)")
        }
    }

    public func clearServerLogSearch() {
        serverLogSearchResult = nil
    }

    public func copyServerLogSearchResults() {
        guard let result = serverLogSearchResult, !result.preformattedOutput.isEmpty else { return }
        terminalService.copyCommand(result.preformattedOutput)
        log(.terminal, .info, "Copied \(result.matchCount) matched line(s) from \(result.logPath) to clipboard")
    }

    public func openEnergySettings() {
        let res = sleepService.openEnergySettings()
        log(.startup, res.ok ? .info : .warn, res.detail)
    }

    public func copyLaunchctlUnloadCommand() {
        let cmd = startupService.launchctlUnloadCommand
        terminalService.copyCommand(cmd)
        appendTerminal(appName: "launchd", text: "Copied: \(cmd)")
        log(.startup, .info, "Copied launchctl unload command to clipboard")
    }

    public func copyCaffeinateCommand() {
        let cmd = sleepService.copyCaffeinateCommand()
        appendTerminal(appName: "sleep", text: "Copied: \(cmd)")
        log(.startup, .info, "Copied caffeinate -s command to clipboard")
    }

    public func installHookScriptsFromApp() async {
        let res = EmbeddedScripts.installViaOpenPanel()
        scriptsInstalled = EmbeddedScripts.areScriptsInstalled()
        log(.system, res.ok ? .info : .warn, res.detail)
        if res.ok {
            bannerError = nil
            appendTerminal(appName: "system", text: res.detail)
            await auditSystemDependencies()
            await refreshLaunchdStatus()
        } else {
            bannerError = res.detail
        }
    }

    public func copyInstallScriptsCommand() {
        let cmd = EmbeddedScripts.terminalInstallOneLiner
        terminalService.copyCommand(cmd)
        appendTerminal(appName: "system", text: "Copied: \(cmd)")
        log(.system, .info, "Copied hook script install command to clipboard")
    }

    // MARK: - GitHub Account Keychain Sync

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
            git.light = .green
            git.statusLabel = "Connected"
            log(.git, .info, "Connected GitHub account @\(verified.username) via Keychain (\(verified.repos.count) repos accessible)")
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
            claude = ClaudeState()
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

    // MARK: - Batch & Utility Actions

    public func refreshAllServices() async {
        busyAction = "refresh-all"
        defer { busyAction = nil }
        await probeAllManagedApps(logTransitions: true)
        await probeBuiltInNodeServer(logTransitions: true)
        await probeOllama(logResult: true)
        if keychain.read(.claudeAPIKey) != nil {
            await probeClaude(logResult: true)
        }
    }

    // MARK: - Built-In Node.js App Host Server

    public func probeBuiltInNodeServer(logTransitions: Bool = false) async {
        let port = config.builtInServer.port
        builtInServer.port = port
        let wasRunning = builtInServer.isRunning

        if let health = await builtInServerService.probeHealth(port: port), health.ok {
            builtInServer.isRunning = true
            builtInServer.light = .green
            builtInServer.statusLabel = "Running :\(port)"
            builtInServer.pid = health.pid
            builtInServer.nodeVersion = health.nodeVersion
            builtInServer.uptimeSec = health.uptimeSec
            builtInServer.lastError = nil
            builtInServer.lastCheckedAt = Date()
            if logTransitions && !wasRunning {
                log(.system, .info, "Built-in Node.js server is online at http://127.0.0.1:\(port) (\(health.nodeVersion ?? "Node.js"))")
            }
        } else {
            builtInServer.isRunning = false
            builtInServer.light = .amber
            builtInServer.statusLabel = "Stopped"
            builtInServer.pid = nil
            builtInServer.uptimeSec = nil
            builtInServer.lastCheckedAt = Date()
            if logTransitions && wasRunning {
                log(.system, .warn, "Built-in Node.js server on port \(port) stopped responding")
            }
        }
    }

    public func startBuiltInNodeServer(restart: Bool = false) async {
        let port = (1024...65535).contains(config.builtInServer.port) ? config.builtInServer.port : 4173
        config.builtInServer.port = port
        builtInServer.port = port
        builtInServerService.writeRegistry(from: config.builtInServer)
        flatFileStore.saveConfig(config)

        let action = restart ? "restart" : "start"
        busyAction = "builtin-node-\(action)"
        defer { busyAction = nil }

        appendTerminal(appName: "node-host", text: "$ beacon-node-server.sh \(action) \(port)")
        let res = await deploymentService.runBuiltInNodeServerAction(
            action,
            port: port,
            registryPath: builtInServerService.registryURL.path
        )
        for line in res.stdoutLines { appendTerminal(appName: "node-host", text: line) }
        for line in res.stderrLines { appendTerminal(appName: "node-host", text: line, isError: true) }

        if res.ok {
            builtInServer.lastError = nil
            await probeBuiltInNodeServer(logTransitions: false)
            log(.system, .info, "Built-in Node.js server running at http://127.0.0.1:\(port)")
        } else {
            builtInServer.isRunning = false
            builtInServer.light = .red
            builtInServer.statusLabel = "Start Failed"
            builtInServer.lastError = res.summary
            bannerError = res.summary
            log(.system, .error, "Built-in Node.js server failed to start: \(res.summary)")
        }
    }

    public func stopBuiltInNodeServer() async {
        let port = config.builtInServer.port
        busyAction = "builtin-node-stop"
        defer { busyAction = nil }

        appendTerminal(appName: "node-host", text: "$ beacon-node-server.sh stop \(port)")
        let res = await deploymentService.runBuiltInNodeServerAction(
            "stop",
            port: port,
            registryPath: builtInServerService.registryURL.path
        )
        for line in res.stdoutLines { appendTerminal(appName: "node-host", text: line) }
        for line in res.stderrLines { appendTerminal(appName: "node-host", text: line, isError: true) }

        builtInServer.isRunning = false
        builtInServer.light = .amber
        builtInServer.statusLabel = "Stopped"
        builtInServer.pid = nil
        builtInServer.uptimeSec = nil
        log(.system, .info, "Stopped built-in Node.js server on port \(port)")
    }

    public func updateBuiltInNodeServerSettings(port: Int, autoStart: Bool) async {
        let clampedPort = (1024...65535).contains(port) ? port : 4173
        let portChanged = clampedPort != config.builtInServer.port
        let wasRunning = builtInServer.isRunning

        if portChanged && wasRunning {
            await stopBuiltInNodeServer()
        }

        config.builtInServer.port = clampedPort
        config.builtInServer.autoStart = autoStart
        builtInServer.port = clampedPort
        flatFileStore.saveConfig(config)
        builtInServerService.writeRegistry(from: config.builtInServer)

        if portChanged && wasRunning {
            await startBuiltInNodeServer(restart: true)
        }
    }

    @discardableResult
    public func loadAppIntoBuiltInServer(
        name: String,
        mode: BuiltInNodeAppMode,
        folderPath: String = "",
        proxyPort: Int? = nil,
        spaFallback: Bool = true,
        makeActiveRoot: Bool = true,
        autoStartServer: Bool = true
    ) async -> BuiltInMountedApp {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Loaded App" : trimmedName
        let trimmedFolder = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reuse existing entry if same folder or proxy port is already mounted
        if let existingIdx = config.builtInServer.mountedApps.firstIndex(where: { existing in
            existing.mode == mode && (
                (mode == .staticFolder && !trimmedFolder.isEmpty && existing.folderPath == trimmedFolder) ||
                (mode == .localProxy && proxyPort != nil && existing.proxyPort == proxyPort)
            )
        }) {
            config.builtInServer.mountedApps[existingIdx].name = finalName
            config.builtInServer.mountedApps[existingIdx].spaFallback = spaFallback
            let updated = config.builtInServer.mountedApps[existingIdx]
            if makeActiveRoot {
                config.builtInServer.activeRootAppID = updated.id
            }
            flatFileStore.saveConfig(config)
            builtInServerService.writeRegistry(from: config.builtInServer)
            log(.system, .info, "Updated \"\(updated.name)\" in built-in Node.js server (/\(updated.slug))")
            if autoStartServer && !builtInServer.isRunning {
                await startBuiltInNodeServer()
            }
            return updated
        }

        let existingSlugs = Set(config.builtInServer.mountedApps.map(\.slug))
        let slug = BuiltInNodeServerService.makeSlug(from: finalName, existingSlugs: existingSlugs)
        let mounted = BuiltInMountedApp(
            name: finalName,
            slug: slug,
            mode: mode,
            folderPath: trimmedFolder,
            proxyPort: mode == .localProxy ? proxyPort : nil,
            spaFallback: spaFallback
        )
        config.builtInServer.mountedApps.append(mounted)
        if makeActiveRoot || config.builtInServer.activeRootAppID == nil {
            config.builtInServer.activeRootAppID = mounted.id
        }
        flatFileStore.saveConfig(config)
        builtInServerService.writeRegistry(from: config.builtInServer)

        let targetDesc = mode == .localProxy
            ? "proxy → 127.0.0.1:\(proxyPort ?? 0)"
            : BuiltInNodeServerService.describeServeRoot(for: trimmedFolder)
        log(.system, .info, "Loaded \"\(mounted.name)\" into built-in Node.js server (\(targetDesc)) at /apps/\(mounted.slug)/")

        if autoStartServer && !builtInServer.isRunning {
            await startBuiltInNodeServer()
        }
        return mounted
    }

    public func loadManagedAppIntoBuiltInServer(_ app: ManagedApp, mode: BuiltInNodeAppMode? = nil) async {
        let chosenMode: BuiltInNodeAppMode
        if let mode {
            chosenMode = mode
        } else {
            let folderDesc = BuiltInNodeServerService.describeServeRoot(for: app.localPath)
            let hasBuiltStatic = folderDesc.contains("index.html")
            let state = runtimeState(for: app.id)
            chosenMode = (state.isHealthy || !hasBuiltStatic) ? .localProxy : .staticFolder
        }

        await loadAppIntoBuiltInServer(
            name: app.name,
            mode: chosenMode,
            folderPath: app.localPath,
            proxyPort: app.port,
            spaFallback: true,
            makeActiveRoot: true,
            autoStartServer: true
        )
    }

    public func setBuiltInRootApp(_ appID: UUID?) {
        config.builtInServer.activeRootAppID = appID
        flatFileStore.saveConfig(config)
        builtInServerService.writeRegistry(from: config.builtInServer)
        if let appID, let match = config.builtInServer.mountedApps.first(where: { $0.id == appID }) {
            log(.system, .info, "Set \"\(match.name)\" as active root app at \(builtInServer.baseURL)/")
        } else {
            log(.system, .info, "Switched built-in Node.js root \(builtInServer.baseURL)/ back to App Launcher")
        }
    }

    public func removeBuiltInMountedApp(_ app: BuiltInMountedApp) {
        config.builtInServer.mountedApps.removeAll { $0.id == app.id }
        if config.builtInServer.activeRootAppID == app.id {
            config.builtInServer.activeRootAppID = config.builtInServer.mountedApps.first?.id
        }
        flatFileStore.saveConfig(config)
        builtInServerService.writeRegistry(from: config.builtInServer)
        log(.system, .info, "Unloaded \"\(app.name)\" from built-in Node.js server")
    }

    public func openBuiltInAppInBrowser(_ app: BuiltInMountedApp? = nil, openLauncher: Bool = false) {
        let base = builtInServer.baseURL
        let urlString: String
        if openLauncher {
            urlString = "\(base)/_beacon/"
        } else if let app {
            if config.builtInServer.activeRootAppID == app.id {
                urlString = "\(base)/"
            } else {
                urlString = "\(base)/apps/\(app.slug)/"
            }
        } else {
            urlString = "\(base)/"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func saveGlobalConfiguration(
        ollamaEndpoint: String,
        gitPollIntervalSec: Int,
        maxRestarts: Int,
        recipientEmail: String,
        notifyOnCrash: Bool,
        notifyOnDeploy: Bool,
        notifyOnOllamaDown: Bool,
        autoCheckForUpdates: Bool? = nil,
        autoInstallUpdates: Bool? = nil
    ) async {
        config.ollamaEndpoint = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        config.gitPollIntervalSec = max(15, min(3600, gitPollIntervalSec))
        config.maxRestarts = max(1, min(100, maxRestarts))
        config.recipientEmail = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        config.notifyOnCrash = notifyOnCrash
        config.notifyOnDeploy = notifyOnDeploy
        config.notifyOnOllamaDown = notifyOnOllamaDown
        if let autoCheckForUpdates { config.autoCheckForUpdates = autoCheckForUpdates }
        _ = autoInstallUpdates
        config.autoInstallUpdates = false
        config.updateFeedRepo = AppUpdateService.pinnedRepo
        ollama.endpoint = config.ollamaEndpoint
        flatFileStore.saveConfig(config)
        log(.system, .info, "Saved flat-file configuration to \(flatFileStore.configFileURL.lastPathComponent)")
        await probeOllama(logResult: false)
    }

    // MARK: - Verified Self-Updates

    public func updateAutoUpdatePreferences(autoCheck: Bool, autoInstall: Bool = false) {
        config.autoCheckForUpdates = autoCheck
        // Silent background binary swaps are disabled; users must explicitly trigger verified installs.
        config.autoInstallUpdates = false
        _ = autoInstall
        flatFileStore.saveConfig(config)
        log(.system, .info, "Update check preference saved (auto-check: \(autoCheck))")
    }

    public func checkForUpdates(userInitiated: Bool) async {
        guard update.status != .checking && update.status != .downloading && update.status != .installing else {
            return
        }
        update.status = .checking
        update.lastError = nil
        update.statusMessage = "Checking GitHub releases for updates…"

        do {
            let release = try await updateService.checkLatestRelease(
                repo: AppUpdateService.pinnedRepo,
                githubToken: keychain.read(.githubToken)
            )
            update.lastCheckedAt = Date()
            update.latestRelease = release

            let cmp = AppUpdateService.compareSemVer(release.version, update.currentVersion)
            if cmp == .orderedDescending {
                update.status = .updateAvailable
                update.statusMessage = "BeaconMac v\(release.version) is available — click Install to verify & update (installed: v\(update.currentVersion))"
                log(.system, .info, "Update available: BeaconMac v\(release.version) (current: v\(update.currentVersion)). Click Install to verify SHA-256, Developer ID signature, and Gatekeeper before updating.")
            } else {
                update.status = .upToDate
                update.statusMessage = "BeaconMac v\(update.currentVersion) is up to date"
                if userInitiated {
                    log(.system, .info, "BeaconMac v\(update.currentVersion) is up to date (latest: v\(release.version))")
                }
            }
        } catch {
            let msg = SecretMasker.redact(error.localizedDescription)
            update.lastCheckedAt = Date()
            update.status = .failed
            update.lastError = msg
            update.statusMessage = "Update check failed"
            if userInitiated {
                bannerError = "Update check failed: \(msg)"
                log(.system, .warn, "Update check failed: \(msg)")
            }
        }
    }

    public func installAvailableUpdate() async {
        guard let release = update.latestRelease else {
            await checkForUpdates(userInitiated: true)
            return
        }
        guard update.status != .downloading && update.status != .installing else { return }

        update.status = .downloading
        update.downloadProgress = 0.08
        update.lastError = nil
        update.statusMessage = "Verifying & downloading BeaconMac v\(release.version)…"
        log(.system, .info, "Starting verified self-update to BeaconMac v\(release.version)...")

        let outcome = await updateService.downloadAndInstall(release: release) { [weak self] progress, message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.update.downloadProgress = progress
                self.update.status = progress >= 0.65 ? .installing : .downloading
                self.update.statusMessage = message
            }
        }

        if outcome.ok {
            update.downloadProgress = 1.0
            update.status = outcome.willRelaunch ? .readyToRelaunch : .upToDate
            update.statusMessage = outcome.detail
            log(.system, .info, outcome.detail)

            if outcome.willRelaunch {
                try? await Task.sleep(for: .milliseconds(450))
                NSApplication.shared.terminate(nil)
            }
        } else {
            update.status = .failed
            update.lastError = outcome.detail
            update.statusMessage = outcome.detail
            bannerError = outcome.detail
            log(.system, .error, "Self-update rejected: \(outcome.detail)")
        }
    }

    public func openLatestReleasePage() {
        let fallback = URL(string: "https://github.com/\(AppUpdateService.pinnedRepo)/releases")!
        if let candidate = update.latestRelease?.htmlReleaseURL,
           AppUpdateService.isAllowedReleasePageURL(candidate) {
            NSWorkspace.shared.open(candidate)
        } else {
            NSWorkspace.shared.open(fallback)
        }
    }

    @discardableResult
    public func exportSessionLogs(
        format: LogExportFormat,
        filteredActivityLogs: [LogEntry]? = nil,
        scopeDescription: String? = nil
    ) -> Bool {
        let isFiltered = filteredActivityLogs != nil
        let bundle = LogExportService.buildBundle(
            from: self,
            activityLogs: filteredActivityLogs,
            terminalLines: terminalLines,
            scopeDescription: scopeDescription
                ?? (isFiltered
                    ? "Filtered Activity Logs + Current Session Deployment Output"
                    : "All Current Session Logs (System, Git, Services & Deployment Output)")
        )

        let panel = NSSavePanel()
        panel.title = "Export BeaconMac Session Logs"
        panel.message = "Save current session logs (system, Git, service events, and deployment output) as \(format.displayName)."
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = LogExportService.suggestedFilename(format: format, filtered: isFiltered)

        guard panel.runModal() == .OK, let dest = panel.url else {
            return false
        }

        do {
            let data = try LogExportService.render(bundle: bundle, format: format)
            try data.write(to: dest, options: .atomic)
            log(
                .system,
                .info,
                "Exported \(format.fileExtension.uppercased()) session logs (\(bundle.metadata.counts.totalActivityLogs) activity, \(bundle.metadata.counts.deploymentOutputLines) deployment lines) to \(dest.lastPathComponent)"
            )
            return true
        } catch {
            let msg = "Failed to export session logs: \(SecretMasker.redact(error.localizedDescription))"
            bannerError = msg
            log(.system, .error, msg)
            return false
        }
    }

    public func exportActivityLog() {
        exportSessionLogs(format: .txt)
    }

    public func clearLogs() {
        flatFileStore.clearLogs()
        logs = []
        log(.system, .info, "Flat-file activity log cleared")
    }

    public func sendTestAlert() async {
        let note = await alertService.sendAlert(
            title: "Test Notification",
            body: "BeaconMac native macOS alerts are active.",
            recipientEmail: config.recipientEmail,
            emailEnabled: config.emailEnabled
        )
        log(.email, .info, note)
    }
}
