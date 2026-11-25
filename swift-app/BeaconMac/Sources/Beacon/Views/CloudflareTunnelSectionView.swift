import AppKit
import SwiftUI

struct CloudflareTunnelSectionView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var customPortText: String = "3000"
    @State private var copiedTunnelID: String?
    @State private var inspectedTunnel: CloudflareTunnelEntry?
    @State private var hoveredTunnelID: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        BeaconSectionHeaderText(
                            title: "Cloudflare Tunnels · 1-Click Internet Access",
                            fontSize: 16,
                            systemImage: "globe"
                        )
                        if let ver = controller.cloudflareTunnel.version {
                            Text("cloudflared \(ver)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text("· Quick Tunnel Mode")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text("Expose any Managed Local App, Built-In Node.js Server, local Ollama instance, or custom localhost port over HTTPS via instant `*.trycloudflare.com` Quick Tunnels — no API token required.")
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
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Expose Local App")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(palette.isLight ? Color.white : Color(red: 0.032, green: 0.045, blue: 0.072))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6.5)
                        .background(palette.accentGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    TextField("3000", text: $customPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 58)
                        .beaconGlassInput(cornerRadius: 7, horizontalPadding: 8, verticalPadding: 5)
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
                    .buttonStyle(BeaconDangerButtonStyle())
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .beaconGlassWell(cornerRadius: 11)

            // Transport & Quick Tunnel Options
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("Transport")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Picker("Transport", selection: Binding(
                        get: { controller.config.cloudflareTunnel.preferredProtocol },
                        set: { next in
                            controller.updateCloudflareTunnelSettings(
                                preferredProtocol: next,
                                autoInstallCloudflared: controller.config.cloudflareTunnel.autoInstallCloudflared,
                                autoCopyURLOnStart: controller.config.cloudflareTunnel.autoCopyURLOnStart
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
                            autoCopyURLOnStart: next
                        )
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
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
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.errorText)
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
                .padding(11)
                .background(Color.red.opacity(palette.isLight ? 0.08 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.32), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Active Tunnels List
            let active = controller.cloudflareTunnel.activeTunnels
            if active.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.accentLink)
                    Text("No active Cloudflare Tunnels yet. Click \"Expose via Cloudflare Tunnel\" on any Managed Local App, \"Expose Ollama\", or enter any local port above to publish an instant HTTPS Quick Tunnel.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                }
                .beaconGlassRow(cornerRadius: 11, padding: 14)
            } else {
                VStack(spacing: 10) {
                    ForEach(active) { entry in
                        tunnelRow(entry)
                    }
                }
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
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
        let isHovered = hoveredTunnelID == entry.id
        return HStack(spacing: 12) {
            Circle()
                .fill(entry.isRunning ? palette.successText : palette.warningText)
                .frame(width: 8, height: 8)
                .shadow(color: (entry.isRunning ? palette.successText : palette.warningText).opacity(0.65), radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.label)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(entry.mode.badgeLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    Text("→ \(entry.targetURL)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                    if let pid = entry.pid {
                        Text("· PID \(pid)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .monospacedDigit()
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
                Button(copiedTunnelID == entry.id ? "Copied ✓" : "Copy URL") {
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
            .buttonStyle(BeaconDangerButtonStyle())
        }
        .beaconGlassRow(
            cornerRadius: 11,
            padding: 13,
            accentBorder: entry.isRunning ? palette.successText.opacity(0.42) : nil,
            isHovered: isHovered
        )
        .onHover { hovering in
            hoveredTunnelID = hovering ? entry.id : (hoveredTunnelID == entry.id ? nil : hoveredTunnelID)
        }
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
        ZStack {
            BeaconAmbientCanvas()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        BeaconSectionHeaderText(title: title, fontSize: 15.5, systemImage: "doc.text.magnifyingglass")
                        if !configPath.isEmpty {
                            Text(configPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    Button(copied ? "Copied ✓" : "Copy YAML") {
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
                        .padding(14)
                }
                .beaconGlassWell(cornerRadius: 11)
            }
            .padding(20)
        }
        .frame(minWidth: 580, minHeight: 360)
    }
}
