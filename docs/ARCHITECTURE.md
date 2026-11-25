# BeaconMac Architecture

BeaconMac is architected as a pure native **Swift 5.10 / SwiftUI (macOS 14+)** application supporting both **Mac App Store** (`Beacon.entitlements`, App Sandbox enabled) and **Direct Developer ID DMG** (`Beacon-DMG.entitlements`, Hardened Runtime, notarized & stapled) distribution while providing multi-app cloning, silent dependency installation, building, local deployment, a **Built-In Node.js Server**, **1-click Cloudflare Quick Tunnels** (for local apps, Node host, and Ollama), **exportable auto-scrolling logs**, Server Log Search, real-time Dark/White theming, and `launchd` startup automation.

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
|     |--- Structured Polling Loop (3s apps / 15s Ollama / Ns Git)                 |
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
|     |                                   └── beacon-cloudflared.sh                |
|     +--> BuiltInNodeServerService   --> Loopback Node.js multi-app static/proxy  |
|     |                                   host (http://127.0.0.1:4173)             |
|     +--> CloudflareTunnelService    --> Sanitized Quick Tunnel config.yml        |
|     |                                   generator (incl. Ollama Host rewrite)    |
|     +--> ServerLogSearchService     --> Sandboxed grep (-E/-F) on server.log     |
|     +--> LogExportService           --> NSSavePanel .txt / .json redacted export |
|     +--> TerminalIntegrationService --> NSWorkspace -> macOS Terminal.app        |
|     |                                   └── tail -f ~/beaconmac/server.log       |
|     +--> StartupSchedulerService    --> Apple launchd (~/Library/LaunchAgents)   |
|     |                                   └── SMAppService.mainApp (Login Item)    |
|     +--> SleepPreventionService     --> IOKit IOPMAssertion (App Sandbox)        |
|     |                                   └── System Settings Energy deep-link     |
|     +--> GitDeployService           --> HTTPS api.github.com (/user, repos)      |
|     +--> OllamaService              --> GET/POST http://127.0.0.1:11434          |
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
  - Host scripts (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `cloudflared`, `launchctl`, `grep`) execute via Apple's approved **`NSUserUnixTask`** API against `~/Library/Application Scripts/<bundle-id>/`.
  - Sandboxed `NSUserUnixTask` captures stdout/stderr via temporary `FileHandle`s in the app container's `temporaryDirectory` (preventing XPC `UserScriptService` `EBADF / Bad file descriptor` errors and pipe buffer deadlocks), and never gates on `FileManager.fileExists(atPath:)` inside Application Scripts.
  - All 10 hook scripts are embedded inside `EmbeddedScripts.swift` with a 1-click `NSOpenPanel` installer inside the app (`Install Hook Scripts`) and a CLI installer (`Scripts/install-sandbox-scripts.sh`).
- **Direct Developer ID DMG (`Sources/Beacon/Resources/Beacon-DMG.entitlements`)**: Sets `com.apple.security.app-sandbox = false` with **Hardened Runtime** enabled via `codesign --options runtime --timestamp`.
  - Auto-installs all 10 embedded scripts on launch and runs local toolchains cleanly via `Foundation.Process`.
  - Built, Developer ID–signed, notarized (`xcrun notarytool`), stapled (`xcrun stapler`), and Gatekeeper-verified (`spctl`) via `Scripts/build-dmg.sh` and `.github/workflows/release-dmg.yml`.

### 2. Built-In Node.js Server & Cloudflare Quick Tunnels
- **Built-In Node.js Server (`BuiltInNodeServerService.swift`, `beacon-node-server.sh`, `beacon-node-host.mjs`)**:
  - Runs a lightweight zero-dependency Node.js HTTP server bound to `127.0.0.1:<port>` (default `4173`), reading its route table from `~/beaconmac/node-host/routes.json`.
  - Supports static/built directories (automatically resolving `dist/`, `build/`, `out/`, `public/`, or root `index.html` with SPA fallback) and local HTTP proxies, plus an Active Root (`/`) switcher and `/_beacon/` launcher.
- **Cloudflare Quick Tunnels (`CloudflareTunnelService.swift`, `beacon-cloudflared.sh`)**:
  - Generates a sanitized `config.yml` per tunnel inside `Application Support/Beacon/tunnels/<key>/` and launches a detached `cloudflared` Quick Tunnel (`*.trycloudflare.com`) pointing strictly to `http://127.0.0.1:<port>`.
  - Supports an optional sanitized `httpHostHeader` (e.g. `localhost:11434`) so Local Ollama accepts tunneled HTTPS requests without manual proxy configuration.

### 3. Reliable Loopback Health Probing & Clean Lifecycle (`LocalProcessService.swift`)
- Performs a non-blocking POSIX TCP pre-check (`127.0.0.1` and `::1`) before creating HTTP tasks so offline local servers do not spam `nw_socket_handle_socket_event` console errors.
- Bypasses system HTTP/SOCKS proxies (`connectionProxyDictionary = [:]`), connects directly to the reachable loopback address while preserving the original `Host` header, streams only response headers (`session.bytes(for:)`), disables redirect loops, and supports self-signed local HTTPS fallback.
- Tracks explicit manual stops (`manuallyStoppedAppIDs`) and unconfigured states so stopped apps stay halted without auto-recovery respawning, and newly added apps remain visually clean until configured/deployed.

### 4. Native macOS `launchd` Supervision & Sleep Prevention
- **Apple `launchd` Daemon (`beacon-launchd.sh` + `beacon-startup.sh`)**: Writes `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive = { SuccessfulExit = false }`, `ProcessType = Background`, logging to `~/beaconmac/server.log`) and manages it with `launchctl load -w` / `launchctl unload`.
- **Native IOKit Sleep Prevention (`SleepPreventionService.swift`)**: Holds `kIOPMAssertionTypePreventUserIdleSystemSleep` via `IOKit.pwr_mgt` while BeaconMac is running, and runs `/usr/bin/caffeinate -s` under `launchd` in headless mode.
- **GUI Login Launch (`SMAppService.mainApp`)**: Guarded by `.app` bundle detection so bare `swift run` launches never crash.

### 5. Security, Keychain Isolation & Export Redaction
- **macOS Keychain (`KeychainStore.swift`)**: Stores your GitHub Personal Access Token under `kSecClassGenericPassword` (service `com.beaconmac.app`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No secrets ever touch `config.json`, scripts, or `.env`.
- **Log, Terminal & Export Redaction (`SecretMasker`)**: Every activity log entry, terminal output line, server log search result, and exported `.txt`/`.json` log file passes through regex scrubbing before display, disk write, or export.
- **Input & SSRF Guards**:
  - Local app URLs are restricted to local loopback hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, `*.local`, no embedded credentials).
  - Repository URLs must start with `https://` or `git@` with no whitespace or leading `-` flags; branch names reject `..` and leading `-`.
  - Dependency installer tool names and strategies are strictly allowlisted (`node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, `cargo`, `rust`, `cloudflared`, `git`; strategies `auto`, `homebrew`, `direct`).
  - Ollama probes strictly validate `http://127.0.0.1` / `http://localhost` on ports `11434–11440`.

### 6. Real-Time Theming (`BeaconTheme.swift`), Flat-File Storage & Release Portal
- **`BeaconTheme.swift`**: Centralized adaptive palette (`BeaconPalette`) and `BeaconSectionHeaderText` component supporting real-time **Dark** and **White (Light)** switching with high-contrast **Blue** section headers across all primary views and sheets.
- **`config.json` & `activity.log` (`FlatFileStore.swift`)**: Atomic writes for `managedApps`, `builtInServer`, `cloudflareTunnel`, `appearanceMode`, `startupSchedule`, Ollama endpoint, poll interval, and alert settings; append-only structured `activity.log` auto-rotated at 2 MB.
- **`index.html` + `privacy.html` + `server.ts`**: Standalone dark HTML release portal serving versioned Universal `.dmg` downloads, `/privacy`, and dynamically zipping `swift-app/BeaconMac/`, `docs/`, `.github/`, `releases/releases.json`, `README.md`, `CHANGELOG.md`, `version.json`, and `LICENSE` via `/api/download-swift`.
