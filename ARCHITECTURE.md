# BeaconMac Architecture

BeaconMac is architected as a pure native **Swift 5.10 / SwiftUI (macOS 14+)** application designed to satisfy Apple's **Mac App Store App Sandbox** and **Hardened Runtime** requirements while preserving full local developer ergonomics.

---

## High-Level Component Diagram

```text
+-----------------------------------------------------------------------+
|                        BeaconMac (SwiftUI macOS 14+)                  |
|                                                                       |
|  [BeaconApp] ---> WindowGroup (ContentView)                           |
|               \-> MenuBarExtra (MenuBarStatusView)                    |
|                                                                       |
|  [BeaconController (@MainActor @Observable)]                          |
|     |--- 3s Polling Task (structured Swift Concurrency)               |
|     |                                                                 |
|     +--> LocalProcessService  --> GET http://localhost:<port>         |
|     |                         \-> NSUserUnixTask (beacon-restart.sh)  |
|     |                                                                 |
|     +--> GitDeployService     --> HTTPS api.github.com (/user,        |
|     |                             /user/repos, /repos/.../commits)    |
|     |                         \-> NSUserUnixTask (beacon-git-pull.sh) |
|     |                                                                 |
|     +--> OllamaService        --> GET/POST http://127.0.0.1:11434     |
|     |                                                                 |
|     +--> ClaudeService        --> GET https://api.anthropic.com/v1/   |
|     |                             models (zero-token health check)    |
|     |                                                                 |
|     +--> AlertService         --> UNUserNotificationCenter            |
|     +--> KeychainStore        --> macOS Security.framework Keychain   |
|     +--> FlatFileStore        --> Application Support/Beacon/         |
|                                   ├── activity.log (2 MB rotation)    |
|                                   └── config.json (atomic writes)     |
+-----------------------------------------------------------------------+
```

---

## Core Design Principles

### 1. App Sandbox & `NSUserUnixTask` Boundary
Mac App Store apps must enable `com.apple.security.app-sandbox = true`, which prohibits directly spawning host binaries such as `/usr/local/bin/node`, `npm`, or `/usr/bin/git`.
- **Network probes** (`localhost`, Ollama `127.0.0.1:11434`, GitHub HTTPS API, Anthropic HTTPS API) execute directly inside the sandbox using `URLSession`, enabled by `com.apple.security.network.client = true` and `NSAllowsLocalNetworking = true` in `Info.plist`.
- **Local process restarts & Git pulls** delegate to user-installed shell scripts in `~/Library/Application Scripts/<bundle-id>/` via Apple's officially approved `NSUserUnixTask` API.

### 2. State Management & Concurrency
- `BeaconController` is annotated with `@MainActor` and `@Observable` (macOS 14 Observation framework), providing fine-grained SwiftUI updates without Combine boilerplate.
- All service clients (`LocalProcessService`, `GitDeployService`, `OllamaService`, `ClaudeService`, `KeychainStore`, `AlertService`) are `Sendable` and use isolated ephemeral `URLSession` instances with tight timeouts so unreachable local ports never stall the UI.
- A single structured `Task` polling loop drives staggered cadences:
  - **Every 3s**: Localhost Vite HTTP probe
  - **Every 15s**: Ollama daemon health probe
  - **Configurable (default 60s)**: GitHub branch commit poll
  - **Every 60s**: Claude API health check (when key is present)

### 3. Security & Secret Isolation
- **macOS Keychain (`KeychainStore.swift`)**: Stores GitHub PATs and Anthropic Claude API keys under `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No secrets ever touch `config.json` or `.env`.
- **Log Redaction (`SecretMasker`)**: Every log entry passes through regex scrubbing before hitting `activity.log`, redacting `ghp_*`, `gho_*`, `ghu_*`, `ghs_*`, `github_pat_*`, and `sk-ant-*` patterns.
- **Loopback-Only SSRF Guards**:
  - Localhost server monitoring strictly validates `http(s)://localhost:*` or `http(s)://127.0.0.1:*` with no embedded credentials.
  - Ollama probes strictly validate `http://127.0.0.1` / `http://localhost` on ports `11434–11440`.

### 4. Flat-File Storage (`FlatFileStore.swift`)
- `config.json`: Pretty-printed JSON written atomically (`Data.write(to:options:.atomic)`).
- `activity.log`: Append-only structured text lines (`<ISO8601> [LEVEL] [SOURCE] <message>`), keeping up to 400 entries in memory and rotating automatically whenever file size exceeds 2 MB.

### 5. Standalone Landing Page (`index.html` + `server.ts`)
- The repository root includes a minimal zero-framework dark HTML landing page (`index.html`) and a lightweight Express server (`server.ts`) that serves the page and packages `swift-app/BeaconMac/` (plus root docs) on the fly via `/api/download-swift`.
