import AppKit
import SwiftUI

struct CloudflareTunnelSectionView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var customPortText: String = "3000"
    @State private var baseDomainDraft: String = ""
    @State private var didLoadDraft = false
    @State private var copiedTunnelID: String?
    @State private var inspectedTunnel: CloudflareTunnelEntry?

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    private func copyURL(_ url: String, tunnelID: String) {
        controller.copyTunnelURL(url)
        copiedTunnelID = tunnelID
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedTunnelID == tunnelID {
                copiedTunnelID = nil
            }
        }
    }

    private func exposeCustomPort() {
        let trimmed = customPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65535).contains(port) else { return }
        Task {
            await controller.exposeCustomPortViaCloudflare(port: port)
        }
    }

    private func saveBaseDomain() {
        controller.updateCloudflareTunnelSettings(
            preferredProtocol: controller.config.cloudflareTunnel.preferredProtocol,
            autoInstallCloudflared: controller.config.cloudflareTunnel.autoInstallCloudflared,
            autoCopyURLOnStart: controller.config.cloudflareTunnel.autoCopyURLOnStart,
            preferCloudflareAPI: controller.config.cloudflareTunnel.preferCloudflareAPI,
            customBaseDomain: baseDomainDraft
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        BeaconSectionHeaderText(title: "Cloudflare Tunnels · 1-Click Internet Access", fontSize: 16)
                        if let ver = controller.cloudflareTunnel.version {
                            Text("cloudflared \(ver)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        if controller.hasCloudflareAPITokenInKeychain {
                            Text("· Keychain Cloudflare API Ready")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.successText)
                        } else {
                            Text("· Quick Tunnel Mode")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Text("Dynamically generates a cloudflared `config.yml` using your Keychain Cloudflare API integration (creating the named tunnel & DNS CNAME automatically) or falls back to an instant `*.trycloudflare.com` Quick Tunnel.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                TrafficLightLampView(
                    active: controller.cloudflareTunnel.light,
                    label: controller.cloudflareTunnel.statusLabel
                )
            }

            // Controls & Quick-Expose Bar
            HStack(spacing: 10) {
                if !controller.cloudflareTunnel.isInstalled {
                    Button(controller.cloudflareTunnel.isInstalling ? "Installing cloudflared…" : "Install cloudflared") {
                        Task { _ = await controller.installCloudflaredSilently() }
                    }
                    .disabled(controller.cloudflareTunnel.isInstalling || controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }

                if !controller.config.managedApps.isEmpty {
                    Menu {
                        ForEach(controller.config.managedApps) { app in
                            let live = controller.cloudflareTunnelEntry(for: app)?.isRunning == true
                            Button(live ? "Stop Tunnel for \"\(app.name)\"" : "Expose \"\(app.name)\" (:\(app.port)) via Cloudflare") {
                                Task { await controller.toggleCloudflareTunnel(for: app) }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Expose Local App")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.14, green: 0.44, blue: 0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                let nginxTunnelLive = controller.cloudflareTunnelEntry(for: "nginx")?.isRunning == true
                let nginxTunnelStarting = controller.cloudflareTunnelEntry(for: "nginx")?.isStarting == true
                Button(nginxTunnelStarting ? "Tunneling NGINX…" : (nginxTunnelLive ? "Stop NGINX Tunnel" : "Expose NGINX (:\(controller.config.nginxProxy.listenPort))")) {
                    Task { await controller.toggleNginxCloudflareTunnel() }
                }
                .disabled(nginxTunnelStarting)
                .buttonStyle(BeaconSecondaryButtonStyle())

                let nodeTunnelLive = controller.cloudflareTunnelEntry(for: "node-host")?.isRunning == true
                let nodeTunnelStarting = controller.cloudflareTunnelEntry(for: "node-host")?.isStarting == true
                Button(nodeTunnelStarting ? "Tunneling Node…" : (nodeTunnelLive ? "Stop Node Tunnel" : "Expose Node Host (:\(controller.config.builtInServer.port))")) {
                    Task { await controller.toggleBuiltInServerCloudflareTunnel() }
                }
                .disabled(nodeTunnelStarting)
                .buttonStyle(BeaconSecondaryButtonStyle())

                let ollamaTunnelLive = controller.ollamaCloudflareTunnel?.isRunning == true
                let ollamaTunnelStarting = controller.ollamaCloudflareTunnel?.isStarting == true
                Button(ollamaTunnelStarting ? "Tunneling Ollama…" : (ollamaTunnelLive ? "Stop Ollama Tunnel" : "Expose Ollama (:\(controller.ollamaPort))")) {
                    Task { await controller.toggleOllamaCloudflareTunnel() }
                }
                .disabled(ollamaTunnelStarting)
                .buttonStyle(BeaconSecondaryButtonStyle())
                .help("Expose local Ollama LLM API over HTTPS via Cloudflare Tunnel")

                // Quick custom port expose
                HStack(spacing: 6) {
                    Text("Port")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    TextField("3000", text: $customPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 58)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(palette.input)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit { exposeCustomPort() }
                    Button("Expose Port") {
                        exposeCustomPort()
                    }
                    .disabled(Int(customPortText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }

                Spacer()

                if controller.cloudflareTunnel.activeCount > 0 {
                    Button("Stop All Tunnels") {
                        Task { await controller.stopAllCloudflareTunnels() }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            }

            // Keychain Cloudflare API & Transport Options
            HStack(spacing: 14) {
                Toggle("Use Keychain Cloudflare API", isOn: Binding(
                    get: { controller.config.cloudflareTunnel.preferCloudflareAPI },
                    set: { next in
                        controller.updateCloudflareTunnelSettings(
                            preferredProtocol: controller.config.cloudflareTunnel.preferredProtocol,
                            autoInstallCloudflared: controller.config.cloudflareTunnel.autoInstallCloudflared,
                            autoCopyURLOnStart: controller.config.cloudflareTunnel.autoCopyURLOnStart,
                            preferCloudflareAPI: next,
                            customBaseDomain: baseDomainDraft
                        )
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                HStack(spacing: 6) {
                    Text("Domain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    TextField("auto-detect zone (or example.com)", text: $baseDomainDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 210)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(palette.input)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit { saveBaseDomain() }
                    if CloudflareTunnelService.sanitizeDomain(baseDomainDraft) != controller.config.cloudflareTunnel.customBaseDomain {
                        Button("Save") { saveBaseDomain() }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }

                HStack(spacing: 6) {
                    Text("Transport")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    Picker("Transport", selection: Binding(
                        get: { controller.config.cloudflareTunnel.preferredProtocol },
                        set: { next in
                            controller.updateCloudflareTunnelSettings(
                                preferredProtocol: next,
                                autoInstallCloudflared: controller.config.cloudflareTunnel.autoInstallCloudflared,
                                autoCopyURLOnStart: controller.config.cloudflareTunnel.autoCopyURLOnStart,
                                preferCloudflareAPI: controller.config.cloudflareTunnel.preferCloudflareAPI,
                                customBaseDomain: baseDomainDraft
                            )
                        }
                    )) {
                        ForEach(CloudflareTunnelProtocol.allCases) { proto in
                            Text(proto.label).tag(proto)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 175)
                }

                Toggle("Auto-copy URL", isOn: Binding(
                    get: { controller.config.cloudflareTunnel.autoCopyURLOnStart },
                    set: { next in
                        controller.updateCloudflareTunnelSettings(
                            preferredProtocol: controller.config.cloudflareTunnel.preferredProtocol,
                            autoInstallCloudflared: controller.config.cloudflareTunnel.autoInstallCloudflared,
                            autoCopyURLOnStart: next,
                            preferCloudflareAPI: controller.config.cloudflareTunnel.preferCloudflareAPI,
                            customBaseDomain: baseDomainDraft
                        )
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                Spacer()

                Button("Refresh") {
                    Task { await controller.probeCloudflareTunnels(logTransitions: false) }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if let err = controller.cloudflareTunnel.lastError, !err.isEmpty {
                HStack(spacing: 8) {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.errorText)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        controller.cloudflareTunnel.lastError = nil
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
                .padding(10)
                .background(Color.red.opacity(palette.isLight ? 0.08 : 0.12))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Active Tunnels List
            let active = controller.cloudflareTunnel.activeTunnels
            if active.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.accentLink)
                    Text(controller.hasCloudflareAPITokenInKeychain
                        ? "Cloudflare API token detected in Keychain. Click \"Expose via Cloudflare Tunnel\" on any app card above to auto-provision a named tunnel, generate `config.yml`, and publish your app online."
                        : "No active Cloudflare Tunnels yet. Click \"Expose via Cloudflare Tunnel\" on any Managed Local App above (or add your Cloudflare API token in Settings for named custom domains).")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                }
                .padding(12)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(active) { entry in
                        tunnelRow(entry)
                    }
                }
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
        .onAppear {
            if !didLoadDraft {
                baseDomainDraft = controller.config.cloudflareTunnel.customBaseDomain
                didLoadDraft = true
            }
        }
        .sheet(item: $inspectedTunnel) { tunnel in
            CloudflareConfigInspectorSheet(
                title: "\(tunnel.label) · cloudflared config.yml",
                configPath: tunnel.configFilePath ?? "",
                configText: controller.generatedCloudflaredConfig(for: tunnel.id) ?? "# No config.yml generated yet."
            )
            .preferredColorScheme(activeScheme)
        }
    }

    private func tunnelRow(_ entry: CloudflareTunnelEntry) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.isRunning ? palette.successText : palette.warningText)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(entry.mode.badgeLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(entry.mode == .apiManaged ? palette.accentLink : palette.secondaryText)
                    Text("→ \(entry.targetURL)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                    if let pid = entry.pid {
                        Text("· PID \(pid)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }
                }

                if let pubURL = entry.publicURL, !pubURL.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.successText)
                        Text(pubURL)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.accentLink)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(entry.statusLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.warningText)
                }
            }

            Spacer()

            if entry.configFilePath != nil {
                Button("config.yml") {
                    inspectedTunnel = entry
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if let pubURL = entry.publicURL, !pubURL.isEmpty {
                Button(copiedTunnelID == entry.id ? "Copied" : "Copy URL") {
                    copyURL(pubURL, tunnelID: entry.id)
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Open") {
                    controller.openTunnelURL(pubURL)
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }

            Button("Stop") {
                Task { await controller.stopCloudflareTunnel(key: entry.id) }
            }
            .buttonStyle(BeaconSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(entry.isRunning ? palette.successText.opacity(0.35) : palette.subtleBorder))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CloudflareConfigInspectorSheet: View {
    let title: String
    let configPath: String
    let configText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    BeaconSectionHeaderText(title: title, fontSize: 15)
                    if !configPath.isEmpty {
                        Text(configPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Button(copied ? "Copied" : "Copy YAML") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }

            ScrollView {
                Text(configText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(palette.console)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 340)
        .background(palette.canvas)
    }
}
