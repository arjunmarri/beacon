# Changelog

All notable changes to **BeaconMac** are documented in this file.  
Versioning follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).

---

## [1.1.0] — 2026-11-24

### Added
- **In-App Silent Dependency Installer (`Install Dependencies`)**: Added an **Install Dependencies** button in the top bar, Managed Local Apps header, per-app rows, and Menu Bar. Select your project type (**Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS**, **Python (python3 + uv)**, **Go**, or **Custom**) and install missing tools silently in the background (`NONINTERACTIVE=1`) via Homebrew or verified direct official downloads (SHA-256–verified Node.js LTS tarballs, standalone `pnpm`, `yarn`, `bun`, and `uv`), plus optional project package syncing (`package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`).
- **AI Help Log Troubleshooting & One-Click Log Copying**: Added `LogTroubleshootingService` and `AILogHelpSheet` so users can send redacted Terminal, Server Log Search, Activity Log, or App Probe errors directly to their connected Local Ollama or Claude API for step-by-step troubleshooting (with a copy-ready prompt fallback), plus one-click `"Copied ✓"` log copy buttons and context menus across every log view.
- **Verified Self-Updates (`AppUpdateService`)**: Checks the pinned `arjunmarri/beacon` GitHub Releases feed (with `releases/releases.json` fallback), enforces a strict release asset URL and CDN redirect allowlist, verifies the published `.sha256` checksum via `CryptoKit` before mounting, requires a Developer ID Team ID on the running app, verifies staged updates via `SecStaticCodeCheckValidity` (pinned Team ID + Apple Developer ID anchor + bundle identifier), `codesign --verify --deep --strict`, and Gatekeeper (`spctl --assess`), preserves `com.apple.quarantine`, and requires explicit user confirmation before installing.
- **Signed & Notarized Universal DMG Pipeline**: Added `Beacon-DMG.entitlements` (Hardened Runtime for Direct Developer ID DMG distribution alongside App Store `Beacon.entitlements`), fail-closed CI secret validation, ephemeral keychain certificate import, `xcrun notarytool` + `xcrun stapler` notarization, and post-staple SHA-256 generation in `build-dmg.sh` and `release-dmg.yml`.
- **Server Log Search (`grep` / Regex)**: Added a dedicated search bar above the Real-Time Activity Log (plus a full-height modal view) to search `~/beaconmac/server.log` using Extended Regex (`-E`) or literal fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, quick presets, and a scrollable preformatted results block.
- **Embedded Hook Scripts & Auto-Installer**: Embedded all 7 shell hook scripts inside the Swift binary so non-sandboxed launches (`swift run`, local Xcode runs, Developer ID DMG) auto-install and run immediately with zero manual setup, while Mac App Store App-Sandboxed builds present a 1-click **Install Hook Scripts** banner.

### Fixed
- **App Sandbox `NSUserUnixTask` `Bad file descriptor` & Missing-Script Errors**: Replaced `Pipe()` with container temporary `FileHandle`s for sandboxed `NSUserUnixTask` execution and removed `FileManager.fileExists` gates on `~/Library/Application Scripts/<bundle-id>/`.
- **Localhost App Health Probing**: Added a silent POSIX loopback TCP pre-check (eliminating console `nw_socket_handle_socket_event` noise), bypassed macOS HTTP proxies (`connectionProxyDictionary = [:]`), enabled direct IPv4/IPv6 loopback routing, prevented redirect loops, and added local HTTPS fallback.
- **Bare SwiftPM Launch Guard**: Guarded `UNUserNotificationCenter.current()` and `SMAppService.mainApp` behind `.app` bundle checks to prevent `bundleProxyForCurrentProcess is nil` crashes under `swift run`.
- **Dual-Target Script Installation**: Updated `install-sandbox-scripts.sh` to install scripts into both `~/Library/Application Scripts/com.beaconmac.app` and `~/Library/Application Scripts/BeaconMac`.

## [1.0.0] — 2026-11-23

### Added
- **Multi-App Local Deployment & Monitoring Hub**: Monitor and deploy unlimited locally hosted Vite, Node.js, Next.js, and custom applications across any localhost or `.local` port.
- **Clone → Check Deps → Build → Deploy Pipeline**: Automatically checks `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`, clones or pulls remote Git repositories, installs missing `node_modules`, builds, and launches locally.
- **Apple `launchd` Background Supervision**: Install, load, inspect, and unload `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist` directly from BeaconMac or the Menu Bar.
- **Persistent Live Logs**: Streams supervisor logs to `~/beaconmac/server.log` and per-app logs to `~/beaconmac/logs/<app>-<port>.log` with one-click `tail -f` Terminal launch.
- **Native macOS Sleep Prevention**: Holds an App-Sandbox-safe IOKit power assertion while running, invokes `caffeinate -s` automatically under `launchd`, and links directly to macOS Energy Settings.
- **Encrypted macOS Keychain Storage**: Direct in-app key paste for GitHub Personal Access Tokens and Anthropic Claude API keys (`/v1/models` zero-token health check), plus local Ollama LLM monitoring and model switching.
- **Versioned Universal DMG Pipeline**: Automated macOS `.dmg` packaging (`Scripts/build-dmg.sh`) and GitHub Actions `macos-14` release workflow (`release-dmg.yml`).
