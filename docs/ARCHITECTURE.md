# BeaconMac Architecture

BeaconMac is architected as a pure native **Swift 5.10 / SwiftUI (macOS 14+)** application supporting both **Mac App Store** (`Beacon.entitlements`, App Sandbox enabled) and **Direct Developer ID DMG** (`Beacon-DMG.entitlements`, Hardened Runtime, notarized & stapled) distribution while providing multi-app cloning, silent dependency installation, building, local deployment, a **Built-In Node.js Server**, an **Inbuilt NGINX Reverse Proxy**, **Cloud AI & Edge Platform API management**, **exportable auto-scrolling logs**, Server Log Search, AI Help log diagnostics, real-time Dark/White theming, and `launchd` startup automation.

---

## High-Level Component Diagram

```text
+----------------------------------------------------------------------------------+
|                           BeaconMac (SwiftUI macOS 14+)                          |
|                                                                                  |
|  [BeaconApp] ---> WindowGroup (ContentView + BeaconTheme Dark/White + Blue Hdrs) |
|               \-> MenuBarExtra (MenuBarStatusView)                               |
|                                                                                  |
|  [BeaconController (@MainActor @Observable)]                                     |
|     |--- Structured Polling Loop (3s apps / 15s Ollama / Ns Git / 60s Cloud AI)  |
|     |                                                                            |
|     +--> LocalProcessService        --> POSIX loopback pre-check + direct        |
|     |                                   IPv4/IPv6 HTTP/HTTPS probe (no proxy)    |
|     +--> AppDeploymentService       --> NSUserUnixTask (tmp FileHandles) or      |
|     |    + EmbeddedScripts              Process() (outside App Sandbox)          |
|     |                                   ├── beacon-deploy.sh                     |
|     |                                   ├── beacon-check-deps.sh (--install)     |
|     |                                   ├── beacon-launchd.sh (incl. grep)       |
|     |                                   ├── beacon-restart.sh                    |
|     |                                   ├── beacon-stop.sh                       |
|     |                                   ├── beacon-git-pull.sh                   |
|     |                                   ├── beacon-startup.sh (+ caffeinate)     |
|     |                                   ├── beacon-node-server.sh                |
|     |                                   ├── beacon-node-host.mjs                 |
|     |                                   └── beacon-nginx.sh                      |
|     +--> BuiltInNodeServerService   --> Loopback Node.js multi-app static/proxy  |
|     |                                   host (http://127.0.0.1:4173)             |
|     +--> NginxProxyService          --> User-space NGINX reverse proxy           |
|     |                                   (~/beaconmac/nginx/, path/*.localhost/LAN|
|     |                                    WebSocket/HMR, nginx -t, -s reload)     |
|     +--> CloudProviderService       --> Live zero-token probes & config for      |
|     |                                   OpenAI, Gemini, Claude, OpenRouter, Groq,|
|     |                                   Custom OpenAI, Cloudflare, Vercel,       |
|     |                                   Supabase                                 |
|     +--> AppUpdateService           --> Pinned GitHub Releases + CryptoKit       |
|     |                                   SHA-256 + SecStaticCodeCheckValidity     |
|     |                                   + codesign + spctl Gatekeeper check      |
|     +--> ServerLogSearchService     --> Sandboxed grep (-E/-F) on server.log     |
|     +--> LogExportService           --> NSSavePanel .txt / .json redacted export |
|     +--> LogTroubleshootingService  --> Redacted log diagnostics via Local       |
|     |                                   Ollama or any connected Cloud AI API     |
|     +--> TerminalIntegrationService --> NSWorkspace -> macOS Terminal.app        |
|     |                                   └── tail -f ~/beaconmac/server.log       |
|     +--> StartupSchedulerService    --> Apple launchd (~/Library/LaunchAgents)   |
|     |                                   └── SMAppService.mainApp (Login Item)    |
|     +--> SleepPreventionService     --> IOKit IOPMAssertion (App Sandbox)        |
|     |                                   └── System Settings Energy deep-link     |
|     +--> GitDeployService           --> HTTPS api.github.com (/user, repos)      |
|     +--> OllamaService              --> GET/POST http://127.0.0.1:11434          |
|     +--> ClaudeService              --> GET https://api.anthropic.com/v1/models  |
|     +--> AlertService               --> UNUserNotificationCenter (.app guard)    |
|     +--> KeychainStore              --> macOS Security.framework Keychain        |
|     +--> FlatFileStore              --> Application Support/Beacon/              |
|                                         ├── activity.log (2 MB rotation)         |
|                                         └── config.json (atomic writes)          |
+----------------------------------------------------------------------------------+
```

---

## Core Design Principles

### 1. Distribution Entitlements & Execution Boundary
BeaconMac ships with two explicit entitlements plists so signing never drops entitlements:
- **Mac App Store (`Sources/Beacon/Resources/Beacon.entitlements`)**: Sets `com.apple.security.app-sandbox = true`.
  - Network probes execute directly inside the sandbox via `URLSession` (`com.apple.security.network.client = true` + `NSAllowsLocalNetworking = true`).
  - Host scripts (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `nginx`, `launchctl`, `grep`) execute via Apple's approved **`NSUserUnixTask`** API against `~/Library/Application Scripts/<bundle-id>/`.
  - Sandboxed `NSUserUnixTask` captures stdout/stderr via temporary `FileHandle`s in the app container's `temporaryDirectory` (preventing XPC `UserScriptService` `EBADF / Bad file descriptor` errors and pipe buffer deadlocks), and never gates on `FileManager.fileExists(atPath:)` inside Application Scripts.
  - All 10 hook scripts are embedded inside `EmbeddedScripts.swift` with a 1-click `NSOpenPanel` installer inside the app (`Install Hook Scripts`) and a CLI installer (`Scripts/install-sandbox-scripts.sh`).
- **Direct Developer ID DMG (`Sources/Beacon/Resources/Beacon-DMG.entitlements`)**: Sets `com.apple.security.app-sandbox = false` with **Hardened Runtime** enabled via `codesign --options runtime --timestamp`.
  - Auto-installs all 10 embedded scripts on launch, runs local toolchains cleanly via `Foundation.Process`, and enables cryptographically verified in-place self-updates.
  - Built, Developer ID–signed, notarized (`xcrun notarytool`), stapled (`xcrun stapler`), and Gatekeeper-verified (`spctl`) via `Scripts/build-dmg.sh` and `.github/workflows/release-dmg.yml`.

### 2. Built-In Node.js Server & Inbuilt NGINX Reverse Proxy
- **Built-In Node.js Server (`BuiltInNodeServerService.swift`, `beacon-node-server.sh`, `beacon-node-host.mjs`)**:
  - Runs a lightweight zero-dependency Node.js HTTP server bound to `127.0.0.1:<port>` (default `4173`), reading its route table from `~/beaconmac/node-host/routes.json`.
  - Supports static/built directories (automatically resolving `dist/`, `build/`, `out/`, `public/`, or root `index.html` with SPA fallback) and local HTTP proxies, plus an Active Root (`/`) switcher and `/_beacon/` launcher.
- **Inbuilt NGINX Reverse Proxy (`NginxProxyService.swift`, `beacon-nginx.sh`)**:
  - Generates a self-contained user-space NGINX layout in `~/beaconmac/nginx/` (`nginx.conf`, `nginx.pid`, `logs/access.log`, `logs/error.log`, and `temp/*`) so NGINX runs with **zero `sudo`** and never touches `/opt/homebrew/etc/nginx` or `/etc/nginx`.
  - Supports path-prefix locations (`/<slug>/`), `*.localhost` virtual hosts (`server_name <slug>.localhost;`), Active Root (`/`), WebSocket/HMR upgrade headers, optional `0.0.0.0` LAN binding (with auto-detected Mac LAN IP via `en0`/`en1`), `nginx -t` config validation, and zero-downtime `nginx -s reload`.

### 3. Verified Self-Updater Security Boundary (`AppUpdateService.swift`)
- **Pinned Feed**: Hard-coded to `arjunmarri/beacon`. Any tampered `updateFeedRepo` or `autoInstallUpdates` flag in `config.json` is ignored; installs always require explicit user confirmation.
- **Strict Asset & Redirect Allowlist**: Accepts only `https://github.com/arjunmarri/beacon/releases/download/...` and `https://api.github.com/repos/arjunmarri/beacon/releases/assets/...` for `.dmg` / `.sha256` downloads, with a `URLSessionTaskDelegate` restricting HTTP redirects strictly to `objects.githubusercontent.com` and `release-assets.githubusercontent.com` (rejecting `raw.githubusercontent.com` and wildcard `*.githubusercontent.com`).
- **Cryptographic Verification Before Swap**:
  1. Verifies the downloaded DMG's streaming `CryptoKit.SHA256` digest against the release's published `.sha256` asset before mounting.
  2. Requires the currently running `.app` bundle to carry a real 10-character Apple Developer Team ID (ad-hoc builds refuse automatic binary replacement).
  3. Validates the staged `BeaconMac.app` via `SecStaticCodeCheckValidity` against a strict Apple Developer ID `SecRequirement` pinned to the running app's bundle ID and `subject.OU` (Team ID), followed by `/usr/bin/codesign --verify --deep --strict` and `/usr/sbin/spctl --assess --type execute`.
  4. Never strips `com.apple.quarantine` during replacement.

### 4. Reliable Loopback Health Probing & Clean Lifecycle (`LocalProcessService.swift`)
- Performs a non-blocking POSIX TCP pre-check (`127.0.0.1` and `::1`) before creating HTTP tasks so offline local servers do not spam `nw_socket_handle_socket_event` console errors.
- Bypasses system HTTP/SOCKS proxies (`connectionProxyDictionary = [:]`), connects directly to the reachable loopback address while preserving the original `Host` header, streams only response headers (`session.bytes(for:)`), disables redirect loops, and supports self-signed local HTTPS fallback.
- Tracks explicit manual stops (`manuallyStoppedAppIDs`) and unconfigured states so stopped apps stay halted without auto-recovery respawning, and newly added apps remain visually clean until configured/deployed.

### 5. Native macOS `launchd` Supervision & Sleep Prevention
- **Apple `launchd` Daemon (`beacon-launchd.sh` + `beacon-startup.sh`)**: Writes `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive = { SuccessfulExit = false }`, `ProcessType = Background`, logging to `~/beaconmac/server.log`) and manages it with `launchctl load -w` / `launchctl unload`.
- **Native IOKit Sleep Prevention (`SleepPreventionService.swift`)**: Holds `kIOPMAssertionTypePreventUserIdleSystemSleep` via `IOKit.pwr_mgt` while BeaconMac is running, and runs `/usr/bin/caffeinate -s` under `launchd` in headless mode.
- **GUI Login Launch (`SMAppService.mainApp`)**: Guarded by `.app` bundle detection so bare `swift run` launches never crash.

### 6. Security, Keychain Isolation & Export Redaction
- **macOS Keychain (`KeychainStore.swift`)**: Stores GitHub PATs, Anthropic Claude, OpenAI (ChatGPT), Google Gemini, OpenRouter, Groq, Custom OpenAI-Compatible, Cloudflare, Vercel, and Supabase API tokens under `kSecClassGenericPassword` (service `com.beaconmac.app`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No secrets ever touch `config.json`, scripts, or `.env`.
- **Log, Terminal, Export & AI Help Redaction (`SecretMasker`)**: Every activity log entry, terminal output line, server log search result, exported `.txt`/`.json` log file, and AI Help troubleshooting payload passes through regex scrubbing before display, disk write, export, or AI submission (`ghp_*`, `gho_*`, `ghu_*`, `ghs_*`, `github_pat_*`, `sk-ant-*`, `sk-*`, `AIza*`, `gsk_*`, `sbp_*`, `sb_secret_*`, etc.).
- **Input & SSRF Guards**:
  - Local app URLs and NGINX upstreams are restricted to local hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, `*.local`, no embedded credentials).
  - Repository URLs must start with `https://` or `git@` with no whitespace or leading `-` flags; branch names reject `..` and leading `-`.
  - Dependency installer tool names and strategies are strictly allowlisted (`node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, `cargo`, `rust`, `nginx`, `git`; strategies `auto`, `homebrew`, `direct`).
  - Ollama probes strictly validate `http://127.0.0.1` / `http://localhost` on ports `11434–11440`.

### 7. Real-Time Theming (`BeaconTheme.swift`), Flat-File Storage & Release Portal
- **`BeaconTheme.swift`**: Centralized adaptive palette (`BeaconPalette`) and `BeaconSectionHeaderText` component supporting real-time **Dark** and **White (Light)** switching with high-contrast **Blue** section headers across all primary views and sheets.
- **`config.json` & `activity.log` (`FlatFileStore.swift`)**: Atomic writes for `managedApps`, `builtInNodeServer`, `nginxProxy`, `cloudProviders` (non-secret metadata only), `appearanceMode`, `startupSchedule`, Ollama endpoint, poll interval, and alert settings; append-only structured `activity.log` auto-rotated at 2 MB.
- **`index.html` + `server.ts`**: Standalone dark HTML release portal serving versioned Universal `.dmg` downloads (local or GitHub Releases) and dynamically zipping `swift-app/BeaconMac/`, `docs/`, `.github/`, `releases/releases.json`, `README.md`, `CHANGELOG.md`, `version.json`, and `LICENSE` via `/api/download-swift`.
