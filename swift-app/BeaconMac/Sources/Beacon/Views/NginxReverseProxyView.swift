import AppKit
import SwiftUI

struct NginxReverseProxyView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var portText: String = "8080"
    @State private var showingAddRouteSheet = false
    @State private var editingRoute: NginxProxyRoute?
    @State private var showingConfigInspector = false
    @State private var copiedRouteID: UUID?
    @State private var copiedLAN = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        BeaconSectionHeaderText(title: "Inbuilt NGINX Reverse Proxy", fontSize: 16)
                        if let ver = controller.nginxProxy.nginxVersion {
                            Text(ver)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        if let pid = controller.nginxProxy.pid, controller.nginxProxy.isRunning {
                            Text("· PID \(pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Text("Expose any local app via clean path prefixes (\(controller.nginxProxy.baseURL)/app/), *.localhost virtual hosts, or LAN with WebSocket & HMR support.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                TrafficLightLampView(
                    active: controller.nginxProxy.light,
                    label: controller.nginxProxy.statusLabel
                )
            }

            // NGINX Control Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Port")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                    TextField("8080", text: $portText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 62)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(palette.input)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit { applyPortChange() }
                    if Int(portText) != controller.config.nginxProxy.listenPort {
                        Button("Apply") { applyPortChange() }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }

                if !controller.nginxProxy.isInstalled {
                    Button("Install NGINX") {
                        Task { await controller.installNginxSilently() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                } else if controller.nginxProxy.isRunning {
                    Button("Reload") {
                        Task { await controller.reloadNginxProxy() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Stop") {
                        Task { await controller.stopNginxProxy() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("Open Proxy") {
                        controller.openNginxRouteInBrowser()
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    let nginxTunnel = controller.cloudflareTunnelEntry(for: "nginx")
                    Button(nginxTunnel?.isStarting == true
                        ? "Tunneling…"
                        : (nginxTunnel?.isRunning == true ? "Stop Tunnel" : "Expose Online")) {
                        Task { await controller.toggleNginxCloudflareTunnel() }
                    }
                    .disabled(nginxTunnel?.isStarting == true)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                } else {
                    Button("Start NGINX") {
                        Task { await controller.startNginxProxy() }
                    }
                    .disabled(controller.busyAction != nil)
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }

                Toggle("Expose LAN (0.0.0.0)", isOn: Binding(
                    get: { controller.config.nginxProxy.exposeOnLAN },
                    set: { next in
                        Task {
                            await controller.updateNginxSettings(
                                listenPort: controller.config.nginxProxy.listenPort,
                                exposeOnLAN: next,
                                autoStart: controller.config.nginxProxy.autoStart
                            )
                        }
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                Toggle("Auto-start", isOn: Binding(
                    get: { controller.config.nginxProxy.autoStart },
                    set: { next in
                        Task {
                            await controller.updateNginxSettings(
                                listenPort: controller.config.nginxProxy.listenPort,
                                exposeOnLAN: controller.config.nginxProxy.exposeOnLAN,
                                autoStart: next
                            )
                        }
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                Spacer()

                if !controller.config.managedApps.isEmpty {
                    Menu {
                        ForEach(controller.config.managedApps) { app in
                            Button("Expose \"\(app.name)\" (:\(app.port))") {
                                Task { await controller.exposeManagedAppViaNginx(app) }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Expose Managed App")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(palette.chipFill)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                Button("View nginx.conf") {
                    showingConfigInspector = true
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("+ Add Proxy Route") {
                    showingAddRouteSheet = true
                }
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.row)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // LAN Share URL strip when LAN exposure is active
            if controller.config.nginxProxy.exposeOnLAN, let lanURL = controller.nginxProxy.lanBaseURL {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                    Text("LAN Reachable:")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                    Text(lanURL)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.primaryText)
                        .textSelection(.enabled)
                    Text("· Accessible from phones & devices on your Wi-Fi")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button(copiedLAN ? "Copied LAN URL ✓" : "Copy LAN URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(lanURL)/", forType: .string)
                        copiedLAN = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedLAN = false
                        }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.activeChipFill)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.sectionAccentBar.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            if let err = controller.nginxProxy.lastError, !err.isEmpty {
                HStack(spacing: 10) {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.errorText)
                        .textSelection(.enabled)
                    Spacer()
                    if !controller.nginxProxy.isInstalled {
                        Button("Install NGINX") {
                            Task { await controller.installNginxSilently() }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    } else {
                        Button("Test Config (nginx -t)") {
                            Task { await controller.testNginxConfig() }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.red.opacity(palette.isLight ? 0.08 : 0.12))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.red.opacity(0.28)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            if controller.config.nginxProxy.routes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No reverse proxy routes configured yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                    Text("Click \"+ Add Proxy Route\" or \"Expose via NGINX\" on any Managed Local App to expose localhost ports through BeaconMac's user-space NGINX instance (zero sudo, instant hot reload, WebSocket/HMR ready).")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 10) {
                    ForEach(controller.config.nginxProxy.routes) { route in
                        routeRow(route)
                    }
                }
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
        .onAppear {
            portText = String(controller.config.nginxProxy.listenPort)
        }
        .onChange(of: controller.config.nginxProxy.listenPort) { _, next in
            portText = String(next)
        }
        .sheet(isPresented: $showingAddRouteSheet) {
            NginxRouteEditorSheet(controller: controller, existingRoute: nil)
                .preferredColorScheme(activeScheme)
        }
        .sheet(item: $editingRoute) { route in
            NginxRouteEditorSheet(controller: controller, existingRoute: route)
                .preferredColorScheme(activeScheme)
        }
        .sheet(isPresented: $showingConfigInspector) {
            NginxConfigInspectorSheet(controller: controller)
                .preferredColorScheme(activeScheme)
        }
    }

    private func routeRow(_ route: NginxProxyRoute) -> some View {
        let isActiveRoot = controller.config.nginxProxy.activeRootRouteID == route.id
        let pathURL = controller.pathURL(for: route)
        let vhostURL = route.serverName.isEmpty ? nil : controller.primaryURL(for: route)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(route.enabled ? palette.successText : palette.secondaryText.opacity(0.45))
                        .frame(width: 7, height: 7)

                    Text(route.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(route.enabled ? palette.primaryText : palette.secondaryText)

                    Text("\(route.targetHost):\(route.targetPort)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accentLink)

                    if route.webSocketsEnabled {
                        Text("· WS")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }

                    if isActiveRoot {
                        Text("· Root (/)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.successText)
                    }
                }

                HStack(spacing: 8) {
                    Text(pathURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.bodyText)
                        .lineLimit(1)
                    if let vhostURL {
                        Text("· vhost: \(vhostURL)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.sectionHeader)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { route.enabled },
                set: { _ in Task { await controller.toggleNginxRoute(route) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(route.enabled ? "Disable this reverse proxy route" : "Enable this reverse proxy route")

            if !isActiveRoot && route.enabled {
                Button("Set as Root") {
                    Task { await controller.setNginxRootRoute(route.id) }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            Button(copiedRouteID == route.id ? "Copied ✓" : "Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vhostURL ?? pathURL, forType: .string)
                copiedRouteID = route.id
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if copiedRouteID == route.id { copiedRouteID = nil }
                }
            }
            .buttonStyle(BeaconSecondaryButtonStyle())

            Button("Open") {
                if !controller.nginxProxy.isRunning && controller.nginxProxy.isInstalled {
                    Task {
                        await controller.startNginxProxy()
                        if controller.nginxProxy.isRunning {
                            controller.openNginxRouteInBrowser(route, useVHost: vhostURL != nil)
                        }
                    }
                } else {
                    controller.openNginxRouteInBrowser(route, useVHost: vhostURL != nil)
                }
            }
            .disabled(!route.enabled)
            .buttonStyle(BeaconPrimaryButtonStyle())

            Button("Edit") {
                editingRoute = route
            }
            .buttonStyle(BeaconSecondaryButtonStyle())

            Button("Remove") {
                Task { await controller.deleteNginxRoute(route) }
            }
            .buttonStyle(BeaconSecondaryButtonStyle())
        }
        .padding(12)
        .background(palette.row)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isActiveRoot && route.enabled ? palette.successText.opacity(0.45) : palette.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func applyPortChange() {
        let parsed = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? controller.config.nginxProxy.listenPort
        let clamped = NginxProxyService.clampedPort(parsed, fallback: 8080)
        portText = String(clamped)
        Task {
            await controller.updateNginxSettings(
                listenPort: clamped,
                exposeOnLAN: controller.config.nginxProxy.exposeOnLAN,
                autoStart: controller.config.nginxProxy.autoStart
            )
        }
    }
}

private struct NginxRouteEditorSheet: View {
    @Bindable var controller: BeaconController
    let existingRoute: NginxProxyRoute?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var pathPrefix: String = "/app"
    @State private var serverName: String = ""
    @State private var targetHost: String = "127.0.0.1"
    @State private var targetPortText: String = "3000"
    @State private var webSocketsEnabled: Bool = true
    @State private var stripPrefix: Bool = true
    @State private var makeActiveRoot: Bool = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var validPort: Int? {
        guard let p = Int(targetPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(p) else { return nil }
        return p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BeaconSectionHeaderText(
                    title: existingRoute == nil ? "Add NGINX Reverse Proxy Route" : "Edit Proxy Route",
                    fontSize: 16
                )
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if !controller.config.managedApps.isEmpty && existingRoute == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick-fill from a Managed Local App")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    Picker("Managed App", selection: Binding(
                        get: { "" },
                        set: { selectedID in
                            if let app = controller.config.managedApps.first(where: { $0.id.uuidString == selectedID }) {
                                let slug = BuiltInNodeServerService.makeSlug(from: app.name, existingSlugs: [])
                                name = app.name
                                pathPrefix = "/\(slug)"
                                serverName = "\(slug).localhost"
                                targetHost = "127.0.0.1"
                                targetPortText = String(app.port)
                            }
                        }
                    )) {
                        Text("Choose an app to pre-fill…").tag("")
                        ForEach(controller.config.managedApps) { app in
                            Text("\(app.name) (localhost:\(app.port))").tag(app.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                inputField("Route Name", placeholder: "e.g. Frontend App", text: $name)
                inputField("Path Prefix", placeholder: "/my-app", text: $pathPrefix)
                    .frame(width: 170)
            }

            inputField("Virtual Host Domain (optional — *.localhost works with zero /etc/hosts setup)", placeholder: "e.g. myapp.localhost", text: $serverName)

            HStack(spacing: 12) {
                inputField("Upstream Target Host", placeholder: "127.0.0.1", text: $targetHost)
                inputField("Upstream Target Port", placeholder: "3000", text: $targetPortText)
                    .frame(width: 150)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable WebSocket & Vite HMR upgrade headers (Upgrade / Connection)", isOn: $webSocketsEnabled)
                Toggle("Strip path prefix before forwarding to upstream (proxy_pass trailing slash)", isOn: $stripPrefix)
                Toggle("Set as Active Root app (serve directly on \(controller.nginxProxy.baseURL)/)", isOn: $makeActiveRoot)
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.bodyText)

            Spacer()

            HStack {
                Spacer()
                Button(existingRoute == nil ? "Add Route & Reload NGINX" : "Save & Reload NGINX") {
                    guard let port = validPort else { return }
                    let route = NginxProxyRoute(
                        id: existingRoute?.id ?? UUID(),
                        name: name,
                        pathPrefix: pathPrefix,
                        serverName: serverName,
                        targetHost: targetHost,
                        targetPort: port,
                        webSocketsEnabled: webSocketsEnabled,
                        stripPrefix: stripPrefix,
                        enabled: existingRoute?.enabled ?? true,
                        addedAt: existingRoute?.addedAt ?? Date()
                    )
                    Task {
                        await controller.upsertNginxRoute(route, makeActiveRoot: makeActiveRoot, autoStartOrReload: true)
                        dismiss()
                    }
                }
                .disabled(validPort == nil)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 560, height: 455)
        .background(palette.sheetCanvas)
        .onAppear {
            if let existingRoute {
                name = existingRoute.name
                pathPrefix = existingRoute.pathPrefix
                serverName = existingRoute.serverName
                targetHost = existingRoute.targetHost
                targetPortText = String(existingRoute.targetPort)
                webSocketsEnabled = existingRoute.webSocketsEnabled
                stripPrefix = existingRoute.stripPrefix
                makeActiveRoot = controller.config.nginxProxy.activeRootRouteID == existingRoute.id
            }
        }
    }

    private func inputField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(palette.input)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct NginxConfigInspectorSheet: View {
    @Bindable var controller: BeaconController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedConf = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    var body: some View {
        let confText = controller.currentNginxConfigText

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Generated nginx.conf", fontSize: 16)
                    Text(controller.nginxProxy.configPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Test (nginx -t)") {
                    Task { await controller.testNginxConfig() }
                }
                .disabled(controller.busyAction != nil || !controller.nginxProxy.isInstalled)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button(copiedConf ? "Copied ✓" : "Copy nginx.conf") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(confText, forType: .string)
                    copiedConf = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedConf = false
                    }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Done") { dismiss() }
                    .buttonStyle(BeaconPrimaryButtonStyle())
            }

            ScrollView([.vertical, .horizontal]) {
                Text(confText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.bodyText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(palette.console)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 520)
        .background(palette.sheetCanvas)
    }
}
