import SwiftUI

struct MultiAppSectionView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAddSheet = false
    @State private var editingApp: ManagedApp?
    @State private var copiedTunnelAppID: UUID?
    @State private var inspectedConfigTunnel: CloudflareTunnelEntry?

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Managed Local Apps (\(controller.config.managedApps.count))", fontSize: 16)
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
                HStack(spacing: 14) {
                    Text("Runtime tools:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    ForEach(visibleTools) { tool in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tool.available ? palette.successText : palette.warningText.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Text("\(tool.name) \(tool.available ? tool.detail : "missing")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(tool.available ? palette.bodyText : palette.secondaryText)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if controller.config.managedApps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No local apps configured yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                    Text("Add any locally deployed Vite, Node.js, or custom app with its remote Git repository URL, local folder, and localhost port. BeaconMac will clone it, check & install required dependencies, build it, and monitor its health.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Button("Add Your First Local App") {
                        showingAddSheet = true
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 12) {
                    ForEach(controller.config.managedApps) { app in
                        appRow(app)
                    }
                }
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
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

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Text(app.stackPreset.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                        if app.runOnStartup {
                            Text("· Startup/Cron")
                                .font(.system(size: 11, weight: .medium))
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

            HStack(spacing: 22) {
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

                    if let pubURL = tunnel.publicURL, tunnel.isRunning {
                        Text(tunnel.mode == .apiManaged ? "Cloudflare API:" : "Public URL:")
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
                        Button(copiedTunnelAppID == app.id ? "Copied" : "Copy URL") {
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
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    } else if tunnel.isStarting {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tunnel.isRunning
                    ? (palette.isLight ? Color(red: 0.91, green: 0.98, blue: 0.94) : Color(red: 0.06, green: 0.16, blue: 0.13))
                    : palette.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    tunnel.isRunning ? palette.successText.opacity(0.38) : palette.subtleBorder
                ))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(state.isDeploying ? "Deploying..." : "Clone & Deploy") {
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

                    Button("Expose via NGINX") {
                        Task { await controller.exposeManagedAppViaNginx(app) }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

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
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)

                    Button("Edit") {
                        editingApp = app
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Remove") {
                        controller.deleteManagedApp(app)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
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
        .padding(14)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func miniMetric(_ title: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color ?? palette.primaryText)
                .lineLimit(1)
        }
    }
}
