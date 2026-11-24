# BeaconMac Architecture

BeaconMac is architected as a pure native **Swift 5.10 / SwiftUI (macOS 14+)** application supporting both **Mac App Store** (`Beacon.entitlements`, App Sandbox enabled) and **Direct Developer ID DMG** (`Beacon-DMG.entitlements`, Hardened Runtime, notarized & stapled) distribution while providing full multi-app cloning, silent dependency installation, building, local deployment, Server Log Search, AI Help log diagnostics, and `launchd` startup automation.

---

## High-Level Component Diagram

```text
+------------------------------------------------------------------------------+
|                         BeaconMac (SwiftUI macOS 14+)                        |
|                                                                              |
|  [BeaconApp] ---> WindowGroup (ContentView)                                  |
|               \-> MenuBarExtra (MenuBarStatusView)                           |
|                                                                              |
|  [BeaconController (@MainActor @Observable)]                                 |
|     |--- Structured Polling Loop (3s apps / 15s Ollama / Ns Git / 60s Claude)|
|     |                                                                        |
|     +--> LocalProcessService        --> POSIX loopback pre-check + direct    |
|     |                                   IPv4/IPv6 HTTP/HTTPS probe (no proxy)|
|     +--> AppDeploymentService       --> NSUserUnixTask (tmp FileHandles) or  |
|     |    + EmbeddedScripts              Process() (outside App Sandbox)      |
|     |                                   ├── beacon-deploy.sh                 |
|     |                                   ├── beacon-check-deps.sh (--install) |
|     |                                   ├── beacon-launchd.sh (incl. grep)   |
|     |                                   ├── beacon-restart.sh                |
|     |                                   ├── beacon-stop.sh                   |
|     |                                   ├── beacon-git-pull.sh               |
|     |                                   └── beacon-startup.sh (+ caffeinate) |
|     +--> AppUpdateService           --> Pinned GitHub Releases + CryptoKit   |
|     |                                   SHA-256 + SecStaticCodeCheckValidity |
|     |                                   + codesign + spctl Gatekeeper check  |
|     +--> ServerLogSearchService     --> Sandboxed grep (-E/-F) on server.log |
|     +--> LogTroubleshootingService  --> Redacted log diagnostics via Local   |
|     |                                   Ollama or Anthropic Claude API       |
|     +--> TerminalIntegrationService --> NSWorkspace -> macOS Terminal.app    |
|     |                                   └── tail -f ~/beaconmac/server.log   |
|     +--> StartupSchedulerService    --> Apple launchd (~/Library/LaunchAgents)|
|     |                                   └── SMAppService.mainApp (Login Item)|
|     +--> SleepPreventionService     --> IOKit IOPMAssertion (App Sandbox)    |
|     |                                   └── System Settings Energy deep-link |
|     +--> GitDeployService           --> HTTPS api.github.com (/user, repos)  |
|     +--> OllamaService              --> GET/POST http://127.0.0.1:11434      |
|     +--> ClaudeService              --> GET https://api.anthropic.com/v1/    |
|     |                                   models (zero-token health check)     |
|     +--> AlertService               --> UNUserNotificationCenter (.app guard)|
|     +--> KeychainStore              --> macOS Security.framework Keychain    |
|     +--> FlatFileStore              --> Application Support/Beacon/          |
|                                         ├── activity.log (2 MB rotation)     |
|                                         └── config.json (atomic writes)      |
+------------------------------------------------------------------------------+
```

---

## Core Design Principles

### 1. Distribution Entitlements & Execution Boundary
BeaconMac ships with two explicit entitlements plists so signing never drops entitlements:
- **Mac App Store (`Sources/Beacon/Resources/Beacon.entitlements`)**: Sets `com.apple.security.app-sandbox = true`.
  - Network probes execute directly inside the sandbox via `URLSession` (`com.apple.security.network.client = true` + `NSAllowsLocalNetworking = true`).
  - Host scripts (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `launchctl`, `grep`) execute via Apple's approved **`NSUserUnixTask`** API against `~/Library/Application Scripts/<bundle-id>/`.
  - Sandboxed `NSUserUnixTask` captures stdout/stderr via temporary `FileHandle`s in the app container's `temporaryDirectory` (preventing XPC `UserScriptService` `EBADF / Bad file descriptor` errors and pipe buffer deadlocks), and never gates on `FileManager.fileExists(atPath:)` inside Application Scripts.
  - All 7 hook scripts are embedded inside `EmbeddedScripts.swift` with a 1-click `NSOpenPanel` installer inside the app (`Install Hook Scripts`) and a CLI installer (`Scripts/install-sandbox-scripts.sh`).
- **Direct Developer ID DMG (`Sources/Beacon/Resources/Beacon-DMG.entitlements`)**: Sets `com.apple.security.app-sandbox = false` with **Hardened Runtime** enabled via `codesign --options runtime --timestamp`.
  - Auto-installs embedded scripts on launch, runs local toolchains cleanly via `Foundation.Process`, and enables cryptographically verified in-place self-updates.
  - Built, Developer ID–signed, notarized (`xcrun notarytool`), stapled (`xcrun stapler`), and Gatekeeper-verified (`spctl`) via `Scripts/build-dmg.sh` and `.github/workflows/release-dmg.yml`.

### 2. Verified Self-Updater Security Boundary (`AppUpdateService.swift`)
- **Pinned Feed**: Hard-coded to `arjunmarri/beacon`. Any tampered `updateFeedRepo` or `autoInstallUpdates` flag in `config.json` is ignored; installs always require explicit user confirmation.
- **Strict Asset & Redirect Allowlist**: Accepts only `https://github.com/arjunmarri/beacon/releases/download/...` and `https://api.github.com/repos/arjunmarri/beacon/releases/assets/...` for `.dmg` / `.sha256` downloads, with a `URLSessionTaskDelegate` restricting HTTP redirects strictly to `objects.githubusercontent.com` and `release-assets.githubusercontent.com` (rejecting `raw.githubusercontent.com` and wildcard `*.githubusercontent.com`).
- **Cryptographic Verification Before Swap**:
  1. Verifies the downloaded DMG's streaming `CryptoKit.SHA256` digest against the release's published `.sha256` asset before mounting.
  2. Requires the currently running `.app` bundle to carry a real 10-character Apple Developer Team ID (ad-hoc builds refuse automatic binary replacement).
  3. Validates the staged `BeaconMac.app` via `SecStaticCodeCheckValidity` against a strict Apple Developer ID `SecRequirement` pinned to the running app's bundle ID and `subject.OU` (Team ID), followed by `/usr/bin/codesign --verify --deep --strict` and `/usr/sbin/spctl --assess --type execute`.
  4. Never strips `com.apple.quarantine` during replacement.

### 3. Reliable Loopback Health Probing (`LocalProcessService.swift`)
- Performs a non-blocking POSIX TCP pre-check (`127.0.0.1` and `::1`) before creating HTTP tasks so offline local servers do not spam `nw_socket_handle_socket_event` console errors.
- Bypasses system HTTP/SOCKS proxies (`connectionProxyDictionary = [:]`), connects directly to the reachable loopback address while preserving the original `Host` header, streams only response headers (`session.bytes(for:)`), disables redirect loops, and supports self-signed local HTTPS fallback.

### 4. Native macOS `launchd` Supervision & Sleep Prevention
- **Apple `launchd` Daemon (`beacon-launchd.sh` + `beacon-startup.sh`)**: Writes `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive = { SuccessfulExit = false }`, `ProcessType = Background`, logging to `~/beaconmac/server.log`) and manages it with `launchctl load -w` / `launchctl unload`.
- **Native IOKit Sleep Prevention (`SleepPreventionService.swift`)**: Holds `kIOPMAssertionTypePreventUserIdleSystemSleep` via `IOKit.pwr_mgt` while BeaconMac is running, and runs `/usr/bin/caffeinate -s` under `launchd` in headless mode.
- **GUI Login Launch (`SMAppService.mainApp`)**: Guarded by `.app` bundle detection so bare `swift run` launches never crash.

### 5. Security & Secret Isolation
- **macOS Keychain (`KeychainStore.swift`)**: Stores GitHub PATs and Anthropic Claude API keys under `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No secrets ever touch `config.json`, scripts, or `.env`.
- **Log, Terminal & AI Help Redaction (`SecretMasker`)**: Every activity log entry, terminal output line, server log search result, and AI Help troubleshooting payload passes through regex scrubbing before display, disk write, or AI submission (`ghp_*`, `gho_*`, `ghu_*`, `ghs_*`, `github_pat_*`, and `sk-ant-*`).
- **Input & SSRF Guards**:
  - Local app URLs are restricted to local hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, `*.local`, no embedded credentials).
  - Repository URLs must start with `https://` or `git@` with no whitespace or leading `-` flags; branch names reject `..` and leading `-`.
  - Dependency installer tool names and strategies are strictly allowlisted (`node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, `cargo`, `rust`, `git`; strategies `auto`, `homebrew`, `direct`).
  - Ollama probes strictly validate `http://127.0.0.1` / `http://localhost` on ports `11434–11440`.

### 6. Flat-File Storage (`FlatFileStore.swift`) & Release Portal (`index.html` + `server.ts`)
- `config.json`: Atomic writes for `managedApps`, `startupSchedule`, Ollama endpoint, poll interval, and alert settings.
- `activity.log`: Append-only structured text lines (`<ISO8601> [LEVEL] [SOURCE] <message>`), auto-rotated at 2 MB.
- `index.html` + `server.ts`: Standalone dark HTML release portal serving versioned Universal `.dmg` downloads (local or GitHub Releases) and dynamically zipping `swift-app/BeaconMac/`, `docs/`, `.github/`, `releases/releases.json`, `README.md`, `CHANGELOG.md`, `version.json`, and `LICENSE` via `/api/download-swift`.
