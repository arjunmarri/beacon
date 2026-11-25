import SwiftUI

struct ServiceCardsView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var gitTokenDraft: String = ""
    @State private var editingGitKey: Bool = false
    @State private var copiedOllamaTunnel: Bool = false
    @State private var inspectedOllamaTunnel: CloudflareTunnelEntry?

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 18)]

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            gitAccountCard
            ollamaCard
        }
        .sheet(item: $inspectedOllamaTunnel) { tunnel in
            CloudflareConfigInspectorSheet(
                title: "\(tunnel.label) · cloudflared config.yml",
                configPath: tunnel.configFilePath ?? "",
                configText: controller.generatedCloudflaredConfig(for: tunnel.id) ?? "# No config.yml generated yet."
            )
            .preferredColorScheme(activeScheme)
        }
    }

    // MARK: - 1. GitHub Account & Keychain Token Card

    private var gitAccountCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "GitHub Account", fontSize: 15.5, systemImage: "chevron.left.forwardslash.chevron.right")
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
                    Text("GitHub token (encrypted in macOS Keychain)")
                        .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accentLink)
                        Button("Clear") { controller.disconnectGitToken() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.errorText)
                    }
                    .beaconGlassInput(cornerRadius: 9, horizontalPadding: 11, verticalPadding: 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste GitHub Personal Access Token (Keychain)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 8) {
                        SecureField("ghp_... or github_pat_...", text: $gitTokenDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .beaconGlassInput(cornerRadius: 9, horizontalPadding: 10, verticalPadding: 7.5)
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

            Divider().overlay(palette.subtleBorder)

            HStack(spacing: 24) {
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 268, alignment: .topLeading)
        .beaconGlassCard(cornerRadius: 16, padding: 20)
    }

    // MARK: - 2. Local LLM (Ollama) Card

    private var ollamaCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Local LLM (Ollama)", fontSize: 15.5, systemImage: "sparkles")
                    Text(controller.ollama.endpoint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                TrafficLightLampView(active: controller.ollama.light, label: controller.ollama.statusLabel)
            }

            Divider().overlay(palette.subtleBorder)

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
                    title: "Models",
                    value: "\(controller.ollama.models.count)"
                )
            }

            Divider().overlay(palette.subtleBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Active local model")
                    .font(.system(size: 11, weight: .medium))
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

            let ollamaTunnel = controller.ollamaCloudflareTunnel
            if let ollamaTunnel, ollamaTunnel.isRunning || ollamaTunnel.isStarting || ollamaTunnel.lastError != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ollamaTunnel.isRunning ? palette.successText : (ollamaTunnel.isStarting ? palette.warningText : palette.errorText))
                            .frame(width: 7, height: 7)
                            .shadow(color: (ollamaTunnel.isRunning ? palette.successText : .clear).opacity(0.65), radius: 4)
                        if let pubURL = ollamaTunnel.publicURL, ollamaTunnel.isRunning {
                            Text("Public URL")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.successText)
                            Text(pubURL)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.accentLink)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if ollamaTunnel.isStarting {
                            Text("Cloudflare Tunnel: \(ollamaTunnel.statusLabel)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.warningText)
                                .lineLimit(1)
                        } else if let tErr = ollamaTunnel.lastError {
                            Text("Tunnel error: \(tErr)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.errorText)
                                .lineLimit(2)
                        }
                    }

                    if let pubURL = ollamaTunnel.publicURL, ollamaTunnel.isRunning {
                        HStack(spacing: 6) {
                            Button(copiedOllamaTunnel ? "Copied ✓" : "Copy URL") {
                                controller.copyTunnelURL(pubURL)
                                copiedOllamaTunnel = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.8))
                                    copiedOllamaTunnel = false
                                }
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())

                            Button("Open") {
                                controller.openTunnelURL(pubURL)
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())

                            if ollamaTunnel.configFilePath != nil {
                                Button("config.yml") {
                                    inspectedOllamaTunnel = ollamaTunnel
                                }
                                .buttonStyle(BeaconSecondaryButtonStyle())
                            }
                            Spacer()
                        }
                    } else if ollamaTunnel.lastError != nil {
                        HStack {
                            Button("Retry Tunnel") {
                                Task { await controller.toggleOllamaCloudflareTunnel() }
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                            Spacer()
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ollamaTunnel.isRunning
                        ? (palette.isLight ? Color(red: 0.90, green: 0.98, blue: 0.94).opacity(0.92) : Color(red: 0.05, green: 0.18, blue: 0.14).opacity(0.75))
                        : palette.row
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ollamaTunnel.isRunning ? palette.successText.opacity(0.42) : palette.subtleBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(ollamaTunnel?.isStarting == true
                    ? "Exposing…"
                    : (ollamaTunnel?.isRunning == true ? "Stop Cloudflare Tunnel" : "Expose via Cloudflare")) {
                    Task { await controller.toggleOllamaCloudflareTunnel() }
                }
                .disabled(ollamaTunnel?.isStarting == true)
                .buttonStyle(BeaconPrimaryButtonStyle())
                .help("Expose local Ollama (:\(controller.ollamaPort)) over HTTPS via Cloudflare Tunnel with automatic Host header rewrite")

                Spacer()

                Button("Health Check") {
                    Task { await controller.probeOllama(logResult: true) }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 268, alignment: .topLeading)
        .beaconGlassCard(cornerRadius: 16, padding: 20)
    }

    // MARK: - Helpers

    private func metricCell(title: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? palette.primaryText)
                .lineLimit(1)
        }
    }
}
