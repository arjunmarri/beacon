import SwiftUI

@main
struct BeaconApp: App {
    @State private var controller = BeaconController()

    private var activeScheme: ColorScheme {
        controller.config.appearanceMode == .light ? .light : .dark
    }

    var body: some Scene {
        WindowGroup("BeaconMac") {
            ContentView(controller: controller)
                .preferredColorScheme(activeScheme)
                .frame(minWidth: 1020, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)

        MenuBarExtra {
            MenuBarStatusView(controller: controller)
                .preferredColorScheme(activeScheme)
        } label: {
            Image(systemName: menuBarSymbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(menuBarTintColor)
        }
        .menuBarExtraStyle(.window)
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
