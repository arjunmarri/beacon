import SwiftUI

struct MultiAppSectionView: View {
    @Bindable var controller: BeaconController

    @State private var showingAddSheet = false
    @State private var editingApp: ManagedApp?

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let rowBackground = Color(red: 0.048, green: 0.056, blue: 0.070)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Managed Local Apps (\(controller.config.managedApps.count))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Clone remote Git repos, check required Vite/Node libraries, build, deploy locally, and monitor multiple apps simultaneously.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check System Tools") {
                    Task { await controller.auditSystemDependencies() }
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
                        .foregroundStyle(.secondary)
                    ForEach(visibleTools) { tool in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tool.available ? Color.green : Color.orange.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text("\(tool.name) \(tool.available ? tool.detail : "missing")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(tool.available ? .white.opacity(0.82) : .secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(rowBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if controller.config.managedApps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No local apps configured yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Add any locally deployed Vite, Node.js, or custom app with its remote Git repository URL, local folder, and localhost port. BeaconMac will clone it, check & install required dependencies, build it, and monitor its health.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Add Your First Local App") {
                        showingAddSheet = true
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
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
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingAddSheet) {
            AppEditorSheet(controller: controller, existingApp: nil)
        }
        .sheet(item: $editingApp) { app in
            AppEditorSheet(controller: controller, existingApp: app)
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
                            .foregroundStyle(.white)
                        Text(app.stackPreset.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if app.runOnStartup {
                            Text("· Startup/Cron")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                    }

                    Text("\(app.monitorURL)  ·  \(app.repoURL.isEmpty ? "Local only" : "\(app.repoURL) (\(app.branch))")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                TrafficLightLampView(active: state.light, label: state.statusLabel)
            }

            HStack(spacing: 22) {
                miniMetric(
                    "HTTP Probe",
                    state.isHealthy
                        ? "\(state.httpStatus ?? 200) · \(state.responseTimeMs ?? 1) ms"
                        : "Unreachable",
                    color: state.isHealthy ? .green : .red
                )
                miniMetric("Commit", state.commitHash)
                miniMetric("Dependencies", state.dependencySummary)
                miniMetric("Restarts", "\(state.restartCount)")
                Spacer()
            }

            if let err = state.lastError, !state.isHealthy {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.88))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(state.isDeploying ? "Deploying..." : "Clone & Deploy") {
                    Task { await controller.cloneBuildAndDeploy(app: app, trigger: "manual") }
                }
                .disabled(state.isDeploying || controller.busyAction != nil)
                .buttonStyle(BeaconPrimaryButtonStyle())

                Button("Check Deps") {
                    Task { await controller.checkDependencies(for: app) }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Restart") {
                    Task { await controller.restartManagedApp(app, reason: "manual") }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Stop") {
                    Task { await controller.stopManagedApp(app) }
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

                Toggle("Startup", isOn: Binding(
                    get: { app.runOnStartup },
                    set: { _ in controller.toggleAppStartup(app) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Button("Edit") {
                    editingApp = app
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Remove") {
                    controller.deleteManagedApp(app)
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(rowBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func miniMetric(_ title: String, _ value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}
