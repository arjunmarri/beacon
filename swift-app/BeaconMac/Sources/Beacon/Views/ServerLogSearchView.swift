import SwiftUI

struct ServerLogSearchView: View {
    @Bindable var controller: BeaconController
    @State private var query: String = ""
    @State private var options = ServerLogSearchOptions()
    @State private var showModal = false
    @State private var copiedResults = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let terminalBackground = Color(red: 0.035, green: 0.041, blue: 0.052)

    private let quickPresets: [(label: String, pattern: String)] = [
        ("Errors / Warn", "ERROR|WARN|fail|Exception"),
        ("Ports / Listen", "EADDRINUSE|localhost:|127\\.0\\.0\\.1:|port\\s+[0-9]+"),
        ("launchd / Sleep", "launchd|caffeinate|startup"),
        ("Deploy / Build", "deploy|build|npm|vite")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Server Log Search (grep / regex)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Target file: \(controller.launchd.serverLogPath) · supports extended regex (-E), literal match (-F), and context lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Tail in Terminal") {
                    controller.watchSupervisorLiveLogs()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Open Modal") {
                    showModal = true
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            searchControlsRow

            HStack(spacing: 6) {
                Text("Presets:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(quickPresets, id: \.label) { preset in
                    Button(preset.label) {
                        query = preset.pattern
                        options.useRegex = true
                        runSearch()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let result = controller.serverLogSearchResult {
                resultsBlock(result: result, height: 220)
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showModal) {
            ServerLogSearchModalSheet(
                controller: controller,
                query: $query,
                options: $options,
                onSearch: runSearch
            )
        }
    }

    private var searchControlsRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("grep / regex pattern on ~/beaconmac/server.log (e.g. ERROR|EADDRINUSE)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .onSubmit {
                        runSearch()
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        controller.clearServerLogSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear pattern and results")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(terminalBackground)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            toggleChip(label: "Regex -E", active: options.useRegex) {
                options.useRegex.toggle()
            }
            .help("Use Extended Regular Expressions (grep -E) vs Fixed String (grep -F)")

            toggleChip(label: "Aa", active: options.caseSensitive) {
                options.caseSensitive.toggle()
            }
            .help("Case-sensitive match (omits -i)")

            toggleChip(label: "±2", active: options.includeContext) {
                options.includeContext.toggle()
            }
            .help("Include 2 lines of surrounding context (grep -C 2)")

            Button(controller.isSearchingServerLog ? "Searching…" : "Search") {
                runSearch()
            }
            .disabled(query.trimmingCharacters(in: .newlines).isEmpty || controller.isSearchingServerLog)
            .buttonStyle(BeaconPrimaryButtonStyle())

            if controller.serverLogSearchResult != nil {
                Button("Clear") {
                    query = ""
                    controller.clearServerLogSearch()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func resultsBlock(result: ServerLogSearchResult, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("$ \(result.commandPreview)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                if result.ok {
                    Text(result.truncated
                         ? "\(result.matchCount)+ matches (capped) · \(result.durationMs) ms"
                         : "\(result.matchCount) \(result.matchCount == 1 ? "match" : "matches") · \(result.durationMs) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(result.matchCount > 0 ? .green : .secondary)
                } else {
                    Text("Search Error · \(result.durationMs) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.9))
                }

                if !result.preformattedOutput.isEmpty {
                    Button(copiedResults ? "Copied ✓" : "Copy Results") {
                        controller.copyServerLogSearchResults()
                        copiedResults = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedResults = false
                        }
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())

                    Button("AI Help") {
                        controller.openAIHelp(
                            title: "Server Log Search (\(result.query))",
                            logText: "$ \(result.commandPreview)\n\n\(result.preformattedOutput)"
                        )
                    }
                    .buttonStyle(BeaconPrimaryButtonStyle())
                }
            }

            ServerLogPreformattedOutputView(result: result, background: terminalBackground)
                .frame(height: height)
        }
    }

    private func toggleChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: active ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(active ? .cyan : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(active ? Color.cyan.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Color.cyan.opacity(0.4) : Color.white.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func runSearch() {
        let pattern = query
        let currentOptions = options
        Task {
            await controller.searchServerLog(query: pattern, options: currentOptions)
        }
    }
}

struct ServerLogPreformattedOutputView: View {
    let result: ServerLogSearchResult
    let background: Color

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Group {
                if !result.ok {
                    Text(result.errorMessage ?? "Unable to search \(result.logPath).")
                        .foregroundStyle(.red.opacity(0.92))
                } else if result.preformattedOutput.isEmpty {
                    Text("No lines matched \"\(result.query)\" in \(result.logPath).")
                        .foregroundStyle(.secondary)
                } else {
                    Text(result.preformattedOutput)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            .monospacedDigit()
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ServerLogSearchModalSheet: View {
    @Bindable var controller: BeaconController
    @Binding var query: String
    @Binding var options: ServerLogSearchOptions
    let onSearch: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copiedModalResults = false

    private let canvasBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    private let terminalBackground = Color(red: 0.031, green: 0.037, blue: 0.047)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Server Log Search — \(controller.launchd.serverLogPath)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Full-view grep / regex search with preserved formatting and horizontal scrolling")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                TextField("grep or regex pattern...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(terminalBackground)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.14)))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onSubmit { onSearch() }

                Toggle("Regex (-E)", isOn: $options.useRegex)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))

                Toggle("Case", isOn: $options.caseSensitive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))

                Toggle("±2 Context", isOn: $options.includeContext)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))

                Button(controller.isSearchingServerLog ? "Searching…" : "Search") {
                    onSearch()
                }
                .disabled(query.trimmingCharacters(in: .newlines).isEmpty || controller.isSearchingServerLog)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }

            if let result = controller.serverLogSearchResult {
                HStack(spacing: 10) {
                    Text("$ \(result.commandPreview)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    if result.ok {
                        Text(result.truncated
                             ? "\(result.matchCount)+ matches (capped) · \(result.durationMs) ms"
                             : "\(result.matchCount) \(result.matchCount == 1 ? "match" : "matches") · \(result.durationMs) ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(result.matchCount > 0 ? .green : .secondary)
                    } else {
                        Text("Search Error · \(result.durationMs) ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    if !result.preformattedOutput.isEmpty {
                        Button(copiedModalResults ? "Copied ✓" : "Copy Results") {
                            controller.copyServerLogSearchResults()
                            copiedModalResults = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copiedModalResults = false
                            }
                        }
                        .buttonStyle(BeaconSecondaryButtonStyle())

                        Button("AI Help") {
                            dismiss()
                            controller.openAIHelp(
                                title: "Server Log Search (\(result.query))",
                                logText: "$ \(result.commandPreview)\n\n\(result.preformattedOutput)"
                            )
                        }
                        .buttonStyle(BeaconPrimaryButtonStyle())
                    }
                }

                ServerLogPreformattedOutputView(result: result, background: terminalBackground)
                    .frame(minHeight: 360, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Enter a grep or regex pattern above and press Return to search \(controller.launchd.serverLogPath).")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                .background(terminalBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 540)
        .background(canvasBackground)
    }
}
