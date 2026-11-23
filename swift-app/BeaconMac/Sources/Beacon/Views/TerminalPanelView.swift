import AppKit
import SwiftUI

struct TerminalPanelView: View {
    @Bindable var controller: BeaconController
    @State private var expanded = true

    private let cardBackground = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let consoleBackground = Color(red: 0.035, green: 0.041, blue: 0.052)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Integrated Terminal Output")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Live stdout/stderr from git clone, dependency audits, npm install, builds, and local deploys")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy Output") {
                    let dump = controller.terminalLines
                        .map { "[\($0.appName)] \($0.text)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dump, forType: .string)
                }
                .disabled(controller.terminalLines.isEmpty)
                .buttonStyle(BeaconSecondaryButtonStyle())

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
                            Text("Terminal output appears here when you run Check System Tools, Check Deps, or Clone & Deploy.")
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
}
