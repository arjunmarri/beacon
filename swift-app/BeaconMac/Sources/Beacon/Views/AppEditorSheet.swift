import AppKit
import SwiftUI

struct AppEditorSheet: View {
    @Bindable var controller: BeaconController
    let existingApp: ManagedApp?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var stackPreset: AppStackPreset = .auto
    @State private var repoURL: String = ""
    @State private var branch: String = "main"
    @State private var localPath: String = ""
    @State private var monitorURL: String = "http://localhost:5173"
    @State private var installCommand: String = "auto"
    @State private var buildCommand: String = "auto"
    @State private var startCommand: String = "auto"
    @State private var autoRestart: Bool = true
    @State private var autoDeploy: Bool = true
    @State private var runOnStartup: Bool = false
    @State private var detectedScriptsNote: String?

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            BeaconAmbientCanvas()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BeaconSectionHeaderText(
                        title: existingApp == nil ? "Add Local App to Monitor & Deploy" : "Edit \(existingApp?.name ?? "App")",
                        fontSize: 16,
                        systemImage: existingApp == nil ? "plus.app.fill" : "slider.horizontal.3"
                    )
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !controller.git.repos.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quick-fill from connected GitHub repositories")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.secondaryText)
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
                                            detectScriptsFromPackageJSON(silentIfMissing: true)
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
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.secondaryText)
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
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            HStack(spacing: 8) {
                                TextField("/Users/you/BeaconApps/my-app", text: $localPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                                    .beaconGlassInput()
                                Button("Browse…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = false
                                    panel.canChooseDirectories = true
                                    panel.canCreateDirectories = true
                                    if panel.runModal() == .OK, let url = panel.url {
                                        localPath = url.path
                                        detectScriptsFromPackageJSON(silentIfMissing: true)
                                    }
                                }
                                .buttonStyle(BeaconSecondaryButtonStyle())
                            }
                        }

                        field("Local App URL to Monitor", placeholder: "http://localhost:5173 or http://127.0.0.1:3000", text: $monitorURL)

                        Divider().overlay(palette.subtleBorder)

                        HStack {
                            Text("Build & Run Commands")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.sectionHeader)
                            Spacer()
                            Button {
                                detectScriptsFromPackageJSON(silentIfMissing: false)
                            } label: {
                                Label("Detect from package.json", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                            .disabled(localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let note = detectedScriptsNote {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.successText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .beaconGlassRow(cornerRadius: 8, padding: 9)
                        }

                        field("Dependency Install Command (auto = detect npm/pnpm/yarn/bun)", placeholder: "auto", text: $installCommand)
                        field("Build Command (auto = run build only if script exists; blank = skip)", placeholder: "auto", text: $buildCommand)
                        field("Start Command (auto = detect dev/start/serve script)", placeholder: "auto", text: $startCommand)

                        Divider().overlay(palette.subtleBorder)

                        HStack(spacing: 20) {
                            Toggle("Auto-restart on crash", isOn: $autoRestart)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            Toggle("Auto-deploy on Git push", isOn: $autoDeploy)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            Toggle("Run on macOS startup / cron", isOn: $runOnStartup)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(palette.bodyText)
                    }
                    .beaconGlassCard(cornerRadius: 14, padding: 16)
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
        }
        .frame(width: 640, height: 650)
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

    private func detectScriptsFromPackageJSON(silentIfMissing: Bool) {
        let dir = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return }
        let pkgURL = URL(fileURLWithPath: dir).appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: pkgURL.path) else {
            if !silentIfMissing {
                detectedScriptsNote = "No package.json found at \(dir) yet. Using \"auto\" will detect scripts right after cloning."
            }
            return
        }
        guard let data = try? Data(contentsOf: pkgURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if !silentIfMissing {
                detectedScriptsNote = "Could not parse package.json at \(dir)."
            }
            return
        }

        let fm = FileManager.default
        let pm: String
        if fm.fileExists(atPath: URL(fileURLWithPath: dir).appendingPathComponent("pnpm-lock.yaml").path) {
            pm = "pnpm"
        } else if fm.fileExists(atPath: URL(fileURLWithPath: dir).appendingPathComponent("yarn.lock").path) {
            pm = "yarn"
        } else if fm.fileExists(atPath: URL(fileURLWithPath: dir).appendingPathComponent("bun.lock").path)
                    || fm.fileExists(atPath: URL(fileURLWithPath: dir).appendingPathComponent("bun.lockb").path) {
            pm = "bun"
        } else {
            pm = "npm"
        }

        let scripts = json["scripts"] as? [String: String] ?? [:]
        let scriptNames = scripts.keys.sorted()
        let port = LocalProcessService.extractPort(from: monitorURL, fallback: 5173)

        installCommand = "auto"

        if scripts["build"] != nil {
            buildCommand = "\(pm) run build"
        } else {
            buildCommand = ""
        }

        if let devScript = scripts["dev"] {
            if devScript.localizedCaseInsensitiveContains("vite")
                || devScript.localizedCaseInsensitiveContains("astro")
                || devScript.localizedCaseInsensitiveContains("nuxt") {
                startCommand = "\(pm) run dev -- --port \(port)"
            } else if devScript.localizedCaseInsensitiveContains("next") {
                startCommand = "\(pm) run dev -- -p \(port)"
            } else {
                startCommand = "\(pm) run dev"
            }
        } else if scripts["start"] != nil {
            startCommand = "\(pm) start"
        } else if scripts["serve"] != nil {
            startCommand = "\(pm) run serve"
        } else if scripts["preview"] != nil {
            startCommand = "\(pm) run preview"
        } else if let mainFile = json["main"] as? String, !mainFile.isEmpty {
            startCommand = "node \(mainFile)"
        } else {
            startCommand = "auto"
        }

        let list = scriptNames.isEmpty ? "none" : scriptNames.joined(separator: ", ")
        let buildSummary = scripts["build"] != nil ? "build enabled" : "build skipped (no \"build\" script)"
        detectedScriptsNote = "Detected \(pm) scripts [\(list)] — \(buildSummary)."
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.primaryText)
                .beaconGlassInput()
        }
    }
}
