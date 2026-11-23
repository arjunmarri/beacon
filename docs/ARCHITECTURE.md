# BeaconMac Architecture

BeaconMac is architected as a pure native **Swift 5.10 / SwiftUI (macOS 14+)** application designed to satisfy Apple's **Mac App Store App Sandbox** and **Hardened Runtime** requirements while providing full multi-app cloning, Vite/Node dependency checking, building, local deployment, Terminal integration, and startup/cron automation.

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
|     +--> LocalProcessService        --> Parallel HTTP probes for [ManagedApp]|
|     +--> AppDeploymentService       --> NSUserUnixTask + stdout/stderr Pipes |
|     |                                   ├── beacon-deploy.sh                 |
|     |                                   ├── beacon-check-deps.sh             |
|     |                                   ├── beacon-launchd.sh                |
|     |                                   ├── beacon-restart.sh                |
|     |                                   └── beacon-stop.sh                   |
|     +--> TerminalIntegrationService --> NSWorkspace -> macOS Terminal.app    |
|     |                                   └── tail -f ~/beaconmac/server.log   |
|     +--> StartupSchedulerService    --> Apple launchd (~/Library/LaunchAgents)|
|     |                                   ├── SMAppService.mainApp (Login Item)|
|     |                                   └── beacon-startup.sh (+ caffeinate) |
|     +--> SleepPreventionService     --> IOKit IOPMAssertion (App Sandbox)    |
|     |                                   └── System Settings Energy deep-link |
|     +--> GitDeployService           --> HTTPS api.github.com (/user, repos)  |
|     +--> OllamaService              --> GET/POST http://127.0.0.1:11434      |
|     +--> ClaudeService              --> GET https://api.anthropic.com/v1/    |
|     |                                   models (zero-token health check)     |
|     +--> AlertService               --> UNUserNotificationCenter             |
|     +--> KeychainStore              --> macOS Security.framework Keychain    |
|     +--> FlatFileStore              --> Application Support/Beacon/          |
|                                         ├── activity.log (2 MB rotation)     |
|                                         └── config.json (atomic writes)      |
+------------------------------------------------------------------------------+
```

---

## Core Design Principles

### 1. App Sandbox & `NSUserUnixTask` Boundary
Mac App Store apps must enable `com.apple.security.app-sandbox = true`, which prohibits directly spawning host binaries such as `/usr/local/bin/node`, `npm`, `pnpm`, `launchctl`, or `/usr/bin/git`.
- **Network probes** (all managed local app URLs, Ollama `127.0.0.1:11434`, GitHub HTTPS API, Anthropic HTTPS API) execute directly inside the sandbox using `URLSession`, enabled by `com.apple.security.network.client = true` and `NSAllowsLocalNetworking = true` in `Info.plist`.
- **Clone, dependency checks, builds, `launchd` load/unload, restarts, and stops** delegate to user-installed scripts in `~/Library/Application Scripts/<bundle-id>/` via Apple's officially approved `NSUserUnixTask` API, capturing both stdout and stderr pipes into BeaconMac's Integrated Terminal Output.
- **One-command installer**: `Scripts/install-sandbox-scripts.sh` installs all 7 sandbox hook scripts with `chmod +x` in a single command.

### 2. Native macOS `launchd` Supervision & Sleep Prevention
- **Apple `launchd` Daemon (`beacon-launchd.sh` + `beacon-startup.sh`)**: Writes `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive = { SuccessfulExit = false }`, `ProcessType = Background`, logging to `~/beaconmac/server.log`) and manages it with `launchctl load -w` / `launchctl unload`.
- **Native IOKit Sleep Prevention (`SleepPreventionService.swift`)**: Holds `kIOPMAssertionTypePreventUserIdleSystemSleep` via `IOKit.pwr_mgt` directly inside the Mac App Store Sandbox while BeaconMac is running, and passes `BEACONMAC_PREVENT_SLEEP=1` to `launchd` so `beacon-startup.sh` executes `/usr/bin/caffeinate -s` in headless mode.
- **GUI Login Launch (`SMAppService.mainApp`)**: Uses Apple's `ServiceManagement.framework` — 100% Mac App Store compliant. Optional `crontab` generation remains available as a secondary fallback.

### 3. Security & Secret Isolation
- **macOS Keychain (`KeychainStore.swift`)**: Stores GitHub PATs and Anthropic Claude API keys under `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No secrets ever touch `config.json`, scripts, or `.env`.
- **Log & Terminal Redaction (`SecretMasker`)**: Every activity log entry and terminal output line passes through regex scrubbing before display or disk write, redacting `ghp_*`, `gho_*`, `ghu_*`, `ghs_*`, `github_pat_*`, and `sk-ant-*` patterns.
- **Input & SSRF Guards**:
  - Local app URLs are restricted to local hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, `*.local`, no embedded credentials).
  - Repository URLs must start with `https://` or `git@` with no whitespace or leading `-` flags; branch names reject `..` and leading `-`.
  - Ollama probes strictly validate `http://127.0.0.1` / `http://localhost` on ports `11434–11440`.

### 4. Flat-File Storage (`FlatFileStore.swift`)
- `config.json`: Stores `managedApps`, `startupSchedule`, Ollama endpoint, poll interval, and alert settings via atomic writes (`Data.write(to:options:.atomic)`).
- `activity.log`: Append-only structured text lines (`<ISO8601> [LEVEL] [SOURCE] <message>`), auto-rotated whenever file size exceeds 2 MB.

### 5. Standalone Landing Page (`index.html` + `server.ts`)
- The repository root includes a minimal zero-framework dark HTML landing page (`index.html`) and a lightweight Express server (`server.ts`) that serves the page and dynamically zips `swift-app/BeaconMac/`, `docs/`, `README.md`, and `LICENSE` via `/api/download-swift`.
