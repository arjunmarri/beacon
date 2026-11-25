# BeaconMac Features

BeaconMac brings XAMPP-style traffic-light clarity to modern macOS local development — combining **multi-app Git clone/build/local deployment**, a **Built-In Node.js Server**, an **Inbuilt NGINX Reverse Proxy**, **in-app silent dependency installation by project type**, **auto-scrolling & exportable Terminal/Activity/Server logs**, **multi-provider Cloud AI & Cloud/Edge Platform API connections**, **high-contrast Blue section headers with real-time White/Dark theme switching**, **native macOS `launchd` & sleep prevention**, **verified self-updates**, and **local Ollama LLM monitoring** in one lightweight native SwiftUI app.

---

## 1. Multi-App Local Monitoring & Deployment Hub
- **Monitor & Manage Unlimited Local Apps**: Add any number of locally deployed apps (each with its own name, stack preset, remote Git repo URL, branch, local folder, and local monitor URL such as `http://localhost:5173`, `http://127.0.0.1:3000`, `http://myapp.local:8080`, etc.). BeaconMac never assumes or monitors itself.
- **Stack Presets for Vite & Node**: Built-in presets for **Vite + Node**, **Node.js Server**, **Next.js**, and **Custom** automatically fill sensible install, build, and port-bound start commands — all editable per app.
- **Full Clone → Dependency Check → Build → Local Deploy Pipeline (`beacon-deploy.sh`)**:
  1. Verifies required system runtimes (`git`, `node`) on `PATH` (including Homebrew `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.local/node/bin`, `~/Library/pnpm`, `~/.bun/bin`, NVM, Volta, fnm).
  2. Clones the remote Git repository automatically if the target local folder is empty or missing, or fetches/pulls updates safely on existing clones (including freshly initialized repos with unborn `HEAD`).
  3. Inspects `package.json` and `node_modules`, auto-detecting `pnpm`, `yarn`, `bun`, or `npm` (or running your custom install command) to install missing libraries.
  4. Runs your build command only when defined (skipping cleanly when a project has no `"build"` script), auto-detects `dev` / `start` / `serve` / `preview` / `main` entry points, gracefully stops any existing listener on the app's port, and launches the local app while streaming logs to `~/beaconmac/logs/<slug>-<port>.log`.
- **Clean Stop & Silent Pre-Configuration State**: Clicking **Stop** halts the process tree cleanly and marks the app as manually stopped so auto-recovery never respawns it unexpectedly. Newly added or unconfigured apps remain quiet without showing premature HTTP probe errors until configured or deployed.
- **Reliable Localhost Health Probing & Crash Recovery**: Uses a silent POSIX loopback TCP pre-check, bypasses macOS HTTP proxies, probes IPv4/IPv6 loopback directly without redirect loops, and supports local HTTPS fallback. Polls every 3 seconds and, after 3 consecutive failures (when not manually stopped), dispatches a macOS alert and restarts the app if `Auto-restart on crash` is enabled.
- **Per-App Git Auto-Deploy**: Polls each GitHub-connected app's branch and triggers a fresh pull, dependency check, rebuild, and restart whenever new commits are pushed.

## 2. Inbuilt NGINX Reverse Proxy (`beacon-nginx.sh`)
- **Zero-`sudo` User-Space NGINX (`~/beaconmac/nginx`)**: Runs NGINX entirely inside `~/beaconmac/nginx/` with its own generated `nginx.conf`, PID file, temp directories, and `access.log` / `error.log` — no root privileges or system `/etc/nginx` edits required.
- **Path-Prefix Routes, `*.localhost` Virtual Hosts & Active Root (`/`)**:
  - Expose any local upstream (`127.0.0.1:<port>` or `localhost:<port>`) at `http://127.0.0.1:<proxy-port>/<slug>/` and optionally as a `*.localhost` virtual host (`http://<slug>.localhost:<proxy-port>`) using `server_name`.
  - Switch any route to be the **Active Root (`/`)** so visiting `http://127.0.0.1:<proxy-port>/` opens that app directly.
- **WebSocket & HMR Upgrade Support**: Automatically injects `Upgrade`, `Connection`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto` headers so Vite HMR, Next.js dev servers, and WebSocket apps work seamlessly behind the proxy.
- **Optional LAN Exposure (`0.0.0.0`)**: Toggle **Expose LAN (`0.0.0.0`)** to bind NGINX on your Mac's local network interface, complete with auto-detected Mac LAN IP and a one-click **Copy LAN URL** banner for testing on phones, tablets, or teammates' machines.
- **One-Click Expose, Live Validation & Config Inspector**:
  - Click **Expose via NGINX** on any Managed Local App row to create a reverse-proxy route instantly.
  - Run **`nginx -t`** live config validation, zero-downtime **`nginx -s reload`**, inspect the generated **`nginx.conf`** in a modal sheet, or install NGINX silently via Homebrew if missing.

## 3. Built-In Node.js Server (`beacon-node-server.sh` & `beacon-node-host.mjs`)
- **Zero-Dependency Multi-App Local Host (`http://127.0.0.1:4173`)**: Load any static/built project folder or local port directly into BeaconMac's built-in Node.js server without running separate dev servers.
- **Smart Build Folder Detection & SPA Fallback**: Automatically detects `dist/`, `build/`, `out/`, `public/`, or a root `index.html` and supports single-page application history fallback.
- **One-Click `Load in Node Host` & `/_beacon/` Launcher**: Mount any Managed Local App with one click, set an **Active Root (`/`)**, or browse all mounted apps at `http://127.0.0.1:4173/_beacon/`.

## 4. In-App Silent Dependency Installer & Auditing (`beacon-check-deps.sh`)
- **One-Click `Install Dependencies` Button**: Available in the top bar, Managed Local Apps header, each app row, and the Menu Bar.
- **Project Type Presets**: Pick **Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS (Node, pnpm, Yarn, Bun)**, **Python (python3 + uv)**, **Go**, or **Custom Selection** (including **`nginx`**) to highlight installed vs. missing tools (`Will install`).
- **Silent Background Installation (Homebrew or Direct Download)**: Runs non-interactively (`NONINTERACTIVE=1`, `HOMEBREW_NO_AUTO_UPDATE=1`) with **Auto (Homebrew, fallback to Direct Download)**, **Homebrew (silent)**, or **Direct Official Download (no Homebrew)**. Direct downloads install SHA-256–verified Node.js LTS tarballs into `~/.local/node`, standalone `pnpm` (`get.pnpm.io` / Corepack), `yarn` (Corepack / `npm`), `bun` (`bun.sh`), and `uv` (`astral.sh`) without leaving BeaconMac.
- **Project Manifest Syncing**: Optionally installs project packages for a selected managed app (`package.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `requirements.txt`, `pyproject.toml`, `uv.lock`, `go.mod`, `Cargo.toml`, `Gemfile`).

## 5. Blue Section Headers & Real-Time White (Light) / Dark Theme Switcher
- **High-Contrast Blue Section Headers**: Every major section and modal sheet displays a crisp **Blue header with a left accent bar** so you can visually scan and jump between Managed Local Apps, Built-In Node.js Server, Inbuilt NGINX Reverse Proxy, Platform Services, Terminal, Activity Logs, and Settings effortlessly.
- **Real-Time White / Dark Theme Toggle (`BeaconTheme.swift`)**: Switch instantly between **Dark** and **White (Light)** themes from the top toolbar, Global Settings, or the Menu Bar — updating every surface, card, input field, log console, and sheet immediately with persisted preference.

## 6. Integrated Terminal, Auto-Scrolling & Exportable Logs, Server Log Search & AI Help
- **Chronological Auto-Scroll & Pause Control**: Activity, Terminal, and Server Log consoles automatically scroll to the latest entry as new lines arrive. Click **Pause auto-scroll** during high-traffic output to inspect earlier lines calmly (with an unread counter badge on **Resume auto-scroll (N)**).
- **Per-Entry Copy & Context Menus**: Every log entry in the Activity Log, Integrated Terminal Output, and Server Log Search includes an inline **Copy** button (`Copied ✓`) and right-click context actions (**Copy Entry**, **Copy Message Only**, **Ask AI About This Entry**), alongside panel-level **Copy All / Copy Filtered**.
- **Export Logs (`.txt` & `.json`) (`LogExportService`)**: Click **Export Logs** in the Activity Log panel to save all current session logs — or the active filter — including system events, Git activity, service checks, and deployment terminal output to a timestamped `.txt` or `.json` file via macOS `NSSavePanel` (always secret-redacted).
- **Server Log Search (`grep` / Regex)**: Search `~/beaconmac/server.log` directly from BeaconMac (inline or full-height modal) with Extended Regex (`-E`), fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, and per-line copy.
- **AI Help Log Troubleshooting (`AILogHelpSheet`)**: Click **AI Help** on Terminal Output, Activity Logs, Server Log Search results, Prerequisite Installer output, or any failing app card to diagnose redacted logs using **Local Ollama** or **any connected Cloud AI provider** (OpenAI ChatGPT, Google Gemini, Anthropic Claude, OpenRouter, Groq, or Custom OpenAI-compatible), with a copy-ready prompt fallback when offline.
- **Persistent macOS Log Paths & `Terminal.app` Handoff**: Supervisor logs write to `~/beaconmac/server.log`, per-app logs write to `~/beaconmac/logs/<slug>-<port>.log`, and NGINX logs write to `~/beaconmac/nginx/logs/`, with one-click **Open Terminal**, **Watch Live Logs / Tail Log**, and **Copy Cmd**.

## 7. Cloud AI & Cloud/Edge Platform API Integrations (macOS Keychain)
- **Settings → Cloud AI & Platform Integrations (`CloudProviderService`)**: Connect, verify live with zero-token health probes, and manage credentials encrypted strictly inside **macOS Keychain** (`Security.framework`, service `com.beaconmac.app`):
  - **Cloud AI Providers**: **OpenAI (ChatGPT)**, **Google Gemini**, **Anthropic Claude**, **OpenRouter**, **Groq**, and **Custom OpenAI-Compatible** (DeepSeek, xAI Grok, Mistral, LM Studio, or any OpenAI-compatible endpoint).
  - **Cloud & Edge Platforms**: **Cloudflare (API Token & optional Account ID for Workers AI)**, **Vercel**, and **Supabase**.
- **GitHub Account & Local Ollama Monitor**:
  - **GitHub PAT (Keychain)**: List repositories for quick-fill and poll branches for auto-deploy.
  - **Ollama Loopback Monitor**: Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`) for latency, loaded VRAM vs. macOS unified memory, installed model count, one-click model switching, and offline **AI Help**.

## 8. Native macOS `launchd` Daemon & Sleep Prevention
- **Apple `launchd` Background Supervisor (`~/Library/LaunchAgents`)**: Install, load (`launchctl load -w` / `bootstrap`), inspect live PID status, and stop (`launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`) directly from BeaconMac or the Menu Bar via `beacon-launchd.sh`.
- **Launch at macOS Login (`SMAppService.mainApp`)**: App-Store-compliant native login item toggle for the BeaconMac GUI app.
- **Keep Mac Awake (IOKit + `caffeinate -s` + System Settings)**:
  - **In-App Native IOKit Assertion**: Uses `IOPMAssertionCreateWithName` (`kIOPMAssertionTypePreventUserIdleSystemSleep`) inside the App Sandbox so local apps remain reachable even when the display sleeps.
  - **Headless `caffeinate -s` under `launchd`**: When the `launchd` supervisor runs with Prevent Sleep enabled, `beacon-startup.sh` holds `caffeinate -s` in the foreground so `launchctl unload` cleanly stops both the daemon and sleep assertion.
  - **One-Click Energy Settings**: Jump straight to *System Settings → Energy / Battery / Displays* or copy `caffeinate -s` from the UI.

## 9. Verified Self-Updates, Flat-File Storage & Menu Bar Extra
- **Cryptographically Verified Updates (`AppUpdateService`)**: Checks the pinned `arjunmarri/beacon` GitHub Releases feed, restricts downloads and CDN redirects strictly to official GitHub release hosts, verifies the published `.sha256` checksum via `CryptoKit` before mounting, validates the staged app's Apple Developer ID signature & matching Team ID via `SecStaticCodeCheckValidity`, `codesign --verify --deep --strict`, and Gatekeeper (`spctl --assess`), preserves `com.apple.quarantine`, and requires explicit user confirmation before swapping and relaunching.
- **Zero-Database Persistence**: Settings persist atomically to `config.json` and logs append to `activity.log` (auto-rotated at 2 MB) with automatic regex secret redaction.
- **Menu Bar Companion**: Displays aggregate green/amber/red status plus every managed local app, Built-In Node Host status, Inbuilt NGINX Reverse Proxy status, platform services, real-time White/Dark theme toggle, **Install Dependencies…**, `launchd` controls, sleep toggle, and **Check for Updates…** right in the macOS menu bar.
