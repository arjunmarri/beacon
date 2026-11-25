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
    public var cloudProviderStates: [CloudProviderKind: CloudProviderRuntimeState] = [:]
    public var launchd = LaunchdDaemonState()
    public var builtInServer = BuiltInServerState()
    public var nginxProxy = NginxProxyState()
    public var cloudflareTunnel = CloudflareTunnelState()
    public var scriptsInstalled: Bool = false
    public var serverLogSearchResult: ServerLogSearchResult?
    public var isSearchingServerLog: Bool = false
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
    private let nginxProxyService: NginxProxyService
    private let cloudflareTunnelService: CloudflareTunnelService
    private let serverLogSearchService = ServerLogSearchService()
    private let gitService = GitDeployService()
    private let ollamaService = OllamaService()
    private let claudeService = ClaudeService()
    private let cloudProviderService = CloudProviderService()
    private let alertService = AlertService()

    private var pollingTask: Task<Void, Never>?
    private var nginxMetricsTask: Task<Void, Never>?
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
        self.nginxProxyService = NginxProxyService(dataDirectoryURL: flatFileStore.dataDirectoryURL)
        self.cloudflareTunnelService = CloudflareTunnelService(dataDirectoryURL: flatFileStore.dataDirectoryURL)
        self.config = loaded
        self.config.startupSchedule.launchAtLogin = startupService.isLaunchAtLoginEnabled
        self.builtInServer.port = loaded.builtInServer.port
        self.nginxProxy.listenPort = loaded.nginxProxy.listenPort
        self.nginxProxy.configPath = self.nginxProxyService.configFileURL.path
        self.nginxProxy.lanAddress = NginxProxyService.detectPrimaryLANIPv4()
        self.ollama.endpoint = loaded.ollamaEndpoint
        self.ollama.activeModel = loaded.ollamaActiveModel
        self.logs = flatFileStore.loadRecentLogs()
        self.logFileBytes = flatFileStore.logFileByteCount()

        for app in loaded.managedApps {
            self.appStates[app.id] = ManagedAppRuntimeState()
        }

        self.builtInServerService.writeRegistry(from: loaded.builtInServer)
        self.nginxProxyService.writeConfig(from: loaded.nginxProxy)
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
        startNginxLiveMetricsLoop()
    }

    public func runtimeState(for appID: UUID) -> ManagedAppRuntimeState {
        appStates[appID] ?? ManagedAppRuntimeState()
    }

    public func cloudProviderConfig(for kind: CloudProviderKind) -> CloudProviderConfig {
        config.cloudProviders[kind.rawValue] ?? CloudProviderConfig(selectedModel: kind.defaultModel)
    }

    public func cloudProviderState(for kind: CloudProviderKind) -> CloudProviderRuntimeState {
        cloudProviderStates[kind] ?? CloudProviderRuntimeState()
    }

    public func setAppearanceMode(_ mode: BeaconAppearanceMode) {
        guard config.appearanceMode != mode else { return }
        config.appearanceMode = mode
        flatFileStore.saveConfig(config)
        log(.system, .info, "Switched dashboard theme to \(mode.label)")
    }

    public func toggleAppearanceMode() {
        setAppearanceMode(config.appearanceMode == .dark ? .light : .dark)
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
        await probeNginxProxy(logTransitions: false)
        if config.nginxProxy.autoStart && nginxProxy.isInstalled && !nginxProxy.isRunning {
            await startNginxProxy()
        }
        await probeCloudflareTunnels(logTransitions: false)
        await probeOllama(logResult: true)

        if let savedGitToken = keychain.read(.githubToken), !savedGitToken.isEmpty {
            git.keyHint = SecretMasker.mask(savedGitToken)
            await connectGitToken(savedGitToken, persistToKeychain: false)
        }

        if let savedClaudeKey = keychain.read(.claudeAPIKey), !savedClaudeKey.isEmpty {
            claude.keyHint = SecretMasker.mask(savedClaudeKey)
            await probeClaude(logResult: true)
        }

        for kind in CloudProviderKind.allCases {
            if let savedSecret = keychain.read(kind.keychainAccount), !savedSecret.isEmpty {
                var st = cloudProviderState(for: kind)
                st.keyHint = SecretMasker.mask(savedSecret)
                cloudProviderStates[kind] = st
                await probeCloudProvider(kind, logResult: false)
            }
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
                    await self.probeNginxProxy(logTransitions: true)
                    if self.cloudflareTunnel.activeCount > 0 {
                        await self.probeCloudflareTunnels(logTransitions: true)
                    }
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

    private func startNginxLiveMetricsLoop() {
        nginxMetricsTask?.cancel()
        nginxMetricsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { break }
                if self.nginxProxy.isRunning && self.nginxProxy.metrics.livePollingEnabled {
                    await self.pollNginxMetricsNow()
                }
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
        let tunnelKey = cloudflareTunnelKey(for: app)
        if cloudflareTunnel.tunnels[tunnelKey]?.isRunning == true {
            Task { await stopCloudflareTunnel(key: tunnelKey) }
        }
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

    private func isAppConfiguredForErrorReporting(_ app: ManagedApp, state: ManagedAppRuntimeState) -> Bool {
        if state.hasEverBeenHealthy || state.lastDeployedAt != nil {
            return true
        }
        let trimmedPath = app.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return false
        }
        // Only treat an un-deployed app as configured once its local directory actually exists on disk
        // and has been started/deployed at least once (or has already responded healthy).
        return false
    }

    private static func isStderrLineActualError(_ line: String, commandSucceeded: Bool) -> Bool {
        if !commandSucceeded {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Cloning into ") || trimmed.hasPrefix("From ") || trimmed.hasPrefix("* branch") {
                return false
            }
            return true
        }
        let lower = line.lowercased()
        return lower.contains("error:") || lower.contains("fatal:") || lower.contains("err!")
    }

    public func probeManagedApp(_ app: ManagedApp, logTransition: Bool) async {
        var state = runtimeState(for: app.id)
        if state.isDeploying { return }

        let wasHealthy = state.isHealthy
        let result = await processService.probe(urlString: app.monitorURL)

        // Re-read state after async await so concurrent Stop or Deploy actions are never clobbered
        state = runtimeState(for: app.id)
        if state.isDeploying { return }

        state.lastCheckedAt = Date()
        state.httpStatus = result.httpStatus
        state.responseTimeMs = result.responseTimeMs
        state.isHealthy = result.healthy

        if result.healthy {
            state.consecutiveFailures = 0
            state.isManuallyStopped = false
            state.hasEverBeenHealthy = true
            state.startupGraceUntil = nil
            state.lastError = nil
            state.light = .green
            state.statusLabel = "Healthy"
            if state.healthySince == nil {
                state.healthySince = Date()
            }
            if logTransition && !wasHealthy {
                log(.vite, .info, "[\(app.name)] Reachable at \(app.monitorURL) (HTTP \(result.httpStatus ?? 200), \(result.responseTimeMs ?? 1) ms)")
            }
            appStates[app.id] = state
            return
        }

        state.healthySince = nil

        // 1. Respect manual Stop: never report errors or auto-restart a stopped app
        if state.isManuallyStopped {
            state.consecutiveFailures = 0
            state.lastError = nil
            state.light = .amber
            state.statusLabel = "Stopped"
            appStates[app.id] = state
            return
        }

        // 2. Respect startup grace period right after Deploy or Start/Restart
        if let graceUntil = state.startupGraceUntil, Date() < graceUntil {
            state.consecutiveFailures = 0
            state.lastError = nil
            state.light = .amber
            state.statusLabel = "Starting..."
            appStates[app.id] = state
            return
        }
        state.startupGraceUntil = nil

        // 3. Until an app is fully configured / deployed (or has been seen healthy), stay blank & silent
        if !isAppConfiguredForErrorReporting(app, state: state) {
            state.consecutiveFailures = 0
            state.lastError = nil
            state.light = .amber
            let trimmedPath = app.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let folderExists = !trimmedPath.isEmpty && FileManager.default.fileExists(atPath: trimmedPath)
            state.statusLabel = (!trimmedPath.isEmpty && !folderExists && !app.repoURL.isEmpty) ? "Not Deployed" : "Idle"
            appStates[app.id] = state
            return
        }

        // 4. Configured / previously running app is unreachable
        state.lastError = result.error
        state.consecutiveFailures += 1
        state.light = .red
        state.statusLabel = "Down"
        appStates[app.id] = state

        if state.consecutiveFailures == 3 {
            log(.vite, .error, "[\(app.name)] Failed 3 consecutive health checks at \(app.monitorURL)")
            if config.notifyOnCrash {
                let note = await alertService.sendAlert(
                    title: "\(app.name) Down",
                    body: "\(app.monitorURL) stopped responding."
                )
                log(.alerts, .info, note)
            }
            if app.autoRestart && !app.localPath.isEmpty && state.restartCount < config.maxRestarts {
                await restartManagedApp(app, reason: "auto-recovery #\(state.restartCount + 1)")
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
            appendTerminal(
                appName: targetLabel,
                text: line,
                isError: Self.isStderrLineActualError(line, commandSucceeded: res.ok)
            )
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

    public func cloneBuildAndDeploy(app: ManagedApp, trigger: String = "manual") async {
        busyAction = "deploy-\(app.id.uuidString)"
        defer { busyAction = nil }

        var state = runtimeState(for: app.id)
        state.isDeploying = true
        state.isManuallyStopped = false
        state.consecutiveFailures = 0
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
            appendTerminal(
                appName: app.name,
                text: line,
                isError: Self.isStderrLineActualError(line, commandSucceeded: res.ok)
            )
        }

        state = runtimeState(for: app.id)
        state.isDeploying = false
        state.consecutiveFailures = 0

        if res.ok {
            state.lastDeployedAt = Date()
            state.startupGraceUntil = Date().addingTimeInterval(15)
            state.lastError = nil
            state.light = .amber
            state.statusLabel = "Starting..."
            state.dependencySummary = "Deps verified & built"
            appStates[app.id] = state
            log(.git, .info, "[\(app.name)] \(res.summary)")
            if config.notifyOnDeploy {
                let note = await alertService.sendAlert(
                    title: "Deployed \(app.name)",
                    body: res.summary
                )
                log(.alerts, .info, note)
            }
            try? await Task.sleep(for: .seconds(2))
            await probeManagedApp(app, logTransition: true)
        } else {
            state.startupGraceUntil = nil
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
        state.isDeploying = true
        state.isManuallyStopped = false
        state.consecutiveFailures = 0
        state.light = .amber
        state.statusLabel = "Starting..."
        state.lastError = nil
        appStates[app.id] = state

        appendTerminal(appName: app.name, text: "$ beacon-restart.sh \"\(app.localPath)\" \(app.port) (\(reason))")
        let res = await deploymentService.restartApp(app)
        for line in res.stdoutLines { appendTerminal(appName: app.name, text: line) }
        for line in res.stderrLines {
            appendTerminal(
                appName: app.name,
                text: line,
                isError: Self.isStderrLineActualError(line, commandSucceeded: res.ok)
            )
        }

        state = runtimeState(for: app.id)
        state.isDeploying = false
        state.consecutiveFailures = 0

        if res.ok {
            state.restartCount += 1
            state.lastDeployedAt = state.lastDeployedAt ?? Date()
            state.startupGraceUntil = Date().addingTimeInterval(15)
            state.lastError = nil
            state.light = .amber
            state.statusLabel = "Starting..."
            appStates[app.id] = state
            log(.vite, .info, "[\(app.name)] Started on port \(app.port) (\(reason))")
            try? await Task.sleep(for: .seconds(2))
            await probeManagedApp(app, logTransition: true)
        } else {
            state.startupGraceUntil = nil
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

        // Mark manually stopped BEFORE running the script so polling never races and auto-restarts
        var preState = runtimeState(for: app.id)
        preState.isManuallyStopped = true
        preState.startupGraceUntil = nil
        preState.consecutiveFailures = 0
        preState.isHealthy = false
        preState.healthySince = nil
        preState.lastError = nil
        preState.light = .amber
        preState.statusLabel = "Stopping..."
        appStates[app.id] = preState

        appendTerminal(appName: app.name, text: "$ beacon-stop.sh \(app.port)")
        let res = await deploymentService.stopApp(port: app.port, workingDir: app.localPath)
        for line in res.stdoutLines { appendTerminal(appName: app.name, text: line) }
        for line in res.stderrLines { appendTerminal(appName: app.name, text: line, isError: !res.ok) }

        var state = runtimeState(for: app.id)
        state.isManuallyStopped = true
        state.startupGraceUntil = nil
        state.consecutiveFailures = 0
        state.light = .amber
        state.statusLabel = "Stopped"
        state.isHealthy = false
        state.healthySince = nil
        state.httpStatus = nil
        state.responseTimeMs = nil
        state.lastError = nil
        appStates[app.id] = state
        log(.vite, .info, "[\(app.name)] \(res.summary)")
    }

    private func pollAutoDeployApps() async {
        let token = keychain.read(.githubToken)
        for app in config.managedApps where app.autoDeploy {
            guard let fullName = app.githubFullName else { continue }
            var state = runtimeState(for: app.id)
            if state.isDeploying || state.isManuallyStopped { continue }

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
                        body: "Local Ollama daemon at \(config.ollamaEndpoint) stopped responding."
                    )
                    log(.alerts, .info, note)
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

    // MARK: - Cloud AI & Platform API Integrations (OpenAI, Gemini, OpenRouter, Groq, Cloudflare, Vercel, Supabase)

    @discardableResult
    public func connectCloudProvider(
        _ kind: CloudProviderKind,
        apiKey: String,
        baseURL: String = "",
        accountID: String = "",
        selectedModel: String = ""
    ) async -> Bool {
        busyAction = "cloud-connect-\(kind.rawValue)"
        bannerError = nil
        defer { busyAction = nil }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 8, !trimmedKey.contains(where: \.isWhitespace) else {
            bannerError = "Paste a valid \(kind.displayName) API key or token."
            return false
        }

        var cfg = cloudProviderConfig(for: kind)
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.supportsBaseURL {
            cfg.baseURL = trimmedBase
        }
        if kind.supportsAccountID {
            cfg.accountID = trimmedAccount
        }
        if !trimmedModel.isEmpty {
            cfg.selectedModel = trimmedModel
        } else if cfg.selectedModel.isEmpty {
            cfg.selectedModel = kind.defaultModel
        }
        config.cloudProviders[kind.rawValue] = cfg
        flatFileStore.saveConfig(config)

        keychain.save(trimmedKey, for: kind.keychainAccount)
        var st = cloudProviderState(for: kind)
        st.keyHint = SecretMasker.mask(trimmedKey)
        cloudProviderStates[kind] = st

        return await probeCloudProvider(kind, logResult: true)
    }

    public func updateCloudProviderSettings(
        _ kind: CloudProviderKind,
        baseURL: String? = nil,
        accountID: String? = nil,
        selectedModel: String? = nil
    ) {
        var cfg = cloudProviderConfig(for: kind)
        if let baseURL { cfg.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let accountID { cfg.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let selectedModel { cfg.selectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines) }
        config.cloudProviders[kind.rawValue] = cfg
        flatFileStore.saveConfig(config)
    }

    @discardableResult
    public func probeCloudProvider(_ kind: CloudProviderKind, logResult: Bool) async -> Bool {
        guard let secret = keychain.read(kind.keychainAccount), !secret.isEmpty else {
            cloudProviderStates[kind] = CloudProviderRuntimeState()
            return false
        }

        let cfg = cloudProviderConfig(for: kind)
        var st = cloudProviderState(for: kind)
        st.keyHint = SecretMasker.mask(secret)
        st.light = .amber
        st.statusLabel = "Checking"
        cloudProviderStates[kind] = st

        let res = await cloudProviderService.probe(
            kind: kind,
            apiKey: secret,
            baseURL: cfg.baseURL,
            accountID: cfg.accountID
        )

        st.lastCheckedAt = Date()
        st.httpStatus = res.httpStatus
        st.latencyMs = res.latencyMs
        st.isConnected = res.connected
        st.accountLabel = res.accountLabel
        st.lastError = res.error

        if res.connected {
            st.light = .green
            st.statusLabel = "Connected"
            st.models = res.models
            if !res.models.isEmpty {
                var updatedCfg = cfg
                if updatedCfg.selectedModel.isEmpty || (!res.models.contains(updatedCfg.selectedModel) && kind != .customOpenAI) {
                    updatedCfg.selectedModel = res.models.first(where: { $0 == kind.defaultModel }) ?? res.models.first ?? kind.defaultModel
                    config.cloudProviders[kind.rawValue] = updatedCfg
                    flatFileStore.saveConfig(config)
                }
            }
            cloudProviderStates[kind] = st
            if logResult {
                log(.system, .info, "\(kind.displayName) connected (HTTP \(res.httpStatus ?? 200), \(res.latencyMs) ms\(res.accountLabel.map { ", \($0)" } ?? ""))")
            }
            return true
        } else {
            st.light = .red
            st.statusLabel = "Error"
            cloudProviderStates[kind] = st
            if logResult {
                bannerError = res.error
                log(.system, .error, "\(kind.displayName) check failed (\(res.error ?? "Unknown error"))")
            }
            return false
        }
    }

    public func disconnectCloudProvider(_ kind: CloudProviderKind) {
        keychain.delete(kind.keychainAccount)
        cloudProviderStates[kind] = CloudProviderRuntimeState()
        log(.system, .info, "Cleared \(kind.displayName) credentials from macOS Keychain")
    }

    // MARK: - Batch & Utility Actions

    public func refreshAllServices() async {
        busyAction = "refresh-all"
        defer { busyAction = nil }
        await probeAllManagedApps(logTransitions: true)
        await probeBuiltInNodeServer(logTransitions: true)
        await probeNginxProxy(logTransitions: true)
        await probeCloudflareTunnels(logTransitions: true)
        await probeOllama(logResult: true)
        if keychain.read(.claudeAPIKey) != nil {
            await probeClaude(logResult: true)
        }
        for kind in CloudProviderKind.allCases where keychain.read(kind.keychainAccount) != nil {
            await probeCloudProvider(kind, logResult: false)
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

    // MARK: - Inbuilt NGINX Reverse Proxy

    public var currentNginxConfigText: String {
        nginxProxyService.generateConfigText(
            from: config.nginxProxy,
            includeStubStatus: nginxProxy.metrics.stubStatusSupported
        )
    }

    private func recordHealthyNginxProbe(port: Int, latencyMs: Int) async {
        nginxProxy.metrics.probeLatencyMs = latencyMs
        nginxProxy.metrics.consecutiveHealthyProbes += 1
        nginxProxy.metrics.consecutiveFailedProbes = 0
        if nginxProxy.metrics.healthySince == nil {
            nginxProxy.metrics.healthySince = Date()
        }

        if let snap = await nginxProxyService.probeStubStatus(port: port) {
            var rps: Double = 0
            if let prev = nginxProxy.metrics.latestSnapshot {
                let dt = snap.capturedAt.timeIntervalSince(prev.capturedAt)
                if dt > 0.25 && snap.requests >= prev.requests {
                    rps = Double(snap.requests - prev.requests) / dt
                }
            }

            nginxProxy.metrics.stubStatusAvailable = true
            nginxProxy.metrics.latestSnapshot = snap
            nginxProxy.metrics.requestsPerSecond = rps
            nginxProxy.metrics.peakActiveConnections = max(nginxProxy.metrics.peakActiveConnections, snap.activeConnections)
            nginxProxy.metrics.peakRequestsPerSecond = max(nginxProxy.metrics.peakRequestsPerSecond, rps)

            let sample = NginxConnectionSample(
                timestamp: snap.capturedAt,
                activeConnections: snap.activeConnections,
                reading: snap.reading,
                writing: snap.writing,
                waiting: snap.waiting,
                requestsPerSecond: rps,
                probeLatencyMs: latencyMs
            )
            nginxProxy.metrics.history.append(sample)
            if nginxProxy.metrics.history.count > 30 {
                nginxProxy.metrics.history = Array(nginxProxy.metrics.history.suffix(30))
            }
        } else {
            nginxProxy.metrics.stubStatusAvailable = false
            nginxProxy.metrics.requestsPerSecond = 0
        }
    }

    public func pollNginxMetricsNow() async {
        let port = NginxProxyService.clampedPort(config.nginxProxy.listenPort, fallback: 8080)
        nginxProxy.listenPort = port
        if let probe = await nginxProxyService.probeHealthWithLatency(port: port), probe.health.ok {
            nginxProxy.isInstalled = true
            nginxProxy.isRunning = true
            nginxProxy.light = .green
            nginxProxy.statusLabel = config.nginxProxy.exposeOnLAN ? "LAN :\(port)" : "Running :\(port)"
            nginxProxy.lastError = nil
            nginxProxy.lastCheckedAt = Date()
            await recordHealthyNginxProbe(port: port, latencyMs: probe.latencyMs)
        } else {
            await probeNginxProxy(logTransitions: false)
        }
    }

    public func setNginxLivePolling(_ enabled: Bool) {
        nginxProxy.metrics.livePollingEnabled = enabled
        if enabled && nginxProxy.isRunning {
            Task { await pollNginxMetricsNow() }
        }
    }

    public func resetNginxMetricsHistory() {
        nginxProxy.metrics.history = []
        nginxProxy.metrics.peakActiveConnections = nginxProxy.metrics.latestSnapshot?.activeConnections ?? 0
        nginxProxy.metrics.peakRequestsPerSecond = nginxProxy.metrics.requestsPerSecond
    }

    public func probeNginxProxy(logTransitions: Bool = false) async {
        let port = NginxProxyService.clampedPort(config.nginxProxy.listenPort, fallback: 8080)
        nginxProxy.listenPort = port
        nginxProxy.configPath = nginxProxyService.configFileURL.path
        nginxProxy.lanAddress = NginxProxyService.detectPrimaryLANIPv4()
        let wasRunning = nginxProxy.isRunning

        if let probe = await nginxProxyService.probeHealthWithLatency(port: port), probe.health.ok {
            nginxProxy.isInstalled = true
            nginxProxy.isRunning = true
            nginxProxy.light = .green
            nginxProxy.statusLabel = config.nginxProxy.exposeOnLAN ? "LAN :\(port)" : "Running :\(port)"
            nginxProxy.lastError = nil
            nginxProxy.lastCheckedAt = Date()
            if nginxProxy.nginxVersion == nil || nginxProxy.pid == nil {
                let statusProbe = await deploymentService.runNginxAction(
                    "status",
                    configPath: nginxProxyService.configFileURL.path,
                    port: port
                )
                if let ver = statusProbe.version { nginxProxy.nginxVersion = ver }
                if let pid = statusProbe.pid { nginxProxy.pid = pid }
                if let stubSup = statusProbe.stubStatusSupported {
                    nginxProxy.metrics.stubStatusSupported = stubSup
                }
            }
            await recordHealthyNginxProbe(port: port, latencyMs: probe.latencyMs)
            if logTransitions && !wasRunning {
                log(.system, .info, "Inbuilt NGINX reverse proxy is online at \(nginxProxy.baseURL)")
            }
            return
        }

        let statusProbe = await deploymentService.runNginxAction(
            "status",
            configPath: nginxProxyService.configFileURL.path,
            port: port
        )
        let installed = statusProbe.isInstalled ?? systemTools.first(where: { $0.name == "nginx" })?.available ?? false
        nginxProxy.isInstalled = installed
        if let ver = statusProbe.version {
            nginxProxy.nginxVersion = ver
        }
        if let stubSup = statusProbe.stubStatusSupported {
            nginxProxy.metrics.stubStatusSupported = stubSup
        }
        nginxProxy.isRunning = false
        nginxProxy.pid = nil
        nginxProxy.lastCheckedAt = Date()
        if wasRunning {
            nginxProxy.metrics.consecutiveFailedProbes += 1
        }
        nginxProxy.metrics.healthySince = nil
        nginxProxy.metrics.probeLatencyMs = nil
        nginxProxy.metrics.stubStatusAvailable = false
        nginxProxy.metrics.requestsPerSecond = 0

        if !installed {
            nginxProxy.light = .amber
            nginxProxy.statusLabel = "Not Installed"
        } else {
            nginxProxy.light = .amber
            nginxProxy.statusLabel = "Stopped"
        }

        if logTransitions && wasRunning {
            log(.system, .warn, "Inbuilt NGINX reverse proxy on port \(port) stopped responding")
        }
    }

    public func startNginxProxy(restart: Bool = false) async {
        let port = NginxProxyService.clampedPort(config.nginxProxy.listenPort, fallback: 8080)
        config.nginxProxy.listenPort = port
        nginxProxy.listenPort = port
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)
        flatFileStore.saveConfig(config)

        let action = restart ? "restart" : "start"
        busyAction = "nginx-\(action)"
        defer { busyAction = nil }

        appendTerminal(appName: "nginx", text: "$ beacon-nginx.sh \(action) \"\(nginxProxyService.configFileURL.path)\" \(port)")
        let probe = await deploymentService.runNginxAction(
            action,
            configPath: nginxProxyService.configFileURL.path,
            port: port
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "nginx", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "nginx", text: line, isError: true) }

        if probe.result.ok {
            nginxProxy.lastError = nil
            if let ver = probe.version { nginxProxy.nginxVersion = ver }
            if let pid = probe.pid { nginxProxy.pid = pid }
            await probeNginxProxy(logTransitions: false)
            log(.system, .info, "Inbuilt NGINX reverse proxy running on \(nginxProxy.baseURL) (\(config.nginxProxy.routes.filter(\.enabled).count) active route(s))")
        } else {
            nginxProxy.isRunning = false
            nginxProxy.light = .red
            nginxProxy.statusLabel = "Start Failed"
            nginxProxy.lastError = probe.result.summary
            bannerError = probe.result.summary
            log(.system, .error, "Inbuilt NGINX reverse proxy failed to start: \(probe.result.summary)")
        }
    }

    public func reloadNginxProxy() async {
        let port = NginxProxyService.clampedPort(config.nginxProxy.listenPort, fallback: 8080)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)

        busyAction = "nginx-reload"
        defer { busyAction = nil }

        appendTerminal(appName: "nginx", text: "$ beacon-nginx.sh reload \"\(nginxProxyService.configFileURL.path)\" \(port)")
        let probe = await deploymentService.runNginxAction(
            "reload",
            configPath: nginxProxyService.configFileURL.path,
            port: port
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "nginx", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "nginx", text: line, isError: true) }

        if probe.result.ok {
            nginxProxy.lastError = nil
            if let ver = probe.version { nginxProxy.nginxVersion = ver }
            if let pid = probe.pid { nginxProxy.pid = pid }
            await probeNginxProxy(logTransitions: false)
            log(.system, .info, "Reloaded inbuilt NGINX reverse proxy configuration")
        } else {
            nginxProxy.lastError = probe.result.summary
            bannerError = probe.result.summary
            log(.system, .error, "NGINX reload failed: \(probe.result.summary)")
        }
    }

    public func stopNginxProxy() async {
        let port = config.nginxProxy.listenPort
        busyAction = "nginx-stop"
        defer { busyAction = nil }

        appendTerminal(appName: "nginx", text: "$ beacon-nginx.sh stop \"\(nginxProxyService.configFileURL.path)\" \(port)")
        let probe = await deploymentService.runNginxAction(
            "stop",
            configPath: nginxProxyService.configFileURL.path,
            port: port
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "nginx", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "nginx", text: line, isError: !probe.result.ok) }

        nginxProxy.isRunning = false
        nginxProxy.pid = nil
        nginxProxy.light = .amber
        nginxProxy.statusLabel = nginxProxy.isInstalled ? "Stopped" : "Not Installed"
        nginxProxy.lastError = nil
        nginxProxy.metrics.healthySince = nil
        nginxProxy.metrics.probeLatencyMs = nil
        nginxProxy.metrics.stubStatusAvailable = false
        nginxProxy.metrics.requestsPerSecond = 0
        nginxProxy.metrics.consecutiveHealthyProbes = 0
        nginxProxy.metrics.consecutiveFailedProbes = 0
        nginxProxy.metrics.latestSnapshot = nil
        log(.system, .info, "Stopped inbuilt NGINX reverse proxy on port \(port)")
    }

    public func testNginxConfig() async {
        let port = config.nginxProxy.listenPort
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)

        busyAction = "nginx-test"
        defer { busyAction = nil }

        appendTerminal(appName: "nginx", text: "$ beacon-nginx.sh test \"\(nginxProxyService.configFileURL.path)\" \(port)")
        let probe = await deploymentService.runNginxAction(
            "test",
            configPath: nginxProxyService.configFileURL.path,
            port: port
        )
        for line in probe.result.stdoutLines { appendTerminal(appName: "nginx", text: line) }
        for line in probe.result.stderrLines { appendTerminal(appName: "nginx", text: line, isError: !probe.result.ok) }

        if probe.result.ok {
            nginxProxy.lastError = nil
            log(.system, .info, "NGINX configuration syntax check passed (nginx -t)")
        } else {
            nginxProxy.lastError = probe.result.summary
            bannerError = probe.result.summary
            log(.system, .error, "NGINX config test failed: \(probe.result.summary)")
        }
    }

    public func installNginxSilently() async {
        let res = await installPrerequisitesAndDependencies(
            for: nil,
            requestedTools: ["nginx"],
            strategy: .auto
        )
        await probeNginxProxy(logTransitions: false)
        if res.ok && nginxProxy.isInstalled {
            log(.system, .info, "Installed NGINX silently (\(nginxProxy.nginxVersion ?? "ready"))")
        }
    }

    public func updateNginxSettings(listenPort: Int, exposeOnLAN: Bool, autoStart: Bool) async {
        let clampedPort = NginxProxyService.clampedPort(listenPort, fallback: 8080)
        let bindChanged = config.nginxProxy.listenPort != clampedPort || config.nginxProxy.exposeOnLAN != exposeOnLAN
        config.nginxProxy.listenPort = clampedPort
        config.nginxProxy.exposeOnLAN = exposeOnLAN
        config.nginxProxy.autoStart = autoStart
        nginxProxy.listenPort = clampedPort
        flatFileStore.saveConfig(config)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)

        if nginxProxy.isRunning {
            if bindChanged {
                await startNginxProxy(restart: true)
            } else {
                await reloadNginxProxy()
            }
        }
    }

    public func upsertNginxRoute(
        _ route: NginxProxyRoute,
        makeActiveRoot: Bool = false,
        autoStartOrReload: Bool = true
    ) async {
        var sanitized = route
        sanitized.name = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.name.isEmpty {
            sanitized.name = "Local :\(route.targetPort)"
        }
        sanitized.pathPrefix = NginxProxyService.sanitizePathPrefix(route.pathPrefix, fallbackName: sanitized.name)
        sanitized.serverName = NginxProxyService.sanitizeServerName(route.serverName)
        sanitized.targetHost = NginxProxyService.sanitizeTargetHost(route.targetHost)
        sanitized.targetPort = max(1, min(65535, route.targetPort))

        if let idx = config.nginxProxy.routes.firstIndex(where: { $0.id == sanitized.id }) {
            config.nginxProxy.routes[idx] = sanitized
            log(.system, .info, "Updated NGINX proxy route \"\(sanitized.name)\" (\(sanitized.pathPrefix) → \(sanitized.targetHost):\(sanitized.targetPort))")
        } else {
            // Ensure unique pathPrefix among existing routes
            let existingPrefixes = Set(config.nginxProxy.routes.map(\.pathPrefix))
            if existingPrefixes.contains(sanitized.pathPrefix) {
                var n = 2
                while existingPrefixes.contains("\(sanitized.pathPrefix)-\(n)") {
                    n += 1
                }
                sanitized.pathPrefix = "\(sanitized.pathPrefix)-\(n)"
            }
            config.nginxProxy.routes.append(sanitized)
            log(.system, .info, "Added NGINX proxy route \"\(sanitized.name)\" (\(sanitized.pathPrefix) → \(sanitized.targetHost):\(sanitized.targetPort))")
        }

        if makeActiveRoot || config.nginxProxy.activeRootRouteID == nil {
            config.nginxProxy.activeRootRouteID = sanitized.id
        }

        flatFileStore.saveConfig(config)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)

        if autoStartOrReload {
            if nginxProxy.isRunning {
                await reloadNginxProxy()
            } else if nginxProxy.isInstalled {
                await startNginxProxy()
            }
        }
    }

    public func exposeManagedAppViaNginx(_ app: ManagedApp) async {
        let slug = BuiltInNodeServerService.makeSlug(from: app.name, existingSlugs: [])
        if let existing = config.nginxProxy.routes.first(where: { $0.targetPort == app.port && $0.targetHost == "127.0.0.1" }) {
            var updated = existing
            updated.name = app.name
            updated.enabled = true
            await upsertNginxRoute(updated, makeActiveRoot: false, autoStartOrReload: true)
            return
        }

        let route = NginxProxyRoute(
            name: app.name,
            pathPrefix: "/\(slug)",
            serverName: "\(slug).localhost",
            targetHost: "127.0.0.1",
            targetPort: app.port,
            webSocketsEnabled: true,
            stripPrefix: true,
            enabled: true
        )
        await upsertNginxRoute(route, makeActiveRoot: config.nginxProxy.routes.isEmpty, autoStartOrReload: true)
    }

    public func toggleNginxRoute(_ route: NginxProxyRoute) async {
        guard let idx = config.nginxProxy.routes.firstIndex(where: { $0.id == route.id }) else { return }
        config.nginxProxy.routes[idx].enabled.toggle()
        flatFileStore.saveConfig(config)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)
        log(.system, .info, "\(config.nginxProxy.routes[idx].enabled ? "Enabled" : "Disabled") NGINX route \"\(route.name)\"")
        if nginxProxy.isRunning {
            await reloadNginxProxy()
        }
    }

    public func setNginxRootRoute(_ routeID: UUID?) async {
        config.nginxProxy.activeRootRouteID = routeID
        flatFileStore.saveConfig(config)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)
        if let routeID, let match = config.nginxProxy.routes.first(where: { $0.id == routeID }) {
            log(.system, .info, "Set \"\(match.name)\" as active NGINX root route at \(nginxProxy.baseURL)/")
        } else {
            log(.system, .info, "Cleared active NGINX root route (showing route directory on /)")
        }
        if nginxProxy.isRunning {
            await reloadNginxProxy()
        }
    }

    public func deleteNginxRoute(_ route: NginxProxyRoute) async {
        config.nginxProxy.routes.removeAll { $0.id == route.id }
        if config.nginxProxy.activeRootRouteID == route.id {
            config.nginxProxy.activeRootRouteID = config.nginxProxy.routes.first?.id
        }
        flatFileStore.saveConfig(config)
        nginxProxyService.writeConfig(from: config.nginxProxy, includeStubStatus: nginxProxy.metrics.stubStatusSupported)
        log(.system, .info, "Removed NGINX proxy route \"\(route.name)\"")
        if nginxProxy.isRunning {
            await reloadNginxProxy()
        }
    }

    public func primaryURL(for route: NginxProxyRoute) -> String {
        let port = config.nginxProxy.listenPort
        if !route.serverName.isEmpty {
            return port == 80 ? "http://\(route.serverName)/" : "http://\(route.serverName):\(port)/"
        }
        if config.nginxProxy.activeRootRouteID == route.id {
            return "\(nginxProxy.baseURL)/"
        }
        let prefix = NginxProxyService.sanitizePathPrefix(route.pathPrefix, fallbackName: route.name)
        return "\(nginxProxy.baseURL)\(prefix)/"
    }

    public func pathURL(for route: NginxProxyRoute) -> String {
        if config.nginxProxy.activeRootRouteID == route.id {
            return "\(nginxProxy.baseURL)/"
        }
        let prefix = NginxProxyService.sanitizePathPrefix(route.pathPrefix, fallbackName: route.name)
        return "\(nginxProxy.baseURL)\(prefix)/"
    }

    public func openNginxRouteInBrowser(_ route: NginxProxyRoute? = nil, useVHost: Bool = false) {
        let urlString: String
        if let route {
            urlString = useVHost ? primaryURL(for: route) : pathURL(for: route)
        } else {
            urlString = "\(nginxProxy.baseURL)/"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - One-Click Cloudflare Tunnels (Keychain API + Dynamic cloudflared Config)

    public var hasCloudflareAPITokenInKeychain: Bool {
        if let token = keychain.read(.cloudflareAPIToken), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    public func cloudflareTunnelKey(for app: ManagedApp) -> String {
        "app-\(app.id.uuidString.lowercased())"
    }

    public func cloudflareTunnelEntry(for key: String) -> CloudflareTunnelEntry? {
        cloudflareTunnel.tunnels[key]
    }

    public func cloudflareTunnelEntry(for app: ManagedApp) -> CloudflareTunnelEntry? {
        cloudflareTunnel.tunnels[cloudflareTunnelKey(for: app)]
    }

    public var ollamaPort: Int {
        LocalProcessService.extractPort(from: config.ollamaEndpoint, fallback: 11434)
    }

    public var ollamaCloudflareTunnel: CloudflareTunnelEntry? {
        cloudflareTunnel.tunnels["ollama"]
    }

    public func generatedCloudflaredConfig(for key: String) -> String? {
        cloudflareTunnelService.readGeneratedConfig(for: key)
    }

    public func probeCloudflareTunnels(logTransitions: Bool = false) async {
        let probe = await deploymentService.runCloudflaredAction("status", tunnelID: "all")
        let installed = probe.isInstalled ?? systemTools.first(where: { $0.name == "cloudflared" })?.available ?? false
        cloudflareTunnel.isInstalled = installed
        if let ver = probe.version, !ver.isEmpty {
            cloudflareTunnel.version = ver
        }
        cloudflareTunnel.lastCheckedAt = Date()

        let previousRunningIDs = Set(cloudflareTunnel.tunnels.values.filter(\.isRunning).map(\.id))
        var discoveredIDs = Set<String>()

        for item in probe.entries {
            discoveredIDs.insert(item.tunnelID)
            let existing = cloudflareTunnel.tunnels[item.tunnelID]
            let targetURL = item.targetURL ?? existing?.targetURL ?? "http://127.0.0.1:3000"
            let parsedPort = LocalProcessService.extractPort(from: targetURL, fallback: existing?.targetPort ?? 3000)

            var label = existing?.label ?? "Local :\(parsedPort)"
            var targetKind = existing?.targetKind ?? .customPort
            var appID = existing?.appID

            if item.tunnelID == "nginx" {
                label = "NGINX Reverse Proxy"
                targetKind = .nginxProxy
            } else if item.tunnelID == "node-host" {
                label = "Built-In Node.js Server"
                targetKind = .builtInNode
            } else if item.tunnelID == "ollama" {
                label = "Ollama LLM"
                targetKind = .ollama
            } else if item.tunnelID.hasPrefix("app-") {
                let rawUUID = String(item.tunnelID.dropFirst(4))
                if let matchedApp = config.managedApps.first(where: { $0.id.uuidString.lowercased() == rawUUID }) {
                    label = matchedApp.name
                    targetKind = .managedApp
                    appID = matchedApp.id
                }
            }

            let configPath = existing?.configFilePath ?? cloudflareTunnelService.configFileURL(for: item.tunnelID).path
            let entry = CloudflareTunnelEntry(
                id: item.tunnelID,
                label: label,
                targetKind: targetKind,
                appID: appID,
                targetPort: parsedPort,
                targetURL: targetURL,
                publicURL: item.publicURL ?? existing?.publicURL,
                mode: item.mode,
                configFilePath: FileManager.default.fileExists(atPath: configPath) ? configPath : existing?.configFilePath,
                cloudflareTunnelID: existing?.cloudflareTunnelID,
                isRunning: true,
                isStarting: false,
                pid: item.pid,
                startedAt: existing?.startedAt ?? Date(),
                lastError: nil,
                light: .green,
                statusLabel: "Live"
            )
            cloudflareTunnel.tunnels[item.tunnelID] = entry
        }

        // Clear any previously running tunnels that exited outside BeaconMac
        for (id, existing) in cloudflareTunnel.tunnels where existing.isRunning && !existing.isStarting && !discoveredIDs.contains(id) {
            cloudflareTunnel.tunnels.removeValue(forKey: id)
            if logTransitions && previousRunningIDs.contains(id) {
                log(.system, .warn, "Cloudflare tunnel for \"\(existing.label)\" stopped responding")
            }
        }
    }

    @discardableResult
    public func installCloudflaredSilently() async -> Bool {
        cloudflareTunnel.isInstalling = true
        cloudflareTunnel.lastError = nil
        defer { cloudflareTunnel.isInstalling = false }

        let res = await installPrerequisitesAndDependencies(
            for: nil,
            requestedTools: ["cloudflared"],
            strategy: .auto
        )
        await probeCloudflareTunnels(logTransitions: false)
        if res.ok && cloudflareTunnel.isInstalled {
            log(.system, .info, "Installed cloudflared silently (\(cloudflareTunnel.version ?? "ready"))")
            return true
        }
        let errMsg = res.summary.isEmpty ? "Failed to install cloudflared." : res.summary
        cloudflareTunnel.lastError = errMsg
        bannerError = errMsg
        return false
    }

    public func toggleCloudflareTunnel(for app: ManagedApp) async {
        let key = cloudflareTunnelKey(for: app)
        if cloudflareTunnel.tunnels[key]?.isRunning == true {
            await stopCloudflareTunnel(key: key)
        } else {
            await startCloudflareTunnel(
                key: key,
                label: app.name,
                targetKind: .managedApp,
                appID: app.id,
                targetPort: app.port
            )
        }
    }

    public func toggleNginxCloudflareTunnel() async {
        let key = "nginx"
        if cloudflareTunnel.tunnels[key]?.isRunning == true {
            await stopCloudflareTunnel(key: key)
        } else {
            if !nginxProxy.isRunning && nginxProxy.isInstalled {
                await startNginxProxy()
            }
            await startCloudflareTunnel(
                key: key,
                label: "NGINX Reverse Proxy",
                targetKind: .nginxProxy,
                targetPort: config.nginxProxy.listenPort
            )
        }
    }

    public func toggleBuiltInServerCloudflareTunnel() async {
        let key = "node-host"
        if cloudflareTunnel.tunnels[key]?.isRunning == true {
            await stopCloudflareTunnel(key: key)
        } else {
            if !builtInServer.isRunning {
                await startBuiltInNodeServer()
            }
            await startCloudflareTunnel(
                key: key,
                label: "Built-In Node.js Server",
                targetKind: .builtInNode,
                targetPort: config.builtInServer.port
            )
        }
    }

    public func toggleOllamaCloudflareTunnel() async {
        let key = "ollama"
        if cloudflareTunnel.tunnels[key]?.isRunning == true {
            await stopCloudflareTunnel(key: key)
            return
        }

        let port = ollamaPort
        if !ollama.isConnected {
            await probeOllama(logResult: false)
            if !ollama.isConnected {
                log(.ollama, .warn, "Starting Cloudflare Tunnel for Ollama on :\(port) — make sure Ollama is running locally at \(config.ollamaEndpoint)")
            }
        }

        await startCloudflareTunnel(
            key: key,
            label: "Ollama LLM",
            targetKind: .ollama,
            targetPort: port,
            httpHostHeader: "localhost:\(port)"
        )
    }

    public func exposeCustomPortViaCloudflare(port: Int, label: String = "") async {
        let clampedPort = max(1, min(65535, port))
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = trimmedLabel.isEmpty ? "Local :\(clampedPort)" : trimmedLabel
        await startCloudflareTunnel(
            key: "port-\(clampedPort)",
            label: resolvedLabel,
            targetKind: .customPort,
            targetPort: clampedPort
        )
    }

    public func startCloudflareTunnel(
        key: String,
        label: String,
        targetKind: CloudflareTunnelTargetKind,
        appID: UUID? = nil,
        targetPort: Int,
        httpHostHeader: String? = nil
    ) async {
        let clampedPort = max(1, min(65535, targetPort))
        let targetURL = "http://127.0.0.1:\(clampedPort)"
        let apiToken = keychain.read(.cloudflareAPIToken)
        let hasKeychainToken = !(apiToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let initialStatus: String
        if !cloudflareTunnel.isInstalled {
            initialStatus = "Installing cloudflared…"
        } else if hasKeychainToken && config.cloudflareTunnel.preferCloudflareAPI {
            initialStatus = "Provisioning via Cloudflare API…"
        } else {
            initialStatus = "Generating config & connecting…"
        }

        cloudflareTunnel.lastError = nil
        cloudflareTunnel.tunnels[key] = CloudflareTunnelEntry(
            id: key,
            label: label,
            targetKind: targetKind,
            appID: appID,
            targetPort: clampedPort,
            targetURL: targetURL,
            publicURL: nil,
            mode: (hasKeychainToken && config.cloudflareTunnel.preferCloudflareAPI) ? .apiManaged : .quickTunnel,
            configFilePath: nil,
            cloudflareTunnelID: nil,
            isRunning: false,
            isStarting: true,
            pid: nil,
            startedAt: Date(),
            lastError: nil,
            light: .amber,
            statusLabel: initialStatus
        )

        // Step 1: Ensure cloudflared binary is installed (silent auto-install if missing)
        if !cloudflareTunnel.isInstalled {
            await probeCloudflareTunnels(logTransitions: false)
        }
        if !cloudflareTunnel.isInstalled {
            if config.cloudflareTunnel.autoInstallCloudflared {
                log(.system, .info, "[\(label)] cloudflared not found — installing silently for one-click Cloudflare Tunnel...")
                let installedOK = await installCloudflaredSilently()
                if !installedOK {
                    var failed = cloudflareTunnel.tunnels[key] ?? CloudflareTunnelEntry(
                        id: key,
                        label: label,
                        targetKind: targetKind,
                        appID: appID,
                        targetPort: clampedPort,
                        targetURL: targetURL
                    )
                    failed.isStarting = false
                    failed.isRunning = false
                    failed.light = .red
                    failed.statusLabel = "Install Failed"
                    failed.lastError = cloudflareTunnel.lastError ?? "Could not install cloudflared."
                    cloudflareTunnel.tunnels[key] = failed
                    return
                }
            } else {
                let msg = "cloudflared is not installed. Click \"Install cloudflared\" first."
                var failed = cloudflareTunnel.tunnels[key]!
                failed.isStarting = false
                failed.light = .red
                failed.statusLabel = "Not Installed"
                failed.lastError = msg
                cloudflareTunnel.tunnels[key] = failed
                bannerError = msg
                return
            }
        }

        // Step 2: Use existing Cloudflare API integration in Keychain to dynamically provision
        // the tunnel & DNS route and generate cloudflared config.yml (with automatic Quick Tunnel fallback).
        if var pending = cloudflareTunnel.tunnels[key] {
            pending.statusLabel = (hasKeychainToken && config.cloudflareTunnel.preferCloudflareAPI)
                ? "Generating config via Cloudflare API…"
                : "Generating cloudflared config…"
            cloudflareTunnel.tunnels[key] = pending
        }

        let cfConfig = cloudProviderConfig(for: .cloudflare)
        let provision = await cloudflareTunnelService.prepareTunnelSession(
            tunnelKey: key,
            appName: label,
            targetPort: clampedPort,
            protocolChoice: config.cloudflareTunnel.preferredProtocol,
            preferCloudflareAPI: config.cloudflareTunnel.preferCloudflareAPI,
            customBaseDomain: config.cloudflareTunnel.customBaseDomain,
            apiToken: apiToken,
            configuredAccountID: cfConfig.accountID,
            httpHostHeader: httpHostHeader
        )

        // Persist auto-discovered Cloudflare Account ID if it wasn't previously entered
        if let resolvedAcct = provision.resolvedAccountID, !resolvedAcct.isEmpty, cfConfig.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateCloudProviderSettings(.cloudflare, accountID: resolvedAcct)
        }

        appendTerminal(appName: "cloudflare", text: "[beacon-cloudflare] \(provision.detailMessage)")
        appendTerminal(appName: "cloudflare", text: "[beacon-cloudflare] Generated config: \(provision.configFilePath)")
        if let fallback = provision.fallbackReason, !fallback.isEmpty {
            appendTerminal(appName: "cloudflare", text: "[beacon-cloudflare] Note: \(fallback)")
            log(.system, .warn, "[\(label)] Cloudflare API fallback to Quick Tunnel: \(fallback)")
        }

        // Step 3: Trigger the detached cloudflared session using the generated config/token
        if var pending = cloudflareTunnel.tunnels[key] {
            pending.mode = provision.mode
            pending.configFilePath = provision.configFilePath
            pending.cloudflareTunnelID = provision.cloudflareTunnelID
            pending.statusLabel = provision.usedCloudflareAPI ? "Starting API Tunnel…" : "Connecting Quick Tunnel…"
            cloudflareTunnel.tunnels[key] = pending
        }

        let probe: AppDeploymentService.CloudflareTunnelProbeResult
        switch provision.launchMode {
        case .localConfigRun:
            let expectedURL = provision.publicURL ?? ""
            appendTerminal(appName: "cloudflare", text: "$ beacon-cloudflared.sh start-config \(key) \"\(provision.configFilePath)\" \(expectedURL) \(targetURL)")
            probe = await deploymentService.runCloudflaredAction(
                "start-config",
                tunnelID: key,
                extraArgs: [provision.configFilePath, expectedURL, targetURL]
            )
        case .remoteTokenRun:
            let expectedURL = provision.publicURL ?? ""
            let tokenFile = provision.tokenFilePath ?? ""
            appendTerminal(appName: "cloudflare", text: "$ beacon-cloudflared.sh start-token \(key) [keychain-token-file] \(expectedURL) \(targetURL)")
            probe = await deploymentService.runCloudflaredAction(
                "start-token",
                tunnelID: key,
                extraArgs: [tokenFile, expectedURL, targetURL]
            )
        case .quickTunnel:
            let proto = config.cloudflareTunnel.preferredProtocol.rawValue
            let hostHeaderArg = CloudflareTunnelService.sanitizeHostHeader(httpHostHeader)
            let extraArgs = hostHeaderArg.map { [targetURL, proto, $0] } ?? [targetURL, proto]
            let headerLogSuffix = hostHeaderArg.map { " \($0)" } ?? ""
            appendTerminal(appName: "cloudflare", text: "$ beacon-cloudflared.sh start \(key) \(targetURL) \(proto)\(headerLogSuffix)")
            probe = await deploymentService.runCloudflaredAction(
                "start",
                tunnelID: key,
                extraArgs: extraArgs
            )
        }

        for line in probe.result.stdoutLines { appendTerminal(appName: "cloudflare", text: line) }
        for line in probe.result.stderrLines {
            appendTerminal(
                appName: "cloudflare",
                text: line,
                isError: Self.isStderrLineActualError(line, commandSucceeded: probe.result.ok)
            )
        }

        if let ver = probe.version, !ver.isEmpty {
            cloudflareTunnel.version = ver
            cloudflareTunnel.isInstalled = true
        }

        let resolvedPublicURL = probe.publicURL ?? provision.publicURL
        if probe.result.ok, let publicURL = resolvedPublicURL, !publicURL.isEmpty {
            let entry = CloudflareTunnelEntry(
                id: key,
                label: label,
                targetKind: targetKind,
                appID: appID,
                targetPort: clampedPort,
                targetURL: targetURL,
                publicURL: publicURL,
                mode: provision.mode,
                configFilePath: provision.configFilePath,
                cloudflareTunnelID: provision.cloudflareTunnelID,
                isRunning: true,
                isStarting: false,
                pid: probe.pid,
                startedAt: Date(),
                lastError: nil,
                light: .green,
                statusLabel: "Live"
            )
            cloudflareTunnel.tunnels[key] = entry
            cloudflareTunnel.lastError = nil

            if config.cloudflareTunnel.autoCopyURLOnStart {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(publicURL, forType: .string)
            }

            let copySuffix = config.cloudflareTunnel.autoCopyURLOnStart ? " (copied to clipboard)" : ""
            log(.system, .info, "[\(label)] Exposed via \(provision.mode.badgeLabel): \(publicURL) → \(targetURL)\(copySuffix)")
        } else {
            let errText = probe.result.summary
            var failed = cloudflareTunnel.tunnels[key] ?? CloudflareTunnelEntry(
                id: key,
                label: label,
                targetKind: targetKind,
                appID: appID,
                targetPort: clampedPort,
                targetURL: targetURL
            )
            failed.isRunning = false
            failed.isStarting = false
            failed.mode = provision.mode
            failed.configFilePath = provision.configFilePath
            failed.light = .red
            failed.statusLabel = "Tunnel Failed"
            failed.lastError = errText
            cloudflareTunnel.tunnels[key] = failed
            cloudflareTunnel.lastError = errText
            bannerError = "[\(label)] Cloudflare Tunnel failed: \(errText)"
            log(.system, .error, "[\(label)] Cloudflare Tunnel failed: \(errText)")
        }
    }

    public func stopCloudflareTunnel(key: String) async {
        let label = cloudflareTunnel.tunnels[key]?.label ?? key
        appendTerminal(appName: "cloudflare", text: "$ beacon-cloudflared.sh stop \(key)")
        let probe = await deploymentService.runCloudflaredAction("stop", tunnelID: key)
        for line in probe.result.stdoutLines { appendTerminal(appName: "cloudflare", text: line) }
        for line in probe.result.stderrLines {
            appendTerminal(appName: "cloudflare", text: line, isError: !probe.result.ok)
        }
        cloudflareTunnel.tunnels.removeValue(forKey: key)
        log(.system, .info, "[\(label)] Stopped Cloudflare Tunnel")
    }

    public func stopAllCloudflareTunnels() async {
        appendTerminal(appName: "cloudflare", text: "$ beacon-cloudflared.sh stop-all")
        let probe = await deploymentService.runCloudflaredAction("stop-all", tunnelID: "all")
        for line in probe.result.stdoutLines { appendTerminal(appName: "cloudflare", text: line) }
        for line in probe.result.stderrLines {
            appendTerminal(appName: "cloudflare", text: line, isError: !probe.result.ok)
        }
        cloudflareTunnel.tunnels.removeAll()
        log(.system, .info, "Stopped all active Cloudflare Tunnels")
    }

    public func updateCloudflareTunnelSettings(
        preferredProtocol: CloudflareTunnelProtocol,
        autoInstallCloudflared: Bool,
        autoCopyURLOnStart: Bool,
        preferCloudflareAPI: Bool? = nil,
        customBaseDomain: String? = nil
    ) {
        config.cloudflareTunnel.preferredProtocol = preferredProtocol
        config.cloudflareTunnel.autoInstallCloudflared = autoInstallCloudflared
        config.cloudflareTunnel.autoCopyURLOnStart = autoCopyURLOnStart
        if let preferCloudflareAPI {
            config.cloudflareTunnel.preferCloudflareAPI = preferCloudflareAPI
        }
        if let customBaseDomain {
            config.cloudflareTunnel.customBaseDomain = CloudflareTunnelService.sanitizeDomain(customBaseDomain)
        }
        flatFileStore.saveConfig(config)
        log(.system, .info, "Updated Cloudflare Tunnel settings (protocol: \(preferredProtocol.rawValue), key-API: \(config.cloudflareTunnel.preferCloudflareAPI))")
    }

    public func copyTunnelURL(_ urlString: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        log(.system, .info, "Copied public Cloudflare Tunnel URL: \(urlString)")
    }

    public func openTunnelURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func saveGlobalConfiguration(
        ollamaEndpoint: String,
        gitPollIntervalSec: Int,
        maxRestarts: Int,
        notifyOnCrash: Bool,
        notifyOnDeploy: Bool,
        notifyOnOllamaDown: Bool
    ) async {
        config.ollamaEndpoint = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        config.gitPollIntervalSec = max(15, min(3600, gitPollIntervalSec))
        config.maxRestarts = max(1, min(100, maxRestarts))
        config.notifyOnCrash = notifyOnCrash
        config.notifyOnDeploy = notifyOnDeploy
        config.notifyOnOllamaDown = notifyOnOllamaDown
        ollama.endpoint = config.ollamaEndpoint
        flatFileStore.saveConfig(config)
        log(.system, .info, "Saved flat-file configuration to \(flatFileStore.configFileURL.lastPathComponent)")
        await probeOllama(logResult: false)
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
            body: "BeaconMac native macOS alerts are active."
        )
        log(.alerts, .info, note)
    }
}
