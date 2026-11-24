import AppKit
import SwiftUI

struct AppEditorSheet: View {
    @Bindable var controller: BeaconController
    let existingApp: ManagedApp?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var stackPreset: AppStackPreset = .vite
    @State private var repoURL: String = ""
    @State private var branch: String = "main"
    @State private var localPath: String = ""
    @State private var monitorURL: String = "http://localhost:5173"
    @State private var installCommand: String = "auto"
    @State private var buildCommand: String = "npm run build"
    @State private var startCommand: String = "npm run dev -- --port 5173"
    @State private var autoRestart: Bool = true
    @State private var autoDeploy: Bool = true
    @State private var runOnStartup: Bool = false

    private let bg = Color(red: 0.055, green: 0.067, blue: 0.086)
    private let inputBg = Color(red: 0.035, green: 0.043, blue: 0.055)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(existingApp == nil ? "Add Local App to Monitor & Deploy" : "Edit \(existingApp?.name ?? "App")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(BeaconSecondaryButtonStyle())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !controller.git.repos.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick-fill from connected GitHub repositories")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Picker("GitHub Repo", selection: Binding(
                                get: { repoURL },
                                set: { selectedCloneURL in
                                    repoURL = selectedCloneURL
                                    if let match = controller.git.repos.first(where: { $0.cloneURL == selectedCloneURL }) {
                                        let repoName = match.fullName.split(separator: "/").last.map(String.init) ?? match.fullName
                                        if name.isEmpty { name = repoName }
                                        branch = match.defaultBranch
                                        if localPath.isEmpty {
                                            localPath = "\(NSHomeDirectory())/BeaconApps/\(repoName)"
                                        }
                                    }
                                }
                            )) {
                                Text("Select a repository...").tag("")
                                ForEach(controller.git.repos) { repo in
                                    Text("\(repo.fullName) (\(repo.defaultBranch))").tag(repo.cloneURL)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    HStack(spacing: 12) {
                        field("App Name", placeholder: "e.g. SoroWiz Web", text: $name)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Stack Preset")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Picker("Stack", selection: $stackPreset) {
                                ForEach(AppStackPreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: stackPreset) { _, next in
                                let port = LocalProcessService.extractPort(from: monitorURL, fallback: 5173)
                                installCommand = next.defaultInstallCommand
                                buildCommand = next.defaultBuildCommand
                                startCommand = next.defaultStartCommand(port: port)
                            }
                        }
                        .frame(width: 170)
                    }

                    HStack(spacing: 12) {
                        field("Remote Git Repository URL", placeholder: "https://github.com/user/my-vite-app.git", text: $repoURL)
                        field("Branch", placeholder: "main", text: $branch)
                            .frame(width: 130)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local Folder (cloned automatically if empty or missing)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("/Users/you/BeaconApps/my-app", text: $localPath)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(inputBg)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    localPath = url.path
                                }
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }

                    field("Local App URL to Monitor", placeholder: "http://localhost:5173 or http://127.0.0.1:3000", text: $monitorURL)

                    Divider().overlay(Color.white.opacity(0.08))

                    field("Dependency Install Command (auto = detect npm/pnpm/yarn/bun)", placeholder: "auto", text: $installCommand)
                    field("Build Command (blank to skip build)", placeholder: "npm run build", text: $buildCommand)
                    field("Start Command", placeholder: "npm run dev -- --port 5173", text: $startCommand)

                    Divider().overlay(Color.white.opacity(0.08))

                    HStack(spacing: 20) {
                        Toggle("Auto-restart on crash", isOn: $autoRestart)
                        Toggle("Auto-deploy on Git push", isOn: $autoDeploy)
                        Toggle("Run on macOS startup / cron", isOn: $runOnStartup)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Save App") {
                    let normalizedMonitorURL = LocalProcessService.normalizeLocalAppURL(monitorURL)
                    let port = LocalProcessService.extractPort(from: normalizedMonitorURL, fallback: 5173)
                    let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Local App :\(port)"
                        : name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let model = ManagedApp(
                        id: existingApp?.id ?? UUID(),
                        name: finalName,
                        stackPreset: stackPreset,
                        repoURL: repoURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        branch: branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : branch.trimmingCharacters(in: .whitespacesAndNewlines),
                        localPath: localPath.trimmingCharacters(in: .whitespacesAndNewlines),
                        monitorURL: normalizedMonitorURL,
                        port: port,
                        installCommand: installCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                        buildCommand: buildCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                        startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                        autoRestart: autoRestart,
                        autoDeploy: autoDeploy,
                        runOnStartup: runOnStartup
                    )
                    Task {
                        await controller.upsertManagedApp(model)
                        dismiss()
                    }
                }
                .disabled(monitorURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 620, height: 590)
        .background(bg)
        .onAppear {
            if let app = existingApp {
                name = app.name
                stackPreset = app.stackPreset
                repoURL = app.repoURL
                branch = app.branch
                localPath = app.localPath
                monitorURL = app.monitorURL
                installCommand = app.installCommand
                buildCommand = app.buildCommand
                startCommand = app.startCommand
                autoRestart = app.autoRestart
                autoDeploy = app.autoDeploy
                runOnStartup = app.runOnStartup
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(inputBg)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}
