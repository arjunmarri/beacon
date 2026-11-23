import SwiftUI

struct ContentView: View {
    @Bindable var controller: BeaconController

    private let obsidianCanvas = Color(red: 0.043, green: 0.051, blue: 0.063)

    var body: some View {
        VStack(spacing: 0) {
            // Minimalist top bar
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Text("BeaconMac")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("macOS Native · App Sandbox")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check All") {
                    Task { await controller.refreshAllServices() }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconSecondaryButtonStyle())

                Button("Restart Server") {
                    Task { await controller.triggerViteRestart(reason: "header action") }
                }
                .disabled(controller.busyAction != nil)
                .buttonStyle(BeaconPrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(obsidianCanvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = controller.bannerError {
                        HStack {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.95))
                            Spacer()
                            Button("Dismiss") { controller.bannerError = nil }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    ServiceCardsView(controller: controller)
                    ActivityLogView(controller: controller)
                    ConfigurationView(controller: controller)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("Designed by")
                            .foregroundStyle(.secondary)
                        Link("SoroAI", destination: URL(string: "https://soroai.com")!)
                            .foregroundStyle(.cyan)
                        Spacer()
                    }
                    .font(.system(size: 11))
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .background(obsidianCanvas)
        }
        .background(obsidianCanvas)
    }
}
