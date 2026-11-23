import AppKit
import Foundation

/// Integrates BeaconMac with macOS Terminal.app and clipboard shell commands
/// in an App-Sandbox-safe manner using NSWorkspace.
public final class TerminalIntegrationService: Sendable {
    public init() {}

    public func appLogPath(for app: ManagedApp) -> String {
        let slug = URL(fileURLWithPath: app.localPath).lastPathComponent
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "~/beaconmac/logs/\(slug.isEmpty ? "app" : slug)-\(app.port).log"
    }

    public var supervisorServerLogPath: String {
        "~/beaconmac/server.log"
    }

    @MainActor
    public func openFolderInTerminal(_ folderPath: String) -> (ok: Bool, detail: String) {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "Configure a local folder path first to open it in Terminal.")
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expanded, isDirectory: true)
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return (false, "Could not locate macOS Terminal.app.")
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: config)
        return (true, "Opened \(trimmed) in macOS Terminal.app.")
    }

    @MainActor
    public func openAppLogInTerminal(app: ManagedApp) -> (ok: Bool, detail: String) {
        let logPath = appLogPath(for: app)
        let cmd = "tail -f \(logPath)"
        copyCommand(cmd)

        let targetDir = app.localPath.isEmpty ? NSHomeDirectory() : app.localPath
        let opened = openFolderInTerminal(targetDir)
        if opened.ok {
            return (true, "Opened Terminal.app and copied live log watch command: \(cmd)")
        }
        return (false, "Copied log command to clipboard: \(cmd)")
    }

    @MainActor
    public func watchSupervisorLogInTerminal() -> (ok: Bool, detail: String) {
        let cmd = "tail -f \(supervisorServerLogPath)"
        copyCommand(cmd)

        let logDir = "\(NSHomeDirectory())/beaconmac"
        let folderToOpen = FileManager.default.fileExists(atPath: logDir) ? logDir : NSHomeDirectory()
        let opened = openFolderInTerminal(folderToOpen)
        if opened.ok {
            return (true, "Opened Terminal.app and copied live log command: \(cmd)")
        }
        return (false, "Copied live log command to clipboard: \(cmd)")
    }

    @MainActor
    public func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    @MainActor
    public func copyDeployCommand(for app: ManagedApp) -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.beaconmac.app"
        let script = "$HOME/Library/Application\\ Scripts/\(bundleID)/beacon-deploy.sh"
        let parts = [
            script,
            shellEscape(app.repoURL),
            shellEscape(app.branch),
            shellEscape(app.localPath),
            String(app.port),
            shellEscape(app.installCommand.isEmpty ? "auto" : app.installCommand),
            shellEscape(app.buildCommand),
            shellEscape(app.startCommand)
        ]
        let command = parts.joined(separator: " ")
        copyCommand(command)
        return command
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
