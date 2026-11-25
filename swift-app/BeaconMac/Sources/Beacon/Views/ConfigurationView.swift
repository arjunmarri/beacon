import SwiftUI

struct ConfigurationView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var ollamaEndpoint: String = "http://127.0.0.1:11434"
    @State private var gitPollIntervalText: String = "60"
    @State private var maxRestartsText: String = "10"
    @State private var notifyOnCrash: Bool = true
    @State private var notifyOnDeploy: Bool = true
    @State private var notifyOnOllamaDown: Bool = true
    @State private var expanded: Bool = true
    @State private var showingPrivacyPolicy: Bool = false

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(
                        title: "Global Settings & Theme",
                        fontSize: 16,
                        systemImage: "slider.horizontal.3"
                    )
                    Text("Persisted to \(controller.flatFileStore.configFileURL.lastPathComponent) · GitHub token encrypted in macOS Keychain")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button(expanded ? "Hide Settings" : "Edit Settings") {
                    if !expanded { syncFromController() }
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                Divider().overlay(palette.subtleBorder)

                // MARK: - Appearance / Theme Switcher
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Liquid Glass Theme (Real-Time)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(palette.sectionHeader)
                        Text("Switch instantly between Light Liquid Glass (default) and Dark Liquid Glass.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer()

                    Picker("Theme", selection: Binding(
                        get: { controller.config.appearanceMode },
                        set: { nextMode in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                controller.setAppearanceMode(nextMode)
                            }
                        }
                    )) {
                        ForEach(BeaconAppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .beaconGlassRow(cornerRadius: 12, padding: 14)

                // MARK: - General Monitoring & Alerts
                VStack(alignment: .leading, spacing: 14) {
                    Text("Monitoring, Alerts & Polling")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            fieldLabel("Ollama Loopback Endpoint")
                            TextField("http://127.0.0.1:11434", text: $ollamaEndpoint)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(palette.primaryText)
                                .beaconGlassInput(cornerRadius: 8.5, horizontalPadding: 10, verticalPadding: 7)
                        }

                        GridRow {
                            fieldLabel("Git Auto-Deploy Poll (sec)")
                            TextField("60", text: $gitPollIntervalText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(palette.primaryText)
                                .frame(width: 120)
                                .beaconGlassInput(cornerRadius: 8.5, horizontalPadding: 10, verticalPadding: 7)
                        }

                        GridRow {
                            fieldLabel("Max Auto-Restarts / App")
                            TextField("10", text: $maxRestartsText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(palette.primaryText)
                                .frame(width: 120)
                                .beaconGlassInput(cornerRadius: 8.5, horizontalPadding: 10, verticalPadding: 7)
                        }
                    }

                    Divider().overlay(palette.subtleBorder)

                    HStack(spacing: 18) {
                        Toggle("Alert on crash", isOn: $notifyOnCrash)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("Alert on deploy", isOn: $notifyOnDeploy)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("Alert on Ollama offline", isOn: $notifyOnOllamaDown)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer()
                        Button("Test Notification") {
                            Task { await controller.sendTestAlert() }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        Button("Save Configuration") {
                            let poll = Int(gitPollIntervalText) ?? controller.config.gitPollIntervalSec
                            let maxR = Int(maxRestartsText) ?? controller.config.maxRestarts
                            Task {
                                await controller.saveGlobalConfiguration(
                                    ollamaEndpoint: ollamaEndpoint,
                                    gitPollIntervalSec: poll,
                                    maxRestarts: maxR,
                                    notifyOnCrash: notifyOnCrash,
                                    notifyOnDeploy: notifyOnDeploy,
                                    notifyOnOllamaDown: notifyOnOllamaDown
                                )
                            }
                        }
                        .buttonStyle(BeaconPrimaryButtonStyle())
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(palette.bodyText)
                }
                .beaconGlassRow(cornerRadius: 12, padding: 15)

                // MARK: - Privacy & Data Handling Placeholder
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & Data Handling")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                    Text("BeaconMac stores all configuration and logs locally on your Mac (`~/Library/Application Support/Beacon/`) and encrypts credentials in macOS Keychain. Zero analytics, zero tracking (`NSPrivacyTracking = false`), and no local logs are transmitted to third-party AI services.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
                    HStack(spacing: 8) {
                        Text("Privacy Policy URL (Placeholder):")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        Text((Bundle.main.object(forInfoDictionaryKey: "BeaconPrivacyPolicyURL") as? String) ?? "https://example.com/beaconmac/privacy")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.accentLink)
                            .textSelection(.enabled)
                        Spacer()
                        Button("View Privacy Policy") {
                            showingPrivacyPolicy = true
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .beaconGlassRow(cornerRadius: 12, padding: 14)
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
        .onAppear {
            syncFromController()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicySheet()
                .preferredColorScheme(controller.config.appearanceMode == .light ? .light : .dark)
        }
    }

    private func syncFromController() {
        ollamaEndpoint = controller.config.ollamaEndpoint
        gitPollIntervalText = "\(controller.config.gitPollIntervalSec)"
        maxRestartsText = "\(controller.config.maxRestarts)"
        notifyOnCrash = controller.config.notifyOnCrash
        notifyOnDeploy = controller.config.notifyOnDeploy
        notifyOnOllamaDown = controller.config.notifyOnOllamaDown
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.secondaryText)
            .frame(width: 180, alignment: .leading)
    }
}
