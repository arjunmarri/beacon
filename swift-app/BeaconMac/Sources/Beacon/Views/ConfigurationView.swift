import SwiftUI

struct ConfigurationView: View {
    @Bindable var controller: BeaconController

    @State private var ollamaEndpoint: String = "http://127.0.0.1:11434"
    @State private var gitPollIntervalText: String = "60"
    @State private var maxRestartsText: String = "10"
    @State private var recipientEmail: String = ""
    @State private var notifyOnCrash: Bool = true
    @State private var notifyOnDeploy: Bool = true
    @State private var notifyOnOllamaDown: Bool = true
    @State private var autoCheckForUpdates: Bool = true
    @State private var autoInstallUpdates: Bool = false
    @State private var expanded: Bool = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let inputBackground = Color(red: 0.043, green: 0.051, blue: 0.063)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Settings & Alerts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Persisted to flat file \(controller.flatFileStore.configFileURL.lastPathComponent) · Secrets stored in macOS Keychain")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(expanded ? "Hide Settings" : "Edit Settings") {
                    if !expanded { syncFromController() }
                    expanded.toggle()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                Divider().overlay(Color.white.opacity(0.08))

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        fieldLabel("Ollama Loopback Endpoint")
                        TextField("http://127.0.0.1:11434", text: $ollamaEndpoint)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Git Auto-Deploy Poll (sec)")
                        TextField("60", text: $gitPollIntervalText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Max Auto-Restarts / App")
                        TextField("10", text: $maxRestartsText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Alert Email Recipient")
                        HStack(spacing: 8) {
                            TextField("ops@example.com", text: $recipientEmail)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button("Test Alert") {
                                Task { await controller.sendTestAlert() }
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }
                }

                HStack {
                    Toggle("Alert on crash", isOn: $notifyOnCrash)
                    Toggle("Alert on deploy", isOn: $notifyOnDeploy)
                    Toggle("Alert on Ollama offline", isOn: $notifyOnOllamaDown)
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Self-Updates (v\(controller.update.currentVersion) · build \(controller.update.currentBuild))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(controller.update.statusMessage)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(controller.update.status == .checking ? "Checking…" : "Check Now") {
                            Task { await controller.checkForUpdates(userInitiated: true) }
                        }
                        .disabled(controller.update.status == .checking || controller.update.status == .downloading || controller.update.status == .installing)
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        if controller.update.status == .updateAvailable, let release = controller.update.latestRelease {
                            Button("Install v\(release.version)") {
                                Task { await controller.installAvailableUpdate() }
                            }
                            .buttonStyle(BeaconPrimaryButtonStyle())
                        }
                    }

                    HStack(spacing: 16) {
                        Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                            .onChange(of: autoCheckForUpdates) { _, newVal in
                                controller.updateAutoUpdatePreferences(autoCheck: newVal, autoInstall: autoInstallUpdates)
                            }

                        Toggle("Automatically download & install DMG updates", isOn: $autoInstallUpdates)
                            .onChange(of: autoInstallUpdates) { _, newVal in
                                controller.updateAutoUpdatePreferences(autoCheck: autoCheckForUpdates, autoInstall: newVal)
                            }
                        Spacer()
                        Button("Save Configuration") {
                            let poll = Int(gitPollIntervalText) ?? controller.config.gitPollIntervalSec
                            let maxR = Int(maxRestartsText) ?? controller.config.maxRestarts
                            Task {
                                await controller.saveGlobalConfiguration(
                                    ollamaEndpoint: ollamaEndpoint,
                                    gitPollIntervalSec: poll,
                                    maxRestarts: maxR,
                                    recipientEmail: recipientEmail,
                                    notifyOnCrash: notifyOnCrash,
                                    notifyOnDeploy: notifyOnDeploy,
                                    notifyOnOllamaDown: notifyOnOllamaDown,
                                    autoCheckForUpdates: autoCheckForUpdates,
                                    autoInstallUpdates: autoInstallUpdates
                                )
                                expanded = false
                            }
                        }
                        .buttonStyle(BeaconPrimaryButtonStyle())
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func syncFromController() {
        ollamaEndpoint = controller.config.ollamaEndpoint
        gitPollIntervalText = "\(controller.config.gitPollIntervalSec)"
        maxRestartsText = "\(controller.config.maxRestarts)"
        recipientEmail = controller.config.recipientEmail
        notifyOnCrash = controller.config.notifyOnCrash
        notifyOnDeploy = controller.config.notifyOnDeploy
        notifyOnOllamaDown = controller.config.notifyOnOllamaDown
        autoCheckForUpdates = controller.config.autoCheckForUpdates
        autoInstallUpdates = controller.config.autoInstallUpdates
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 175, alignment: .leading)
    }
}
