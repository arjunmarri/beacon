import SwiftUI

struct ContentView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }
    private var activeScheme: ColorScheme { controller.config.appearanceMode == .light ? .light : .dark }

    var body: some View {
        VStack(spacing: 0) {
            // Minimalist top bar
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text("BeaconMac")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.sectionHeader)
                    Text("macOS Native · Multi-App Deploy & Watchdog")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                // Real-time White / Dark Theme Switcher
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        controller.toggleAppearanceMode()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: controller.config.appearanceMode == .light ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(controller.config.appearanceMode == .light ? "Dark Theme" : "White Theme")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.sectionHeader)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.activeChipFill)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.sectionAccentBar.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Switch between White (Light) and Dark theme in real time")

                Button("Install Dependencies") {
                    controller.openDependencyInstaller()
                }
                .disabled(controller.busyAction != nil)
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
            .background(palette.topBar)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = controller.bannerError {
                        HStack {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.errorText)
                            Spacer()
                            Button("Dismiss") { controller.bannerError = nil }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.primaryText.opacity(0.8))
                        }
                        .padding(12)
                        .background(Color.red.opacity(palette.isLight ? 0.08 : 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if !controller.scriptsInstalled {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("One-Time macOS App Sandbox Script Setup Required")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                Text("Install BeaconMac's \(EmbeddedScripts.requiredScriptNames.count) helper scripts into \(EmbeddedScripts.targetScriptsDirectoryURL().lastPathComponent) to enable Clone & Deploy, Built-In Node.js Server, NGINX Reverse Proxy, 1-Click Cloudflare Tunnels, Check Deps, Restart, and launchd.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.bodyText)
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
                        .background(palette.isLight ? Color(red: 0.92, green: 0.96, blue: 1.0) : Color(red: 0.08, green: 0.16, blue: 0.24))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.sectionAccentBar.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    MultiAppSectionView(controller: controller)
                    BuiltInNodeServerView(controller: controller)
                    NginxReverseProxyView(controller: controller)
                    NginxHealthMonitorView(controller: controller)
                    CloudflareTunnelSectionView(controller: controller)
                    ServiceCardsView(controller: controller)
                    TerminalPanelView(controller: controller)
                    StartupScheduleView(controller: controller)
                    ServerLogSearchView(controller: controller)
                    ActivityLogView(controller: controller)
                    ConfigurationView(controller: controller)

                    HStack(spacing: 6) {
                        Spacer()
                        Text("Designed by")
                            .foregroundStyle(palette.secondaryText)
                        Link("SoroAI", destination: URL(string: "https://soroai.com")!)
                            .foregroundStyle(palette.accentLink)
                        Text("·")
                            .foregroundStyle(palette.secondaryText)
                        Text("Local-first privacy · No telemetry or third-party log sharing")
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .background(palette.canvas)
        }
        .background(palette.canvas)
        .sheet(isPresented: $controller.showingDependencyInstaller) {
            PrerequisiteInstallerSheet(
                controller: controller,
                selectedAppID: controller.dependencyInstallerAppID
            )
            .preferredColorScheme(activeScheme)
        }
    }
}
