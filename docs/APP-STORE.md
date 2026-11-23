# BeaconMac — Native SwiftUI macOS App (Apple App Store Ready)

A 100% native Swift 5.10 + SwiftUI macOS 14+ macOS app built for **Mac App Store** distribution (App Sandbox enabled, zero Electron/Node runtime overhead, macOS Keychain secret storage, and flat-file logging).

## Step 1: Generate & Open `BeaconMac.xcodeproj`

### Option A — Generate `BeaconMac.xcodeproj` with XcodeGen (Recommended for App Store)
```bash
brew install xcodegen
cd BeaconMac
chmod +x Scripts/generate-xcode-project.sh
./Scripts/generate-xcode-project.sh
```
This creates `BeaconMac.xcodeproj` and opens it in Xcode with **App Sandbox**, **Hardened Runtime**, `Info.plist`, and **Mac App Store** entitlements pre-configured.

### Option B — Quick Local Run via Swift Package Manager
```bash
cd BeaconMac
swift run
```
(Or double-click `Package.swift` to open directly in Xcode.)

---

## Step 2: Configure Signing & Bundle ID in Xcode
1. Select the **BeaconMac** project in Xcode -> **BeaconMac** target -> **Signing & Capabilities**.
2. Choose your **Apple Developer Program Team** (required for App Store Connect).
3. Change **Bundle Identifier** from `com.beaconmac.app` to your own unique reverse-DNS identifier (for example `com.yourname.beaconmac`).
4. Add a macOS **AppIcon** asset set (16px to 1024px) in `Assets.xcassets` — Apple requires a 1024×1024 icon for Mac App Store validation.

---

## Step 3: Archive & Upload to the Mac App Store
1. In Xcode’s toolbar, choose **Any Mac (Apple Silicon, Intel)** as the build destination.
2. Click **Product → Archive**.
3. When Organizer opens, select the archive and click **Distribute App → App Store Connect → Upload**.
4. In **App Store Connect**, complete app metadata, privacy disclosures (no tracking; API keys stored locally in Keychain), and submit for App Review.

---

## App Sandbox Note for Restarting Local Node/Vite & Git Pull
Apple’s **Mac App Store App Sandbox** prevents sandboxed apps from directly spawning arbitrary binaries like `/usr/local/bin/node` or `/usr/bin/git`. BeaconMac uses Apple’s official **`NSUserUnixTask`** API:

```bash
mkdir -p "$HOME/Library/Application Scripts/com.beaconmac.app"
cp Scripts/beacon-restart.sh "$HOME/Library/Application Scripts/com.beaconmac.app/"
cp Scripts/beacon-git-pull.sh "$HOME/Library/Application Scripts/com.beaconmac.app/"
chmod +x "$HOME/Library/Application Scripts/com.beaconmac.app/"*.sh
```
*(Replace `com.beaconmac.app` with your final Bundle Identifier.)*

---

Designed by [SoroAI](https://soroai.com).
