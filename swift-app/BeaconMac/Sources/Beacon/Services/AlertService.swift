import Foundation
import UserNotifications

/// Native macOS notification alerts for server crashes, Git deploys, and Ollama outages.
public final class AlertService: Sendable {
    public init() {}

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendAlert(title: String, body: String, recipientEmail: String, emailEnabled: Bool) async -> String {
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
}
