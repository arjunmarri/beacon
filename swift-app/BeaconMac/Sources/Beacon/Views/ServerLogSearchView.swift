import AppKit
import SwiftUI

struct ServerLogSearchView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var query: String = ""
    @State private var options = ServerLogSearchOptions()
    @State private var showModal = false
    @State private var copiedResults = false
    @State private var autoScrollEnabled = true

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    private let quickPresets: [(label: String, pattern: String)] = [
        ("Errors / Warn", "ERROR|WARN|fail|Exception"),
        ("Ports / Listen", "EADDRINUSE|localhost:|127\\.0\\.0\\.1:|port\\s+[0-9]+"),
        ("launchd / Sleep", "launchd|caffeinate|startup"),
        ("Deploy / Build", "deploy|build|npm|vite")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Server Log Search (grep / regex)", fontSize: 15.5)
                    Text("Target file: \(controller.launchd.serverLogPath) · supports extended regex (-E), literal match (-F), and per-entry copy")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
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
                    .foregroundStyle(palette.secondaryText)

                ForEach(quickPresets, id: \.label) { preset in
                    Button(preset.label) {
                        query = preset.pattern
                        options.useRegex = true
                        runSearch()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.bodyText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.chipFill)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.subtleBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let result = controller.serverLogSearchResult {
                resultsBlock(result: result, height: 220)
            }
        }
        .padding(18)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.cardShadow, radius: 6, y: 2)
        .sheet(isPresented: $showModal) {
            ServerLogSearchModalSheet(
                controller: controller,
                query: $query,
                options: $options,
                autoScrollEnabled: $autoScrollEnabled,
                onSearch: runSearch
            )
            .preferredColorScheme(activeScheme)
        }
    }

    private var searchControlsRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)

                TextField("grep / regex pattern on ~/beaconmac/server.log (e.g. ERROR|EADDRINUSE)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
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
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Clear pattern and results")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(palette.input)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
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
                    .foregroundStyle(palette.accentLink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                if result.ok {
                    Text(result.truncated
                         ? "\(result.matchCount)+ matches (capped) · \(result.durationMs) ms"
                         : "\(result.matchCount) \(result.matchCount == 1 ? "match" : "matches") · \(result.durationMs) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(result.matchCount > 0 ? palette.successText : palette.secondaryText)
                } else {
                    Text("Search Error · \(result.durationMs) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.errorText)
                }

                if !result.preformattedOutput.isEmpty {
                    Button {
                        autoScrollEnabled.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(autoScrollEnabled ? "Pause auto-scroll" : "Resume auto-scroll")
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
                          ? "Pause automatic scrolling to latest matched server log entry"
                          : "Resume automatic scrolling and jump to the latest matched entry")

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

            ServerLogPreformattedOutputView(
                result: result,
                background: palette.console,
                autoScrollEnabled: autoScrollEnabled,
                onAskAI: { entryText in
                    controller.openAIHelp(
                        title: "Server Log Entry (\(result.query))",
                        logText: entryText
                    )
                }
            )
            .frame(height: height)
        }
    }

    private func toggleChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: active ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(active ? palette.sectionHeader : palette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(active ? palette.activeChipFill : palette.chipFill)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? palette.sectionHeader.opacity(0.45) : palette.inputBorder))
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

private struct ParsedServerLogLine: Identifiable, Equatable {
    let id: Int
    let lineNumberLabel: String?
    let isContextLine: Bool
    let isDivider: Bool
    let content: String
    let rawLine: String

    static func parse(_ output: String) -> [ParsedServerLogLine] {
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: "\n").enumerated().map { index, raw in
            if raw == "--" {
                return ParsedServerLogLine(
                    id: index,
                    lineNumberLabel: nil,
                    isContextLine: false,
                    isDivider: true,
                    content: "--",
                    rawLine: raw
                )
            }

            var cursor = raw.startIndex
            while cursor < raw.endIndex, raw[cursor].isNumber {
                cursor = raw.index(after: cursor)
            }

            if cursor > raw.startIndex, cursor < raw.endIndex, (raw[cursor] == ":" || raw[cursor] == "-") {
                let sep = raw[cursor]
                let numPart = String(raw[raw.startIndex..<cursor])
                let afterSep = raw.index(after: cursor)
                let body = String(raw[afterSep...])
                return ParsedServerLogLine(
                    id: index,
                    lineNumberLabel: "\(numPart)\(sep)",
                    isContextLine: sep == "-",
                    isDivider: false,
                    content: body,
                    rawLine: raw
                )
            }

            return ParsedServerLogLine(
                id: index,
                lineNumberLabel: nil,
                isContextLine: false,
                isDivider: false,
                content: raw,
                rawLine: raw
            )
        }
    }
}

struct ServerLogPreformattedOutputView: View {
    let result: ServerLogSearchResult
    let background: Color
    var autoScrollEnabled: Bool = true
    var onAskAI: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredRowID: Int?
    @State private var copiedRowID: Int?

    private let bottomAnchorID = "server-log-output-bottom-anchor"

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var parsedLines: [ParsedServerLogLine] {
        ParsedServerLogLine.parse(result.preformattedOutput)
    }

    private func copyLine(_ row: ParsedServerLogLine, includeLineNumber: Bool = false) {
        let text = includeLineNumber ? row.rawLine : row.content
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedRowID = row.id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedRowID == row.id {
                copiedRowID = nil
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !result.ok {
                        Text(result.errorMessage ?? "Unable to search \(result.logPath).")
                            .foregroundStyle(palette.errorText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    } else if parsedLines.isEmpty {
                        Text("No lines matched \"\(result.query)\" in \(result.logPath).")
                            .foregroundStyle(palette.secondaryText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .padding(12)
                    } else {
                        ForEach(parsedLines) { row in
                            if row.isDivider {
                                HStack(spacing: 8) {
                                    Rectangle()
                                        .fill(palette.border)
                                        .frame(height: 1)
                                    Text("context break")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(palette.secondaryText)
                                    Rectangle()
                                        .fill(palette.border)
                                        .frame(height: 1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                            } else {
                                let isCopied = copiedRowID == row.id
                                let isHovered = hoveredRowID == row.id

                                HStack(alignment: .top, spacing: 8) {
                                    if let numLabel = row.lineNumberLabel {
                                        Text(numLabel)
                                            .foregroundStyle(row.isContextLine ? palette.secondaryText : palette.accentLink)
                                            .frame(minWidth: 44, alignment: .trailing)
                                    }

                                    Text(row.content)
                                        .foregroundStyle(row.isContextLine ? palette.secondaryText : palette.bodyText)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        copyLine(row)
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
                                    .help("Copy this server log entry")
                                }
                                .font(.system(size: 11.5, design: .monospaced))
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(isHovered ? palette.hoverFill : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .onHover { hovering in
                                    if hovering {
                                        hoveredRowID = row.id
                                    } else if hoveredRowID == row.id {
                                        hoveredRowID = nil
                                    }
                                }
                                .contextMenu {
                                    Button("Copy Entry") {
                                        copyLine(row, includeLineNumber: false)
                                    }
                                    if row.lineNumberLabel != nil {
                                        Button("Copy With Line Number") {
                                            copyLine(row, includeLineNumber: true)
                                        }
                                    }
                                    Button("Copy All Matched Results") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(result.preformattedOutput, forType: .string)
                                    }
                                    if let onAskAI {
                                        Divider()
                                        Button("Ask AI About This Entry") {
                                            onAskAI(row.rawLine)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.vertical, 6)
            }
            .onAppear {
                if autoScrollEnabled && !parsedLines.isEmpty {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: result.preformattedOutput) { _, newValue in
                if autoScrollEnabled && !newValue.isEmpty {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: autoScrollEnabled) { _, enabled in
                if enabled && !parsedLines.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ServerLogSearchModalSheet: View {
    @Bindable var controller: BeaconController
    @Binding var query: String
    @Binding var options: ServerLogSearchOptions
    @Binding var autoScrollEnabled: Bool
    let onSearch: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedModalResults = false

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(title: "Server Log Search — \(controller.launchd.serverLogPath)", fontSize: 16)
                    Text("Full-view grep / regex search with auto-scroll controls and per-entry copy")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
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
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(palette.input)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.inputBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onSubmit { onSearch() }

                Toggle("Regex (-E)", isOn: $options.useRegex)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.bodyText)

                Toggle("Case", isOn: $options.caseSensitive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.bodyText)

                Toggle("±2 Context", isOn: $options.includeContext)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.bodyText)

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
                        .foregroundStyle(palette.accentLink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    if result.ok {
                        Text(result.truncated
                             ? "\(result.matchCount)+ matches (capped) · \(result.durationMs) ms"
                             : "\(result.matchCount) \(result.matchCount == 1 ? "match" : "matches") · \(result.durationMs) ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(result.matchCount > 0 ? palette.successText : palette.secondaryText)
                    } else {
                        Text("Search Error · \(result.durationMs) ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.errorText)
                    }

                    if !result.preformattedOutput.isEmpty {
                        Button {
                            autoScrollEnabled.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(autoScrollEnabled ? "Pause auto-scroll" : "Resume auto-scroll")
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

                ServerLogPreformattedOutputView(
                    result: result,
                    background: palette.console,
                    autoScrollEnabled: autoScrollEnabled,
                    onAskAI: { entryText in
                        dismiss()
                        controller.openAIHelp(
                            title: "Server Log Entry (\(result.query))",
                            logText: entryText
                        )
                    }
                )
                .frame(minHeight: 360, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Enter a grep or regex pattern above and press Return to search \(controller.launchd.serverLogPath).")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                .background(palette.console)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 540)
        .background(palette.sheetCanvas)
    }
}
