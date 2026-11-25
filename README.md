# BeaconMac

**BeaconMac** is an open-source, lightweight native macOS **multi-app local deployer, Node.js app host, and traffic-light monitor** built in **Swift 5.10 & SwiftUI (macOS 14+)** for **Mac App Store** and **signed, notarized Universal DMG** distribution.

Add any number of locally deployed **Vite, Node.js, Next.js, or custom apps** — BeaconMac clones each remote Git repository, audits and **silently installs missing dependencies** (`node`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, `git`) by project type via Homebrew or verified direct official downloads, builds and deploys locally, hosts static/built apps or local proxies on its **Built-In Node.js Server** (`http://127.0.0.1:4173`), publishes any local app, Node host, **Local Ollama LLM**, or custom localhost port over HTTPS via **1-click Cloudflare Quick Tunnels** (`*.trycloudflare.com`, zero API token required), streams live output to its **integrated Terminal & Activity Log consoles** (with **auto-scroll + Pause/Resume**, **per-entry copy**, **Server Log Search**, and **Export Logs to `.txt`/`.json`**), switches seamlessly between **Dark & White (Light) themes in real time** with high-contrast **Blue section headers**, manages background startup natively via **Apple `launchd`** (`~/Library/LaunchAgents`) + **`SMAppService`**, prevents Mac sleep via **IOKit Power Management** and **`caffeinate -s`**, and monitors **Local Ollama** alongside **GitHub** (encrypted in **macOS Keychain**) with local **flat-file logs** (zero database, zero login screen, zero analytics).

---

## Documentation

All project documentation is organized in the [`docs/`](./docs/) folder:

- **[Setup Guide](./docs/setup-guide.md)** — Step-by-step configuration for Git repositories, macOS Keychain GitHub token, Built-In Node.js Server, 1-click Cloudflare Quick Tunnels (local apps & Ollama), local `launchd` daemons, live logs, Export Logs, White/Dark themes, and sleep prevention
- **[Features](./docs/FEATURES.md)** — Full feature breakdown covering Multi-App Deploy, Built-In Node.js Server, 1-Click Cloudflare Quick Tunnels, Local Ollama Monitoring, Silent Dependency Installer, Log Auto-Scroll / Copy / Export, Blue Headers & Real-Time Theme Switcher, `launchd`, and sleep prevention
- **[Architecture](./docs/ARCHITECTURE.md)** — System diagram, App Sandbox + `NSUserUnixTask` boundary (10 embedded scripts), Built-In Node Host & Cloudflare Quick Tunnel architecture, `launchd` + `IOKit`, Keychain security, and flat-file layout
- **[Context](./docs/CONTEXT.md)** — Problem statement, product decisions, and Dark/White + Blue-header design system
- **[App Store Guide](./docs/APP-STORE.md)** — Step-by-step XcodeGen, code signing, sandbox scripts installer, and App Store Connect submission
- **[Privacy Policy (Placeholder)](./docs/PRIVACY_POLICY.md)** — Local-first privacy disclosure template for Mac App Store compliance
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
│   ├── PRIVACY_POLICY.md                # Mac App Store privacy policy placeholder
│   └── setup-guide.md                   # Step-by-step Git, Keychain, Node Host, Tunnels & launchd guide
├── index.html                           # Standalone dark DMG download portal, preview & FAQ
├── privacy.html                         # Hosted Privacy Policy page (/privacy)
├── server.ts                            # Serves index.html, /privacy, versioned DMG downloads & source ZIP
└── swift-app/BeaconMac/                 # Native SwiftUI macOS 14+ App Store project
    ├── Package.swift
    ├── project.yml                      # XcodeGen spec for BeaconMac.xcodeproj
    ├── Scripts/
    │   ├── build-dmg.sh                 # Compiles Universal BeaconMac.app & packages versioned .dmg
    │   ├── bump-version.sh              # Bumps version across version.json, project.yml, releases.json & CHANGELOG.md
    │   ├── generate-xcode-project.sh    # Generates & opens BeaconMac.xcodeproj
    │   ├── install-sandbox-scripts.sh   # Installs all 10 NSUserUnixTask hooks in one command
    │   ├── beacon-launchd.sh            # Native macOS launchd install/load/unload/status + server.log grep
    │   ├── beacon-startup.sh            # launchd supervisor -> ~/beaconmac/server.log + caffeinate -s
    │   ├── beacon-deploy.sh             # Clone/pull -> check deps -> install -> build -> deploy
    │   ├── beacon-check-deps.sh         # Audits & silently installs runtimes & project deps
    │   ├── beacon-restart.sh            # Restarts a managed local app on its port
    │   ├── beacon-stop.sh               # Cleanly stops a managed local app by port
    │   ├── beacon-git-pull.sh           # Standalone git fetch/pull helper
    │   ├── beacon-node-server.sh        # Starts/stops/reloads the Built-In Node.js Server
    │   ├── beacon-node-host.mjs         # Zero-dependency Node.js multi-app static & proxy host
    │   └── beacon-cloudflared.sh        # Manages detached Cloudflare Quick Tunnel sessions
    └── Sources/Beacon/
        ├── BeaconApp.swift
        ├── Models/BeaconModels.swift
        ├── Services/
        │   ├── AlertService.swift
        │   ├── AppDeploymentService.swift
        │   ├── BeaconController.swift
        │   ├── BuiltInNodeServerService.swift
        │   ├── CloudflareTunnelService.swift
        │   ├── EmbeddedScripts.swift
        │   ├── FlatFileStore.swift
        │   ├── GitDeployService.swift
        │   ├── KeychainStore.swift
        │   ├── LocalProcessService.swift
        │   ├── LogExportService.swift
        │   ├── OllamaService.swift
        │   ├── ServerLogSearchService.swift
        │   ├── SleepPreventionService.swift
        │   ├── StartupSchedulerService.swift
        │   └── TerminalIntegrationService.swift
        ├── Views/
        │   ├── ActivityLogView.swift
        │   ├── AppEditorSheet.swift
        │   ├── BeaconTheme.swift
        │   ├── BuiltInNodeServerView.swift
        │   ├── CloudflareTunnelSectionView.swift
        │   ├── ConfigurationView.swift
        │   ├── ContentView.swift
        │   ├── MenuBarStatusView.swift
        │   ├── MultiAppSectionView.swift
        │   ├── PrerequisiteInstallerSheet.swift
        │   ├── PrivacyPolicySheet.swift
        │   ├── ServerLogSearchView.swift
        │   ├── ServiceCardsView.swift
        │   ├── StartupScheduleView.swift
        │   ├── TerminalPanelView.swift
        │   └── TrafficLightLampView.swift
        └── Resources/
            ├── Beacon.entitlements          # Mac App Store (App Sandbox enabled)
            ├── Beacon-DMG.entitlements      # Direct Developer ID DMG (Hardened Runtime, unsandboxed)
            ├── Info.plist
            ├── PRIVACY_POLICY.md            # Bundled privacy disclosure
            └── PrivacyInfo.xcprivacy        # Apple Privacy Manifest (NSPrivacyTracking = false)
```

---

## Building & Versioning Direct `.dmg` Releases

BeaconMac maintains semantic versions via `version.json`, `releases/releases.json`, and `CHANGELOG.md`.

### Distribution Entitlements
- **Mac App Store (`Sources/Beacon/Resources/Beacon.entitlements`)**: Ships with `com.apple.security.app-sandbox = true` and uses `NSUserUnixTask` hook scripts in `~/Library/Application Scripts/<bundle-id>/`. All updates for Mac App Store builds are delivered exclusively through the App Store.
- **Direct Developer ID DMG (`Sources/Beacon/Resources/Beacon-DMG.entitlements`)**: Ships intentionally unsandboxed (`com.apple.security.app-sandbox = false`) with **Hardened Runtime** enabled so direct DMG users can run local toolchains (`git`, `node`, `npm`, `cloudflared`, `launchctl`) directly. Set `BEACONMAC_SANDBOX_DMG=1` if you want to package a sandboxed DMG instead.

### Option A — Automated Signed & Notarized DMG via GitHub Actions (Recommended)
Configure these repository secrets under **Settings → Secrets and variables → Actions** before tagging a public release (the workflow intentionally fails if any signing or notarization secret is missing):

- `APPLE_CERTIFICATE_P12_BASE64` — Base64-encoded Developer ID Application `.p12` certificate
- `APPLE_CERTIFICATE_PASSWORD` — Export password for the `.p12` file
- `APPLE_SIGN_IDENTITY` — Exact signing identity (e.g. `Developer ID Application: Your Name (TEAMID)`)
- `APPLE_ID` — Apple Developer account email used for `notarytool`
- `APPLE_TEAM_ID` — 10-character Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD` — App-specific password generated at appleid.apple.com

Push any version tag (`v1.1.0`, `v1.1.1`, etc.) to GitHub. `.github/workflows/release-dmg.yml` runs on `macos-14`, builds a Universal (`arm64` + `x86_64`) `BeaconMac.app`, signs it with Hardened Runtime + `Beacon-DMG.entitlements`, notarizes & staples the DMG via `notarytool`/`stapler`, verifies `codesign` & `spctl`, computes the final `.sha256`, and publishes the GitHub Release:

```bash
./swift-app/BeaconMac/Scripts/bump-version.sh 1.1.1 "Short summary of changes"
git add version.json releases/releases.json swift-app/BeaconMac/project.yml CHANGELOG.md
git commit -m "Release v1.1.1"
git tag v1.1.1 && git push origin main --tags
```

### Option B — Build the `.dmg` Locally on Your Mac
```bash
chmod +x swift-app/BeaconMac/Scripts/*.sh
# For a signed, notarized release DMG:
REQUIRE_SIGNING=1 \
APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_NOTARY_PROFILE="BeaconMacNotary" \
./swift-app/BeaconMac/Scripts/build-dmg.sh

# Or for local-only development testing (ad-hoc signed with entitlements — not for distribution):
./swift-app/BeaconMac/Scripts/build-dmg.sh
```
This outputs `releases/BeaconMac-<version>-universal.dmg` + `.sha256` and updates `releases/releases.json` with the exact post-stapling SHA-256 checksum and byte size. The web server automatically serves any `.dmg` file present in `releases/`.

---

## Native macOS Operations (`launchd`, Tunnels, Logs & Sleep Prevention)

1. **Expose local apps or Ollama via 1-Click Cloudflare Quick Tunnels**:
   - Click **Expose via Cloudflare Tunnel** on any Managed Local App, **Expose via Cloudflare** on the **Local LLM (Ollama)** card (with automatic `Host: localhost:<port>` header rewrite), or **Expose Node Host** / **Expose Port** in the Cloudflare Tunnels section to publish an instant HTTPS `*.trycloudflare.com` URL — no Cloudflare API token required.
2. **Load apps directly into the Built-In Node.js Server**:
   - Mount any static/built folder (`dist/`, `build/`, `out/`, `public/`, or root `index.html` with SPA fallback) or local proxy port onto `http://127.0.0.1:4173` — or click **Load in Node Host** on any managed app.
3. **Watch live logs or export session logs**:
   ```bash
   tail -f ~/beaconmac/server.log
   # or per-app logs:
   tail -f ~/beaconmac/logs/<app>-<port>.log
   ```
   Inside BeaconMac, use **Pause auto-scroll**, per-entry **Copy**, **Server Log Search**, and **Export Logs** (`.txt` or `.json`) in the Activity Log panel.
4. **Stop the `launchd` background service**:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist
   ```
5. **Prevent Mac from sleeping** (so local servers stay reachable):
   - Toggle **Prevent Mac Sleep (IOKit + `caffeinate -s`)** inside BeaconMac (holds a native IOKit power assertion while BeaconMac is open, and runs `caffeinate -s` automatically under `launchd`), or run `caffeinate -s` manually / click **Energy Settings** to adjust *System Settings → Energy / Displays → Prevent automatic sleeping when display is off*.

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
To enable local `git clone`, dependency installs, builds, restarts, stops, the Built-In Node.js Server, Cloudflare Quick Tunnels, and native `launchd` background management while remaining 100% Mac App Store App Sandbox compliant (`NSUserUnixTask`):

```bash
./Scripts/install-sandbox-scripts.sh com.beaconmac.app
```
*(Replace `com.beaconmac.app` with your final Bundle Identifier.)*

### 3. Configure Signing for the Mac App Store
1. Open the **BeaconMac** target → **Signing & Capabilities** in Xcode.
2. Select your **Apple Developer Team** and set your unique **Bundle Identifier** (e.g. `com.yourorg.beaconmac`).
3. Ensure your **AppIcon** asset set (16px to 1024px) is present and replace the placeholder URL in `Info.plist` (`BeaconPrivacyPolicyURL`) with your published HTTPS Privacy Policy URL.
4. Select **Any Mac (Apple Silicon, Intel)** → **Product → Archive** → **Distribute App → App Store Connect**.

---

## Secrets & Environment Variables

**No `.env` file is required for BeaconMac.** Paste your **GitHub Personal Access Token** directly inside the **GitHub Account** card — it is stored encrypted in your **macOS Keychain** (`Security.framework`, service `com.beaconmac.app`), automatically redacted from logs and exports, and restored seamlessly across restarts.

---

## License

BeaconMac is open-source software licensed under the **[MIT License](./LICENSE)**.

---

Designed by [SoroAI](https://soroai.com).
