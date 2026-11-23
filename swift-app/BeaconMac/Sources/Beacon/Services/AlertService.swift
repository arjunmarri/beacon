import Foundation
import UserNotifications

/// Native macOS notification alerts for server crashes, Git deploys, and Ollama outages.
public final class AlertService: Sendable {
    public init() {}

    /// `UNUserNotificationCenter.current()` throws an uncaught `NSInternalInconsistencyException`
    /// (`bundleProxyForCurrentProcess is nil`) when launched as a bare SwiftPM executable
    /// (e.g., opening `Package.swift` in Xcode or `swift run`) without a `.app` bundle.
    private var supportsUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app" && Bundle.main.bundleIdentifier != nil
    }

    public func requestPermission() {
        guard supportsUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendAlert(title: String, body: String, recipientEmail: String, emailEnabled: Bool) async -> String {
        if supportsUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = "Beacon: \(title)"
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)

            if emailEnabled, !recipientEmail.isEmpty {
                return "Delivered macOS notification and logged alert for \(recipientEmail): \(title)"
            }
            return "Delivered macOS notification: \(title)"
        }

        if emailEnabled, !recipientEmail.isEmpty {
            return "Logged alert for \(recipientEmail) (system notifications require a .app bundle): \(title)"
        }
        return "Logged alert (system notifications require a .app bundle): \(title)"
    }
}
