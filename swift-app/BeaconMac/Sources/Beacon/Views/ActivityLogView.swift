import AppKit
import SwiftUI

struct ActivityLogView: View {
    @Bindable var controller: BeaconController
    @State private var selectedSource: LogSource? = nil
    @State private var searchQuery: String = ""
    @State private var copiedLogs = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let terminalBackground = Color(red: 0.043, green: 0.051, blue: 0.063)

    private var filteredLogs: [LogEntry] {
        controller.logs.reversed().filter { entry in
            if let selectedSource, entry.source != selectedSource {
                return false
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                return entry.message.lowercased().contains(q) || entry.source.rawValue.contains(q)
            }
            return true
        }
    }

    private func formatEntry(_ entry: LogEntry) -> String {
        let ts = entry.timestamp.formatted(date: .omitted, time: .standard)
        return "\(ts) [\(entry.level.rawValue.uppercased())] [\(entry.source.rawValue)] \(entry.message)"
    }

    private var formattedFilteredLogs: String {
        filteredLogs.reversed().map(formatEntry).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-Time Activity Log")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Flat file: \(controller.flatFileStore.logFileURL.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: controller.logFileBytes, countStyle: .file)) · Right-click any entry to copy or ask AI")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Filter logs...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: 170)
                    .background(terminalBackground)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1)))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Button(copiedLogs ? "Copied ✓" : "Copy Logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formattedFilteredLogs, forType: .string)
                    copiedLogs = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedLogs = false
                    }
                }
                .disabled(filteredLogs.isEmpty)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("AI Help") {
                    controller.openAIHelp(
                        title: "Real-Time Activity Log",
                        logText: formattedFilteredLogs
                    )
                }
                .disabled(filteredLogs.isEmpty)
                .buttonStyle(BeaconPrimaryButtonStyle())

                Button("Export .log") {
                    controller.exportActivityLog()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Clear") {
                    controller.clearLogs()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            HStack(spacing: 6) {
                filterButton(label: "All", source: nil)
                ForEach(LogSource.allCases) { source in
                    filterButton(label: source.label, source: source)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredLogs.isEmpty {
                        Text("No log entries match the active filter.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                Text(entry.source.rawValue)
                                    .foregroundStyle(sourceColor(entry.source))
                                    .frame(width: 64, alignment: .leading)
                                Text(entry.level.rawValue)
                                    .foregroundStyle(levelColor(entry.level))
                                    .frame(width: 42, alignment: .leading)
                                Text(entry.message)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 11.5, design: .monospaced))
                            .monospacedDigit()
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .contextMenu {
                                Button("Copy Entry") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(formatEntry(entry), forType: .string)
                                }
                                Button("Copy All Filtered Logs") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(formattedFilteredLogs, forType: .string)
                                }
                                Divider()
                                Button("Ask AI About This Entry") {
                                    controller.openAIHelp(
                                        title: "Activity Log (\(entry.source.label))",
                                        logText: formatEntry(entry)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 230)
            .background(terminalBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func filterButton(label: String, source: LogSource?) -> some View {
        let active = selectedSource == source
        return Button(label) {
            selectedSource = source
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: active ? .semibold : .medium))
        .foregroundStyle(active ? .white : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(active ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sourceColor(_ source: LogSource) -> Color {
        switch source {
        case .vite: return .cyan
        case .git: return .purple
        case .ollama: return .green
        case .claude: return .orange
        case .terminal: return .mint
        case .startup: return .teal
        case .email: return .yellow
        case .system: return .gray
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
