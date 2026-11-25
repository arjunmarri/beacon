import AppKit
import SwiftUI

struct PrerequisiteInstallerSheet: View {
    @Bindable var controller: BeaconController
    @State var selectedAppID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedProjectType: DependencyProjectType = .nodejsPnpm
    @State private var installStrategy: DependencyInstallStrategy = .auto
    @State private var selectedTools: Set<String> = Set(DependencyProjectType.nodejsPnpm.requiredTools)
    @State private var installOutput: [String] = []
    @State private var isInstalling = false
    @State private var lastStatus: String?
    @State private var lastSucceeded: Bool = true
    @State private var copiedOutput = false
    @State private var didInitializePreset = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private let installableTools: [(id: String, label: String, subtitle: String)] = [
        ("node", "Node.js + npm", "Homebrew or official Node.js LTS tarball"),
        ("pnpm", "pnpm", "Homebrew, Corepack, or get.pnpm.io"),
        ("yarn", "Yarn", "Homebrew, Corepack, or npm"),
        ("bun", "Bun", "Homebrew or bun.sh direct installer"),
        ("python3", "Python 3 + pip", "Homebrew Python for requirements.txt"),
        ("uv", "uv", "Homebrew or astral.sh direct installer"),
        ("go", "Go", "Homebrew Go toolchain"),
        ("nginx", "NGINX", "Homebrew reverse proxy server"),
        ("cloudflared", "Cloudflare Tunnel (cloudflared)", "Homebrew or direct official macOS binary"),
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
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Install Dependencies", fontSize: 16)
                    Text("Select your project type to silently install missing tools (Node.js, pnpm, Yarn, Bun, Python, uv, Go) via Homebrew or direct official download.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
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
                            .foregroundStyle(palette.secondaryText)
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
                            .foregroundStyle(palette.secondaryText)
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
                    .foregroundStyle(palette.secondaryText)

                Divider().overlay(palette.subtleBorder)

                HStack(spacing: 10) {
                    Text("Project Folder (optional):")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.secondaryText)

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
                        .foregroundStyle(palette.accentLink)
                }
            }
            .padding(12)
            .background(palette.card)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 2. Tools Status & Overrides
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tools Included in Selection")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)

                    if !missingSelectedTools.isEmpty {
                        Text("· \(missingSelectedTools.count) missing (\(missingSelectedTools.joined(separator: ", ")))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.warningText)
                    } else if !selectedTools.isEmpty {
                        Text("· All selected tools already installed")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.successText)
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
                                            .fill(isInstalled ? palette.successText : (isChecked ? palette.warningText : Color.gray.opacity(0.45)))
                                            .frame(width: 6, height: 6)
                                        Text(tool.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.primaryText)
                                        if isInstalled, let detail = status?.detail {
                                            Text(detail)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(palette.successText)
                                                .lineLimit(1)
                                        } else if isChecked {
                                            Text("Will install")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(palette.warningText)
                                        }
                                    }
                                    Text(tool.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .toggleStyle(.checkbox)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.row)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isChecked ? palette.sectionHeader.opacity(0.45) : palette.subtleBorder)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(12)
            .background(palette.card)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
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
                        .foregroundStyle(lastSucceeded ? palette.successText : palette.errorText)
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
                }
            }

            // 4. Silent installation log
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if installOutput.isEmpty {
                        Text("Runs silently in the background with zero terminal popups (NONINTERACTIVE=1). Missing tools install automatically via Homebrew or verified direct official downloads, and output is also mirrored to Integrated Terminal Output.")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                            .padding(10)
                    } else {
                        ForEach(Array(installOutput.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(line.localizedCaseInsensitiveContains("error") ? palette.errorText : palette.bodyText)
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
            .background(palette.console)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 640)
        .background(palette.sheetCanvas)
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
