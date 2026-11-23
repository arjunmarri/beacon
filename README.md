# BeaconMac

**BeaconMac** is a lightweight, native macOS traffic-light monitor built in **Swift 5.10 & SwiftUI (macOS 14+)** for **Mac App Store** distribution.

It monitors local Node.js / Vite servers on any localhost port with automatic crash recovery, tracks GitHub auto-deployments, monitors local **Ollama** LLMs with instant model switching, and checks **Claude API** health — all backed by encrypted **macOS Keychain** secret storage and local **flat-file logs** (zero database, zero login screen).

---

## Key Capabilities

- **Vite / Localhost Server Watchdog** — Monitor any `http://localhost:<port>` or `http://127.0.0.1:<port>` app with live HTTP status, response latency, uptime, and automatic crash restart via App-Sandbox-safe `NSUserUnixTask` hooks.
- **Git Auto-Deploy Watcher** — Paste your GitHub Personal Access Token directly in the app (stored encrypted in macOS Keychain), browse accessible repositories, poll remote branch commits, and trigger local pulls.
- **Local LLM (Ollama) Monitor** — Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`), displays latency & loaded VRAM, and switches active local models with one click.
- **Claude API Health Checker** — Paste your Anthropic API key (`sk-ant-...`) directly in the app (stored in macOS Keychain) and verify authentication, latency, and accessible models via `GET https://api.anthropic.com/v1/models` at zero token cost.
- **Flat-File Storage (No Database, No Login)** — Logs (`activity.log`, auto-rotated at 2 MB) and settings (`config.json`) live cleanly inside the sandboxed macOS Application Support directory.
- **Native Menu Bar Companion** — Live aggregate traffic-light status in the macOS menu bar with quick refresh and server restart controls.

See [FEATURES.md](./FEATURES.md), [ARCHITECTURE.md](./ARCHITECTURE.md), and [CONTEXT.md](./CONTEXT.md) for complete documentation.

---

## Repository Structure

```text
.
├── README.md
├── FEATURES.md
├── ARCHITECTURE.md
├── CONTEXT.md
├── CONTRIBUTING.md
├── LICENSE
├── index.html                           # Standalone dark landing page & download portal
├── server.ts                            # Lightweight static + Swift project ZIP server
└── swift-app/BeaconMac/                 # Native SwiftUI macOS 14+ App Store project
    ├── Package.swift
    ├── project.yml                      # XcodeGen spec for BeaconMac.xcodeproj
    ├── README-APP-STORE.md
    ├── Scripts/
    │   ├── generate-xcode-project.sh
    │   ├── beacon-restart.sh            # NSUserUnixTask Vite restart hook
    │   └── beacon-git-pull.sh           # NSUserUnixTask Git pull hook
    └── Sources/Beacon/
        ├── BeaconApp.swift
        ├── Models/BeaconModels.swift
        ├── Services/
        │   ├── AlertService.swift
        │   ├── BeaconController.swift
        │   ├── ClaudeService.swift
        │   ├── FlatFileStore.swift
        │   ├── GitDeployService.swift
        │   ├── KeychainStore.swift
        │   ├── LocalProcessService.swift
        │   └── OllamaService.swift
        ├── Views/
        │   ├── ActivityLogView.swift
        │   ├── ConfigurationView.swift
        │   ├── ContentView.swift
        │   ├── MenuBarStatusView.swift
        │   ├── ServiceCardsView.swift
        │   └── TrafficLightLampView.swift
        └── Resources/
            ├── Beacon.entitlements
            └── Info.plist
```

---

## Quick Start (macOS / Xcode)

### 1. Generate & Open `BeaconMac.xcodeproj`
```bash
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
*(Or run directly with Swift Package Manager: `swift run`)*

### 2. Configure Signing for the Mac App Store
1. Open **BeaconMac** target → **Signing & Capabilities** in Xcode.
2. Select your **Apple Developer Team** and set your unique **Bundle Identifier** (e.g. `com.yourorg.beaconmac`).
3. Add a 1024×1024 **AppIcon** asset set.
4. Select **Any Mac (Apple Silicon, Intel)** → **Product → Archive** → **Distribute App → App Store Connect**.

### 3. Optional App Sandbox Scripts (Local Restart & Git Pull)
To allow BeaconMac to restart your local Vite/Node server or run `git pull` while staying 100% App Store Sandbox compliant, install the two helper scripts into Apple's user scripts directory:

```bash
mkdir -p "$HOME/Library/Application Scripts/com.beaconmonitor.mac"
cp swift-app/BeaconMac/Scripts/beacon-restart.sh "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"
cp swift-app/BeaconMac/Scripts/beacon-git-pull.sh "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"
chmod +x "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"*.sh
```

---

## Secrets & Environment Variables

**No `.env` file is required for BeaconMac.** Paste your GitHub Personal Access Token and Anthropic Claude API key directly inside the macOS app — both are saved encrypted in your **macOS Keychain** (`Security.framework`) and restored automatically across restarts.

---

Designed by [SoroAI](https://soroai.com).
