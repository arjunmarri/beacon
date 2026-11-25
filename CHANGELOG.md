# Changelog

All notable changes to **BeaconMac** are documented in this file.  
Versioning follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).

---

## [1.1.0] — 2026-11-25

### Added
- **1-Click Cloudflare Quick Tunnels (`CloudflareTunnelService`, `CloudflareTunnelSectionView`, `beacon-cloudflared.sh`)**: Expose any Managed Local App, Built-In Node.js Server, **Local Ollama LLM** (with automatic `--http-host-header localhost:<port>` rewrite), or custom localhost port over HTTPS via instant `*.trycloudflare.com` Quick Tunnels — zero Cloudflare API token required, silent `cloudflared` auto-install, live `config.yml` inspector, and automatic clipboard copy.
- **Built-In Node.js Server (`BuiltInNodeServerService`, `BuiltInNodeServerView`, `beacon-node-server.sh`, `beacon-node-host.mjs`)**: Zero-dependency loopback Node.js multi-app host (`http://127.0.0.1:4173`) that loads any static/built app folder (auto-detecting `dist/`, `build/`, `out/`, `public/`, or root `index.html` with SPA fallback) or proxies a local port, with 1-click **Load in Node Host** on Managed Local Apps, Active Root (`/`) switcher, and built-in `/_beacon/` launcher.
- **Blue Section Headers & Real-Time White (Light) / Dark Theme Switcher (`BeaconTheme.swift`)**: High-contrast Blue section headers with a left accent bar across all dashboard sections and modal sheets, plus a real-time **Dark / White** theme toggle in the top bar, Global Settings, and Menu Bar that updates every card, terminal, log console, and sheet immediately.
- **Enhanced Log Viewer & Export Logs (`LogExportService`, `ActivityLogView`, `TerminalPanelView`, `ServerLogSearchView`)**: Chronological auto-scroll to the latest log line, **Pause auto-scroll / Resume auto-scroll (N)** toggle with live unread badge, inline per-entry **Copy** buttons + right-click context menus (`Copy Entry`, `Copy Message Only`) across Activity, Terminal, and Server Log Search panels, plus an **Export Logs** menu to save all or filtered session logs (system, Git, services, deployment terminal output) as secret-redacted `.txt` or `.json`.
- **In-App Silent Dependency Installer (`Install Dependencies`)**: Added an **Install Dependencies** button in the top bar, Managed Local Apps header, per-app rows, and Menu Bar. Select your project type (**Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS**, **Python (python3 + uv)**, **Go**, or **Custom**) and install missing tools silently in the background (`NONINTERACTIVE=1`) via Homebrew or verified direct official downloads (SHA-256–verified Node.js LTS tarballs, standalone `pnpm`, `yarn`, `bun`, and `uv`), plus optional project package syncing (`package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`).
- **Mac App Store Privacy & Compliance (`PrivacyInfo.xcprivacy`, `PrivacyPolicySheet`, `PRIVACY_POLICY.md`, `/privacy`)**: Added Apple Privacy Manifest (`NSPrivacyTracking = false`), in-app Privacy Policy sheet & footer link, hosted `/privacy` disclosure page, and `BeaconPrivacyPolicyURL` configuration key.
- **Signed & Notarized Universal DMG Pipeline**: Added `Beacon-DMG.entitlements` (Hardened Runtime for Direct Developer ID DMG distribution alongside App Store `Beacon.entitlements`), fail-closed CI secret validation, ephemeral keychain certificate import, `xcrun notarytool` + `xcrun stapler` notarization, and post-staple SHA-256 generation in `build-dmg.sh` and `release-dmg.yml`.
- **Server Log Search (`grep` / Regex)**: Added a dedicated search bar above the Real-Time Activity Log (plus a full-height modal view) to search `~/beaconmac/server.log` using Extended Regex (`-E`) or literal fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, quick presets, per-line copy, and a scrollable preformatted results block.
- **10 Embedded Hook Scripts & Auto-Installer**: Embedded all 10 helper scripts (`beacon-deploy.sh`, `beacon-check-deps.sh`, `beacon-launchd.sh`, `beacon-restart.sh`, `beacon-stop.sh`, `beacon-git-pull.sh`, `beacon-startup.sh`, `beacon-node-server.sh`, `beacon-node-host.mjs`, `beacon-cloudflared.sh`) inside the Swift binary so non-sandboxed launches auto-install immediately, while Mac App Store builds provide a 1-click **Install Hook Scripts** banner.

### Changed & Removed (Mac App Store Preparation)
- Removed **Cloud & Edge API verifications**, **Cloud API integrations**, **NGINX Reverse Proxy / Health Monitor**, **third-party AI log sharing**, **in-app external self-updater UI**, and **non-functional Alert Email UI** from the `main` release branch so BeaconMac 1.1 stays streamlined, local-first, and ready for Mac App Store review. *(The full-featured snapshot with Cloud APIs and NGINX remains preserved on the `feature/cloud-apis-nginx` Git branch.)*

### Fixed
- **Clean Local App Stop (No Unwanted Auto-Restart)**: Clicking **Stop** on a managed app now marks it as manually stopped, cancels active probes/auto-recovery, terminates the entire process tree cleanly, and keeps the app stopped until you explicitly start or deploy it again.
- **Clean Preview for Newly Added / Unconfigured Apps**: Newly added or unconfigured apps remain quiet (blank/neutral state) instead of firing premature "HTTP Probe unreachable" errors before the app has been configured or deployed.
- **Graceful Build & Start Script Auto-Detection (`beacon-deploy.sh` & `beacon-restart.sh`)**: Projects without a `"build"` script in `package.json` no longer abort deployment; scripts now inspect `package.json` cleanly, fall back across `dev`, `start`, `serve`, `preview`, or `main`, and surface real startup log excerpts if a server exits immediately.
- **App Sandbox `NSUserUnixTask` `Bad file descriptor` & Missing-Script Errors**: Replaced `Pipe()` with container temporary `FileHandle`s for sandboxed `NSUserUnixTask` execution and removed `FileManager.fileExists` gates on `~/Library/Application Scripts/<bundle-id>/`.
- **Localhost App Health Probing**: Added a silent POSIX loopback TCP pre-check (eliminating console `nw_socket_handle_socket_event` noise), bypassed macOS HTTP proxies (`connectionProxyDictionary = [:]`), enabled direct IPv4/IPv6 loopback routing, prevented redirect loops, and added local HTTPS fallback.
- **Bare SwiftPM Launch Guard**: Guarded `UNUserNotificationCenter.current()` and `SMAppService.mainApp` behind `.app` bundle checks to prevent `bundleProxyForCurrentProcess is nil` crashes under `swift run`.
- **Dual-Target Script Installation**: Updated `install-sandbox-scripts.sh` to install all 10 scripts into both `~/Library/Application Scripts/com.beaconmac.app` and `~/Library/Application Scripts/BeaconMac`.

## [1.0.0] — 2026-11-23

### Added
- **Multi-App Local Deployment & Monitoring Hub**: Monitor and deploy unlimited locally hosted Vite, Node.js, Next.js, and custom applications across any localhost or `.local` port.
- **Clone → Check Deps → Build → Deploy Pipeline**: Automatically checks `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`, clones or pulls remote Git repositories, installs missing `node_modules`, builds, and launches locally.
- **Apple `launchd` Background Supervision**: Install, load, inspect, and unload `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist` directly from BeaconMac or the Menu Bar.
- **Persistent Live Logs**: Streams supervisor logs to `~/beaconmac/server.log` and per-app logs to `~/beaconmac/logs/<app>-<port>.log` with one-click `tail -f` Terminal launch.
- **Native macOS Sleep Prevention**: Holds an App-Sandbox-safe IOKit power assertion while running, invokes `caffeinate -s` automatically under `launchd`, and links directly to macOS Energy Settings.
- **Encrypted macOS Keychain Storage**: Direct in-app paste for GitHub Personal Access Tokens plus local Ollama LLM monitoring and model switching.
- **Versioned Universal DMG Pipeline**: Automated macOS `.dmg` packaging (`Scripts/build-dmg.sh`) and GitHub Actions `macos-14` release workflow (`release-dmg.yml`).
