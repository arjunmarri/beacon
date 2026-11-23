# BeaconMac — Native SwiftUI macOS App (Apple App Store Ready)

A 100% native Swift 5.10 + SwiftUI macOS 14+ application built for **Mac App Store** distribution (App Sandbox enabled, zero Electron/Node runtime overhead, macOS Keychain secret storage, `SMAppService` Launch at Login, and flat-file logging).

## Step 1: Generate & Open `BeaconMac.xcodeproj`

### Option A — Generate `BeaconMac.xcodeproj` with XcodeGen (Recommended for App Store)
```bash
brew install xcodegen
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
This creates `BeaconMac.xcodeproj` and opens it in Xcode with **App Sandbox**, **Hardened Runtime**, `ServiceManagement.framework`, `Info.plist`, and **Mac App Store** entitlements pre-configured.

### Option B — Quick Local Run via Swift Package Manager
```bash
cd swift-app/BeaconMac
swift run
```
*(Or double-click `Package.swift` to open directly in Xcode.)*

---

## Step 2: Install App Sandbox Hook Scripts (Clone, Deps, Build, Deploy, Startup)
Apple's **Mac App Store App Sandbox** prevents sandboxed apps from directly spawning host binaries like `git`, `node`, `npm`, `pnpm`, `yarn`, or `bun`. BeaconMac uses Apple's official **`NSUserUnixTask`** API. Install all 6 hook scripts in one command:

```bash
cd swift-app/BeaconMac
./Scripts/install-sandbox-scripts.sh com.beaconmac.app
```
*(Replace `com.beaconmac.app` with your final Bundle Identifier.)*

This copies `beacon-deploy.sh`, `beacon-check-deps.sh`, `beacon-launchd.sh`, `beacon-restart.sh`, `beacon-stop.sh`, `beacon-git-pull.sh`, and `beacon-startup.sh` into:
```text
~/Library/Application Scripts/<your-bundle-id>/
```

---

## Step 3: Configure Signing & Bundle ID in Xcode
1. Select the **BeaconMac** project in Xcode → **BeaconMac** target → **Signing & Capabilities**.
2. Choose your **Apple Developer Program Team** (required for App Store Connect).
3. Change **Bundle Identifier** from `com.beaconmac.app` to your own unique reverse-DNS identifier (e.g. `com.yourname.beaconmac`).
4. Add a macOS **AppIcon** asset set (16px to 1024px) in `Assets.xcassets` — Apple requires a 1024×1024 icon for Mac App Store validation.

---

## Step 4: Archive & Upload to the Mac App Store
1. In Xcode's toolbar, choose **Any Mac (Apple Silicon, Intel)** as the build destination.
2. Click **Product → Archive**.
3. When Organizer opens, select the archive and click **Distribute App → App Store Connect → Upload**.
4. In **App Store Connect**, complete app metadata, privacy disclosures (no tracking; API keys stored locally in Keychain), and submit for App Review.

---

## Native macOS `launchd`, Live Logs & Sleep Prevention
- **Install & Start `launchd` Daemon**: Click **Install & Start launchd** inside BeaconMac to write and load `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive` on crash, logging to `~/beaconmac/server.log`).
- **Watch Live Logs**: Click **Watch Live Logs** or run `tail -f ~/beaconmac/server.log`.
- **Stop Background Service**: Click **Stop Service (`launchctl unload`)** or run `launchctl unload ~/Library/LaunchAgents/<bundle-id>.supervisor.plist`.
- **Prevent Mac from Sleeping**: BeaconMac uses native **IOKit** (`IOPMAssertionCreateWithName`, 100% App Sandbox compliant) while running, automatically invokes `caffeinate -s` under `launchd`, and provides a one-click **Energy Settings** shortcut to *System Settings → Energy / Displays*.

---

Designed by [SoroAI](https://soroai.com).
