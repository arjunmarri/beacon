import SwiftUI

struct ServiceCardsView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var gitTokenDraft: String = ""
    @State private var editingGitKey: Bool = false
    @State private var claudeKeyDraft: String = ""
    @State private var editingClaudeKey: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

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
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "GitHub Account", fontSize: 15)
                    Text(controller.git.connectedUsername.map { "@\($0) · \(controller.git.repos.count) repos" } ?? "Paste PAT to sync & auto-deploy repos")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.git.light, label: controller.git.statusLabel)
            }

            if let keyHint = controller.git.keyHint, !editingGitKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub token (stored in macOS Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(palette.successText)
                            .font(.system(size: 11))
                        Text(keyHint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.bodyText)
                        Spacer()
                        Button("Replace") { editingGitKey = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.accentLink)
                        Button("Clear") { controller.disconnectGitToken() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.errorText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.inputBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste GitHub Personal Access Token (Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 8) {
                        SecureField("ghp_... or github_pat_...", text: $gitTokenDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.inputBorder))
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

            Divider().overlay(palette.border)

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
                    .foregroundStyle(palette.errorText)
                    .lineLimit(2)
            } else {
                Text("Connected repositories populate the Quick Pick menu inside + Add Local App and enable automatic commit polling.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 255, alignment: .topLeading)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
    }

    // MARK: - 2. Local LLM (Ollama) Card

    private var ollamaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Local LLM (Ollama)", fontSize: 15)
                    Text(controller.ollama.endpoint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.ollama.light, label: controller.ollama.statusLabel)
            }

            Divider().overlay(palette.border)

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

            Divider().overlay(palette.border)

            VStack(alignment: .leading, spacing: 6) {
                Text("Active local model")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                if controller.ollama.models.isEmpty {
                    Text("Start Ollama locally on port 11434 to list models")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
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
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
    }

    // MARK: - 3. Claude API Health Checker Card

    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Claude API", fontSize: 15)
                    Text("api.anthropic.com · /v1/models")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                TrafficLightLampView(active: controller.claude.light, label: controller.claude.statusLabel)
            }

            if let hint = controller.claude.keyHint, controller.claude.isConnected, !editingClaudeKey {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude API key (stored in macOS Keychain)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(palette.successText)
                            .font(.system(size: 11))
                        Text(hint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.bodyText)
                        Spacer()
                        Button("Replace") { editingClaudeKey = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.accentLink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.inputBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste Claude API key (verified via /v1/models)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 8) {
                        SecureField("sk-ant-api03-...", text: $claudeKeyDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.inputBorder))
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

            Divider().overlay(palette.border)

            HStack(spacing: 22) {
                metricCell(
                    title: "HTTP Status",
                    value: controller.claude.isConnected
                        ? "\(controller.claude.httpStatus ?? 200) OK"
                        : (controller.claude.httpStatus.map { "HTTP \($0)" } ?? "—"),
                    valueColor: controller.claude.isConnected
                        ? palette.successText
                        : (controller.claude.lastError != nil ? palette.errorText : palette.secondaryText)
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
                    .foregroundStyle(palette.errorText)
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
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
    }

    // MARK: - Helpers

    private func metricCell(title: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? palette.primaryText)
                .lineLimit(1)
        }
    }
}
