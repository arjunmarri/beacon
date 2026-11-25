import AppKit
import SwiftUI

struct BuiltInNodeServerView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var portText: String = "4173"
    @State private var showingCustomLoadSheet = false
    @State private var copiedAppID: UUID?
    @State private var hoveredMountedID: UUID?

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        BeaconSectionHeaderText(
                            title: "Built-In Node.js Server",
                            fontSize: 16,
                            systemImage: "server.rack"
                        )
                        if let nodeVer = controller.builtInServer.nodeVersion {
                            Text(nodeVer)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        if let pid = controller.builtInServer.pid, controller.builtInServer.isRunning {
                            Text("· PID \(pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Text("Load any HTML, Vite dist, React build, or local port directly into BeaconMac's built-in loopback Node.js host (\(controller.builtInServer.baseURL)).")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                TrafficLightLampView(
                    active: controller.builtInServer.light,
                    label: controller.builtInServer.statusLabel
                )
            }

            // Server Controls Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Port")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    TextField("4173", text: $portText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 62)
                        .beaconGlassInput(cornerRadius: 7, horizontalPadding: 8, verticalPadding: 5)
                        .onSubmit { applyPortChange() }
                    if Int(portText) != controller.config.builtInServer.port {
                        Button("Apply") { applyPortChange() }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }

                if controller.builtInServer.isRunning {
                    Button("Restart") {
                        Task { await controller.startBuiltInNodeServer(restart: true) }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Stop") {
                        Task { await controller.stopBuiltInNodeServer() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Open Launcher") {
                        controller.openBuiltInAppInBrowser(openLauncher: true)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    let nodeTunnel = controller.cloudflareTunnelEntry(for: "node-host")
                    Button(nodeTunnel?.isStarting == true
                        ? "Tunneling…"
                        : (nodeTunnel?.isRunning == true ? "Stop Tunnel" : "Expose Online")) {
                        Task { await controller.toggleBuiltInServerCloudflareTunnel() }
                    }
                    .disabled(nodeTunnel?.isStarting == true)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                } else {
                    Button("Start Server") {
                        Task { await controller.startBuiltInNodeServer() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }

                Toggle("Auto-start", isOn: Binding(
                    get: { controller.config.builtInServer.autoStart },
                    set: { next in
                        Task {
                            await controller.updateBuiltInNodeServerSettings(
                                port: controller.config.builtInServer.port,
                                autoStart: next
                            )
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                Spacer()

                if !controller.config.managedApps.isEmpty {
                    Menu {
                        ForEach(controller.config.managedApps) { app in
                            Button("Load \"\(app.name)\" (auto)") {
                                Task { await controller.loadManagedAppIntoBuiltInServer(app) }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Load Managed App")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 11.5)
                        .padding(.vertical, 6)
                        .background(palette.chipFill)
                        .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                Button("Custom / Proxy…") {
                    showingCustomLoadSheet = true
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("+ Load App Folder") {
                    pickAndLoadFolder()
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .beaconGlassWell(cornerRadius: 11)

            if let err = controller.builtInServer.lastError, !controller.builtInServer.isRunning {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.errorText)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.errorText)
                        .textSelection(.enabled)
                    Spacer()
                    if err.localizedCaseInsensitiveContains("node") {
                        Button("Install Node.js") {
                            controller.openDependencyInstaller()
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.red.opacity(palette.isLight ? 0.08 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.30), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if controller.config.builtInServer.mountedApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No apps loaded into the built-in Node.js server yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("Click \"+ Load App Folder\" to select any web project folder (HTML/JS, Vite dist, React build, Next static export) or mount a running local port. BeaconMac auto-starts the built-in Node.js server and serves your app immediately on \(controller.builtInServer.baseURL).")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .beaconGlassRow(cornerRadius: 12, padding: 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(controller.config.builtInServer.mountedApps) { app in
                        mountedAppRow(app)
                    }
                }
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
        .onAppear {
            portText = String(controller.config.builtInServer.port)
        }
        .onChange(of: controller.config.builtInServer.port) { _, next in
            portText = String(next)
        }
        .sheet(isPresented: $showingCustomLoadSheet) {
            BuiltInAppLoadSheet(controller: controller)
                .preferredColorScheme(activeScheme)
        }
    }

    private func mountedAppRow(_ app: BuiltInMountedApp) -> some View {
        let isActiveRoot = controller.config.builtInServer.activeRootAppID == app.id
        let isHovered = hoveredMountedID == app.id
        let primaryURL = isActiveRoot
            ? "\(controller.builtInServer.baseURL)/"
            : "\(controller.builtInServer.baseURL)/apps/\(app.slug)/"
        let sourceDetail = app.mode == .localProxy
            ? "Proxy → 127.0.0.1:\(app.proxyPort ?? 0)"
            : "\(BuiltInNodeServerService.describeServeRoot(for: app.folderPath)) · \(app.folderPath)"

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    Text(app.mode == .localProxy ? "PROXY" : "STATIC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accentLink)

                    if isActiveRoot {
                        Text("· Active on /")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.successText)
                    }
                }

                Text("\(primaryURL)  ·  \(sourceDetail)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !isActiveRoot {
                Button("Set as Root (/)") {
                    controller.setBuiltInRootApp(app.id)
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            Button(copiedAppID == app.id ? "Copied ✓" : "Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(primaryURL, forType: .string)
                copiedAppID = app.id
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if copiedAppID == app.id { copiedAppID = nil }
                }
            }
            .buttonStyle(BeaconSecondaryButtonStyle())

            Button("Open") {
                if !controller.builtInServer.isRunning {
                    Task {
                        await controller.startBuiltInNodeServer()
                        if controller.builtInServer.isRunning {
                            controller.openBuiltInAppInBrowser(app)
                        }
                    }
                } else {
                    controller.openBuiltInAppInBrowser(app)
                }
            }
            .buttonStyle(BeaconPrimaryButtonStyle())

            Button("Unload") {
                controller.removeBuiltInMountedApp(app)
            }
            .buttonStyle(BeaconDangerButtonStyle())
        }
        .beaconGlassRow(
            cornerRadius: 11,
            padding: 13,
            accentBorder: isActiveRoot ? palette.successText.opacity(0.45) : nil,
            isHovered: isHovered
        )
        .onHover { hovering in
            hoveredMountedID = hovering ? app.id : (hoveredMountedID == app.id ? nil : hoveredMountedID)
        }
    }

    private func applyPortChange() {
        let parsed = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? controller.config.builtInServer.port
        let clamped = max(1024, min(65535, parsed))
        portText = String(clamped)
        Task {
            await controller.updateBuiltInNodeServerSettings(
                port: clamped,
                autoStart: controller.config.builtInServer.autoStart
            )
        }
    }

    private func pickAndLoadFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select App Folder to Load into Built-In Node.js Server"
        panel.prompt = "Load App"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let folderName = url.lastPathComponent
        Task {
            await controller.loadAppIntoBuiltInServer(
                name: folderName,
                mode: .staticFolder,
                folderPath: url.path,
                spaFallback: true,
                makeActiveRoot: true,
                autoStartServer: true
            )
        }
    }
}

private struct BuiltInAppLoadSheet: View {
    @Bindable var controller: BeaconController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var mode: BuiltInNodeAppMode = .staticFolder
    @State private var folderPath: String = ""
    @State private var proxyPortText: String = "3001"
    @State private var spaFallback: Bool = true
    @State private var makeActiveRoot: Bool = true

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var canSubmit: Bool {
        if mode == .staticFolder {
            return !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            guard let p = Int(proxyPortText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return (1...65535).contains(p)
        }
    }

    var body: some View {
        ZStack {
            BeaconAmbientCanvas()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BeaconSectionHeaderText(
                        title: "Load App into Built-In Node.js Server",
                        fontSize: 16,
                        systemImage: "server.rack"
                    )
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hosting Mode")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                        Picker("Mode", selection: $mode) {
                            ForEach(BuiltInNodeAppMode.allCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("App Display Name")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                        TextField("e.g. My Web App", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.primaryText)
                            .beaconGlassInput()
                    }

                    if mode == .staticFolder {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("App Folder (auto-detects dist/, build/, out/, public/, or root index.html)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            HStack(spacing: 8) {
                                TextField("/Users/you/Projects/my-app", text: $folderPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                                    .beaconGlassInput()
                                Button("Browse…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        folderPath = url.path
                                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            name = url.lastPathComponent
                                        }
                                    }
                                }
                                .buttonStyle(BeaconSecondaryButtonStyle())
                            }
                            if !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Detected serve root: \(BuiltInNodeServerService.describeServeRoot(for: folderPath))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.successText)
                            }
                        }

                        Toggle("SPA Fallback (route unknown paths to index.html)", isOn: $spaFallback)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.bodyText)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Local Target Port (proxies strictly to 127.0.0.1:<port>)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            TextField("3001", text: $proxyPortText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(palette.primaryText)
                                .beaconGlassInput()
                        }
                    }

                    Toggle("Set as Active Root app (serve directly on \(controller.builtInServer.baseURL)/)", isOn: $makeActiveRoot)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.bodyText)
                }
                .beaconGlassCard(cornerRadius: 14, padding: 16)

                Spacer()

                HStack {
                    Spacer()
                    Button("Load & Start") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fallbackName = mode == .staticFolder
                            ? URL(fileURLWithPath: folderPath).lastPathComponent
                            : "Local :\(proxyPortText)"
                        let finalName = trimmedName.isEmpty ? fallbackName : trimmedName
                        let portVal = Int(proxyPortText.trimmingCharacters(in: .whitespacesAndNewlines))
                        Task {
                            await controller.loadAppIntoBuiltInServer(
                                name: finalName,
                                mode: mode,
                                folderPath: folderPath,
                                proxyPort: mode == .localProxy ? portVal : nil,
                                spaFallback: spaFallback,
                                makeActiveRoot: makeActiveRoot,
                                autoStartServer: true
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canSubmit)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
            }
            .padding(22)
        }
        .frame(width: 560, height: 420)
    }
}
