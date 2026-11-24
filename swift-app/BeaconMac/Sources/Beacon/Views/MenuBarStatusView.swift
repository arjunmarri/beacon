import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var controller: BeaconController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BeaconMac Monitor")
                .font(.headline)

            Divider()

            if controller.config.managedApps.isEmpty {
                Text("No local apps configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.config.managedApps) { app in
                    let state = controller.runtimeState(for: app.id)
                    statusRow(name: app.name, light: state.light, detail: state.statusLabel)
                }
            }

            Divider()

            statusRow(name: "launchd Daemon", light: controller.launchd.light, detail: controller.launchd.statusLabel)
            statusRow(
                name: "Prevent Mac Sleep",
                light: controller.launchd.sleepAssertionActive ? .green : .amber,
                detail: controller.launchd.sleepAssertionActive ? "Awake (IOKit)" : "Off"
            )
            statusRow(name: "GitHub Account", light: controller.git.light, detail: controller.git.statusLabel)
            statusRow(name: "Local LLM (Ollama)", light: controller.ollama.light, detail: controller.ollama.statusLabel)
            statusRow(name: "Claude API", light: controller.claude.light, detail: controller.claude.statusLabel)

            Divider()

            Button(controller.config.startupSchedule.preventSleep ? "Allow Mac Sleep" : "Prevent Mac Sleep (IOKit)") {
                controller.togglePreventSleep(!controller.config.startupSchedule.preventSleep)
            }

            Button("Watch Live Logs (tail -f)") {
                controller.watchSupervisorLiveLogs()
            }

            Button(controller.launchd.isLoaded ? "Stop launchd Daemon" : "Start launchd Daemon") {
                Task {
                    if controller.launchd.isLoaded {
                        await controller.unloadLaunchdAgent()
                    } else {
                        await controller.installAndLoadLaunchdAgent()
                    }
                }
            }

            Button("Install Dependencies…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                controller.openDependencyInstaller()
            }

            Button("Check All Services") {
                Task { await controller.refreshAllServices() }
            }

            if controller.update.status == .updateAvailable, let release = controller.update.latestRelease {
                Button("Update to v\(release.version)…") {
                    Task { await controller.installAvailableUpdate() }
                }
            } else {
                Button("Check for Updates…") {
                    Task { await controller.checkForUpdates(userInitiated: true) }
                }
            }

            Divider()

            Button("Quit BeaconMac") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 270)
    }

    private func statusRow(name: String, light: TrafficLightColor, detail: String) -> some View {
        HStack {
            Circle()
                .fill(light == .green ? Color.green : (light == .amber ? Color.orange : Color.red))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
