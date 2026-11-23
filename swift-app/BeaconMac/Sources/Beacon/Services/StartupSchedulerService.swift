import AppKit
import Foundation
import ServiceManagement

/// Manages Apple's native launchd background supervisor (~/Library/LaunchAgents/*.supervisor.plist),
/// macOS Launch at Login (SMAppService — 100% App Store compliant), live log commands, and
/// optional legacy crontab schedules.
public final class StartupSchedulerService: Sendable {
    public init() {}

    public var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.beaconmac.app"
    }

    public var launchdLabel: String {
        "\(bundleID).supervisor"
    }

    public var launchdPlistTildePath: String {
        "~/Library/LaunchAgents/\(launchdLabel).plist"
    }

    public var serverLogTildePath: String {
        "~/beaconmac/server.log"
    }

    public var tailServerLogCommand: String {
        "tail -f \(serverLogTildePath)"
    }

    public var launchctlLoadCommand: String {
        "launchctl load -w \(launchdPlistTildePath)"
    }

    public var launchctlUnloadCommand: String {
        "launchctl unload \(launchdPlistTildePath)"
    }

    public var caffeinateCommand: String {
        "caffeinate -s"
    }

    private var hasAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app" && Bundle.main.bundleIdentifier != nil
    }

    public var isLaunchAtLoginEnabled: Bool {
        guard hasAppBundle else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) -> (ok: Bool, detail: String) {
        guard hasAppBundle else {
            return (
                false,
                "Launch at Login requires running BeaconMac as a .app bundle (open BeaconMac.xcodeproj via xcodegen or run BeaconMac.app)."
            )
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                return (true, "Registered BeaconMac to launch automatically at macOS login (SMAppService).")
            } else {
                try SMAppService.mainApp.unregister()
                return (true, "Disabled automatic launch at macOS login.")
            }
        } catch {
            return (false, "Could not update Launch at Login: \(error.localizedDescription)")
        }
    }

    public func buildLaunchAgentPlist(
        bundleID: String? = nil,
        preventSleep: Bool = true
    ) -> String {
        let resolvedID = bundleID ?? self.bundleID
        let label = "\(resolvedID).supervisor"
        let home = NSHomeDirectory()
        let scriptPath = "\(home)/Library/Application Scripts/\(resolvedID)/beacon-startup.sh"
        let serverLog = "\(home)/beaconmac/server.log"
        let sleepFlag = preventSleep ? "1" : "0"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptPath)</string>
                <string>--launchd</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>BEACONMAC_BUNDLE_ID</key>
                <string>\(resolvedID)</string>
                <key>BEACONMAC_PREVENT_SLEEP</key>
                <string>\(sleepFlag)</string>
                <key>PATH</key>
                <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(serverLog)</string>
            <key>StandardErrorPath</key>
            <string>\(serverLog)</string>
        </dict>
        </plist>
        """
    }

    public func buildCrontabLine(cronExpression: String) -> String {
        let sanitized = cronExpression
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expr = sanitized.isEmpty ? "@reboot" : sanitized
        let scriptPath = "$HOME/Library/Application Scripts/\(bundleID)/beacon-startup.sh"
        return "\(expr) /bin/bash \"\(scriptPath)\" >> $HOME/beaconmac/server.log 2>&1"
    }

    @MainActor
    public func copyCrontabCommand(cronExpression: String) -> String {
        let line = buildCrontabLine(cronExpression: cronExpression)
        let escapedLine = line.replacingOccurrences(of: "'", with: "'\\''")
        let installCmd = "(crontab -l 2>/dev/null | grep -v 'beacon-startup.sh'; echo '\(escapedLine)') | crontab -"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCmd, forType: .string)
        return installCmd
    }

    @MainActor
    public func exportLaunchAgentPlist(preventSleep: Bool = true) -> (ok: Bool, detail: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(launchdLabel).plist"
        panel.message = "Save to ~/Library/LaunchAgents/ so macOS launchd manages your startup apps automatically."
        if panel.runModal() == .OK, let dest = panel.url {
            let content = buildLaunchAgentPlist(bundleID: bundleID, preventSleep: preventSleep)
            do {
                try content.write(to: dest, atomically: true, encoding: .utf8)
                return (true, "Exported LaunchAgent plist to \(dest.path). Start with: launchctl load -w \(dest.path)")
            } catch {
                return (false, "Failed to export LaunchAgent plist: \(error.localizedDescription)")
            }
        }
        return (false, "Export cancelled.")
    }
}
