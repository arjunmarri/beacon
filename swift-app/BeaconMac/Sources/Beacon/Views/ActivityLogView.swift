import AppKit
import SwiftUI

struct ActivityLogView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSource: LogSource? = nil
    @State private var searchQuery: String = ""
    @State private var autoScrollEnabled = true
    @State private var pausedNewEntriesCount = 0
    @State private var copiedLogs = false
    @State private var exportedLogs = false
    @State private var copiedEntryID: String?
    @State private var hoveredEntryID: String?

    private let bottomAnchorID = "activity-log-bottom-anchor"

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var hasActiveFilter: Bool {
        selectedSource != nil || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Chronological order (oldest → newest) so newly appended lines appear at the bottom
    /// and auto-scroll smoothly tracks the latest entry.
    private var filteredLogs: [LogEntry] {
        controller.logs.filter { entry in
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
        filteredLogs.map(formatEntry).joined(separator: "\n")
    }

    private func copySingleEntry(_ entry: LogEntry, messageOnly: Bool = false) {
        let payload = messageOnly ? entry.message : formatEntry(entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }

    private func triggerExport(format: LogExportFormat, filteredOnly: Bool) {
        let chronologicalFiltered = filteredOnly ? filteredLogs : nil
        var scopeParts: [String] = []
        if let selectedSource {
            scopeParts.append("source=\(selectedSource.rawValue)")
        }
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            scopeParts.append("query=\"\(trimmedQuery)\"")
        }
        let scopeDesc = filteredOnly
            ? "Filtered Activity Logs (\(scopeParts.joined(separator: ", "))) + Deployment Output"
            : nil

        let ok = controller.exportSessionLogs(
            format: format,
            filteredActivityLogs: chronologicalFiltered,
            scopeDescription: scopeDesc
        )
        if ok {
            exportedLogs = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                exportedLogs = false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Real-Time Activity Log", fontSize: 15.5)
                    Text("Flat file: \(controller.flatFileStore.logFileURL.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: controller.logFileBytes, countStyle: .file)) · Hover or right-click any entry to copy or ask AI")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                TextField("Filter logs...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: 160)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Button {
                    autoScrollEnabled.toggle()
                    if autoScrollEnabled {
                        pausedNewEntriesCount = 0
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(autoScrollEnabled
                             ? "Pause auto-scroll"
                             : (pausedNewEntriesCount > 0 ? "Resume auto-scroll (\(pausedNewEntriesCount))" : "Resume auto-scroll"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(autoScrollEnabled ? palette.primaryText : palette.warningText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(autoScrollEnabled ? palette.chipFill : Color.orange.opacity(palette.isLight ? 0.14 : 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(autoScrollEnabled ? palette.inputBorder : Color.orange.opacity(0.45))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(autoScrollEnabled
                      ? "Pause automatic scrolling to inspect earlier log entries"
                      : "Resume automatic scrolling and jump to the latest log entry")

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

                Menu {
                    Button {
                        triggerExport(format: .txt, filteredOnly: false)
                    } label: {
                        Label("Export All Session Logs (.txt)", systemImage: "doc.plaintext")
                    }

                    Button {
                        triggerExport(format: .json, filteredOnly: false)
                    } label: {
                        Label("Export All Session Logs (.json)", systemImage: "curlybraces")
                    }

                    if hasActiveFilter {
                        Divider()

                        Button {
                            triggerExport(format: .txt, filteredOnly: true)
                        } label: {
                            Label("Export Filtered View (.txt)", systemImage: "line.3.horizontal.decrease.circle")
                        }

                        Button {
                            triggerExport(format: .json, filteredOnly: true)
                        } label: {
                            Label("Export Filtered View (.json)", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: exportedLogs ? "checkmark" : "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text(exportedLogs ? "Exported ✓" : "Export Logs")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(palette.chipFill)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(controller.logs.isEmpty && controller.terminalLines.isEmpty)
                .help("Save all current session logs (system, Git, and deployment output) as .txt or .json")

                Button("Clear") {
                    pausedNewEntriesCount = 0
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if filteredLogs.isEmpty {
                            Text("No log entries match the active filter.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                                .padding(12)
                        } else {
                            ForEach(filteredLogs) { entry in
                                let isCopied = copiedEntryID == entry.id
                                let isHovered = hoveredEntryID == entry.id

                                HStack(alignment: .top, spacing: 10) {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .foregroundStyle(palette.secondaryText)
                                        .frame(width: 72, alignment: .leading)
                                    Text(entry.source.rawValue)
                                        .foregroundStyle(sourceColor(entry.source))
                                        .frame(width: 64, alignment: .leading)
                                    Text(entry.level.rawValue)
                                        .foregroundStyle(levelColor(entry.level))
                                        .frame(width: 42, alignment: .leading)
                                    Text(entry.message)
                                        .foregroundStyle(palette.bodyText)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        copySingleEntry(entry)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 10, weight: .semibold))
                                            if isCopied {
                                                Text("Copied")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                        }
                                        .foregroundStyle(
                                            isCopied
                                                ? palette.successText
                                                : (isHovered ? palette.primaryText : palette.secondaryText.opacity(0.65))
                                        )
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            isCopied
                                                ? palette.successText.opacity(0.14)
                                                : (isHovered ? palette.chipFill : Color.clear)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy this log entry")
                                }
                                .font(.system(size: 11.5, design: .monospaced))
                                .monospacedDigit()
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(isHovered ? palette.hoverFill : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .onHover { hovering in
                                    if hovering {
                                        hoveredEntryID = entry.id
                                    } else if hoveredEntryID == entry.id {
                                        hoveredEntryID = nil
                                    }
                                }
                                .contextMenu {
                                    Button("Copy Entry") {
                                        copySingleEntry(entry)
                                    }
                                    Button("Copy Message Only") {
                                        copySingleEntry(entry, messageOnly: true)
                                    }
                                    Button("Copy All Filtered Logs") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(formattedFilteredLogs, forType: .string)
                                    }
                                    Divider()
                                    Button("Export All Session Logs (.txt)") {
                                        triggerExport(format: .txt, filteredOnly: false)
                                    }
                                    Button("Export All Session Logs (.json)") {
                                        triggerExport(format: .json, filteredOnly: false)
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

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if autoScrollEnabled && !filteredLogs.isEmpty {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
                .onChange(of: controller.logs.last?.id) { _, newID in
                    guard let newID else {
                        pausedNewEntriesCount = 0
                        return
                    }
                    guard filteredLogs.last?.id == newID else { return }
                    if autoScrollEnabled {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    } else {
                        pausedNewEntriesCount += 1
                    }
                }
                .onChange(of: selectedSource) { _, _ in
                    if autoScrollEnabled && !filteredLogs.isEmpty {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
                .onChange(of: searchQuery) { _, _ in
                    if autoScrollEnabled && !filteredLogs.isEmpty {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
                .onChange(of: autoScrollEnabled) { _, enabled in
                    if enabled && !filteredLogs.isEmpty {
                        pausedNewEntriesCount = 0
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 240)
            .background(palette.console)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
    }

    private func filterButton(label: String, source: LogSource?) -> some View {
        let active = selectedSource == source
        return Button(label) {
            selectedSource = source
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: active ? .semibold : .medium))
        .foregroundStyle(active ? palette.sectionHeader : palette.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(active ? palette.activeChipFill : palette.chipFill)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? palette.sectionHeader.opacity(0.4) : palette.subtleBorder))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sourceColor(_ source: LogSource) -> Color {
        if palette.isLight {
            switch source {
            case .vite: return Color(red: 0.06, green: 0.42, blue: 0.78)
            case .git: return Color(red: 0.48, green: 0.18, blue: 0.78)
            case .ollama: return Color(red: 0.05, green: 0.50, blue: 0.28)
            case .claude: return Color(red: 0.76, green: 0.36, blue: 0.04)
            case .terminal: return Color(red: 0.04, green: 0.52, blue: 0.48)
            case .startup: return Color(red: 0.06, green: 0.46, blue: 0.56)
            case .email: return Color(red: 0.68, green: 0.48, blue: 0.0)
            case .system: return Color(red: 0.36, green: 0.42, blue: 0.52)
            }
        }
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
        case .info: return palette.secondaryText
        case .warn: return palette.warningText
        case .error: return palette.errorText
        }
    }
}
