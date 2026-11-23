import SwiftUI

struct ConfigurationView: View {
    @Bindable var controller: BeaconController
    @State private var draft: BeaconConfig = .defaults
    @State private var expanded: Bool = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let inputBackground = Color(red: 0.043, green: 0.051, blue: 0.063)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration & Alerts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Persisted to flat file \(controller.flatFileStore.configFileURL.lastPathComponent) · Secrets stored in macOS Keychain")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(expanded ? "Hide Settings" : "Edit Settings") {
                    if !expanded { draft = controller.config }
                    expanded.toggle()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                Divider().overlay(Color.white.opacity(0.08))

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        fieldLabel("Local Project Folder")
                        HStack(spacing: 8) {
                            TextField("/Users/you/my-vite-app", text: $draft.workingDir)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button("Browse...") {
                                controller.chooseProjectFolder()
                                draft.workingDir = controller.config.workingDir
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }

                    GridRow {
                        fieldLabel("GitHub Repo (owner/repo)")
                        HStack(spacing: 8) {
                            TextField("username/repo", text: $draft.gitRepoFullName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))

                            TextField("main", text: $draft.gitBranch)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 110)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }

                    GridRow {
                        fieldLabel("Ollama Loopback Endpoint")
                        TextField("http://127.0.0.1:11434", text: $draft.ollamaEndpoint)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    GridRow {
                        fieldLabel("Alert Email Recipient")
                        HStack(spacing: 8) {
                            TextField("ops@example.com", text: $draft.recipientEmail)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Button("Test Alert") {
                                Task { await controller.sendTestAlert() }
                            }
                            .buttonStyle(BeaconSecondaryButtonStyle())
                        }
                    }
                }

                HStack {
                    Toggle("Alert on crash", isOn: $draft.notifyOnCrash)
                    Toggle("Alert on deploy", isOn: $draft.notifyOnDeploy)
                    Toggle("Alert on Ollama offline", isOn: $draft.notifyOnOllamaDown)
                    Spacer()
                    Button("Save Configuration") {
                        Task {
                            await controller.saveConfiguration(draft)
                            expanded = false
                        }
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 170, alignment: .leading)
    }
}
