import AppKit
import SwiftUI

struct PrerequisiteInstallerSheet: View {
    @Bindable var controller: BeaconController
    @State var selectedAppID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProjectType: DependencyProjectType = .nodejsPnpm
    @State private var installStrategy: DependencyInstallStrategy = .auto
    @State private var selectedTools: Set<String> = Set(DependencyProjectType.nodejsPnpm.requiredTools)
    @State private var installOutput: [String] = []
    @State private var isInstalling = false
    @State private var lastStatus: String?
    @State private var lastSucceeded: Bool = true
    @State private var copiedOutput = false
    @State private var didInitializePreset = false

    private let canvasBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let terminalBackground = Color(red: 0.031, green: 0.037, blue: 0.047)

    private let installableTools: [(id: String, label: String, subtitle: String)] = [
        ("node", "Node.js + npm", "Homebrew or official Node.js LTS tarball"),
        ("pnpm", "pnpm", "Homebrew, Corepack, or get.pnpm.io"),
        ("yarn", "Yarn", "Homebrew, Corepack, or npm"),
        ("bun", "Bun", "Homebrew or bun.sh direct installer"),
        ("python3", "Python 3 + pip", "Homebrew Python for requirements.txt"),
        ("uv", "uv", "Homebrew or astral.sh direct installer"),
        ("go", "Go", "Homebrew Go toolchain"),
        ("git", "Git", "Homebrew or Xcode Command Line Tools")
    ]

    private var selectedApp: ManagedApp? {
        guard let selectedAppID else { return nil }
        return controller.config.managedApps.first { $0.id == selectedAppID }
    }

    private var missingSelectedTools: [String] {
        selectedTools.sorted().filter { toolID in
            !(controller.systemTools.first(where: { $0.name == toolID })?.available ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Dependencies")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Select your project type to silently install missing tools (Node.js, pnpm, Yarn, Bun, Python, uv, Go) via Homebrew or direct official download.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            // 1. Project Type & Install Method Selector
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Type")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Picker("Project Type", selection: $selectedProjectType) {
                            ForEach(DependencyProjectType.allCases) { projectType in
                                Text(projectType.rawValue).tag(projectType)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: selectedProjectType) { _, newType in
                            applyProjectType(newType)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Silent Install Method")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Picker("Silent Install Method", selection: $installStrategy) {
                            ForEach(DependencyInstallStrategy.allCases) { strategy in
                                Text(strategy.label).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(selectedProjectType.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Divider().overlay(Color.white.opacity(0.06))

                HStack(spacing: 10) {
                    Text("Project Folder (optional):")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("Target App", selection: $selectedAppID) {
                        Text("Tools Only (no project folder)").tag(UUID?.none)
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
                    Text("Detected project status: \(state.dependencySummary)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.9))
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 2. Tools Status & Overrides
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tools Included in Selection")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if !missingSelectedTools.isEmpty {
                        Text("· \(missingSelectedTools.count) missing (\(missingSelectedTools.joined(separator: ", ")))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.95))
                    } else if !selectedTools.isEmpty {
                        Text("· All selected tools already installed")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.9))
                    }

                    Spacer()

                    Button("Refresh Detected") {
                        Task { await controller.auditSystemDependencies() }
                    }
                    .disabled(isInstalling)
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
                                    if selectedProjectType != .custom && selectedTools != Set(selectedProjectType.requiredTools) {
                                        selectedProjectType = .custom
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isInstalled ? Color.green : (isChecked ? Color.orange : Color.gray.opacity(0.45)))
                                            .frame(width: 6, height: 6)
                                        Text(tool.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                        if isInstalled, let detail = status?.detail {
                                            Text(detail)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.green.opacity(0.85))
                                                .lineLimit(1)
                                        } else if isChecked {
                                            Text("Will install")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.orange.opacity(0.95))
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
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isChecked ? Color.cyan.opacity(0.42) : Color.white.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 3. Action row
            HStack(spacing: 10) {
                Button(isInstalling ? "Installing Silently…" : installButtonLabel) {
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
                            title: "Dependency Installer Output",
                            logText: dump,
                            appName: appName
                        )
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }
            }

            // 4. Silent installation log
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if installOutput.isEmpty {
                        Text("Runs silently in the background with zero terminal popups (NONINTERACTIVE=1). Missing tools install automatically via Homebrew or verified direct official downloads, and output is also mirrored to Integrated Terminal Output.")
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
            .frame(minHeight: 145, maxHeight: .infinity)
            .background(terminalBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 640)
        .background(canvasBackground)
        .onAppear {
            if !didInitializePreset {
                didInitializePreset = true
                let inferred = DependencyProjectType.defaultType(for: selectedApp?.stackPreset)
                selectedProjectType = inferred
                selectedTools = Set(inferred.requiredTools)
            }
            if controller.systemTools.isEmpty {
                Task { await controller.auditSystemDependencies() }
            }
        }
    }

    private var installButtonLabel: String {
        if let app = selectedApp {
            if missingSelectedTools.isEmpty {
                return "Install \(app.name) Dependencies"
            }
            return "Install \(missingSelectedTools.count) Missing Tool(s) & \(app.name) Deps"
        }
        if missingSelectedTools.isEmpty {
            return "Verify Selected Dependencies"
        }
        return "Install \(missingSelectedTools.count) Missing Tool(s) Silently"
    }

    private func applyProjectType(_ type: DependencyProjectType) {
        guard type != .custom else { return }
        selectedTools = Set(type.requiredTools)
    }

    private func runInstall() {
        isInstalling = true
        lastStatus = nil
        installOutput = []
        let app = selectedApp
        let tools = Array(selectedTools).sorted()
        let strategy = installStrategy

        Task {
            let res = await controller.installPrerequisitesAndDependencies(
                for: app,
                requestedTools: tools,
                strategy: strategy
            )
            installOutput = res.stdoutLines + res.stderrLines.map { "[stderr] \($0)" }
            if installOutput.isEmpty {
                installOutput = [res.summary]
            }
            lastSucceeded = res.ok
            lastStatus = res.ok ? "Dependencies installed silently." : res.summary
            isInstalling = false
        }
    }

    private func appendLocal(_ line: String) {
        installOutput.append(line)
    }
}
