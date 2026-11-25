import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @Bindable var controller: BeaconController
    @Environment(\.colorScheme) private var colorScheme

    @State private var expanded = true
    @State private var autoScrollEnabled = true
    @State private var pausedNewLinesCount = 0
    @State private var copiedAll = false
    @State private var copiedErrors = false
    @State private var copiedLineID: String?
    @State private var hoveredLineID: String?

    private let bottomAnchorID = "terminal-output-bottom-anchor"

    private var palette: BeaconPalette {
        BeaconPalette(colorScheme: colorScheme)
    }

    private var errorLines: [TerminalOutputLine] {
        controller.terminalLines.filter { $0.isError || $0.text.localizedCaseInsensitiveContains("error") }
    }

    private func formatLine(_ line: TerminalOutputLine) -> String {
        let ts = line.timestamp.formatted(date: .omitted, time: .standard)
        return "\(ts) [\(line.appName)] \(line.text)"
    }

    private func formattedDump(_ lines: [TerminalOutputLine]) -> String {
        lines.map(formatLine).joined(separator: "\n")
    }

    private func copySingleLine(_ line: TerminalOutputLine, includeTimestamp: Bool = true) {
        let payload = includeTimestamp ? formatLine(line) : "[\(line.appName)] \(line.text)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        copiedLineID = line.id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedLineID == line.id {
                copiedLineID = nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    BeaconSectionHeaderText(
                        title: "Integrated Terminal Output",
                        fontSize: 15.5,
                        systemImage: "terminal.fill"
                    )
                    Text("Live stdout/stderr from git clone, dependency installs, builds, and local deploys · Hover or right-click any line to copy")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                }

                Spacer()

                Button {
                    autoScrollEnabled.toggle()
                    if autoScrollEnabled {
                        pausedNewLinesCount = 0
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: autoScrollEnabled ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(autoScrollEnabled
                             ? "Pause auto-scroll"
                             : (pausedNewLinesCount > 0 ? "Resume auto-scroll (\(pausedNewLinesCount))" : "Resume auto-scroll"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(autoScrollEnabled ? palette.primaryText : palette.warningText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(autoScrollEnabled ? palette.chipFill : Color.orange.opacity(palette.isLight ? 0.14 : 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .strokeBorder(autoScrollEnabled ? palette.border : Color.orange.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(autoScrollEnabled
                      ? "Pause automatic scrolling to inspect earlier terminal output"
                      : "Resume automatic scrolling and jump to the latest terminal line")

                Button(copiedAll ? "Copied ✓" : "Copy Output") {
                    copyToPasteboard(formattedDump(controller.terminalLines), flag: $copiedAll)
                }
                .disabled(controller.terminalLines.isEmpty)
                .buttonStyle(BeaconSecondaryButtonStyle())

                if !errorLines.isEmpty {
                    Button(copiedErrors ? "Copied Errors ✓" : "Copy Errors (\(errorLines.count))") {
                        copyToPasteboard(formattedDump(errorLines), flag: $copiedErrors)
                    }
                    .buttonStyle(BeaconSecondaryButtonStyle())
                }

                Button("Clear") {
                    pausedNewLinesCount = 0
                    controller.clearTerminal()
                }
                .disabled(controller.terminalLines.isEmpty)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button(expanded ? "Collapse" : "Expand") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if controller.terminalLines.isEmpty {
                                Text("Terminal output appears here when you run Check System Tools, Install Prerequisites, Check Deps, or Clone & Deploy.")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                                    .padding(12)
                            } else {
                                ForEach(controller.terminalLines) { line in
                                    let isCopied = copiedLineID == line.id
                                    let isHovered = hoveredLineID == line.id

                                    HStack(alignment: .top, spacing: 8) {
                                        Text(line.timestamp.formatted(date: .omitted, time: .standard))
                                            .foregroundStyle(palette.secondaryText)
                                            .frame(width: 72, alignment: .leading)
                                        Text("[\(line.appName)]")
                                            .foregroundStyle(palette.accentLink)
                                            .frame(width: 96, alignment: .leading)
                                            .lineLimit(1)
                                        Text(line.text)
                                            .foregroundStyle(line.isError ? palette.errorText : palette.bodyText)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Button {
                                            copySingleLine(line)
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
                                                    : (isHovered ? palette.primaryText : palette.secondaryText.opacity(0.60))
                                            )
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                isCopied
                                                    ? palette.successText.opacity(0.14)
                                                    : (isHovered ? palette.chipFill : Color.clear)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy this terminal log entry")
                                    }
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .monospacedDigit()
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(isHovered ? palette.hoverFill : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .onHover { hovering in
                                        if hovering {
                                            hoveredLineID = line.id
                                        } else if hoveredLineID == line.id {
                                            hoveredLineID = nil
                                        }
                                    }
                                    .contextMenu {
                                        Button("Copy Entry") {
                                            copySingleLine(line, includeTimestamp: true)
                                        }
                                        Button("Copy Message Only") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(line.text, forType: .string)
                                            copiedLineID = line.id
                                            Task {
                                                try? await Task.sleep(for: .seconds(1.8))
                                                if copiedLineID == line.id { copiedLineID = nil }
                                            }
                                        }
                                        Button("Copy All Output") {
                                            copyToPasteboard(formattedDump(controller.terminalLines), flag: $copiedAll)
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
                        if autoScrollEnabled && !controller.terminalLines.isEmpty {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                    .onChange(of: controller.terminalLines.last?.id) { _, newID in
                        guard newID != nil else {
                            pausedNewLinesCount = 0
                            return
                        }
                        if autoScrollEnabled {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                            }
                        } else {
                            pausedNewLinesCount += 1
                        }
                    }
                    .onChange(of: autoScrollEnabled) { _, enabled in
                        if enabled && !controller.terminalLines.isEmpty {
                            pausedNewLinesCount = 0
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(height: 210)
                .beaconGlassWell(cornerRadius: 11)
            }
        }
        .beaconGlassCard(cornerRadius: 16, padding: 20)
    }

    private func copyToPasteboard(_ text: String, flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            flag.wrappedValue = false
        }
    }
}
