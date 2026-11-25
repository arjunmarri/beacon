# BeaconMac Setup & Configuration Guide

This guide walks through installing BeaconMac on macOS, storing API keys and secrets securely in the **macOS Keychain** (GitHub, ChatGPT, Gemini, Claude, OpenRouter, Groq, Cloudflare, Vercel, Supabase), adding and deploying **Git repositories**, loading apps into the **Built-In Node.js Server**, exposing local apps via the **Inbuilt NGINX Reverse Proxy**, configuring **local `launchd` background daemons**, inspecting/exporting live logs, switching between **White (Light) and Dark themes**, and keeping your Mac awake.

---

## 1. Prerequisites & First Launch

### System Requirements
- **macOS 14 (Sonoma) or later** (Apple Silicon or Intel)
- **Xcode 15.4+** (or Swift 5.10 toolchain) if building from source
- Developer runtimes (`git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, `nginx`) — **can be installed silently right inside BeaconMac** using the **Install Dependencies** button!

### Build & Launch BeaconMac
```bash
cd swift-app/BeaconMac
chmod +x Scripts/*.sh
./Scripts/generate-xcode-project.sh
```
*(Or run directly without generating an Xcode project: `swift run`)*

### Install Missing Tools Silently Inside BeaconMac (`Install Dependencies`)
You don't need to leave BeaconMac to install missing runtimes, package managers, or NGINX:
1. Click **Install Dependencies** in BeaconMac's top bar, Managed Local Apps header, any app row, or the Menu Bar.
2. Choose your **Project Type** — e.g. **Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS**, **Python (python3 + uv)**, **Go**, or **Custom Selection** (which also includes **`nginx`**).
3. Pick your **Silent Install Method**: **Auto (Homebrew, fallback to Direct Download)**, **Homebrew (silent)**, or **Direct Official Download (no Homebrew)** (downloads SHA-256–verified Node.js LTS tarballs, standalone `pnpm`, `yarn`, `bun`, and `uv` non-interactively).
4. Optionally pick a managed app folder to sync `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, or `Cargo.toml` packages in the same pass, then click **Install**.

### Install App-Sandbox Hook Scripts (Mac App Store Builds Only)
Direct Developer ID DMGs and `swift run` auto-install all 10 embedded scripts on launch. For **Mac App Store** builds (`com.apple.security.app-sandbox = true`), BeaconMac uses Apple's approved **`NSUserUnixTask`** API pointing to `~/Library/Application Scripts/<your-bundle-id>/`.

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

After launching BeaconMac, click **Audit Tools** in the top bar (or **Check System Tools** in the Managed Local Apps card) to confirm `git`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `python3`, `uv`, `go`, and `nginx` are detected.

---

## 2. Setting Up Keys & Cloud APIs in macOS Keychain

**BeaconMac itself does not use a `.env` file.** All credentials are pasted directly inside the app and persisted encrypted in your **macOS Keychain** (`Security.framework`, service `com.beaconmac.app`) under `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (scoped to this Mac only, never written to `config.json` or `activity.log`).

> **Why macOS may show a `"login" keychain` dialog after upgrading from a DMG:** When you update or reinstall BeaconMac from a new build/DMG, macOS Keychain asks once: *"BeaconMac wants to use your confidential information stored in `com.beaconmac.app` in your keychain."* That is BeaconMac restoring your saved GitHub and Cloud API keys stored under `com.beaconmac.app`. Enter your Mac login password and click **Always Allow** to grant access to the updated binary.

### A. Connect Your GitHub Personal Access Token (Keychain)
1. Create a GitHub Personal Access Token:
   - **Fine-grained PAT (recommended):** Grant **Contents (Read-only)** and **Metadata (Read-only)** on the repositories you want to monitor/deploy.
   - **Classic PAT:** Select `repo` (for private repositories) or `public_repo` (for public repositories).
2. In BeaconMac, open the **GitHub Account** card.
3. Paste your token (`ghp_...` or `github_pat_...`) into the secure field and click **Connect**.
4. BeaconMac verifies the token against `https://api.github.com/user`, stores it in macOS Keychain, displays only a masked hint (e.g. `ghp_••••4a1f`), and loads your accessible repositories for quick-fill when adding apps.

### B. Connect Cloud AI & Cloud/Edge Platform APIs in Settings
Expand **Global Settings & Alerts** → **Cloud AI & Platform API Integrations** to connect and live-verify any of the following (all keys stored encrypted in macOS Keychain):
- **Cloud AI Providers** (also available inside **AI Help** log troubleshooting alongside Local Ollama):
  - **OpenAI (ChatGPT)** — API key (`sk-...`) + preferred model (e.g. `gpt-4o-mini`, `gpt-4.1`).
  - **Google Gemini** — API key (`AIza...`) + preferred model (e.g. `gemini-2.5-flash`).
  - **Anthropic Claude** — API key (`sk-ant-...`), verified via zero-token `GET /v1/models` (also accessible on the top **Claude API** card).
  - **OpenRouter** — API key (`sk-or-...`) + preferred model.
  - **Groq** — API key (`gsk_...`) + preferred model.
  - **Custom OpenAI-Compatible** — Base URL + API key + model for DeepSeek, xAI Grok, Mistral, or any OpenAI-compatible gateway.
- **Cloud & Edge Platforms**:
  - **Cloudflare** — API Token (verified via `/client/v4/user/tokens/verify`) + optional Account ID for Workers / Pages / Workers AI.
  - **Vercel** — Access Token (verified via `/v2/user`).
  - **Supabase** — Project URL + Secret / Service Key or Personal Access Token.

Click **Save & Verify** on any provider to run a lightweight live health check, or **Remove** to delete the key from macOS Keychain at any time.

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
- **Automatic Log Redaction:** BeaconMac's `SecretMasker` automatically scrubs GitHub, Claude, OpenAI, Gemini, Groq, Supabase, and generic bearer/token patterns before displaying lines in **Integrated Terminal Output**, writing to `activity.log`, exporting logs, or calling **AI Help**.

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
   - **Local App URL to Monitor:** Any local URL/port where your app listens (`http://localhost:5173`, `http://127.0.0.1:3000`, `http://[::1]:8080`, `http://myapp.local:4000`).
   - **Dependency Install Command:** Leave as `auto` to auto-detect `pnpm`, `yarn`, `bun`, or `npm`, or enter a custom command (use `skip` to bypass installs).
   - **Build Command:** Leave blank or set e.g. `npm run build` (if a project's `package.json` has no `"build"` script, BeaconMac skips the build step cleanly rather than aborting).
   - **Start Command:** e.g. `npm run dev -- --port 5173` or `npm start` (auto-detected from `package.json` if omitted).
4. Choose automation toggles (**Auto-restart on crash**, **Auto-deploy on Git push**, **Run on macOS startup / cron**) and click **Save App**.
   - Newly added apps stay clean and quiet until configured or deployed (no premature HTTP probe error banner).

### Step 2: Deploy, Stop, Load in Node Host, or Expose via NGINX
- Click **Check Deps** on any app row to inspect its folder, `.git` status, `package.json`, and `node_modules`.
- Click **Clone & Deploy** to clone/pull, install missing dependencies, build (when defined), and launch the app with logs streamed to `~/beaconmac/logs/<slug>-<port>.log`.
- Click **Stop** to terminate the app cleanly — BeaconMac marks it as manually stopped so auto-recovery will not restart it until you explicitly click **Restart** or **Clone & Deploy**.
- Click **Load in Node Host** to mount the app inside the **Built-In Node.js Server**, or **Expose via NGINX** to add a reverse-proxy route instantly.

### Private Repository Authentication for `git clone` / `git pull`
- **SSH (recommended):** Add your SSH key to macOS Keychain (`ssh-add --apple-use-keychain ~/.ssh/id_ed25519`) and use `git@github.com:owner/repo.git`.
- **HTTPS:** Enable Apple's Git credential helper (`git config --global credential.helper osxkeychain`) or authenticate via `gh auth login`.

---

## 4. Using the Built-In Node.js Server

Load any static/built project folder or local port directly into BeaconMac's built-in loopback Node.js host (`http://127.0.0.1:4173`):
1. Open the **Built-In Node.js Server** section and click **Start Server** (configure the port if desired).
2. Click **+ Load App** (or click **Load in Node Host** on any Managed Local App) and pick:
   - **Static / Built Folder**: Point to any project root — BeaconMac automatically detects `dist/`, `build/`, `out/`, `public/`, or root `index.html` and serves SPAs with history fallback.
   - **Local Port Proxy**: Forward requests to an existing local port (`127.0.0.1:<port>`).
3. Access each app at `http://127.0.0.1:4173/<slug>/`, browse all mounted apps at `http://127.0.0.1:4173/_beacon/`, or click **Set Root (`/`)** to serve an app directly at `/`.

---

## 5. Exposing Local Apps with the Inbuilt NGINX Reverse Proxy

BeaconMac includes a user-space NGINX reverse proxy running entirely under `~/beaconmac/nginx/` (**no `sudo` required**):
1. Open the **Inbuilt NGINX Reverse Proxy** section.
   - If NGINX is not yet installed on your Mac, click **Install NGINX** to install it silently via Homebrew (or install via **Install Dependencies → Custom → nginx**).
2. Click **+ Add Route** (or click **Expose via NGINX** on any Managed Local App):
   - **Route Slug & Upstream**: e.g. slug `billing` → upstream `http://127.0.0.1:3002`.
   - **Path Prefix**: Accessible at `http://127.0.0.1:8080/billing/`.
   - **`*.localhost` Virtual Host**: Optionally enable `billing.localhost` so `http://billing.localhost:8080` routes directly to that app with WebSocket/HMR upgrade headers intact.
   - **Set as Active Root (`/`)**: Route `http://127.0.0.1:8080/` directly to your chosen app.
3. Click **Start NGINX** (or **Reload** after adding routes — runs `nginx -t` automatically and performs a zero-downtime `nginx -s reload`).
4. **Share over your Local Network (LAN):** Toggle **Expose LAN (`0.0.0.0`)** ON to bind NGINX to all interfaces and reveal the **Copy LAN URL** banner with your Mac's auto-detected LAN IP (e.g. `http://192.168.1.42:8080/billing/`).
5. Click **Test Config (`nginx -t`)** or **View `nginx.conf`** at any time to inspect the generated configuration, or tail `~/beaconmac/nginx/logs/access.log` and `error.log`.

---

## 6. Appearance (White / Dark Theme) & Log Inspection / Export

### Real-Time White (Light) & Dark Theme Switching
- Click the **Theme** toggle (**Dark / White**) in BeaconMac's top bar, **Global Settings & Alerts**, or the **Menu Bar** to switch instantly between Dark Mode and crisp White (Light) Mode.
- All section headers use high-contrast **Blue** accents so every panel stands out cleanly in both themes.

### Auto-Scroll, Pause, Copy & Export Logs
- **Pause / Resume Auto-Scroll**: Activity, Terminal, and Server Log consoles stay pinned to the newest entry automatically. Click **Pause auto-scroll** to inspect earlier output without jumping; an unread badge shows how many new lines arrived until you click **Resume auto-scroll**.
- **Per-Entry Copy**: Hover or click the inline **Copy** icon on any log line (or right-click → **Copy Entry** / **Copy Message Only** / **Ask AI About This Entry**).
- **Export Logs (`.txt` / `.json`)**: Click **Export Logs** in the Activity Log panel to save either **All Session Logs** (system, Git, services, and terminal output) or **Filtered Logs** as a `.txt` or `.json` file via macOS Save Panel. All secrets are automatically redacted prior to export.

---

## 7. Configuring Local `launchd` Daemons & Sleep Prevention

BeaconMac integrates natively with Apple's **`launchd`** (`~/Library/LaunchAgents/`) so your startup apps boot automatically on login and stay supervised in the background even when BeaconMac's window is closed.

### Step 1: Mark Apps for Startup & Install `launchd`
1. Toggle **Startup** ON for each app you want `launchd` to launch automatically.
2. Scroll to **macOS `launchd` Daemon, Live Logs & Sleep Prevention** and choose:
   - **Launch BeaconMac at Login:** Registers the GUI app via Apple's App-Store-compliant `SMAppService.mainApp`.
   - **Prevent Mac Sleep (IOKit + `caffeinate -s`):** Keeps your Mac awake while BeaconMac is open (via native IOKit) and passes `BEACONMAC_PREVENT_SLEEP=1` to `launchd` so the background daemon holds `caffeinate -s`.
   - **Pull & Rebuild on Boot:** Runs a full `beacon-deploy.sh` at boot when enabled, or fast `beacon-restart.sh` when disabled.
3. Click **Install & Start launchd** — BeaconMac writes `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist` and loads it (`launchctl load -w` / `bootstrap`).

### Day-to-Day `launchd`, Log & Sleep Commands
```bash
# Watch live supervisor & startup logs:
tail -f ~/beaconmac/server.log

# Watch a specific app's stdout/stderr log:
tail -f ~/beaconmac/logs/<app-folder>-<port>.log

# Watch inbuilt NGINX access & error logs:
tail -f ~/beaconmac/nginx/logs/access.log ~/beaconmac/nginx/logs/error.log

# Stop the launchd background service (also releases caffeinate -s):
launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist

# Start / reload the launchd service manually:
launchctl load -w ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist
```

> **macOS Energy Settings:** Click **Energy Settings** inside BeaconMac to open **System Settings → Battery / Energy / Displays** and enable *"Prevent automatic sleeping on power adapter when the display is off"*.

---

## 8. Global Settings, Ollama & Local File Locations

Expand **Global Settings & Alerts** at the bottom of BeaconMac to configure:
- **Appearance**: Switch between **Dark** and **White (Light)** themes in real time.
- **Cloud AI & Platform APIs**: OpenAI (ChatGPT), Google Gemini, Anthropic Claude, OpenRouter, Groq, Custom OpenAI-Compatible, Cloudflare, Vercel, and Supabase.
- **Ollama Loopback Endpoint**: Default `http://127.0.0.1:11434` (strictly restricted to loopback ports `11434–11440`).
- **Git Auto-Deploy Poll Interval**: Frequency in seconds (15–3600s, default 60s).
- **Max Auto-Restarts / App**: Crash-loop protection cap per app (default 10).
- **Alert Email & macOS Notifications**: Toggle native `UserNotifications` alerts for crashes, deployments, and Ollama outages.

### Local File Locations
| File / Directory | Location | Purpose |
| :--- | :--- | :--- |
| **App Configuration** | `~/Library/Containers/<bundle-id>/Data/Library/Application Support/Beacon/config.json` *(or `~/Library/Application Support/Beacon/config.json` via SwiftPM)* | Non-secret app list, Node Host routes, NGINX routes, theme preference, startup schedule, and settings |
| **Activity Log** | Same folder → `activity.log` | Structured, secret-redacted event log (auto-rotates at 2 MB) |
| **Supervisor Live Log** | `~/beaconmac/server.log` | Combined `launchd` startup & deployment log |
| **Per-App Live Logs** | `~/beaconmac/logs/<slug>-<port>.log` | Live stdout/stderr for each locally deployed app |
| **Built-In Node Host** | `~/beaconmac/node-host/` | `routes.json`, PID file, and `node-host.log` |
| **Inbuilt NGINX Proxy** | `~/beaconmac/nginx/` | Generated `nginx.conf`, PID file, temp dirs, and `logs/access.log` + `logs/error.log` |
| **Sandbox Scripts** | `~/Library/Application Scripts/<bundle-id>/*` | All 10 Apple-approved `NSUserUnixTask` hook scripts |
| **LaunchAgent Plist** | `~/Library/LaunchAgents/<bundle-id>.supervisor.plist` | Native macOS `launchd` agent definition |

---

## 9. Troubleshooting & AI Help

- **One-Click AI Help & Log Copy:** Every log view (**Integrated Terminal Output**, **Server Log Search**, **Activity Log**, **Install Dependencies**, and failing app cards) includes per-entry **Copy** buttons (`Copied ✓`) and an **AI Help** button that redacts secrets and analyzes errors using **Local Ollama** or any connected **Cloud AI provider** (ChatGPT, Gemini, Claude, OpenRouter, Groq, Custom OpenAI).
- **"Missing script" error (`beacon-deploy.sh`, `beacon-nginx.sh`, `beacon-node-server.sh`, etc.):**
  Click **Install Hook Scripts** inside BeaconMac or run `./Scripts/install-sandbox-scripts.sh <your-bundle-id>` and verify the Bundle Identifier matches Xcode (`com.beaconmac.app` by default).
- **"`node`, `pnpm`, `yarn`, `bun`, `nginx`, or `git` not found":**
  Click **Install Dependencies** inside BeaconMac to install missing tools silently via Homebrew or direct download.
- **Local app running on `localhost:<port>` shows Unreachable:**
  BeaconMac bypasses system HTTP proxies and checks both IPv4 (`127.0.0.1`) and IPv6 (`::1`) loopback automatically (including local HTTPS fallback). Confirm your local server is listening via `lsof -iTCP:<port> -sTCP:LISTEN`.
- **Port already in use:**
  Click **Stop** on the app row (runs `beacon-stop.sh <port>`) or run `lsof -i :<port>` in Terminal to inspect conflicting processes.
- **Monitor URL rejected:**
  For SSRF protection, BeaconMac only allows local hosts (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `*.localhost`, or `*.local`) with no embedded credentials.

---

Designed by [SoroAI](https://soroai.com).
