import AppKit
import Foundation
import IOKit.pwr_mgt

/// Native macOS sleep prevention tightly coupled with IOKit Power Management
/// (100% App Sandbox & Mac App Store compliant) plus System Settings & caffeinate -s helpers.
public final class SleepPreventionService: @unchecked Sendable {
    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var active: Bool = false

    public var isAssertionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    public init() {}

    deinit {
        lock.lock()
        if active {
            IOPMAssertionRelease(assertionID)
            active = false
            assertionID = 0
        }
        lock.unlock()
    }

    @discardableResult
    public func setPreventSystemSleep(_ enabled: Bool) -> (ok: Bool, detail: String) {
        lock.lock()
        defer { lock.unlock() }

        if enabled {
            if active {
                return (true, "macOS idle system sleep prevention is already active (IOKit assertion #\(assertionID)).")
            }
            var newID: IOPMAssertionID = 0
            let reason = "BeaconMac keeping local Vite/Node servers reachable while display sleeps" as CFString
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &newID
            )
            if status == kIOReturnSuccess {
                assertionID = newID
                active = true
                return (true, "Preventing macOS idle system sleep via IOKit Power Management (assertion #\(newID)).")
            }
            return (false, "Failed to create IOKit sleep assertion (IOReturn \(status)).")
        } else {
            if active {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
                active = false
                return (true, "Released macOS IOKit sleep prevention assertion.")
            }
            return (true, "Sleep prevention is already disabled.")
        }
    }

    @MainActor
    public func openEnergySettings() -> (ok: Bool, detail: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.EnergySaver-Settings.extension",
            "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return (true, "Opened macOS System Settings -> Energy / Battery.")
            }
        }
        return (false, "Open System Settings > Energy / Displays and enable 'Prevent automatic sleeping when display is off'.")
    }

    @MainActor
    public func copyCaffeinateCommand() -> String {
        let cmd = "caffeinate -s"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        return cmd
    }
}
