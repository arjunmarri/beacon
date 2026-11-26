import SwiftUI

enum BeaconDestination: String, CaseIterable, Identifiable {
    case overview
    case apps
    case tunnels
    case system
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .apps: return "Apps & Node Host"
        case .tunnels: return "Tunnels & AI"
        case .system: return "System & launchd"
        case .logs: return "Logs & Terminal"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Live local apps, built-in hosting, tunnels, and developer services"
        case .apps: return "Git clone, build, multi-app watchdog, and built-in loopback Node.js server"
        case .tunnels: return "1-click Cloudflare Quick Tunnels, GitHub Keychain sync, and local Ollama LLM"
        case .system: return "Native Apple launchd background supervision and IOKit sleep prevention"
        case .logs: return "Integrated terminal stream, grep/regex server log search, and activity log"
        case .settings: return "Real-time theme, polling intervals, local notifications, and privacy policy"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .apps: return "shippingbox"
        case .tunnels: return "globe"
        case .system: return "cpu"
        case .logs: return "terminal"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var navNamespace

    @State private var selectedDestination: BeaconDestination = .overview
    @State private var hoveredDestination: BeaconDestination?
    @State private var showingPrivacyPolicy: Bool = false

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }
    private var activeScheme: ColorScheme { controller.config.appearanceMode == .light ? .light : .dark }

    private var healthyAppsCount: Int {
        controller.config.managedApps.filter { controller.runtimeState(for: $0.id).isHealthy }.count
    }

    var body: some View {
        ZStack {
            BeaconAmbientCanvas()

            HStack(spacing: 0) {
                glassSidebar
                    .padding(.leading, 12)
                    .padding(.top, 36)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    glassTopBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            alertBanners

                            destinationContent
                                .id(selectedDestination)
                                .transition(.opacity.combined(with: .offset(y: 6)))

                            footerBar
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                    }
                    .animation(.spring(response: 0.30, dampingFraction: 0.86), value: selectedDestination)
                }
            }
        }
        .sheet(isPresented: $controller.showingDependencyInstaller) {
            PrerequisiteInstallerSheet(
                controller: controller,
                selectedAppID: controller.dependencyInstallerAppID
            )
            .preferredColorScheme(activeScheme)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicySheet()
                .preferredColorScheme(activeScheme)
        }
    }

    // MARK: - Transparent Floating Liquid Glass Sidebar Menu

    private var glassSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Brand Lockup
            HStack(spacing: 11) {
                BeaconBrandMarkView(size: 32, cornerRadius: 9.5)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BeaconMac")
                        .font(.system(size: 15.5, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(palette.primaryText)
                    Text("Local Deploy & Watchdog")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 14)

            // Navigation List
            VStack(spacing: 4) {
                ForEach(BeaconDestination.allCases) { item in
                    sidebarItem(item)
                }
            }
            .padding(.horizontal, 9)

            Spacer()

            // Live Aggregate Health & Theme Card at Bottom of Transparent Menu
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("System Health")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TrafficLightLampView(
                        active: controller.aggregateLight,
                        label: aggregateStatusText
                    )
                }

                Divider().overlay(palette.subtleBorder)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        controller.toggleAppearanceMode()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: controller.config.appearanceMode == .light ? "moon.stars.fill" : "sun.max.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.sectionHeader)
                        Text(controller.config.appearanceMode == .light ? "Switch to Dark" : "Switch to Light")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.menuItemSelected)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.sectionAccentBar.opacity(0.28), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Toggle between Light and Dark Liquid Glass themes in real time")
            }
            .padding(12)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.menuMaterial)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.sidebarFill)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 234)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.menuMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.sidebarFill)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.glassTopSheen)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: palette.cardShadow, radius: palette.isLight ? 16 : 22, x: 0, y: 6)
    }

    private var aggregateStatusText: String {
        switch controller.aggregateLight {
        case .green: return "Nominal"
        case .amber: return "Attention"
        case .red: return "Issue"
        }
    }

    private func sidebarBadge(for destination: BeaconDestination) -> (text: String, tint: Color)? {
        switch destination {
        case .apps:
            let total = controller.config.managedApps.count
            guard total > 0 else { return nil }
            return ("\(healthyAppsCount)/\(total)", healthyAppsCount == total ? palette.successText : palette.secondaryText)
        case .tunnels:
            let count = controller.cloudflareTunnel.activeCount
            guard count > 0 else { return nil }
            return ("\(count) live", palette.successText)
        case .system:
            if controller.launchd.isLoaded {
                return ("On", palette.successText)
            }
            return nil
        default:
            return nil
        }
    }

    private func sidebarItem(_ item: BeaconDestination) -> some View {
        let isSelected = selectedDestination == item
        let isHovered = hoveredDestination == item

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedDestination = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.sectionHeader : palette.secondaryText)
                    .frame(width: 18, alignment: .center)

                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.primaryText : palette.bodyText)
                    .lineLimit(1)

                Spacer()

                if let badge = sidebarBadge(for: item) {
                    Text(badge.text)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(badge.tint)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8.5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.menuItemSelected)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
                        )
                        .shadow(color: palette.cardShadow.opacity(0.6), radius: 5, y: 2)
                        .matchedGeometryEffect(id: "sidebar-selection", in: navNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.menuItemHover)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                hoveredDestination = hovering ? item : (hoveredDestination == item ? nil : hoveredDestination)
            }
        }
    }

    // MARK: - Translucent Liquid Glass Top Bar

    private var glassTopBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDestination.title)
                    .font(.system(size: 16.5, weight: .bold))
                    .tracking(-0.25)
                    .foregroundStyle(palette.primaryText)
                Text(selectedDestination.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if let busy = controller.busyAction {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(busy)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.chipFill)
                .clipShape(Capsule())
            }

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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.menuMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.topBar)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.glassTopSheen)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: palette.cardShadow, radius: palette.isLight ? 12 : 18, x: 0, y: 4)
    }

    // MARK: - Persistent Banners

    @ViewBuilder
    private var alertBanners: some View {
        if let error = controller.bannerError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.errorText)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.errorText)
                Spacer()
                Button("Dismiss") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        controller.bannerError = nil
                    }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
            .padding(14)
            .background(Color.red.opacity(palette.isLight ? 0.08 : 0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.32), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if !controller.scriptsInstalled {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.activeChipFill)
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("One-Time macOS App Sandbox Script Setup Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("Install BeaconMac's \(EmbeddedScripts.requiredScriptNames.count) helper scripts into \(EmbeddedScripts.targetScriptsDirectoryURL().lastPathComponent) to enable Clone & Deploy, Built-In Node.js Server, 1-Click Cloudflare Tunnels, Check Deps, Restart, and launchd.")
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
            .beaconGlassCard(cornerRadius: 14, padding: 15)
        }
    }

    // MARK: - Destination Viewport

    @ViewBuilder
    private var destinationContent: some View {
        switch selectedDestination {
        case .overview:
            VStack(alignment: .leading, spacing: 20) {
                overviewMetricStrip
                MultiAppSectionView(controller: controller)
                ServiceCardsView(controller: controller)
            }

        case .apps:
            VStack(alignment: .leading, spacing: 20) {
                MultiAppSectionView(controller: controller)
                BuiltInNodeServerView(controller: controller)
            }

        case .tunnels:
            VStack(alignment: .leading, spacing: 20) {
                CloudflareTunnelSectionView(controller: controller)
                ServiceCardsView(controller: controller)
            }

        case .system:
            VStack(alignment: .leading, spacing: 20) {
                StartupScheduleView(controller: controller)
            }

        case .logs:
            VStack(alignment: .leading, spacing: 20) {
                TerminalPanelView(controller: controller)
                ServerLogSearchView(controller: controller)
                ActivityLogView(controller: controller)
            }

        case .settings:
            VStack(alignment: .leading, spacing: 20) {
                ConfigurationView(controller: controller)
            }
        }
    }

    // MARK: - Executive Summary Metric Strip (Overview)

    private var overviewMetricStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            overviewTile(
                tag: "DEPLOY",
                title: "Managed Apps",
                value: "\(healthyAppsCount) / \(controller.config.managedApps.count)",
                detail: controller.config.managedApps.isEmpty ? "Ready to add first app" : "Healthy running locally",
                systemImage: "shippingbox",
                statusLight: controller.config.managedApps.isEmpty ? .amber : (healthyAppsCount == controller.config.managedApps.count ? .green : .amber),
                target: .apps
            )

            overviewTile(
                tag: "HOST",
                title: "Node.js Host",
                value: controller.builtInServer.isRunning ? ":\(controller.config.builtInServer.port)" : "Stopped",
                detail: "\(controller.config.builtInServer.mountedApps.count) mounted · \(controller.builtInServer.statusLabel)",
                systemImage: "server.rack",
                statusLight: controller.builtInServer.light,
                target: .apps
            )

            overviewTile(
                tag: "TUNNEL",
                title: "Cloudflare Tunnels",
                value: "\(controller.cloudflareTunnel.activeCount) Active",
                detail: controller.cloudflareTunnel.activeCount > 0 ? "Public HTTPS live" : "1-click Quick Tunnels",
                systemImage: "globe",
                statusLight: controller.cloudflareTunnel.light,
                target: .tunnels
            )

            overviewTile(
                tag: "NATIVE",
                title: "Local Ollama LLM",
                value: controller.ollama.isConnected ? "\(controller.ollama.models.count) Models" : "Offline",
                detail: controller.ollama.isConnected ? controller.ollama.activeModel : "Loopback port \(controller.ollamaPort)",
                systemImage: "cpu",
                statusLight: controller.ollama.light,
                target: .tunnels
            )
        }
    }

    private func overviewTile(
        tag: String,
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        statusLight: TrafficLightColor,
        target: BeaconDestination
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedDestination = target
            }
        } label: {
            OverviewGlassTile(
                tag: tag,
                title: title,
                value: value,
                detail: detail,
                systemImage: systemImage,
                statusLight: statusLight
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtle Footer

    private var footerBar: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Designed by")
                .foregroundStyle(palette.secondaryText)
            Link("SoroAI", destination: URL(string: "https://soroai.com")!)
                .foregroundStyle(palette.accentLink)
            Text("·")
                .foregroundStyle(palette.secondaryText)
            Button("Privacy Policy") {
                showingPrivacyPolicy = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accentLink)
            .help("View BeaconMac's Privacy Policy placeholder notice or open the local policy file")
            Text("·")
                .foregroundStyle(palette.secondaryText)
            Text("Local-first privacy · No telemetry or third-party log sharing")
                .foregroundStyle(palette.secondaryText)
            Spacer()
        }
        .font(.system(size: 11))
        .padding(.top, 6)
    }
}

private struct OverviewGlassTile: View {
    let tag: String
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let statusLight: TrafficLightColor

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        let dotColor: Color = {
            switch statusLight {
            case .green: return palette.successText
            case .amber: return palette.warningText
            case .red: return palette.errorText
            }
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader.opacity(isHovered ? 1.0 : 0.78))
                        .offset(y: isHovered ? -0.5 : 0)
                    Text(tag)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.sectionHeader)
                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondaryText)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: dotColor.opacity(0.65), radius: 4)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.glassMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.card)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.hoverFill)
                    .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: palette.cardShadow, radius: isHovered ? 16 : 10, y: isHovered ? 6 : 3)
        .offset(y: isHovered ? -1.5 : 0)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
