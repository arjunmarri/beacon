# Beacon — Native SwiftUI macOS App (Apple App Store Ready)

A 100% native Swift 5.10 + SwiftUI macOS 14+ rewrite of **Beacon** built for Mac App Store distribution (App Sandbox enabled, zero Electron/Node runtime overhead, macOS Keychain secret storage, and flat-file logging).

## Features Included
- **Vite / Localhost Server Watchdog**: Monitors any `http://localhost:<port>` or `http://127.0.0.1:<port>` app, measures live HTTP status & latency, tracks uptime & consecutive failure recovery, and triggers App-Store-safe restarts via `NSUserUnixTask`.
- **Git Auto-Deploy Watcher**: Paste your GitHub Personal Access Token directly in the app (stored encrypted in macOS Keychain), verify scopes & accessible repositories, monitor remote commits on your chosen branch, and trigger local pull/redeploy hooks.
- **Local LLM (Ollama) Monitor**: Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`), displays latency, loaded VRAM, and switches active local models on demand.
- **Claude API Health Checker**: Paste your Anthropic API key (`sk-ant-...`) directly in the app (stored in macOS Keychain), verify live status & latency via `GET https://api.anthropic.com/v1/models` (zero token cost), and browse accessible Claude models.
- **Flat-File Activity Log & Config (No Database, No Login)**: Stored inside the sandboxed container at:
  - `~/Library/Containers/com.beaconmonitor.mac/Data/Library/Application Support/Beacon/activity.log`
  - `~/Library/Containers/com.beaconmonitor.mac/Data/Library/Application Support/Beacon/config.json`
- **Menu Bar Companion**: Shows live aggregate traffic-light status in the macOS menu bar with one-click Refresh and Restart controls.

---

## Step 1: Generate & Open the Xcode Project

### Option A — Generate `Beacon.xcodeproj` with XcodeGen (Recommended for App Store)
```bash
brew install xcodegen
cd BeaconMac
chmod +x Scripts/generate-xcode-project.sh
./Scripts/generate-xcode-project.sh
```
This creates `Beacon.xcodeproj` and opens it in Xcode with **App Sandbox**, **Hardened Runtime**, `Info.plist`, and **Mac App Store** entitlements pre-configured.

### Option B — Quick Local Run via Swift Package Manager
```bash
cd BeaconMac
swift run
```
(Or double-click `Package.swift` to open directly in Xcode.)

---

## Step 2: Configure Signing & Bundle ID in Xcode
1. Select the **Beacon** project in Xcode -> **Beacon** target -> **Signing & Capabilities**.
2. Choose your **Apple Developer Program Team** (required for App Store Connect).
3. Change **Bundle Identifier** from `com.beaconmonitor.mac` to your own unique reverse-DNS identifier (for example `com.yourname.beacon`).
4. Add a macOS **AppIcon** asset set (16px to 1024px) in `Assets.xcassets` — Apple requires a 1024×1024 icon for Mac App Store validation.

---

## Step 3: Archive & Upload to the Mac App Store
1. In Xcode’s toolbar, choose **Any Mac (Apple Silicon, Intel)** as the build destination.
2. Click **Product → Archive**.
3. When Organizer opens, select the archive and click **Distribute App → App Store Connect → Upload**.
4. In **App Store Connect**, complete app metadata, privacy disclosures (no tracking; API keys stored locally in Keychain), and submit for App Review.

---

## App Sandbox Note for Restarting Local Node/Vite & Git Pull
Apple’s **Mac App Store App Sandbox** prevents sandboxed apps from directly spawning arbitrary binaries like `/usr/local/bin/node` or `/usr/bin/git`. Beacon handles this using Apple’s official **`NSUserUnixTask`** API:

1. In Beacon, open **Configuration → Sandbox Hook Scripts**, or copy the two sample scripts into your user scripts folder:
   ```bash
   mkdir -p "$HOME/Library/Application Scripts/com.beaconmonitor.mac"
   cp Scripts/beacon-restart.sh "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"
   cp Scripts/beacon-git-pull.sh "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"
   chmod +x "$HOME/Library/Application Scripts/com.beaconmonitor.mac/"*.sh
   ```
   *(Replace `com.beaconmonitor.mac` with your final Bundle Identifier.)*
2. Because Apple explicitly approves `NSUserUnixTask` for user-installed scripts in `~/Library/Application Scripts/<bundle-id>/`, Beacon stays 100% App Store compliant while still restarting your local Vite server and pulling Git updates automatically.
