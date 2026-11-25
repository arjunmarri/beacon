import SwiftUI

struct MultiAppSectionView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddSheet = false
    @State private var editingApp: ManagedApp?
    @State private var copiedTunnelAppID: UUID?
    @State private var inspectedConfigTunnel: CloudflareTunnelEntry?
    @State private var hoveredAppID: UUID?

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(
                        title: "Managed Local Apps (\(controller.config.managedApps.count))",
                        fontSize: 16,
                        systemImage: "shippingbox.fill"
                    )
                    Text("Clone remote Git repos, check required Vite/Node libraries, build, deploy locally, and monitor multiple apps simultaneously.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Button("Check System Tools") {
                    Task { await controller.auditSystemDependencies() }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Install Dependencies") {
                    controller.openDependencyInstaller()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("+ Add Local App") {
                    showingAddSheet = true
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }

            let visibleTools = controller.systemTools.filter { !$0.isOptional || $0.available }
            if !visibleTools.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        Text("Runtime tools")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        ForEach(visibleTools) { tool in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(tool.available ? palette.successText : palette.warningText.opacity(0.85))
                                    .frame(width: 6, height: 6)
                                Text("\(tool.name) \(tool.available ? tool.detail : "missing")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(tool.available ? palette.bodyText : palette.secondaryText)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .beaconGlassWell(cornerRadius: 10)
            }

            if controller.config.managedApps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.app.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(palette.sectionHeader)
                        Text("No local apps configured yet")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                    }
                    Text("Add any locally deployed Vite, Node.js, or custom app with its remote Git repository URL, local folder, and localhost port. BeaconMac will clone it, check & install required dependencies, build it, and monitor its health.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Button("Add Your First Local App") {
                        showingAddSheet = true
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .beaconGlassRow(cornerRadius: 12, padding: 18)
            } else {
                VStack(spacing: 12) {
                    ForEach(controller.config.managedApps) { app in
                        appRow(app)
                    }
                }
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
        .sheet(isPresented: $showingAddSheet) {
            AppEditorSheet(controller: controller, existingApp: nil)
                .preferredColorScheme(activeScheme)
        }
        .sheet(item: $editingApp) { app in
            AppEditorSheet(controller: controller, existingApp: app)
                .preferredColorScheme(activeScheme)
        }
        .sheet(item: $inspectedConfigTunnel) { tunnel in
            CloudflareConfigInspectorSheet(
                title: "\(tunnel.label) · cloudflared config.yml",
                configPath: tunnel.configFilePath ?? "",
                configText: controller.generatedCloudflaredConfig(for: tunnel.id) ?? "# No config.yml generated yet."
            )
            .preferredColorScheme(activeScheme)
        }
    }

    private func appRow(_ app: ManagedApp) -> some View {
        let state = controller.runtimeState(for: app.id)
        let isHovered = hoveredAppID == app.id

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Text(app.stackPreset.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                        if app.runOnStartup {
                            Text("· Startup/Cron")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accentLink)
                        }
                    }

                    Text("\(app.monitorURL)  ·  \(app.repoURL.isEmpty ? "Local only" : "\(app.repoURL) (\(app.branch))")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                TrafficLightLampView(active: state.light, label: state.statusLabel)
            }

            let isPendingOrStopped = state.isManuallyStopped
                || state.isDeploying
                || state.statusLabel == "Idle"
                || state.statusLabel == "Not Deployed"
                || state.statusLabel == "Starting..."
                || state.statusLabel == "Stopping..."

            HStack(spacing: 24) {
                miniMetric(
                    "HTTP Probe",
                    state.isHealthy
                        ? "\(state.httpStatus ?? 200) · \(state.responseTimeMs ?? 1) ms"
                        : (isPendingOrStopped ? "—" : (state.httpStatus.map { "HTTP \($0)" } ?? "Unreachable")),
                    color: state.isHealthy ? palette.successText : (isPendingOrStopped ? palette.secondaryText : palette.errorText)
                )
                miniMetric("Commit", state.commitHash)
                miniMetric("Dependencies", state.dependencySummary)
                miniMetric("Restarts", "\(state.restartCount)")
                Spacer()
            }

            if let err = state.lastError, !err.isEmpty, !state.isHealthy, !isPendingOrStopped {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.errorText)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            let tunnel = controller.cloudflareTunnelEntry(for: app)
            if let tunnel, tunnel.isRunning || tunnel.isStarting || (tunnel.lastError != nil) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(tunnel.isRunning ? palette.successText : (tunnel.isStarting ? palette.warningText : palette.errorText))
                        .frame(width: 7, height: 7)
                        .shadow(color: (tunnel.isRunning ? palette.successText : .clear).opacity(0.65), radius: 4)

                    if let pubURL = tunnel.publicURL, tunnel.isRunning {
                        Text("Public URL")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.successText)
                        Text(pubURL)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.accentLink)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer()
                        if tunnel.configFilePath != nil {
                            Button("config.yml") {
                                inspectedConfigTunnel = tunnel
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                        Button(copiedTunnelAppID == app.id ? "Copied ✓" : "Copy URL") {
                            controller.copyTunnelURL(pubURL)
                            copiedTunnelAppID = app.id
                            Task {
                                try? await Task.sleep(for: .seconds(1.8))
                                if copiedTunnelAppID == app.id {
                                    copiedTunnelAppID = nil
                                }
                            }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        Button("Open Online") {
                            controller.openTunnelURL(pubURL)
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        Button("Stop Tunnel") {
                            Task { await controller.stopCloudflareTunnel(key: tunnel.id) }
                        }
                        .buttonStyle(BeaconDangerButtonStyle())
                    } else if tunnel.isStarting {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Cloudflare Tunnel: \(tunnel.statusLabel)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.warningText)
                        Spacer()
                    } else if let tErr = tunnel.lastError {
                        Text("Cloudflare Tunnel error: \(tErr)")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.errorText)
                            .lineLimit(2)
                        Spacer()
                        Button("Retry") {
                            Task { await controller.toggleCloudflareTunnel(for: app) }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    tunnel.isRunning
                        ? (palette.isLight ? Color(red: 0.90, green: 0.98, blue: 0.94).opacity(0.92) : Color(red: 0.05, green: 0.18, blue: 0.14).opacity(0.75))
                        : palette.console
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tunnel.isRunning ? palette.successText.opacity(0.42) : palette.subtleBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            Divider().overlay(palette.subtleBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(state.isDeploying ? "Deploying…" : "Clone & Deploy") {
                        Task { await controller.cloneBuildAndDeploy(app: app, trigger: "manual") }
                    }
                    .disabled(state.isDeploying || controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())

                    Button(state.isManuallyStopped ? "Start" : "Restart") {
                        Task { await controller.restartManagedApp(app, reason: "manual") }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Stop") {
                        Task { await controller.stopManagedApp(app) }
                    }
                    .disabled(controller.busyAction != nil || (state.isManuallyStopped && !state.isHealthy))
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    let appTunnel = controller.cloudflareTunnelEntry(for: app)
                    Button(appTunnel?.isStarting == true
                        ? "Exposing…"
                        : (appTunnel?.isRunning == true ? "Stop Cloudflare Tunnel" : "Expose via Cloudflare Tunnel")) {
                        Task { await controller.toggleCloudflareTunnel(for: app) }
                    }
                    .disabled(appTunnel?.isStarting == true)
                    .buttonStyle(BeaconPrimaryButtonStyle())

                    Button("Load in Node Host") {
                        Task { await controller.loadManagedAppIntoBuiltInServer(app) }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Spacer()

                    Toggle("Startup", isOn: Binding(
                        get: { app.runOnStartup },
                        set: { _ in controller.toggleAppStartup(app) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)

                    Button("Edit") {
                        editingApp = app
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Remove") {
                        controller.deleteManagedApp(app)
                    }
                    .buttonStyle(BeaconDangerButtonStyle())
                }

                HStack(spacing: 8) {
                    Button("Check Deps") {
                        Task { await controller.checkDependencies(for: app) }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Install Dependencies") {
                        controller.openDependencyInstaller(for: app)
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Open Terminal") {
                        controller.openInTerminal(app: app)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Tail Log") {
                        controller.tailLogsInTerminal(app: app)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Copy Cmd") {
                        controller.copyDeployCommand(for: app)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Spacer()
                }
            }
        }
        .beaconGlassRow(
            cornerRadius: 13,
            padding: 15,
            accentBorder: state.isHealthy ? palette.successText.opacity(isHovered ? 0.45 : 0.25) : nil,
            isHovered: isHovered
        )
        .onHover { hovering in
            hoveredAppID = hovering ? app.id : (hoveredAppID == app.id ? nil : hoveredAppID)
        }
    }

    private func miniMetric(_ title: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color ?? palette.primaryText)
                .lineLimit(1)
        }
    }
}
