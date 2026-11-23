import SwiftUI

struct ServiceCardsView: View {
    @Bindable var controller: BeaconController

    @State private var monitorURLDraft: String = ""
    @State private var gitTokenDraft: String = ""
    @State private var editingGitKey: Bool = false
    @State private var claudeKeyDraft: String = ""
    @State private var editingClaudeKey: Bool = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let inputBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            viteCard
            gitCard
            ollamaCard
            claudeCard
        }
        .onAppear {
            monitorURLDraft = controller.vite.monitorURL
        }
        .onChange(of: controller.vite.monitorURL) { _, newValue in
            monitorURLDraft = newValue
        }
    }

    // MARK: - 1. Vite / Localhost Watchdog Card

    private var viteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vite / Node.js Server")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(controller.vite.monitorURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.vite.light, label: controller.vite.statusLabel)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Localhost URL to monitor")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("http://localhost:5173", text: $monitorURLDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(inputBackground)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            Task { await controller.updateMonitorURL(monitorURLDraft) }
                        }

                    Button("Monitor") {
                        Task { await controller.updateMonitorURL(monitorURLDraft) }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 24) {
                metricCell(
                    title: "HTTP Probe",
                    value: controller.vite.isHealthy
                        ? "\(controller.vite.httpStatus ?? 200) · \(controller.vite.responseTimeMs ?? 1) ms"
                        : "Unreachable",
                    valueColor: controller.vite.isHealthy ? .green : .red
                )
                metricCell(title: "Uptime", value: formatUptime(controller.vite.uptimeSeconds))
                metricCell(title: "Restarts", value: "\(controller.vite.restartCount)")
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Toggle("Auto-restart on crash", isOn: Binding(
                    get: { controller.vite.autoRestart },
                    set: { _ in controller.toggleViteAutoRestart() }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Check") {
                    Task { await controller.probeVite(logTransition: true) }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Restart") {
                    Task { await controller.triggerViteRestart(reason: "manual button") }
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 2. Git Auto-Deploy & Direct Key Paste Card

    private var gitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Git Auto-Deploy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(controller.git.branch) · \(controller.git.commitHash)\(controller.git.connectedUsername.map { " · @\($0)" } ?? "")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.git.light, label: controller.git.statusLabel)
            }

            if let keyHint = controller.git.keyHint, !editingGitKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub key (stored in macOS Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text(keyHint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Button("Replace Key") { editingGitKey = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.cyan)
                        Button("Clear") { controller.disconnectGitToken() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste Git key / Personal Access Token (Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("ghp_... or github_pat_...", text: $gitTokenDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button("Connect") {
                            let token = gitTokenDraft
                            Task {
                                let ok = await controller.connectGitToken(token)
                                if ok {
                                    gitTokenDraft = ""
                                    editingGitKey = false
                                }
                            }
                        }
                        .disabled(gitTokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(BeaconPrimaryButtonStyle())

                        if editingGitKey {
                            Button("Cancel") {
                                editingGitKey = false
                                gitTokenDraft = ""
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }
                }
            }

            if !controller.git.repos.isEmpty {
                Picker("Repository", selection: Binding(
                    get: { controller.git.repoFullName },
                    set: { selected in
                        let branch = controller.git.repos.first(where: { $0.fullName == selected })?.defaultBranch ?? controller.git.branch
                        Task { await controller.selectGitRepo(selected, branch: branch) }
                    }
                )) {
                    ForEach(controller.git.repos) { repo in
                        Text("\(repo.fullName) (\(repo.defaultBranch))").tag(repo.fullName)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.git.lastError != nil ? "Last Sync Issue" : "Latest Commit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(controller.git.lastError ?? controller.git.commitMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(controller.git.lastError != nil ? .red.opacity(0.9) : .white.opacity(0.88))
                    .lineLimit(1)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Toggle("Auto-pull (\(controller.git.pollIntervalSec)s)", isOn: Binding(
                    get: { controller.git.autoDeploy },
                    set: { _ in controller.toggleGitAutoDeploy() }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Pull & Redeploy") {
                    Task { await controller.checkAndDeployGit(forcePull: true, trigger: "manual") }
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 3. Local LLM (Ollama) Card

    private var ollamaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local LLM (Ollama)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(controller.ollama.endpoint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TrafficLightLampView(active: controller.ollama.light, label: controller.ollama.statusLabel)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 24) {
                metricCell(
                    title: "Latency",
                    value: controller.ollama.latencyMs.map { "\($0) ms" } ?? "—"
                )
                metricCell(
                    title: "Loaded VRAM",
                    value: controller.ollama.isConnected
                        ? String(format: "%.1f / %.0f GB", controller.ollama.vramUsedGB, controller.ollama.totalMemoryGB)
                        : "—"
                )
                metricCell(
                    title: "Local Models",
                    value: "\(controller.ollama.models.count)"
                )
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text("Active local model")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if controller.ollama.models.isEmpty {
                    Text("Start Ollama locally on port 11434 to list models")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Ollama Model", selection: Binding(
                        get: { controller.ollama.activeModel },
                        set: { model in
                            Task { await controller.switchOllamaModel(model) }
                        }
                    )) {
                        ForEach(controller.ollama.models) { model in
                            Text("\(model.name) (\(model.parameterSize) · \(String(format: "%.1f", model.sizeGB)) GB)")
                                .tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Health Check") {
                    Task { await controller.probeOllama(logResult: true) }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 4. Claude API Health Checker Card

    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude API")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("api.anthropic.com · /v1/models")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TrafficLightLampView(active: controller.claude.light, label: controller.claude.statusLabel)
            }

            if let hint = controller.claude.keyHint, controller.claude.isConnected, !editingClaudeKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude API key (stored in macOS Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text(hint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Button("Replace Key") { editingClaudeKey = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste Claude API key (verified via /v1/models)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("sk-ant-api03-...", text: $claudeKeyDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button("Check Key") {
                            let key = claudeKeyDraft
                            claudeKeyDraft = ""
                            Task {
                                let ok = await controller.connectClaudeKey(key)
                                if ok { editingClaudeKey = false }
                            }
                        }
                        .disabled(claudeKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(BeaconPrimaryButtonStyle())

                        if editingClaudeKey {
                            Button("Cancel") {
                                editingClaudeKey = false
                                claudeKeyDraft = ""
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 24) {
                metricCell(
                    title: "HTTP Status",
                    value: controller.claude.isConnected
                        ? "\(controller.claude.httpStatus ?? 200) OK"
                        : (controller.claude.httpStatus.map { "HTTP \($0)" } ?? "—"),
                    valueColor: controller.claude.isConnected ? .green : (controller.claude.lastError != nil ? .red : .secondary)
                )
                metricCell(
                    title: "Latency",
                    value: controller.claude.latencyMs.map { "\($0) ms" } ?? "—"
                )
                metricCell(
                    title: "Models",
                    value: controller.claude.models.isEmpty ? "—" : "\(controller.claude.models.count)"
                )
            }

            if let error = controller.claude.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(1)
            }

            if !controller.claude.models.isEmpty {
                Picker("Claude Model", selection: Binding(
                    get: { controller.claude.activeModel },
                    set: { controller.claude.activeModel = $0 }
                )) {
                    ForEach(controller.claude.models) { model in
                        Text("\(model.displayName) (\(model.id))").tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Health Check") {
                    Task { _ = await controller.probeClaude(logResult: true) }
                }
                .disabled(controller.claude.keyHint == nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Clear Key") {
                    editingClaudeKey = false
                    claudeKeyDraft = ""
                    controller.disconnectClaudeKey()
                }
                .disabled(controller.claude.keyHint == nil)
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func metricCell(title: String, value: String, valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
    }

    private func formatUptime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m \(String(format: "%02d", s))s" }
        return "\(s)s"
    }
}

struct BeaconPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.043, green: 0.051, blue: 0.063))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(configuration.isPressed ? 0.8 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct BeaconSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
