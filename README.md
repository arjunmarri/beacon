# BeaconMac

**BeaconMac** is an open-source, lightweight native macOS **multi-app local deployer and traffic-light monitor** built in **Swift 5.10 & SwiftUI (macOS 14+)** for **Mac App Store** distribution.

Add any number of locally deployed **Vite, Node.js, Next.js, or custom apps** — BeaconMac clones each remote Git repository, checks system tools (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`) and required project libraries (`package.json` / `node_modules`), builds and deploys locally, streams live output to its **integrated Terminal console** (plus one-click `Terminal.app` launch), manages background startup natively via **Apple `launchd`** (`~/Library/LaunchAgents`) + **`SMAppService`**, prevents Mac sleep via **IOKit Power Management** and **`caffeinate -s`**, and monitors **Ollama** local LLMs and **Claude API** health — all backed by encrypted **macOS Keychain** storage and local **flat-file logs** (zero database, zero login screen).

---

## Documentation

All project documentation is organized in the [`docs/`](./docs/) folder:

- **[Setup Guide](./docs/setup-guide.md)** — Step-by-step configuration for Git repositories, macOS Keychain secrets, local `launchd` daemons, live logs, and sleep prevention
- **[Features](./docs/FEATURES.md)** — Multi-app clone/build/deploy pipeline, Vite/Node dependency auditing, Terminal integration, native `launchd` daemon, sleep prevention (`IOKit` + `caffeinate -s`), Ollama switcher, and Claude API health checker
- **[Architecture](./docs/ARCHITECTURE.md)** — System diagram, App Sandbox + `NSUserUnixTask` boundary, `launchd` + `IOKit` integration, Keychain security, and flat-file layout
- **[Context](./docs/CONTEXT.md)** — Problem statement, design decisions, and visual guidelines
- **[App Store Guide](./docs/APP-STORE.md)** — Step-by-step XcodeGen, code signing, sandbox scripts installer, and App Store Connect submission
- **[Contributing](./docs/CONTRIBUTING.md)** — Local macOS development workflow and coding guidelines

---

## Repository Structure

```text
.
├── README.md                            # Default repository README
├── LICENSE                              # Open-source MIT License
├── CHANGELOG.md                         # Semantic version changelog
├── version.json                         # Current BeaconMac version & DMG filename
├── .github/workflows/
│   └── release-dmg.yml                  # Automated macos-14 Universal DMG GitHub Release workflow
├── releases/
│   └── releases.json                    # Version manifest (DMG filenames, checksums, notes)
├── docs/
│   ├── APP-STORE.md                     # Mac App Store archive & sandbox guide
│   ├── ARCHITECTURE.md                  # System architecture & security model
│   ├── CONTEXT.md                       # Product philosophy & design decisions
│   ├── CONTRIBUTING.md                  # Contribution guidelines
│   ├── FEATURES.md                      # Detailed feature breakdown
│   └── setup-guide.md                   # Step-by-step Git, Keychain & launchd setup guide
├── index.html                           # Standalone dark DMG download portal & version history
├── server.ts                            # Serves index.html, versioned DMG downloads & source ZIP
└── swift-app/BeaconMac/                 # Native SwiftUI macOS 14+ App Store project
    ├── Package.swift
    ├── project.yml                      # XcodeGen spec for BeaconMac.xcodeproj
    ├── Scripts/
    │   ├── build-dmg.sh                 # Compiles Universal BeaconMac.app & packages versioned .dmg
    │   ├── bump-version.sh              # Bumps version across version.json, project.yml, releases.json & CHANGELOG.md
    │   ├── generate-xcode-project.sh    # Generates & opens BeaconMac.xcodeproj
    │   ├── install-sandbox-scripts.sh   # Installs all NSUserUnixTask hooks in one command
    │   ├── beacon-launchd.sh            # Native macOS launchd install/load/unload/status
    │   ├── beacon-startup.sh            # launchd supervisor -> ~/beaconmac/server.log + caffeinate -s
    │   ├── beacon-deploy.sh             # Clone/pull -> check deps -> install -> build -> deploy
    │   ├── beacon-check-deps.sh         # Audits git/node/npm/pnpm/yarn/bun & node_modules
    │   ├── beacon-restart.sh            # Restarts a managed local app on its port
    │   ├── beacon-stop.sh               # Stops a managed local app by port
    │   └── beacon-git-pull.sh           # Standalone git fetch/pull helper
    └── Sources/Beacon/
        ├── BeaconApp.swift
        ├── Models/BeaconModels.swift
        ├── Services/
        │   ├── AlertService.swift
        │   ├── AppDeploymentService.swift
        │   ├── BeaconController.swift
        │   ├── ClaudeService.swift
        │   ├── FlatFileStore.swift
        │   ├── GitDeployService.swift
        │   ├── KeychainStore.swift
        │   ├── LocalProcessService.swift
        │   ├── OllamaService.swift
        │   ├── SleepPreventionService.swift
        │   ├── StartupSchedulerService.swift
        │   └── TerminalIntegrationService.swift
        ├── Views/
        │   ├── ActivityLogView.swift
        │   ├── AppEditorSheet.swift
        │   ├── ConfigurationView.swift
        │   ├── ContentView.swift
        │   ├── MenuBarStatusView.swift
        │   ├── MultiAppSectionView.swift
        │   ├── ServiceCardsView.swift
        │   ├── StartupScheduleView.swift
        │   ├── TerminalPanelView.swift
        │   └── TrafficLightLampView.swift
        └── Resources/
            ├── Beacon.entitlements
            └── Info.plist
```

---

## Building & Versioning Direct `.dmg` Releases

BeaconMac maintains semantic versions via `version.json`, `releases/releases.json`, and `CHANGELOG.md`.

### Option A — Automated macOS DMG Build via GitHub Actions (Recommended)
Push any version tag (`v1.0.0`, `v1.0.1`, etc.) to GitHub. `.github/workflows/release-dmg.yml` runs on Apple's `macos-14` runner, builds a Universal (`arm64` + `x86_64`) `BeaconMac.app`, packages `BeaconMac-<version>-universal.dmg` + `.sha256`, and publishes a GitHub Release that the website automatically detects and serves directly at `/download/dmg`:

```bash
./swift-app/BeaconMac/Scripts/bump-version.sh 1.0.1 "Short summary of changes"
git add version.json releases/releases.json swift-app/BeaconMac/project.yml CHANGELOG.md
git commit -m "Release v1.0.1"
git tag v1.0.1 && git push origin main --tags
```

### Option B — Build the `.dmg` Locally on Your Mac
```bash
chmod +x swift-app/BeaconMac/Scripts/*.sh
./swift-app/BeaconMac/Scripts/build-dmg.sh
```
This outputs `releases/BeaconMac-<version>-universal.dmg` and updates `releases/releases.json` with the exact SHA-256 checksum and byte size. The web server automatically serves any `.dmg` file present in `releases/`.

---

## Native macOS Operations (`launchd`, Logs & Sleep Prevention)

1. **Watch live logs**:
   ```bash
   tail -f ~/beaconmac/server.log
   # or per-app logs:
   tail -f ~/beaconmac/logs/<app>-<port>.log
   ```
2. **Stop the `launchd` background service**:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist
   ```
3. **Prevent Mac from sleeping** (so local servers stay reachable):
   - Toggle **Prevent Mac Sleep (IOKit + `caffeinate -s`)** inside BeaconMac (holds a native IOKit power assertion while BeaconMac is open, and runs `caffeinate -s` automatically inside the `launchd` supervisor), or run `caffeinate -s` manually / click **Energy Settings** to adjust *System Settings → Energy / Displays → Prevent automatic sleeping when display is off*.

---

## Quick Start (macOS / Xcode)

### 1. Generate & Open `BeaconMac.xcodeproj`
```bash
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
*(Or run directly with Swift Package Manager: `swift run`)*

### 2. Install App Sandbox Hook Scripts (One Command)
To enable local `git clone`, Vite/Node dependency checks, builds, restarts, stops, and native `launchd` background management while remaining 100% Mac App Store App Sandbox compliant (`NSUserUnixTask`):

```bash
./Scripts/install-sandbox-scripts.sh com.beaconmac.app
```
*(Replace `com.beaconmac.app` with your final Bundle Identifier.)*

### 3. Configure Signing for the Mac App Store
1. Open the **BeaconMac** target → **Signing & Capabilities** in Xcode.
2. Select your **Apple Developer Team** and set your unique **Bundle Identifier** (e.g. `com.yourorg.beaconmac`).
3. Add a 1024×1024 **AppIcon** asset set.
4. Select **Any Mac (Apple Silicon, Intel)** → **Product → Archive** → **Distribute App → App Store Connect**.

---

## Secrets & Environment Variables

**No `.env` file is required for BeaconMac.** Paste your GitHub Personal Access Token and Anthropic Claude API key directly inside the macOS app — both are saved encrypted in your **macOS Keychain** (`Security.framework`) and restored automatically across restarts.

---

## License

BeaconMac is open-source software licensed under the **[MIT License](./LICENSE)**.

---

Designed by [SoroAI](https://soroai.com).
