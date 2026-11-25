import SwiftUI

struct ConfigurationView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var ollamaEndpoint: String = "http://127.0.0.1:11434"
    @State private var gitPollIntervalText: String = "60"
    @State private var maxRestartsText: String = "10"
    @State private var notifyOnCrash: Bool = true
    @State private var notifyOnDeploy: Bool = true
    @State private var notifyOnOllamaDown: Bool = true
    @State private var expanded: Bool = true

    // Per-provider draft state (stored only in memory while editing; secrets persist solely to macOS Keychain)
    @State private var keyDrafts: [CloudProviderKind: String] = [:]
    @State private var baseURLDrafts: [CloudProviderKind: String] = [:]
    @State private var accountIDDrafts: [CloudProviderKind: String] = [:]
    @State private var modelDrafts: [CloudProviderKind: String] = [:]
    @State private var editingKeyFor: Set<CloudProviderKind> = []
    @State private var claudeKeyDraft: String = ""
    @State private var editingClaudeKey: Bool = false

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }

    private var connectedCloudCount: Int {
        let others = CloudProviderKind.allCases.filter { controller.cloudProviderState(for: $0).isConnected }.count
        return others + (controller.claude.isConnected ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Global Settings, Theme & Cloud APIs", fontSize: 15.5)
                    Text("Persisted to \(controller.flatFileStore.configFileURL.lastPathComponent) · All API keys & tokens encrypted in macOS Keychain · \(connectedCloudCount) cloud integration(s) connected")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button(expanded ? "Hide Settings" : "Edit Settings") {
                    if !expanded { syncFromController() }
                    expanded.toggle()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                Divider().overlay(palette.border)

                // MARK: - Appearance / Theme Switcher
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dashboard Theme (Real-Time)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.sectionHeader)
                        Text("Switch instantly between Dark mode and crisp White (Light) mode.")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer()

                    Picker("Theme", selection: Binding(
                        get: { controller.config.appearanceMode },
                        set: { nextMode in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                controller.setAppearanceMode(nextMode)
                            }
                        }
                    )) {
                        ForEach(BeaconAppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(12)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // MARK: - Cloud AI & Infrastructure APIs
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cloud AI APIs (ChatGPT, Gemini, Claude, OpenRouter, Groq & Custom)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.sectionHeader)
                            Text("Connect any cloud AI API below to store your key in macOS Keychain and monitor endpoint reachability.")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                    }

                    // Anthropic Claude row (linked directly to existing Claude Keychain & state)
                    claudeSettingsRow

                    // OpenAI (ChatGPT), Google Gemini, OpenRouter, Groq, Custom OpenAI-Compatible
                    ForEach(CloudProviderKind.allCases.filter { $0.category == .ai }) { kind in
                        cloudProviderRow(kind)
                    }

                    Divider().overlay(palette.border)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud & Edge Platforms (Cloudflare, Vercel, Supabase)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.sectionHeader)
                        Text("Verify API tokens in macOS Keychain. Adding a Cloudflare Account ID enables named Cloudflare Tunnel provisioning.")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondaryText)
                    }

                    ForEach(CloudProviderKind.allCases.filter { $0.category == .cloud }) { kind in
                        cloudProviderRow(kind)
                    }
                }

                Divider().overlay(palette.border)

                // MARK: - General Monitoring & Alerts
                Text("Monitoring, Alerts & Polling")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.sectionHeader)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        fieldLabel("Ollama Loopback Endpoint")
                        TextField("http://127.0.0.1:11434", text: $ollamaEndpoint)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Git Auto-Deploy Poll (sec)")
                        TextField("60", text: $gitPollIntervalText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 120)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Max Auto-Restarts / App")
                        TextField("10", text: $maxRestartsText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 120)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                }

                HStack(spacing: 16) {
                    Toggle("Alert on crash", isOn: $notifyOnCrash)
                    Toggle("Alert on deploy", isOn: $notifyOnDeploy)
                    Toggle("Alert on Ollama offline", isOn: $notifyOnOllamaDown)
                    Spacer()
                    Button("Test Notification") {
                        Task { await controller.sendTestAlert() }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Save Configuration") {
                        let poll = Int(gitPollIntervalText) ?? controller.config.gitPollIntervalSec
                        let maxR = Int(maxRestartsText) ?? controller.config.maxRestarts
                        Task {
                            await controller.saveGlobalConfiguration(
                                ollamaEndpoint: ollamaEndpoint,
                                gitPollIntervalSec: poll,
                                maxRestarts: maxR,
                                notifyOnCrash: notifyOnCrash,
                                notifyOnDeploy: notifyOnDeploy,
                                notifyOnOllamaDown: notifyOnOllamaDown
                            )
                        }
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)

                Divider().overlay(palette.border)

                // MARK: - Privacy & Data Handling Placeholder
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy & Data Handling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                    Text("BeaconMac stores all configuration and logs locally on your Mac (`~/Library/Application Support/Beacon/`) and encrypts credentials in macOS Keychain. Zero analytics, zero tracking (`NSPrivacyTracking = false`), and no local logs are transmitted to third-party AI services.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 8) {
                        Text("Privacy Policy URL (Placeholder):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                        Text((Bundle.main.object(forInfoDictionaryKey: "BeaconPrivacyPolicyURL") as? String) ?? "https://example.com/beaconmac/privacy")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.accentLink)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
        .onAppear {
            syncFromController()
        }
    }

    // MARK: - Anthropic Claude Row inside Settings

    private var claudeSettingsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(controller.claude.isConnected ? Color.green : (controller.claude.lastError != nil ? Color.red : Color.gray.opacity(0.45)))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Anthropic Claude")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("api.anthropic.com · Verify Anthropic API key & model reachability")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                if controller.claude.isConnected, let ms = controller.claude.latencyMs {
                    Text("HTTP \(controller.claude.httpStatus ?? 200) · \(ms) ms · \(controller.claude.models.count) models")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.successText)
                } else {
                    Text(controller.claude.statusLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(controller.claude.lastError != nil ? palette.errorText : palette.secondaryText)
                }
            }

            if let hint = controller.claude.keyHint, !editingClaudeKey {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(palette.successText)
                        .font(.system(size: 10.5))
                    Text(hint)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.bodyText)
                    if !controller.claude.activeModel.isEmpty {
                        Text("· \(controller.claude.activeModel)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.accentLink)
                    }
                    Spacer()
                    Button("Test") {
                        Task { _ = await controller.probeClaude(logResult: true) }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                    Button("Replace") {
                        editingClaudeKey = true
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                    Button("Clear") {
                        editingClaudeKey = false
                        claudeKeyDraft = ""
                        controller.disconnectClaudeKey()
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-api03-...", text: $claudeKeyDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.input)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    Button("Connect & Verify") {
                        let key = claudeKeyDraft
                        claudeKeyDraft = ""
                        Task {
                            let ok = await controller.connectClaudeKey(key)
                            if ok { editingClaudeKey = false }
                        }
                    }
                    .disabled(claudeKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.busyAction != nil)
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

            if let err = controller.claude.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.errorText)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(controller.claude.isConnected ? Color.green.opacity(0.32) : palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Generic Cloud AI / Cloud Platform Provider Row

    private func cloudProviderRow(_ kind: CloudProviderKind) -> some View {
        let state = controller.cloudProviderState(for: kind)
        let cfg = controller.cloudProviderConfig(for: kind)
        let isEditing = editingKeyFor.contains(kind) || state.keyHint == nil

        let keyBinding = Binding<String>(
            get: { keyDrafts[kind] ?? "" },
            set: { keyDrafts[kind] = $0 }
        )
        let baseURLBinding = Binding<String>(
            get: { baseURLDrafts[kind] ?? cfg.baseURL },
            set: {
                baseURLDrafts[kind] = $0
                controller.updateCloudProviderSettings(kind, baseURL: $0)
            }
        )
        let accountIDBinding = Binding<String>(
            get: { accountIDDrafts[kind] ?? cfg.accountID },
            set: {
                accountIDDrafts[kind] = $0
                controller.updateCloudProviderSettings(kind, accountID: $0)
            }
        )
        let modelBinding = Binding<String>(
            get: {
                let draft = modelDrafts[kind] ?? cfg.selectedModel
                return draft.isEmpty ? kind.defaultModel : draft
            },
            set: {
                modelDrafts[kind] = $0
                controller.updateCloudProviderSettings(kind, selectedModel: $0)
            }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(state.isConnected ? Color.green : (state.lastError != nil ? Color.red : Color.gray.opacity(0.45)))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(kind.subtitle)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if state.isConnected {
                    let details = [
                        state.httpStatus.map { "HTTP \($0)" },
                        state.latencyMs.map { "\($0) ms" },
                        state.accountLabel
                    ].compactMap { $0 }.joined(separator: " · ")
                    Text(details.isEmpty ? "Connected" : details)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.successText)
                } else {
                    Text(state.statusLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(state.lastError != nil ? palette.errorText : palette.secondaryText)
                }
            }

            // Optional secondary config fields (Base URL for Custom AI / Supabase, Account ID for Cloudflare)
            if kind.supportsBaseURL || kind.supportsAccountID {
                HStack(spacing: 8) {
                    if kind.supportsBaseURL {
                        Text(kind == .supabase ? "Project URL" : "Base URL")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: 78, alignment: .leading)
                        TextField(kind.baseURLPlaceholder, text: baseURLBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if kind.supportsAccountID {
                        Text("Account ID")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondaryText)
                            .frame(width: 78, alignment: .leading)
                        TextField("Optional: 32-char Cloudflare Account ID (for Workers AI)", text: accountIDBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Keychain credential row or Connect input
            if let hint = state.keyHint, !isEditing {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(palette.successText)
                        .font(.system(size: 10.5))
                    Text(hint)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.bodyText)

                    if kind.supportsModelSelection {
                        if !state.models.isEmpty {
                            Picker("Model", selection: modelBinding) {
                                ForEach(state.models, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 230)
                        } else {
                            TextField("Model ID", text: modelBinding)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.primaryText)
                                .frame(width: 190)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.input)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Spacer()

                    Button("Test") {
                        Task { _ = await controller.probeCloudProvider(kind, logResult: true) }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Replace") {
                        editingKeyFor.insert(kind)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Clear") {
                        editingKeyFor.remove(kind)
                        keyDrafts[kind] = ""
                        controller.disconnectCloudProvider(kind)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 8) {
                    SecureField(kind.keyPlaceholder, text: keyBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.input)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    if kind == .customOpenAI {
                        TextField("Model ID (e.g. deepseek-chat)", text: modelBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 175)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(palette.input)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    Button("Connect & Verify") {
                        let key = keyDrafts[kind] ?? ""
                        let base = baseURLDrafts[kind] ?? cfg.baseURL
                        let acct = accountIDDrafts[kind] ?? cfg.accountID
                        let mod = modelDrafts[kind] ?? cfg.selectedModel
                        Task {
                            let ok = await controller.connectCloudProvider(
                                kind,
                                apiKey: key,
                                baseURL: base,
                                accountID: acct,
                                selectedModel: mod
                            )
                            if ok {
                                keyDrafts[kind] = ""
                                editingKeyFor.remove(kind)
                            }
                        }
                    }
                    .disabled((keyDrafts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())

                    if state.keyHint != nil {
                        Button("Cancel") {
                            editingKeyFor.remove(kind)
                            keyDrafts[kind] = ""
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }
            }

            if let err = state.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.errorText)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(state.isConnected ? Color.green.opacity(0.32) : palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func syncFromController() {
        ollamaEndpoint = controller.config.ollamaEndpoint
        gitPollIntervalText = "\(controller.config.gitPollIntervalSec)"
        maxRestartsText = "\(controller.config.maxRestarts)"
        notifyOnCrash = controller.config.notifyOnCrash
        notifyOnDeploy = controller.config.notifyOnDeploy
        notifyOnOllamaDown = controller.config.notifyOnOllamaDown
        for kind in CloudProviderKind.allCases {
            let cfg = controller.cloudProviderConfig(for: kind)
            baseURLDrafts[kind] = cfg.baseURL
            accountIDDrafts[kind] = cfg.accountID
            modelDrafts[kind] = cfg.selectedModel.isEmpty ? kind.defaultModel : cfg.selectedModel
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondaryText)
            .frame(width: 175, alignment: .leading)
    }
}
