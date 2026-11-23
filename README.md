# BeaconMac

**BeaconMac** is an open-source, lightweight native macOS traffic-light monitor built in **Swift 5.10 & SwiftUI (macOS 14+)** for **Mac App Store** distribution.

It monitors local Node.js / Vite servers on any localhost port with automatic crash recovery, tracks GitHub auto-deployments, monitors local **Ollama** LLMs with instant model switching, and checks **Claude API** health — all backed by encrypted **macOS Keychain** secret storage and local **flat-file logs** (zero database, zero login screen).

---

## Documentation

All project documentation is organized in the [`docs/`](./docs/) folder:

- **[Features](./docs/FEATURES.md)** — Full feature breakdown (Vite/localhost watchdog, Git auto-deploy, Ollama switcher, Claude checker, flat-file logs, and menu bar companion)
- **[Architecture](./docs/ARCHITECTURE.md)** — System diagram, App Sandbox + `NSUserUnixTask` boundary, concurrency, Keychain security, and flat-file layout
- **[Context](./docs/CONTEXT.md)** — Problem statement, design decisions, and visual guidelines
- **[App Store Guide](./docs/APP-STORE.md)** — Step-by-step XcodeGen, code signing, sandbox scripts, and App Store Connect submission
- **[Contributing](./docs/CONTRIBUTING.md)** — Local macOS development workflow and coding guidelines

---

## Repository Structure

```text
.
├── README.md                            # Default repository README
├── LICENSE                              # Open-source MIT License
├── docs/
│   ├── APP-STORE.md                     # Mac App Store archive & sandbox guide
│   ├── ARCHITECTURE.md                  # System architecture & security model
│   ├── CONTEXT.md                       # Product philosophy & design decisions
│   ├── CONTRIBUTING.md                  # Contribution guidelines
│   └── FEATURES.md                      # Detailed feature breakdown
├── index.html                           # Standalone dark landing page & download portal
├── server.ts                            # Lightweight static + Swift project ZIP server
└── swift-app/BeaconMac/                 # Native SwiftUI macOS 14+ App Store project
    ├── Package.swift
    ├── project.yml                      # XcodeGen spec for BeaconMac.xcodeproj
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
1. Open the **BeaconMac** target → **Signing & Capabilities** in Xcode.
2. Select your **Apple Developer Team** and set your unique **Bundle Identifier** (e.g. `com.yourorg.beaconmac`).
3. Add a 1024×1024 **AppIcon** asset set.
4. Select **Any Mac (Apple Silicon, Intel)** → **Product → Archive** → **Distribute App → App Store Connect**.

### 3. Optional App Sandbox Scripts (Local Restart & Git Pull)
To allow BeaconMac to restart your local Vite/Node server or run `git pull` while staying 100% App Store Sandbox compliant, install the two helper scripts into Apple's user scripts directory:

```bash
mkdir -p "$HOME/Library/Application Scripts/com.beaconmac.app"
cp swift-app/BeaconMac/Scripts/beacon-restart.sh "$HOME/Library/Application Scripts/com.beaconmac.app/"
cp swift-app/BeaconMac/Scripts/beacon-git-pull.sh "$HOME/Library/Application Scripts/com.beaconmac.app/"
chmod +x "$HOME/Library/Application Scripts/com.beaconmac.app/"*.sh
```

---

## Secrets & Environment Variables

**No `.env` file is required for BeaconMac.** Paste your GitHub Personal Access Token and Anthropic Claude API key directly inside the macOS app — both are saved encrypted in your **macOS Keychain** (`Security.framework`) and restored automatically across restarts.

---

## License

BeaconMac is open-source software licensed under the **[MIT License](./LICENSE)**.

---

Designed by [SoroAI](https://soroai.com).
