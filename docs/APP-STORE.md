# BeaconMac — Mac App Store & Direct Developer ID Distribution Guide

A 100% native Swift 5.10 + SwiftUI macOS 14+ application supporting both **Mac App Store** (`Beacon.entitlements`, App Sandbox enabled) and **Direct Developer ID DMG** (`Beacon-DMG.entitlements`, Hardened Runtime + Apple Notarization) distribution.

---

## Entitlements Overview

BeaconMac maintains two explicit entitlements files so every build path is signed with deliberate permissions:

| Distribution Channel | Entitlements File | App Sandbox | Self-Updater |
| :--- | :--- | :--- | :--- |
| **Mac App Store** | `Sources/Beacon/Resources/Beacon.entitlements` | Enabled (`true`) | Managed by App Store (links to release page) |
| **Direct Developer ID DMG** | `Sources/Beacon/Resources/Beacon-DMG.entitlements` | Disabled (`false`) + Hardened Runtime | Verified in-place updater (SHA-256 + Team ID + `codesign` + `spctl`) |

*(Set `BEACONMAC_SANDBOX_DMG=1` when running `Scripts/build-dmg.sh` if you prefer to ship a sandboxed DMG using `Beacon.entitlements`.)*

---

## Step 1: Generate & Open `BeaconMac.xcodeproj`

### Option A — Generate `BeaconMac.xcodeproj` with XcodeGen (Recommended for App Store)
```bash
brew install xcodegen
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
This creates `BeaconMac.xcodeproj` and opens it in Xcode with **App Sandbox**, **Hardened Runtime**, `ServiceManagement.framework`, `Security.framework`, `IOKit.framework`, `Info.plist`, and **Mac App Store** entitlements (`Beacon.entitlements`) pre-configured.

### Option B — Quick Local Run via Swift Package Manager
```bash
cd swift-app/BeaconMac
swift run
```
*(Or double-click `Package.swift` to open directly in Xcode.)*

---

## Step 2: Install App Sandbox Hook Scripts (Mac App Store Builds)
Apple's **Mac App Store App Sandbox** prevents sandboxed apps from directly spawning host binaries like `git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `nginx`, or `launchctl`. BeaconMac uses Apple's official **`NSUserUnixTask`** API with all 10 helper scripts embedded inside the app:

- **Inside BeaconMac (1-Click):** Click **Install Hook Scripts** in the setup banner to write all 10 scripts into `~/Library/Application Scripts/<your-bundle-id>/` via macOS's `NSOpenPanel`.
- **Or via Terminal (One Command):**
  ```bash
  cd swift-app/BeaconMac
  ./Scripts/install-sandbox-scripts.sh com.beaconmac.app
  ```
  *(Replace `com.beaconmac.app` with your final Bundle Identifier.)*

This installs `beacon-deploy.sh`, `beacon-check-deps.sh`, `beacon-launchd.sh`, `beacon-restart.sh`, `beacon-stop.sh`, `beacon-git-pull.sh`, `beacon-startup.sh`, `beacon-node-server.sh`, `beacon-node-host.mjs`, and `beacon-nginx.sh`. Non-sandboxed launches (`swift run` and Direct Developer ID DMGs) auto-install all 10 scripts automatically on boot.

---

## Step 3: Configure Signing & Bundle ID in Xcode (Mac App Store)
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

## Step 5: Direct Developer ID DMG Signing & Notarization (GitHub Actions / Local)
For direct `.dmg` releases outside the Mac App Store, `.github/workflows/release-dmg.yml` requires all six Developer ID & notarization secrets in **Repository Settings → Secrets and variables → Actions** and fails fast if any are missing:
- `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGN_IDENTITY`
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`

To build, sign, notarize, staple, and Gatekeeper-verify a release DMG locally:
```bash
REQUIRE_SIGNING=1 \
APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_NOTARY_PROFILE="BeaconMacNotary" \
./swift-app/BeaconMac/Scripts/build-dmg.sh
```

---

## Native macOS `launchd`, Live Logs & Sleep Prevention
- **Install & Start `launchd` Daemon**: Click **Install & Start launchd** inside BeaconMac to write and load `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` (`RunAtLoad = true`, `KeepAlive` on crash, logging to `~/beaconmac/server.log`).
- **Watch Live Logs**: Click **Watch Live Logs** or run `tail -f ~/beaconmac/server.log`.
- **Stop Background Service**: Click **Stop Service (`launchctl unload`)** or run `launchctl unload ~/Library/LaunchAgents/<bundle-id>.supervisor.plist`.
- **Prevent Mac from Sleeping**: BeaconMac uses native **IOKit** (`IOPMAssertionCreateWithName`, 100% App Sandbox compliant) while running, automatically invokes `caffeinate -s` under `launchd`, and provides a one-click **Energy Settings** shortcut to *System Settings → Energy / Displays*.

---

Designed by [SoroAI](https://soroai.com).
