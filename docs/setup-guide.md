# BeaconMac Setup & Configuration Guide

This guide walks through installing BeaconMac on macOS, storing API keys and secrets securely in the **macOS Keychain**, adding and deploying **Git repositories** (Vite, Node.js, Next.js, or custom stacks), configuring **local `launchd` background daemons**, watching live logs, and keeping your Mac awake so locally deployed apps stay reachable.

---

## 1. Prerequisites & First Launch

### System Requirements
- **macOS 14 (Sonoma) or later** (Apple Silicon or Intel)
- **Xcode 15.4+** (or Swift 5.10 toolchain) if building from source
- Developer runtimes (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`) — **can be installed silently right inside BeaconMac** using the **Install Dependencies** button!

### Build & Launch BeaconMac
```bash
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
*(Or run directly without generating an Xcode project: `swift run`)*

### Install Missing Tools Silently Inside BeaconMac (`Install Dependencies`)
You don't need to leave BeaconMac to install missing runtimes or package managers:
1. Click **Install Dependencies** in BeaconMac's top bar, Managed Local Apps header, any app row, or the Menu Bar.
2. Choose your **Project Type** — e.g. **Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS**, **Python (python3 + uv)**, **Go**, or **Custom Selection**.
3. Pick your **Silent Install Method**: **Auto (Homebrew, fallback to Direct Download)**, **Homebrew (silent)**, or **Direct Official Download (no Homebrew)** (downloads SHA-256–verified Node.js LTS tarballs, standalone `pnpm`, `yarn`, `bun`, and `uv` non-interactively).
4. Optionally pick a managed app folder to sync `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, or `Cargo.toml` packages in the same pass, then click **Install**.

### Install App-Sandbox Hook Scripts (Mac App Store Builds Only)
Direct Developer ID DMGs and `swift run` auto-install all 7 embedded scripts on launch. For **Mac App Store** builds (`com.apple.security.app-sandbox = true`), BeaconMac uses Apple's approved **`NSUserUnixTask`** API pointing to `~/Library/Application Scripts/<your-bundle-id>/`.

- **1-Click In-App:** Click **Install Hook Scripts** in the banner at the top of BeaconMac.
- **Or via Terminal:**
  ```bash
  cd swift-app/BeaconMac
  ./Scripts/install-sandbox-scripts.sh com.beaconmac.app
  ```
> **Custom Bundle ID:** If you changed the Bundle Identifier in Xcode (for example to `com.yourorg.beaconmac`), pass your custom Bundle ID as the argument:
> ```bash
> ./Scripts/install-sandbox-scripts.sh com.yourorg.beaconmac
> ```

After launching BeaconMac, click **Audit Tools** in the top bar (or **Check System Tools** in the Managed Local Apps card) to confirm `git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, and `go` are detected.

---

## 2. Setting Up Keys & Environment Variables in macOS Keychain

**BeaconMac itself does not use a `.env` file.** All credentials are pasted directly inside the app and persisted encrypted in your **macOS Keychain** (`Security.framework`) under `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (scoped to this Mac only, never written to `config.json` or `activity.log`).

### A. Connect Your GitHub Personal Access Token (Keychain)
1. Create a GitHub Personal Access Token:
   - **Fine-grained PAT (recommended):** Grant **Contents (Read-only)** and **Metadata (Read-only)** on the repositories you want to monitor/deploy.
   - **Classic PAT:** Select `repo` (for private repositories) or `public_repo` (for public repositories).
2. In BeaconMac, open the **GitHub Account** card.
3. Paste your token (`ghp_...` or `github_pat_...`) into the secure field and click **Connect**.
4. BeaconMac verifies the token against `https://api.github.com/user`, stores it in macOS Keychain under account `github_personal_access_token`, displays only a masked hint (e.g. `ghp_••••4a1f`), and loads your accessible repositories for quick-fill when adding apps.
5. Use **Replace** or **Clear** at any time to rotate or remove the token from Keychain.

### B. Connect Your Anthropic Claude API Key (Keychain)
1. In BeaconMac, open the **Claude API** card.
2. Paste your Anthropic key (`sk-ant-...`) and click **Check**.
3. BeaconMac stores the key in macOS Keychain under account `claude_api_key` and verifies health via `GET https://api.anthropic.com/v1/models` (zero inference token cost).

### C. Managing App-Specific Environment Variables Securely
When deploying your own Vite or Node.js repositories locally, keep each app's runtime secrets out of Git and out of `config.json`:

- **Option 1 — Local `.env` inside each app's working directory (standard for Vite/Node):**
  Place `.env.local` or `.env` inside your app's local folder (e.g. `~/BeaconApps/my-vite-app/.env.local`) and ensure it is listed in `.gitignore`. `beacon-deploy.sh` preserves untracked `.env*` files across `git pull` deployments.
- **Option 2 — Pull secrets from macOS Keychain in your Start Command (zero plaintext `.env` on disk):**
  1. Store an app secret in your login Keychain once via Terminal:
     ```bash
     security add-generic-password -U -a "$USER" -s "beaconmac.myapp.DATABASE_URL" -w "postgres://..."
     ```
  2. Reference it in your app's **Start Command** inside BeaconMac:
     ```bash
     DATABASE_URL="$(security find-generic-password -a "$USER" -s "beaconmac.myapp.DATABASE_URL" -w)" npm run dev -- --port 5173
     ```
- **Automatic Log Redaction:** BeaconMac's `SecretMasker` automatically scrubs `ghp_*`, `gho_*`, `ghu_*`, `ghs_*`, `github_pat_*`, and `sk-ant-*` patterns before displaying lines in **Integrated Terminal Output** or writing to `activity.log`.

---

## 3. Adding & Deploying Git Repositories

BeaconMac monitors and deploys **any number of external local applications** simultaneously — it never assumes or monitors itself.

### Step 1: Add a Local App
1. Click **+ Add Local App** in the **Managed Local Apps** section.
2. *(Optional)* If you connected your GitHub account, select a repo from **Quick-fill from connected GitHub repositories** to auto-populate the App Name, Clone URL, default branch, and a default local folder (`~/BeaconApps/<repo>`).
3. Configure the app fields:
   - **App Name:** Friendly display name (e.g. `Billing Web`, `API Server`).
   - **Stack Preset:** Choose **Vite + Node**, **Node.js Server**, **Next.js**, or **Custom** to auto-fill standard install, build, and port-bound start commands.
   - **Remote Git Repository URL:** HTTPS (`https://github.com/owner/repo.git`) or SSH (`git@github.com:owner/repo.git`).
   - **Branch:** Target branch to track (e.g. `main`).
   - **Local Folder:** Existing checkout directory or a new directory path (BeaconMac will `git clone` automatically if the folder is missing or empty).
   - **Local App URL to Monitor:** Any local URL/port where your app listens, such as:
     - `http://localhost:5173`
     - `http://127.0.0.1:3000`
     - `http://[::1]:8080`
     - `http://myapp.local:4000`
   - **Dependency Install Command:** Leave as `auto` to auto-detect `pnpm` (`pnpm-lock.yaml`), `yarn` (`yarn.lock`), `bun` (`bun.lock`/`bun.lockb`), or `npm`, or enter a custom command (use `skip` to bypass installs).
   - **Build Command:** e.g. `npm run build` (leave blank to skip building for pure Node dev servers).
   - **Start Command:** e.g. `npm run dev -- --port 5173` or `npm start`.
4. Choose automation toggles:
   - **Auto-restart on crash:** Restarts the app automatically after 3 consecutive failed HTTP probes.
   - **Auto-deploy on Git push:** Polls the remote GitHub branch on your configured interval (default 60s) and triggers pull → dependency check → build → restart on new commits.
   - **Run on macOS startup / cron:** Includes this app in your macOS `launchd` startup daemon.
5. Click **Save App**.

### Step 2: Verify Dependencies & Deploy Locally
- Click **Check Deps** on any app row to inspect its folder, `.git` status, `package.json`, and `node_modules`.
- Click **Clone & Deploy** to execute the full pipeline (`beacon-deploy.sh`):
  1. Verifies `git` and `node` are available.
  2. Clones the remote repo (or fetches/fast-forwards existing clones, safely handling repos with unborn `HEAD`).
  3. Checks `package.json` vs. `node_modules` and installs missing libraries.
  4. Runs your build command.
  5. Gracefully stops any previous listener on the target port (`SIGTERM`) and starts your app, logging to `~/beaconmac/logs/<slug>-<port>.log`.
- Watch real-time output in the **Integrated Terminal Output** panel, or use **Open Terminal**, **Tail Log**, and **Copy Cmd** for direct macOS `Terminal.app` access.

### Private Repository Authentication for `git clone` / `git pull`
While BeaconMac uses your Keychain GitHub token to poll the GitHub REST API, host `git clone`/`git pull` executed by `beacon-deploy.sh` uses your macOS Git credentials:
- **SSH (recommended):** Add your SSH key to macOS Keychain (`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`) and use `git@github.com:owner/repo.git`.
- **HTTPS:** Enable Apple's Git credential helper (`git config --global credential.helper osxkeychain`) or authenticate via `gh auth login`.

---

## 4. Configuring Local `launchd` Daemons (Apple Native Background Manager)

BeaconMac integrates natively with Apple's **`launchd`** (`~/Library/LaunchAgents/`) so your startup apps boot automatically on login and stay supervised in the background even when BeaconMac's window is closed.

### Step 1: Mark Apps for Startup
Toggle **Startup** ON for each app you want `launchd` to launch automatically.

### Step 2: Install & Load the `launchd` Agent from BeaconMac
1. Scroll to **macOS `launchd` Daemon, Live Logs & Sleep Prevention**.
2. Choose your startup preferences:
   - **Launch BeaconMac at Login:** Registers the GUI app via Apple's App-Store-compliant `SMAppService.mainApp`.
   - **Prevent Mac Sleep (IOKit + `caffeinate -s`):** Keeps your Mac awake while BeaconMac is open (via IOKit) and passes `BEACONMAC_PREVENT_SLEEP=1` to `launchd` so the background daemon runs `caffeinate -s`.
   - **Pull & Rebuild on Boot:** When enabled, `beacon-startup.sh` runs a full `beacon-deploy.sh` (pull + deps + build + start) at boot; when disabled, it restarts existing checkouts quickly via `beacon-restart.sh`.
3. Click **Install & Start launchd**.
   - BeaconMac executes `beacon-launchd.sh install`, writes `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`, and loads it into `launchd` (`launchctl load -w` / `launchctl bootstrap`).
   - The traffic light turns **Green (`Loaded · PID ...`)**.

### Generated LaunchAgent `.plist` Structure
BeaconMac writes (or exports via **Export `.plist`**) the following LaunchAgent to `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.beaconmac.app.supervisor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USER/Library/Application Scripts/com.beaconmac.app/beacon-startup.sh</string>
        <string>--launchd</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>BEACONMAC_BUNDLE_ID</key>
        <string>com.beaconmac.app</string>
        <key>BEACONMAC_PREVENT_SLEEP</key>
        <string>1</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USER/beaconmac/server.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USER/beaconmac/server.log</string>
</dict>
</plist>
```

### Day-to-Day `launchd` & Log Commands
All three commands are also available as one-click buttons inside BeaconMac and the Menu Bar:

1. **Watch live supervisor & startup logs:**
   ```bash
   tail -f ~/beaconmac/server.log
   ```
   *(Or watch a specific app's stdout/stderr log:)*
   ```bash
   tail -f ~/beaconmac/logs/<app-folder>-<port>.log
   ```
2. **Stop the `launchd` background service (also releases `caffeinate -s`):**
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist
   ```
   *(Modern macOS equivalent: `launchctl bootout gui/$(id -u)/com.beaconmac.app.supervisor`)*
3. **Start / reload the `launchd` service manually:**
   ```bash
   launchctl load -w ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist
   ```
4. **Verify `launchd` daemon status:**
   ```bash
   launchctl list | grep beaconmac
   ```

> **Prefer Cron Instead?** Expand **Optional Legacy `crontab` Schedule** inside BeaconMac to configure `@reboot` or any 5-field schedule (e.g. `*/30 * * * *`) and click **Copy crontab Command**.

---

## 5. Preventing Your Mac from Sleeping

To keep local Vite/Node servers reachable over localhost or LAN when your display turns off, BeaconMac supports three complementary macOS mechanisms:

1. **In-App Native IOKit Assertion (Automatic):**
   Keep **Prevent Mac Sleep (IOKit + `caffeinate -s`)** toggled ON (also accessible from the Menu Bar). BeaconMac acquires a native `kIOPMAssertionTypePreventUserIdleSystemSleep` assertion via `IOKit.framework` and releases it cleanly on toggle-off or quit.
2. **Headless `caffeinate -s` (When Running via `launchd`):**
   When `BEACONMAC_PREVENT_SLEEP=1`, `beacon-startup.sh --launchd` holds `/usr/bin/caffeinate -s` (prevents system sleep while on AC power) until you unload the service. You can also run `caffeinate -s` manually in any Terminal window.
3. **macOS System Settings:**
   Click **Energy Settings** inside BeaconMac to open **System Settings → Battery / Energy / Displays** and enable **"Prevent automatic sleeping on power adapter when the display is off"**.

---

## 6. Global Settings, Ollama & Flat-File Storage

Expand **Global Settings & Alerts** at the bottom of BeaconMac to configure:
- **Ollama Loopback Endpoint:** Default `http://127.0.0.1:11434` (strictly restricted to loopback ports `11434–11440`).
- **Git Auto-Deploy Poll Interval:** Frequency in seconds (15–3600s, default 60s).
- **Max Auto-Restarts / App:** Crash-loop protection cap per app (default 10).
- **Alert Email & macOS Notifications:** Toggle native `UserNotifications` alerts for crashes, deployments, and Ollama outages.

### Local File Locations
| File | Location | Purpose |
| :--- | :--- | :--- |
| **App Configuration** | `~/Library/Containers/<bundle-id>/Data/Library/Application Support/Beacon/config.json` *(or `~/Library/Application Support/Beacon/config.json` via SwiftPM)* | Non-secret app list, startup schedule, and global settings |
| **Activity Log** | Same folder → `activity.log` | Structured, secret-redacted event log (auto-rotates at 2 MB) |
| **Supervisor Live Log** | `~/beaconmac/server.log` | Combined `launchd` startup & deployment log |
| **Per-App Live Logs** | `~/beaconmac/logs/<slug>-<port>.log` | Live stdout/stderr for each locally deployed app |
| **Sandbox Scripts** | `~/Library/Application Scripts/<bundle-id>/*.sh` | Apple-approved `NSUserUnixTask` hook scripts |
| **LaunchAgent Plist** | `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` | Native macOS `launchd` agent definition |

---

## 7. Troubleshooting & AI Help

- **One-Click AI Help & Log Copy:** Every log view (**Integrated Terminal Output**, **Server Log Search**, **Activity Log**, **Install Dependencies**, and failing app cards) includes **Copy** buttons (`Copied ✓`) and an **AI Help** button that redacts secrets and analyzes errors using your connected **Local Ollama** model or **Claude API** (or copies a ready-to-paste troubleshooting prompt).
- **"Missing beacon-deploy.sh / beacon-launchd.sh" error:**
  Click **Install Hook Scripts** inside BeaconMac or run `./Scripts/install-sandbox-scripts.sh <your-bundle-id>` and verify the Bundle Identifier matches the one configured in Xcode (`com.beaconmac.app` by default).
- **"`node`, `pnpm`, `yarn`, `bun`, or `git` not found" during deploy or `launchd` boot:**
  Click **Install Dependencies** inside BeaconMac to install missing tools silently via Homebrew or direct download. BeaconMac's scripts automatically prepend `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.local/node/bin`, `~/Library/pnpm`, `~/.bun/bin`, and the latest NVM Node version.
- **Local app running on `localhost:<port>` shows Unreachable:**
  BeaconMac bypasses system HTTP proxies and checks both IPv4 (`127.0.0.1`) and IPv6 (`::1`) loopback automatically (including local HTTPS fallback). Confirm your local server is listening on the configured port via `lsof -iTCP:<port> -sTCP:LISTEN`.
- **Port already in use:**
  Click **Stop** on the app row (runs `beacon-stop.sh <port>` via `lsof -tiTCP:<port>`) or run `lsof -i :<port>` in Terminal to inspect conflicting processes.
- **Monitor URL rejected:**
  For SSRF protection, BeaconMac only allows local hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, or `*.local`) with no embedded credentials.

---

Designed by [SoroAI](https://soroai.com).
