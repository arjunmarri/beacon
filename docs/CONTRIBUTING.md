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
- Keep all macOS App Store **App Sandbox** constraints intact (`com.apple.security.app-sandbox = true`). Never add direct unsigned subprocess execution outside `NSUserUnixTask`.
- Never write API keys, Personal Access Tokens, or passwords to `config.json`, `UserDefaults`, or `activity.log` — always use `KeychainStore` and `SecretMasker.redact`.
- Validate all local monitoring endpoints to loopback hosts (`localhost` / `127.0.0.1`) only.

## Submitting Changes
1. Create a feature branch (`git checkout -b feat/my-improvement`).
2. Verify the project builds cleanly in Xcode with **App Sandbox** enabled.
3. Open a Pull Request against `main` at https://github.com/arjunmarri/beacon.
