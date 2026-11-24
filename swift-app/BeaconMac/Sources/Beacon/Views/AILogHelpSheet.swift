import AppKit
import SwiftUI

struct AILogHelpSheet: View {
    @Bindable var controller: BeaconController
    let context: AILogContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: AIHelpProvider = .auto
    @State private var followUpQuestion: String = ""
    @State private var showRawLogs: Bool = false
    @State private var copiedLogs = false
    @State private var copiedPrompt = false
    @State private var copiedAnswer = false

    private let canvasBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let terminalBackground = Color(red: 0.031, green: 0.037, blue: 0.047)

    private var hasConnectedAI: Bool {
        controller.claude.isConnected || controller.ollama.isConnected || controller.keychain.read(.claudeAPIKey) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.cyan)
                            .font(.system(size: 14, weight: .semibold))
                        Text("AI Log Troubleshooter — \(context.title)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Secrets are automatically redacted before analysis · Powered by your connected Local Ollama or Claude API")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIHelpProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 135)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            // Provider readiness strip + quick copy buttons
            HStack(spacing: 12) {
                providerIndicator(
                    label: "Claude API",
                    connected: controller.claude.isConnected,
                    detail: controller.claude.isConnected ? controller.claude.activeModel : "Not connected"
                )
                providerIndicator(
                    label: "Local Ollama",
                    connected: controller.ollama.isConnected,
                    detail: controller.ollama.isConnected ? controller.ollama.activeModel : "Offline"
                )

                Spacer()

                Button(copiedLogs ? "Copied Logs ✓" : "Copy Logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(context.logText, forType: .string)
                    flashFlag($copiedLogs)
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button(copiedPrompt ? "Copied Prompt ✓" : "Copy AI Prompt") {
                    let prompt = controller.buildAITroubleshootingPrompt(context: context, followUp: followUpQuestion)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt, forType: .string)
                    flashFlag($copiedPrompt)
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button(showRawLogs ? "Hide Logs" : "View Logs") {
                    showRawLogs.toggle()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if showRawLogs {
                ScrollView([.vertical, .horizontal]) {
                    Text(context.logText.isEmpty ? "(No log output captured yet)" : context.logText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.86))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 120)
                .background(terminalBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Custom question + trigger
            HStack(spacing: 8) {
                TextField("Optional question (e.g. \"Why is localhost:3001 failing?\" or leave blank for full diagnosis)", text: $followUpQuestion)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(terminalBackground)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.14)))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onSubmit {
                        runAnalysis()
                    }

                Button(controller.isAnalyzingLogs ? "Analyzing…" : "Analyze with AI") {
                    runAnalysis()
                }
                .disabled(controller.isAnalyzingLogs || context.logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }

            // AI Diagnosis Output
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if controller.isAnalyzingLogs {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing redacted logs…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                    } else if let result = controller.aiHelpResult {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(result.ok ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(result.ok
                                 ? "Diagnosis via \(result.providerLabel) · \(result.durationMs) ms"
                                 : result.providerLabel)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(result.ok ? .white.opacity(0.88) : .orange)
                        }
                    } else {
                        Text("AI Troubleshooting Output")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let answer = controller.aiHelpResult?.answer, !answer.isEmpty {
                        Button(copiedAnswer ? "Copied Answer ✓" : "Copy Answer") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(answer, forType: .string)
                            flashFlag($copiedAnswer)
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())
                    }
                }

                ScrollView {
                    Group {
                        if let result = controller.aiHelpResult {
                            if result.ok {
                                Text(result.answer)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.94))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(result.error ?? "Unable to analyze logs.")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.orange)
                                        .textSelection(.enabled)
                                    Text("Tip: You can connect a Claude API key or start Local Ollama (port 11434) in the Service Cards, or click \"Copy AI Prompt\" above to paste these redacted logs into any AI tool.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        } else if !controller.isAnalyzingLogs {
                            Text(hasConnectedAI
                                 ? "Click \"Analyze with AI\" above to diagnose these logs."
                                 : "No AI provider connected yet. Connect Claude API or start Local Ollama in BeaconMac, or click \"Copy AI Prompt\" above to copy a ready-to-paste troubleshooting prompt.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                }
                .frame(minHeight: 280, maxHeight: .infinity)
                .background(terminalBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 540)
        .background(canvasBackground)
        .onAppear {
            controller.aiHelpResult = nil
            if hasConnectedAI && !context.logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runAnalysis()
            }
        }
    }

    private func runAnalysis() {
        let provider = selectedProvider
        let q = followUpQuestion
        Task {
            await controller.analyzeLogsWithAI(context: context, followUp: q, provider: provider)
        }
    }

    private func providerIndicator(label: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("\(label):")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(connected ? .white.opacity(0.9) : .secondary)
                .lineLimit(1)
        }
    }

    private func flashFlag(_ binding: Binding<Bool>) {
        binding.wrappedValue = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            binding.wrappedValue = false
        }
    }
}
