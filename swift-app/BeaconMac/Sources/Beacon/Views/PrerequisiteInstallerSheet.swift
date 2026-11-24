import AppKit
import SwiftUI

struct PrerequisiteInstallerSheet: View {
    @Bindable var controller: BeaconController
    @State var selectedAppID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTools: Set<String> = []
    @State private var installOutput: [String] = []
    @State private var isInstalling = false
    @State private var lastStatus: String?
    @State private var lastSucceeded: Bool = true
    @State private var copiedOutput = false

    private let canvasBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let terminalBackground = Color(red: 0.031, green: 0.037, blue: 0.047)

    private let installableTools: [(id: String, label: String, subtitle: String)] = [
        ("node", "Node.js + npm", "JavaScript runtime & npm"),
        ("bun", "Bun", "Fast JS/TS runtime & bundler"),
        ("pnpm", "pnpm", "Fast workspace package manager"),
        ("yarn", "Yarn", "Classic / Berry JS package manager"),
        ("python3", "Python 3 + pip", "For requirements.txt / pyproject.toml"),
        ("uv", "uv", "Fast Python package manager"),
        ("go", "Go", "For go.mod projects"),
        ("git", "Git", "Repository clone & sync")
    ]

    private var selectedApp: ManagedApp? {
        guard let selectedAppID else { return nil }
        return controller.config.managedApps.first { $0.id == selectedAppID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Prerequisites & Project Dependencies")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Auto-detects package.json, lockfiles (npm/pnpm/yarn/bun), requirements.txt, pyproject.toml, go.mod, Cargo.toml, and installs missing runtimes & packages in-app.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            // Target project selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Project Requirements Source")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Picker("Target App", selection: $selectedAppID) {
                        Text("System Prerequisites Only (no project folder)").tag(UUID?.none)
                        ForEach(controller.config.managedApps) { app in
                            Text("\(app.name) — \(app.localPath.isEmpty ? "no folder set" : app.localPath)")
                                .tag(UUID?.some(app.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if let app = selectedApp, !app.localPath.isEmpty {
                        Button("Check App Deps") {
                            Task {
                                await controller.checkDependencies(for: app)
                                appendLocal("Checked dependencies for \(app.name): \(controller.runtimeState(for: app.id).dependencySummary)")
                            }
                        }
                        .disabled(isInstalling || controller.busyAction != nil)
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }

                if let app = selectedApp, !app.localPath.isEmpty {
                    let state = controller.runtimeState(for: app.id)
                    Text("Detected status: \(state.dependencySummary)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.9))
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Runtime tools checkboxes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("System Runtimes & Package Managers (optional overrides — project lockfiles are auto-detected too)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Detected") {
                        Task { await controller.auditSystemDependencies() }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(installableTools, id: \.id) { tool in
                        let status = controller.systemTools.first(where: { $0.name == tool.id })
                        let isInstalled = status?.available ?? false
                        let isChecked = selectedTools.contains(tool.id)

                        HStack(spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { isChecked },
                                set: { checked in
                                    if checked {
                                        selectedTools.insert(tool.id)
                                    } else {
                                        selectedTools.remove(tool.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isInstalled ? Color.green : Color.gray.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                        Text(tool.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                        if isInstalled, let detail = status?.detail {
                                            Text(detail)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.green.opacity(0.85))
                                                .lineLimit(1)
                                        }
                                    }
                                    Text(tool.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(terminalBackground)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isChecked ? Color.cyan.opacity(0.4) : Color.white.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action row
            HStack(spacing: 10) {
                Button(isInstalling ? "Installing Prerequisites…" : installButtonLabel) {
                    runInstall()
                }
                .disabled(isInstalling || (selectedApp == nil && selectedTools.isEmpty))
                .buttonStyle(BeaconPrimaryButtonStyle())

                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                } else if let status = lastStatus {
                    Text(status)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(lastSucceeded ? .green : .red.opacity(0.92))
                        .lineLimit(1)
                }

                Spacer()

                if !installOutput.isEmpty {
                    Button(copiedOutput ? "Copied ✓" : "Copy Output") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installOutput.joined(separator: "\n"), forType: .string)
                        copiedOutput = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedOutput = false
                        }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("AI Help") {
                        let dump = installOutput.joined(separator: "\n")
                        let appName = selectedApp?.name
                        dismiss()
                        controller.openAIHelp(
                            title: "Prerequisite Installer Output",
                            logText: dump,
                            appName: appName
                        )
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            }

            // Live output log
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if installOutput.isEmpty {
                        Text("Installation logs stream here and into BeaconMac's Integrated Terminal Output. Uses Homebrew when available plus official installers (npm / corepack / bun.sh / pip3).")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(10)
                    } else {
                        ForEach(Array(installOutput.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(line.localizedCaseInsensitiveContains("error") ? .red.opacity(0.92) : .white.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minHeight: 155, maxHeight: .infinity)
            .background(terminalBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 590)
        .background(canvasBackground)
    }

    private var installButtonLabel: String {
        if let app = selectedApp {
            return selectedTools.isEmpty
                ? "Auto-Detect & Install All Deps for \(app.name)"
                : "Install Selected Tools & \(app.name) Deps"
        }
        return "Install Selected System Tools"
    }

    private func runInstall() {
        isInstalling = true
        lastStatus = nil
        installOutput = []
        let app = selectedApp
        let tools = Array(selectedTools).sorted()

        Task {
            let res = await controller.installPrerequisitesAndDependencies(
                for: app,
                requestedTools: tools
            )
            installOutput = res.stdoutLines + res.stderrLines.map { "[stderr] \($0)" }
            if installOutput.isEmpty {
                installOutput = [res.summary]
            }
            lastSucceeded = res.ok
            lastStatus = res.ok ? "Installation completed." : res.summary
            isInstalling = false
        }
    }

    private func appendLocal(_ line: String) {
        installOutput.append(line)
    }
}
