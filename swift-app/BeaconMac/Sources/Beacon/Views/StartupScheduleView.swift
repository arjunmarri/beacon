import SwiftUI

struct StartupScheduleView: View {
    @Bindable var controller: BeaconController

    @State private var cronExpression: String = "@reboot"
    @State private var autoDeployOnStartup: Bool = false
    @State private var cronEnabled: Bool = false
    @State private var showLegacyCron: Bool = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let inputBackground = Color(red: 0.043, green: 0.051, blue: 0.063)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS launchd Daemon, Live Logs & Sleep Prevention")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Native Apple launchd background supervision (~/Library/LaunchAgents), IOKit + caffeinate -s keep-awake, and persistent ~/beaconmac/server.log.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TrafficLightLampView(active: controller.launchd.light, label: controller.launchd.statusLabel)
            }

            Divider().overlay(Color.white.opacity(0.08))

            // Native macOS ecosystem toggles
            HStack(spacing: 22) {
                Toggle("Launch BeaconMac at Login", isOn: Binding(
                    get: { controller.config.startupSchedule.launchAtLogin },
                    set: { controller.toggleLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)

                Toggle(
                    controller.launchd.sleepAssertionActive
                        ? "Prevent Mac Sleep (IOKit Active)"
                        : "Prevent Mac Sleep (IOKit + caffeinate -s)",
                    isOn: Binding(
                        get: { controller.config.startupSchedule.preventSleep },
                        set: { controller.togglePreventSleep($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle("Pull & Rebuild on Boot", isOn: $autoDeployOnStartup)
                    .toggleStyle(.switch)
                    .onChange(of: autoDeployOnStartup) { _, next in
                        controller.updateStartupSchedule(
                            autoDeploy: next,
                            cronEnabled: cronEnabled,
                            cronExpression: cronExpression
                        )
                    }

                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.88))

            // Primary launchd, live logs, and Energy Settings actions
            HStack(spacing: 8) {
                Button(controller.launchd.isLoaded ? "Reload launchd Agent" : "Install & Start launchd") {
                    Task { await controller.installAndLoadLaunchdAgent() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconPrimaryButtonStyle())

                Button("Stop Service (launchctl unload)") {
                    Task { await controller.unloadLaunchdAgent() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Watch Live Logs") {
                    controller.watchSupervisorLiveLogs()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Energy Settings") {
                    controller.openEnergySettings()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Export .plist") {
                    controller.exportLaunchAgentPlist()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Refresh Status") {
                    Task { await controller.refreshLaunchdStatus() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Spacer()
            }

            // macOS Ecosystem CLI Quick-Reference (exact 1-click copyable commands)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("macOS Native Commands (\(controller.config.managedApps.filter(\.runOnStartup).count) startup app(s) configured)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if controller.launchd.sleepAssertionActive || controller.launchd.caffeinateActive {
                        Text("Awake protection active — local servers remain reachable while display is off")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.9))
                    }
                }

                commandRow(
                    step: "1. Watch live logs",
                    command: controller.startupService.tailServerLogCommand,
                    actionLabel: "Watch"
                ) {
                    controller.watchSupervisorLiveLogs()
                }

                commandRow(
                    step: "2. Stop background service",
                    command: controller.startupService.launchctlUnloadCommand,
                    actionLabel: "Copy"
                ) {
                    controller.copyLaunchctlUnloadCommand()
                }

                commandRow(
                    step: "3. Prevent Mac sleeping",
                    command: "\(controller.startupService.caffeinateCommand)   # or System Settings > Energy / Displays",
                    actionLabel: "Copy"
                ) {
                    controller.copyCaffeinateCommand()
                }
            }

            // Optional collapsible legacy cron schedule
            DisclosureGroup(isExpanded: $showLegacyCron) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("@reboot", text: $cronExpression)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 170)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Button("Save Schedule") {
                            cronEnabled = true
                            controller.updateStartupSchedule(
                                autoDeploy: autoDeployOnStartup,
                                cronEnabled: true,
                                cronExpression: cronExpression
                            )
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        Button("Copy crontab Command") {
                            controller.copyCrontabInstallCommand()
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }

                    Text(controller.startupService.buildCrontabLine(cronExpression: cronExpression))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(inputBackground)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08)))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .padding(.top, 8)
            } label: {
                Text("Optional Legacy crontab Schedule (if preferred over launchd)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            cronExpression = controller.config.startupSchedule.cronExpression
            autoDeployOnStartup = controller.config.startupSchedule.autoDeployOnStartup
            cronEnabled = controller.config.startupSchedule.cronEnabled
        }
    }

    private func commandRow(
        step: String,
        command: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(step)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 165, alignment: .leading)

            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .textSelection(.enabled)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionLabel, action: action)
                .buttonStyle(BeaconSecondaryButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(inputBackground)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
