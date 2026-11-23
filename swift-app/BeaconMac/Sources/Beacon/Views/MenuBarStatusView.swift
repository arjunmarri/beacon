import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var controller: BeaconController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Beacon Service Monitor")
                .font(.headline)

            Divider()

            statusRow(name: "Vite / Localhost", light: controller.vite.light, detail: controller.vite.statusLabel)
            statusRow(name: "Git Auto-Deploy", light: controller.git.light, detail: controller.git.statusLabel)
            statusRow(name: "Local LLM (Ollama)", light: controller.ollama.light, detail: controller.ollama.statusLabel)
            statusRow(name: "Claude API", light: controller.claude.light, detail: controller.claude.statusLabel)

            Divider()

            Button("Check All Services") {
                Task { await controller.refreshAllServices() }
            }

            Button("Restart Local Server") {
                Task { await controller.triggerViteRestart(reason: "menu bar") }
            }

            Divider()

            Button("Quit Beacon") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 240)
    }

    private func statusRow(name: String, light: TrafficLightColor, detail: String) -> some View {
        HStack {
            Circle()
                .fill(light == .green ? Color.green : (light == .amber ? Color.orange : Color.red))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12))
            Spacer()
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
