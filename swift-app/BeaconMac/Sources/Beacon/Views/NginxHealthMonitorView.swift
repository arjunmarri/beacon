import SwiftUI

struct NginxHealthMonitorView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var metrics: NginxHealthMetrics {
        controller.nginxProxy.metrics
    }

    private var snapshot: NginxStubStatusSnapshot? {
        metrics.latestSnapshot
    }

    private var healthLight: TrafficLightColor {
        if !controller.nginxProxy.isRunning {
            return .amber
        }
        if metrics.consecutiveFailedProbes > 0 {
            return .red
        }
        return .green
    }

    private var healthStatusLabel: String {
        if !controller.nginxProxy.isInstalled {
            return "Not Installed"
        }
        if !controller.nginxProxy.isRunning {
            return "Offline"
        }
        if let ms = metrics.probeLatencyMs {
            return "Healthy · \(ms) ms"
        }
        return "Healthy"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header + Live Telemetry Controls
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        BeaconSectionHeaderText(title: "NGINX Health & Live Connection Stats", fontSize: 16)
                        if let ver = controller.nginxProxy.nginxVersion {
                            Text(ver)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        if controller.nginxProxy.isRunning, let pid = controller.nginxProxy.pid {
                            Text("· PID \(pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        if controller.nginxProxy.isRunning, metrics.uptimeSeconds > 0 {
                            Text("· Up \(formatUptime(metrics.uptimeSeconds))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.successText)
                        }
                    }

                    Text("Monitors `/_beacon/nginx-health` latency and real-time `stub_status` connections, requests/sec, and active route health on \(controller.config.nginxProxy.exposeOnLAN ? "0.0.0.0" : "127.0.0.1"):\(controller.nginxProxy.listenPort).")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Toggle("Live 2s", isOn: Binding(
                    get: { controller.nginxProxy.metrics.livePollingEnabled },
                    set: { controller.setNginxLivePolling($0) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)

                Button("Poll Now") {
                    Task { await controller.pollNginxMetricsNow() }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                if !metrics.history.isEmpty {
                    Button("Reset") {
                        controller.resetNginxMetricsHistory()
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }

                TrafficLightLampView(active: healthLight, label: healthStatusLabel)
            }

            // State-specific banner when offline or running older config without stub_status
            if !controller.nginxProxy.isRunning {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.warningText)
                    Text(controller.nginxProxy.isInstalled
                        ? "Built-in NGINX is currently stopped. Start NGINX to stream real-time connection stats, active sockets, and requests/sec."
                        : "NGINX is not installed yet. Click \"Install NGINX\" in the reverse proxy section above to enable live health & connection telemetry.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if controller.nginxProxy.isInstalled {
                        Button("Start NGINX") {
                            Task { await controller.startNginxProxy() }
                        }
                        .disabled(controller.busyAction != nil)
                        .buttonStyle(BeaconPrimaryButtonStyle())
                    }
                }
                .padding(12)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !metrics.stubStatusAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.warningText)
                    Text(metrics.stubStatusSupported
                        ? "NGINX is healthy, but `/_beacon/nginx-status` is not active yet in the running process. Reload NGINX to enable live `stub_status` connection metrics."
                        : "This NGINX binary was compiled without `ngx_http_stub_status_module`. Health probe latency is still monitored in real time.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if metrics.stubStatusSupported {
                        Button("Reload for Live Stats") {
                            Task { await controller.reloadNginxProxy() }
                        }
                        .disabled(controller.busyAction != nil)
                        .buttonStyle(BeaconPrimaryButtonStyle())
                    }
                }
                .padding(12)
                .background(palette.row)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warningText.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 4 Real-Time KPI Tiles
            HStack(spacing: 12) {
                kpiTile(
                    title: "ACTIVE CONNECTIONS",
                    value: controller.nginxProxy.isRunning ? (snapshot.map { "\($0.activeConnections)" } ?? "—") : "—",
                    accent: palette.accentLink,
                    detail: snapshot.map { "Peak \(metrics.peakActiveConnections) · R:\($0.reading) W:\($0.writing) Idle:\($0.waiting)" } ?? "Waiting for stub_status"
                )

                kpiTile(
                    title: "THROUGHPUT (REQ/S)",
                    value: controller.nginxProxy.isRunning && metrics.stubStatusAvailable
                        ? String(format: "%.1f", metrics.requestsPerSecond)
                        : "—",
                    accent: palette.successText,
                    detail: snapshot.map {
                        String(format: "Peak %.1f/s · %.1f req/conn", metrics.peakRequestsPerSecond, $0.requestsPerConnection)
                    } ?? "Sampling live delta"
                )

                kpiTile(
                    title: "HEALTH PROBE",
                    value: controller.nginxProxy.isRunning
                        ? (metrics.probeLatencyMs.map { "\($0) ms" } ?? "OK")
                        : "Stopped",
                    accent: controller.nginxProxy.isRunning ? palette.successText : palette.warningText,
                    detail: controller.nginxProxy.isRunning
                        ? "\(metrics.consecutiveHealthyProbes) OK probes · \(controller.config.nginxProxy.routes.filter(\.enabled).count)/\(controller.config.nginxProxy.routes.count) routes"
                        : "Probe paused while stopped"
                )

                let dropped = snapshot?.droppedConnections ?? 0
                kpiTile(
                    title: "TOTAL REQUESTS",
                    value: snapshot.map { formatCount($0.requests) } ?? "—",
                    accent: dropped > 0 ? palette.errorText : palette.primaryText,
                    detail: snapshot.map {
                        "Accepted \(formatCount($0.accepts)) · Handled \(formatCount($0.handled)) · Dropped \(dropped)"
                    } ?? "No cumulative traffic yet"
                )
            }

            // Connection Breakdown Bar + Rolling Real-Time Sparklines
            if controller.nginxProxy.isRunning && (metrics.stubStatusAvailable || !metrics.history.isEmpty) {
                HStack(alignment: .top, spacing: 12) {
                    // Active Connections Sparkline
                    sparklineCard(
                        title: "Active Connections (Last \(metrics.history.count) Polls)",
                        latestLabel: snapshot.map { "\($0.activeConnections) active" } ?? "—",
                        values: metrics.history.map { Double($0.activeConnections) },
                        barColor: palette.accentLink,
                        minMaxFormatter: { "\(Int($0.rounded()))" }
                    )

                    // Requests/sec Sparkline
                    sparklineCard(
                        title: "Requests / Second (Real-Time Delta)",
                        latestLabel: String(format: "%.1f req/s", metrics.requestsPerSecond),
                        values: metrics.history.map(\.requestsPerSecond),
                        barColor: palette.successText,
                        minMaxFormatter: { String(format: "%.1f", $0) }
                    )
                }

                // Connection State Distribution Strip
                if let snap = snapshot {
                    let total = max(1, snap.reading + snap.writing + snap.waiting)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            Text("Connection Breakdown")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(palette.primaryText)

                            stateLegendDot(color: Color(red: 0.96, green: 0.68, blue: 0.20), label: "Reading", value: snap.reading)
                            stateLegendDot(color: palette.successText, label: "Writing", value: snap.writing)
                            stateLegendDot(color: palette.accentLink, label: "Waiting (Keep-Alive)", value: snap.waiting)

                            Spacer()

                            if let checked = controller.nginxProxy.lastCheckedAt {
                                Text("Updated \(checked.formatted(date: .omitted, time: .standard))")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }

                        GeometryReader { geo in
                            let w = max(1, geo.size.width)
                            let readW = w * CGFloat(snap.reading) / CGFloat(total)
                            let writeW = w * CGFloat(snap.writing) / CGFloat(total)
                            let waitW = max(0, w - readW - writeW)

                            HStack(spacing: 1) {
                                if snap.reading > 0 {
                                    Rectangle()
                                        .fill(Color(red: 0.96, green: 0.68, blue: 0.20))
                                        .frame(width: max(4, readW))
                                }
                                if snap.writing > 0 {
                                    Rectangle()
                                        .fill(palette.successText)
                                        .frame(width: max(4, writeW))
                                }
                                if snap.waiting > 0 {
                                    Rectangle()
                                        .fill(palette.accentLink.opacity(0.85))
                                        .frame(width: max(4, waitW))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.subtleBorder)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(height: 8)
                    }
                    .padding(12)
                    .background(palette.row)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
    }

    private func kpiTile(title: String, value: String, accent: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sparklineCard(
        title: String,
        latestLabel: String,
        values: [Double],
        barColor: Color,
        minMaxFormatter: (Double) -> String
    ) -> some View {
        let maxVal = max(1.0, values.max() ?? 1.0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(latestLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barColor)
            }

            if values.isEmpty {
                Text("Collecting live samples…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                        let normalized = max(0.08, min(1.0, val / maxVal))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, CGFloat(normalized) * 54))
                    }
                }
                .frame(height: 54, alignment: .bottom)
            }

            HStack {
                Text("0")
                Spacer()
                Text("Max: \(minMaxFormatter(maxVal))")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.row)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.subtleBorder))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stateLegendDot(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label): \(value)")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.bodyText)
        }
    }

    private func formatUptime(_ seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hrs > 0 {
            return String(format: "%dh %02dm", hrs, mins)
        }
        if mins > 0 {
            return String(format: "%dm %02ds", mins, secs)
        }
        return "\(secs)s"
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
}
