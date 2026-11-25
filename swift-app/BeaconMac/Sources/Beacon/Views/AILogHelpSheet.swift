import AppKit
import SwiftUI

struct AILogHelpSheet: View {
    @Bindable var controller: BeaconController
    let context: AILogContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedProvider: AIHelpProvider = .auto
    @State private var followUpQuestion: String = ""
    @State private var showRawLogs: Bool = false
    @State private var copiedLogs = false
    @State private var copiedPrompt = false
    @State private var copiedAnswer = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var hasConnectedAI: Bool {
        controller.hasAnyConnectedAIProvider
    }

    private var connectedProviderBadges: [(label: String, connected: Bool, detail: String)] {
        var items: [(String, Bool, String)] = []

        if controller.claude.isConnected {
            items.append(("Claude", true, controller.claude.activeModel))
        }
        let cloudOrder: [(CloudProviderKind, String)] = [
            (.openai, "ChatGPT"),
            (.gemini, "Gemini"),
            (.openrouter, "OpenRouter"),
            (.groq, "Groq"),
            (.cloudflare, "Cloudflare AI"),
            (.customOpenAI, "Custom AI")
        ]
        for (kind, label) in cloudOrder {
            let st = controller.cloudProviderState(for: kind)
            if st.isConnected {
                let model = controller.cloudProviderConfig(for: kind).selectedModel
                items.append((label, true, model.isEmpty ? kind.defaultModel : model))
            }
        }
        if controller.ollama.isConnected {
            items.append(("Ollama", true, controller.ollama.activeModel))
        }

        if items.isEmpty {
            items = [
                ("Cloud AI APIs", false, "Connect ChatGPT, Gemini, or Claude in Settings"),
                ("Local Ollama", false, "Offline")
            ]
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(palette.sectionHeader)
                            .font(.system(size: 14, weight: .semibold))
                        BeaconSectionHeaderText(title: "AI Log Troubleshooter — \(context.title)", fontSize: 16)
                    }
                    Text("Secrets are automatically redacted before analysis · Powered by ChatGPT, Gemini, Claude, OpenRouter, Groq, Cloudflare AI, or Local Ollama")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIHelpProvider.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 175)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            // Provider readiness strip + quick copy buttons
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(connectedProviderBadges, id: \.label) { badge in
                            providerIndicator(
                                label: badge.label,
                                connected: badge.connected,
                                detail: badge.detail
                            )
                        }
                    }
                }

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
            .background(palette.card)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if showRawLogs {
                ScrollView([.vertical, .horizontal]) {
                    Text(context.logText.isEmpty ? "(No log output captured yet)" : context.logText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.bodyText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 120)
                .background(palette.console)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Custom question + trigger
            HStack(spacing: 8) {
                TextField("Optional question (e.g. \"Why is localhost:3001 failing?\" or leave blank for full diagnosis)", text: $followUpQuestion)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
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
                                .foregroundStyle(palette.accentLink)
                        }
                    } else if let result = controller.aiHelpResult {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(result.ok ? palette.successText : palette.warningText)
                                .frame(width: 7, height: 7)
                            Text(result.ok
                                 ? "Diagnosis via \(result.providerLabel) · \(result.durationMs) ms"
                                 : result.providerLabel)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(result.ok ? palette.bodyText : palette.warningText)
                        }
                    } else {
                        Text("AI Troubleshooting Output")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
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
                                    .foregroundStyle(palette.primaryText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(result.error ?? "Unable to analyze logs.")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(palette.warningText)
                                        .textSelection(.enabled)
                                    Text("Tip: Connect ChatGPT (OpenAI), Google Gemini, Claude, OpenRouter, Groq, or Cloudflare AI in Settings, start Local Ollama (port 11434), or click \"Copy AI Prompt\" above.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        } else if !controller.isAnalyzingLogs {
                            Text(hasConnectedAI
                                 ? "Click \"Analyze with AI\" above to diagnose these logs."
                                 : "No AI provider connected yet. Connect ChatGPT, Google Gemini, Claude, OpenRouter, Groq, or Cloudflare AI in Settings (or start Local Ollama), or click \"Copy AI Prompt\" above.")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                }
                .frame(minHeight: 280, maxHeight: .infinity)
                .background(palette.console)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 540)
        .background(palette.sheetCanvas)
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
                .fill(connected ? palette.successText : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("\(label):")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(connected ? palette.bodyText : palette.secondaryText)
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
