import SwiftUI

struct StartupScheduleView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var cronExpression: String = "@reboot"
    @State private var autoDeployOnStartup: Bool = false
    @State private var cronEnabled: Bool = false
    @State private var showLegacyCron: Bool = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(
                        title: "macOS launchd Daemon, Live Logs & Sleep Prevention",
                        fontSize: 16,
                        systemImage: "cpu"
                    )
                    Text("Native Apple launchd background supervision (~/Library/LaunchAgents), IOKit + caffeinate -s keep-awake, and persistent ~/beaconmac/server.log.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                TrafficLightLampView(active: controller.launchd.light, label: controller.launchd.statusLabel)
            }

            Divider().overlay(palette.subtleBorder)

            // Native macOS ecosystem toggles
            HStack(spacing: 24) {
                Toggle("Launch BeaconMac at Login", isOn: Binding(
                    get: { controller.config.startupSchedule.launchAtLogin },
                    set: { controller.toggleLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

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
                .controlSize(.small)

                Toggle("Pull & Rebuild on Boot", isOn: $autoDeployOnStartup)
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
            .foregroundStyle(palette.bodyText)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .beaconGlassWell(cornerRadius: 11)

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
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("macOS Native Commands (\(controller.config.managedApps.filter(\.runOnStartup).count) startup app(s) configured)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if controller.launchd.sleepAssertionActive || controller.launchd.caffeinateActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette.successText)
                                .frame(width: 6, height: 6)
                            Text("Awake protection active — local servers remain reachable while display is off")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.successText)
                        }
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("@reboot", text: $cronExpression)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 170)
                            .beaconGlassInput(cornerRadius: 8, horizontalPadding: 10, verticalPadding: 6)

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
                        .foregroundStyle(palette.secondaryText)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .beaconGlassWell(cornerRadius: 9)
                }
                .padding(.top, 8)
            } label: {
                Text("Optional Legacy crontab Schedule (if preferred over launchd)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 165, alignment: .leading)

            Text(command)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.bodyText)
                .textSelection(.enabled)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionLabel, action: action)
                .buttonStyle(BeaconSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7.5)
        .beaconGlassWell(cornerRadius: 10)
    }
}
