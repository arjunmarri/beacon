import SwiftUI

struct ContentView: View {
    @Bindable var controller: BeaconController

    private let obsidianCanvas = Color(red: 0.043, green: 0.051, blue: 0.063)

    var body: some View {
        VStack(spacing: 0) {
            // Minimalist top bar
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    Text("BeaconMac")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("macOS Native · Multi-App Deploy & Watchdog")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(controller.update.status == .checking ? "Checking…" : "Check Updates") {
                    Task { await controller.checkForUpdates(userInitiated: true) }
                }
                .disabled(controller.update.status == .checking || controller.update.status == .downloading || controller.update.status == .installing)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Audit Tools") {
                    Task { await controller.auditSystemDependencies() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Check All") {
                    Task { await controller.refreshAllServices() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(obsidianCanvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = controller.bannerError {
                        HStack {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.95))
                            Spacer()
                            Button("Dismiss") { controller.bannerError = nil }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let release = controller.update.latestRelease,
                       (controller.update.status == .updateAvailable || controller.update.status == .downloading || controller.update.status == .installing || controller.update.status == .readyToRelaunch) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("BeaconMac v\(release.version) Available (installed: v\(controller.update.currentVersion))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(controller.update.statusMessage)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            Spacer()
                            Button("Release Notes") {
                                controller.openLatestReleasePage()
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())

                            Button(controller.update.status == .downloading || controller.update.status == .installing ? "Updating…" : "Update & Relaunch") {
                                Task { await controller.installAvailableUpdate() }
                            }
                            .disabled(controller.update.status == .downloading || controller.update.status == .installing || controller.update.status == .readyToRelaunch)
                            .buttonStyle(BeaconPrimaryButtonStyle())
                        }
                        .padding(14)
                        .background(Color(red: 0.07, green: 0.19, blue: 0.15))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.38)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !controller.scriptsInstalled {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("One-Time macOS App Sandbox Script Setup Required")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Install BeaconMac's 7 helper scripts into \(EmbeddedScripts.targetScriptsDirectoryURL().lastPathComponent) to enable Clone & Deploy, Check Deps, Restart, and launchd.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            Spacer()
                            Button("Copy Terminal Cmd") {
                                controller.copyInstallScriptsCommand()
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())

                            Button("Install Hook Scripts") {
                                Task { await controller.installHookScriptsFromApp() }
                            }
                            .buttonStyle(BeaconPrimaryButtonStyle())
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.16, blue: 0.24))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    MultiAppSectionView(controller: controller)
                    ServiceCardsView(controller: controller)
                    TerminalPanelView(controller: controller)
                    StartupScheduleView(controller: controller)
                    ServerLogSearchView(controller: controller)
                    ActivityLogView(controller: controller)
                    ConfigurationView(controller: controller)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("Designed by")
                            .foregroundStyle(.secondary)
                        Link("SoroAI", destination: URL(string: "https://soroai.com")!)
                            .foregroundStyle(.cyan)
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .background(obsidianCanvas)
        }
        .background(obsidianCanvas)
    }
}
