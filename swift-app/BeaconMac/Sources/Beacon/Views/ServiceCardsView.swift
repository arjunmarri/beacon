import SwiftUI

struct ServiceCardsView: View {
    @Bindable var controller: BeaconController

    @State private var gitTokenDraft: String = ""
    @State private var editingGitKey: Bool = false
    @State private var claudeKeyDraft: String = ""
    @State private var editingClaudeKey: Bool = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let inputBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            gitAccountCard
            ollamaCard
            claudeCard
        }
    }

    // MARK: - 1. GitHub Account & Keychain Token Card

    private var gitAccountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub Account")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(controller.git.connectedUsername.map { "@\($0) · \(controller.git.repos.count) repos" } ?? "Paste PAT to sync & auto-deploy repos")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.git.light, label: controller.git.statusLabel)
            }

            if let keyHint = controller.git.keyHint, !editingGitKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub token (stored in macOS Keychain)")
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
                        Button("Replace") { editingGitKey = true }
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
                    Text("Paste GitHub Personal Access Token (Keychain)")
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

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 22) {
                metricCell(
                    title: "Accessible Repos",
                    value: controller.git.repos.isEmpty ? "—" : "\(controller.git.repos.count)"
                )
                metricCell(
                    title: "Auto-Deploy Apps",
                    value: "\(controller.config.managedApps.filter(\.autoDeploy).count)"
                )
                metricCell(
                    title: "Poll Interval",
                    value: "\(controller.config.gitPollIntervalSec)s"
                )
            }

            if let error = controller.git.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            } else {
                Text("Connected repositories populate the Quick Pick menu inside + Add Local App and enable automatic commit polling.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 255, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 2. Local LLM (Ollama) Card

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
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.ollama.light, label: controller.ollama.statusLabel)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 22) {
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
                    title: "Models",
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
        .frame(maxWidth: .infinity, minHeight: 255, alignment: .topLeading)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 3. Claude API Health Checker Card

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
                        Button("Replace") { editingClaudeKey = true }
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
                        Button("Check") {
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

            HStack(spacing: 22) {
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
        .frame(maxWidth: .infinity, minHeight: 255, alignment: .topLeading)
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
