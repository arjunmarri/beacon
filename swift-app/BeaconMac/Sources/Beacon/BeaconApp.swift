import SwiftUI

@main
struct BeaconApp: App {
    @State private var controller = BeaconController()

    var body: some Scene {
        WindowGroup("BeaconMac") {
            ContentView(controller: controller)
                .preferredColorScheme(controller.config.appearanceMode == .light ? .light : .dark)
                .frame(minWidth: 940, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 820)

        MenuBarExtra {
            MenuBarStatusView(controller: controller)
        } label: {
            Image(systemName: menuBarSymbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarTintColor)
        }
    }

    private var menuBarSymbolName: String {
        switch controller.aggregateLight {
        case .green: return "circle.fill"
        case .amber: return "exclamationmark.circle.fill"
        case .red: return "xmark.octagon.fill"
        }
    }

    private var menuBarTintColor: Color {
        switch controller.aggregateLight {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }
}
