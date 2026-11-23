# Changelog

All notable changes to **BeaconMac** are documented in this file.  
Versioning follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).

---

## [1.1.0] — 2026-11-23

### Added
- **Automatic Self-Updates**: Added `AppUpdateService` to check GitHub Releases (with `releases/releases.json` fallback) on launch and every 6 hours, with opt-in automatic DMG download, atomic `.app` swap & relaunch, plus **Check Updates** / **Update & Relaunch** controls in the top bar, Settings, and Menu Bar.
- **Server Log Search (`grep` / Regex)**: Added a dedicated search bar above the Real-Time Activity Log (plus a full-height modal view) to search `~/beaconmac/server.log` using Extended Regex (`-E`) or literal fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, quick presets, and a scrollable preformatted results block.
- **Embedded Hook Scripts & Auto-Installer**: Embedded all 7 shell hook scripts inside the Swift binary so non-sandboxed launches (`swift run`, local Xcode runs, Developer ID DMG) auto-install and run immediately with zero manual setup, while Mac App Store App-Sandboxed builds present a 1-click **Install Hook Scripts** banner.
- **App-Sandbox `grep` Subcommand**: Added a safe `grep` action to `beacon-launchd.sh` for sandboxed log searching via `NSUserUnixTask` with automatic secret redaction.

### Fixed
- **Dual-Target Script Installation**: Updated `install-sandbox-scripts.sh` to install scripts into both `~/Library/Application Scripts/com.beaconmac.app` and `~/Library/Application Scripts/BeaconMac` to eliminate missing-script errors under `swift run`.

## [1.0.0] — 2026-11-23

### Added
- **Multi-App Local Deployment & Monitoring Hub**: Monitor and deploy unlimited locally hosted Vite, Node.js, Next.js, and custom applications across any localhost or `.local` port.
- **Clone → Check Deps → Build → Deploy Pipeline**: Automatically checks `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`, clones or pulls remote Git repositories, installs missing `node_modules`, builds, and launches locally.
- **Apple `launchd` Background Supervision**: Install, load, inspect, and unload `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist` directly from BeaconMac or the Menu Bar.
- **Persistent Live Logs**: Streams supervisor logs to `~/beaconmac/server.log` and per-app logs to `~/beaconmac/logs/<app>-<port>.log` with one-click `tail -f` Terminal launch.
- **Native macOS Sleep Prevention**: Holds an App-Sandbox-safe IOKit power assertion while running, invokes `caffeinate -s` automatically under `launchd`, and links directly to macOS Energy Settings.
- **Encrypted macOS Keychain Storage**: Direct in-app key paste for GitHub Personal Access Tokens and Anthropic Claude API keys (`/v1/models` zero-token health check), plus local Ollama LLM monitoring and model switching.
- **Versioned Universal DMG Pipeline**: Automated macOS `.dmg` packaging (`Scripts/build-dmg.sh`) and GitHub Actions `macos-14` release workflow (`release-dmg.yml`).
