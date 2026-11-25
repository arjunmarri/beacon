# Contributing to BeaconMac

Thank you for contributing to **BeaconMac**!

## Development Setup (macOS)

1. Ensure you have **macOS 14 (Sonoma)** or newer and **Xcode 15.4+**.
2. Clone the repository:
   ```bash
   git clone https://github.com/arjunmarri/beacon.git
   cd beacon/swift-app/BeaconMac
   ```
3. Generate and open the Xcode project:
   ```bash
   chmod +x Scripts/*.sh
   ./Scripts/generate-xcode-project.sh
   ```
   Or run directly via Swift Package Manager:
   ```bash
   swift run
   ```

## Coding Guidelines
- Target **Swift 5.10+** and **macOS 14+** using the Observation framework (`@Observable`) and Swift Concurrency (`async`/`await`, `Sendable`).
- Preserve both distribution entitlements (`Resources/Beacon.entitlements` with `com.apple.security.app-sandbox = true` for Mac App Store builds, and `Resources/Beacon-DMG.entitlements` with Hardened Runtime for Direct Developer ID DMG builds). Inside App Sandbox, always execute host scripts through `NSUserUnixTask` using temporary `FileHandle`s (never `Pipe()`).
- Whenever you modify any of the 10 runtime scripts under `swift-app/BeaconMac/Scripts/` (`beacon-*.sh` or `beacon-node-host.mjs`), keep the matching embedded copy in `Sources/Beacon/Services/EmbeddedScripts.swift` synchronized.
- Use `BeaconTheme` (`BeaconPalette` and `BeaconSectionHeaderText`) for surfaces, borders, and Blue section headers so every view adapts cleanly to both Dark and White (Light) themes in real time.
- Never write Personal Access Tokens or passwords to `config.json`, `UserDefaults`, or `activity.log` — always use `KeychainStore` and `SecretMasker.redact`.
- Validate all local monitoring endpoints to local loopback hosts (`localhost`, `127.0.0.1`, `::1`, `*.localhost`, `*.local`) only.

## Submitting Changes
1. Create a feature branch (`git checkout -b feat/my-improvement`).
2. Verify the project builds cleanly in Xcode with **App Sandbox** enabled and via `swift build`.
3. Open a Pull Request against `main` at https://github.com/arjunmarri/beacon.
