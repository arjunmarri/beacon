import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }

    private var aggregateStatusText: String {
        switch controller.aggregateLight {
        case .green: return "Nominal"
        case .amber: return "Attention"
        case .red: return "Issue"
        }
    }

    var body: some View {
        ZStack {
            BeaconAmbientCanvas(interactive: false)
                .opacity(palette.isLight ? 0.45 : 0.36)
            Rectangle()
                .fill(palette.menuMaterial)
            Rectangle()
                .fill(palette.sidebarFill)
            Rectangle()
                .fill(palette.glassTopSheen)

            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 9) {
                    BeaconBrandMarkView(size: 26, cornerRadius: 7.5)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("BeaconMac")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                        Text("v1.1.0 · Local Watchdog")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer()

                    TrafficLightLampView(
                        active: controller.aggregateLight,
                        label: aggregateStatusText
                    )
                }
                .padding(.horizontal, 4)

                // Managed Apps Section
                VStack(alignment: .leading, spacing: 6) {
                    if controller.config.managedApps.isEmpty {
                        Text("No local apps configured")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.secondaryText)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(controller.config.managedApps) { app in
                            let state = controller.runtimeState(for: app.id)
                            statusRow(name: app.name, light: state.light, detail: state.statusLabel)
                        }
                    }
                }
                .padding(10)
                .background(palette.row.opacity(palette.isLight ? 0.65 : 0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                // Services Section
                VStack(alignment: .leading, spacing: 6) {
                    statusRow(name: "launchd Daemon", light: controller.launchd.light, detail: controller.launchd.statusLabel)
                    statusRow(name: "Cloudflare Tunnels", light: controller.cloudflareTunnel.light, detail: controller.cloudflareTunnel.statusLabel)
                    statusRow(
                        name: "Prevent Mac Sleep",
                        light: controller.launchd.sleepAssertionActive ? .green : .amber,
                        detail: controller.launchd.sleepAssertionActive ? "Awake (IOKit)" : "Off"
                    )
                    statusRow(name: "GitHub Account", light: controller.git.light, detail: controller.git.statusLabel)
                    statusRow(name: "Local LLM (Ollama)", light: controller.ollama.light, detail: controller.ollama.statusLabel)
                }
                .padding(10)
                .background(palette.row.opacity(palette.isLight ? 0.65 : 0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                // Tunnel Quick Actions
                VStack(alignment: .leading, spacing: 2) {
                    let ollamaTunnelLive = controller.ollamaCloudflareTunnel?.isRunning == true
                    MenuBarGlassActionRow(
                        title: ollamaTunnelLive ? "Stop Ollama Cloudflare Tunnel" : "Expose Ollama via Cloudflare",
                        systemImage: ollamaTunnelLive ? "stop.circle" : "globe"
                    ) {
                        Task { await controller.toggleOllamaCloudflareTunnel() }
                    }

                    let liveTunnels = controller.cloudflareTunnel.activeTunnels.filter { $0.isRunning && $0.publicURL != nil }
                    if !liveTunnels.isEmpty {
                        ForEach(liveTunnels) { tunnel in
                            if let pubURL = tunnel.publicURL {
                                MenuBarGlassActionRow(
                                    title: "Copy \(tunnel.label) Public URL",
                                    systemImage: "doc.on.doc"
                                ) {
                                    controller.copyTunnelURL(pubURL)
                                }
                            }
                        }
                        MenuBarGlassActionRow(
                            title: "Stop All Cloudflare Tunnels",
                            systemImage: "xmark.circle",
                            isDestructive: true
                        ) {
                            Task { await controller.stopAllCloudflareTunnels() }
                        }
                    }
                }

                Divider().overlay(palette.subtleBorder)

                // System & App Actions
                VStack(alignment: .leading, spacing: 2) {
                    MenuBarGlassActionRow(
                        title: controller.config.appearanceMode == .light ? "Switch to Dark Theme" : "Switch to Light Theme",
                        systemImage: controller.config.appearanceMode == .light ? "moon.stars.fill" : "sun.max.fill"
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            controller.toggleAppearanceMode()
                        }
                    }

                    MenuBarGlassActionRow(
                        title: controller.config.startupSchedule.preventSleep ? "Allow Mac Sleep" : "Prevent Mac Sleep (IOKit)",
                        systemImage: controller.config.startupSchedule.preventSleep ? "moon.zzz" : "bolt.fill"
                    ) {
                        controller.togglePreventSleep(!controller.config.startupSchedule.preventSleep)
                    }

                    MenuBarGlassActionRow(
                        title: "Watch Live Logs (tail -f)",
                        systemImage: "terminal"
                    ) {
                        controller.watchSupervisorLiveLogs()
                    }

                    MenuBarGlassActionRow(
                        title: controller.launchd.isLoaded ? "Stop launchd Daemon" : "Start launchd Daemon",
                        systemImage: controller.launchd.isLoaded ? "pause.circle" : "play.circle"
                    ) {
                        Task {
                            if controller.launchd.isLoaded {
                                await controller.unloadLaunchdAgent()
                            } else {
                                await controller.installAndLoadLaunchdAgent()
                            }
                        }
                    }

                    MenuBarGlassActionRow(
                        title: "Install Dependencies…",
                        systemImage: "arrow.down.circle"
                    ) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        controller.openDependencyInstaller()
                    }

                    MenuBarGlassActionRow(
                        title: "Check All Services",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task { await controller.refreshAllServices() }
                    }
                }

                Divider().overlay(palette.subtleBorder)

                MenuBarGlassActionRow(
                    title: "Quit BeaconMac",
                    systemImage: "power",
                    shortcut: "⌘Q",
                    isDestructive: true
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(14)
        }
        .frame(width: 304)
    }

    private func statusRow(name: String, light: TrafficLightColor, detail: String) -> some View {
        let dotColor: Color = {
            switch light {
            case .green: return palette.successText
            case .amber: return palette.warningText
            case .red: return palette.errorText
            }
        }()

        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7.5, height: 7.5)
                .shadow(color: dotColor.opacity(0.6), radius: 3)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
        }
    }
}

private struct MenuBarGlassActionRow: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)

        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isHovered ? (isDestructive ? Color.white : palette.accentInk) : (isDestructive ? palette.errorText : palette.sectionHeader))
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? (isDestructive ? Color.white : palette.accentInk) : (isDestructive ? palette.errorText : palette.primaryText))
                    .lineLimit(1)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(isHovered ? (isDestructive ? Color.white.opacity(0.85) : palette.accentInk.opacity(0.85)) : palette.secondaryText)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    if isDestructive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.84, green: 0.18, blue: 0.24))
                            .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.accentGradient)
                            .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
