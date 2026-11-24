import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @Bindable var controller: BeaconController
    @State private var expanded = true
    @State private var copiedAll = false
    @State private var copiedErrors = false

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let consoleBackground = Color(red: 0.035, green: 0.041, blue: 0.052)

    private var errorLines: [TerminalOutputLine] {
        controller.terminalLines.filter { $0.isError || $0.text.localizedCaseInsensitiveContains("error") }
    }

    private func formattedDump(_ lines: [TerminalOutputLine]) -> String {
        lines.map { line in
            let ts = line.timestamp.formatted(date: .omitted, time: .standard)
            return "\(ts) [\(line.appName)] \(line.text)"
        }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Integrated Terminal Output")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Live stdout/stderr from git clone, dependency installs, builds, and local deploys · Right-click any line to copy or ask AI")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

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

                Button("AI Help") {
                    controller.openAIHelp(
                        title: "Integrated Terminal Output",
                        logText: formattedDump(controller.terminalLines)
                    )
                }
                .disabled(controller.terminalLines.isEmpty)
                .buttonStyle(BeaconPrimaryButtonStyle())

                Button("Clear") {
                    controller.clearTerminal()
                }
                .disabled(controller.terminalLines.isEmpty)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button(expanded ? "Collapse" : "Expand") {
                    expanded.toggle()
                }
                .buttonStyle(BeaconSecondaryButtonStyle())
            }

            if expanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if controller.terminalLines.isEmpty {
                            Text("Terminal output appears here when you run Check System Tools, Install Prerequisites, Check Deps, or Clone & Deploy.")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        } else {
                            ForEach(controller.terminalLines) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(line.timestamp.formatted(date: .omitted, time: .standard))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 70, alignment: .leading)
                                    Text("[\(line.appName)]")
                                        .foregroundStyle(.cyan)
                                        .frame(width: 96, alignment: .leading)
                                        .lineLimit(1)
                                    Text(line.text)
                                        .foregroundStyle(line.isError ? .red.opacity(0.92) : .white.opacity(0.9))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(size: 11.5, design: .monospaced))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .contextMenu {
                                    Button("Copy Line") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("[\(line.appName)] \(line.text)", forType: .string)
                                    }
                                    Button("Copy All Output") {
                                        copyToPasteboard(formattedDump(controller.terminalLines), flag: $copiedAll)
                                    }
                                    Divider()
                                    Button("Ask AI About This Line") {
                                        controller.openAIHelp(
                                            title: "Terminal Line (\(line.appName))",
                                            logText: "[\(line.appName)] \(line.text)",
                                            appName: line.appName
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 175)
                .background(consoleBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
