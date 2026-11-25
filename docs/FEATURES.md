# BeaconMac Features

BeaconMac brings XAMPP-style traffic-light clarity to modern macOS local development — combining **multi-app Git clone/build/local deployment**, a **Built-In Node.js Server**, **1-click Cloudflare Quick Tunnels for local apps & Ollama**, **in-app silent dependency installation by project type**, **auto-scrolling & exportable Terminal/Activity/Server logs**, **high-contrast Blue section headers with real-time White/Dark theme switching**, **native macOS `launchd` & sleep prevention**, and **local Ollama LLM monitoring** in one lightweight native SwiftUI app.

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

## 2. Built-In Node.js Server (`beacon-node-server.sh` & `beacon-node-host.mjs`)
- **Zero-Dependency Multi-App Local Host (`http://127.0.0.1:4173`)**: Load any static/built project folder or local port directly into BeaconMac's built-in Node.js server without running separate dev servers.
- **Smart Build Folder Detection & SPA Fallback**: Automatically detects `dist/`, `build/`, `out/`, `public/`, or a root `index.html` and supports single-page application history fallback.
- **One-Click `Load in Node Host` & `/_beacon/` Launcher**: Mount any Managed Local App with one click, set an **Active Root (`/`)**, or browse all mounted apps at `http://127.0.0.1:4173/_beacon/`.

## 3. 1-Click Cloudflare Quick Tunnels (`beacon-cloudflared.sh`)
- **Zero-Token HTTPS Sharing (`*.trycloudflare.com`)**: Expose any Managed Local App, the Built-In Node.js Server, your **Local Ollama LLM**, or any custom local port over HTTPS with one click — no Cloudflare account or API token required.
- **Automatic `Host` Header Rewrite for Ollama**: Clicking **Expose via Cloudflare** on the **Local LLM (Ollama)** card automatically injects `--http-host-header localhost:<port>` so Ollama accepts tunneled HTTPS requests cleanly.
- **Silent `cloudflared` Auto-Install & Config Inspector**: Automatically installs `cloudflared` if missing, generates a sanitized `config.yml` you can inspect in-app, auto-copies public URLs to the clipboard, and lets you stop individual or all tunnels in one click.

## 4. In-App Silent Dependency Installer & Auditing (`beacon-check-deps.sh`)
- **One-Click `Install Dependencies` Button**: Available in the top bar, Managed Local Apps header, each app row, and the Menu Bar.
- **Project Type Presets**: Pick **Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS (Node, pnpm, Yarn, Bun)**, **Python (python3 + uv)**, **Go**, or **Custom Selection** to highlight installed vs. missing tools (`Will install`).
- **Silent Background Installation (Homebrew or Direct Download)**: Runs non-interactively (`NONINTERACTIVE=1`, `HOMEBREW_NO_AUTO_UPDATE=1`) with **Auto (Homebrew, fallback to Direct Download)**, **Homebrew (silent)**, or **Direct Official Download (no Homebrew)**. Direct downloads install SHA-256–verified Node.js LTS tarballs into `~/.local/node`, standalone `pnpm` (`get.pnpm.io` / Corepack), `yarn` (Corepack / `npm`), `bun` (`bun.sh`), and `uv` (`astral.sh`) without leaving BeaconMac.
- **Project Manifest Syncing**: Optionally installs project packages for a selected managed app (`package.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `requirements.txt`, `pyproject.toml`, `uv.lock`, `go.mod`, `Cargo.toml`, `Gemfile`).

## 5. Blue Section Headers & Real-Time White (Light) / Dark Theme Switcher
- **High-Contrast Blue Section Headers**: Every major section and modal sheet displays a crisp **Blue header with a left accent bar** so you can visually scan and jump between Managed Local Apps, Built-In Node.js Server, Cloudflare Tunnels, Platform Services, Terminal, Activity Logs, and Settings effortlessly.
- **Real-Time White / Dark Theme Toggle (`BeaconTheme.swift`)**: Switch instantly between **Dark** and **White (Light)** themes from the top toolbar, Global Settings, or the Menu Bar — updating every surface, card, input field, log console, and sheet immediately with persisted preference.

## 6. Integrated Terminal, Auto-Scrolling & Exportable Logs & Server Log Search
- **Chronological Auto-Scroll & Pause Control**: Activity, Terminal, and Server Log consoles automatically scroll to the latest entry as new lines arrive. Click **Pause auto-scroll** during high-traffic output to inspect earlier lines calmly (with an unread counter badge on **Resume auto-scroll (N)**).
- **Per-Entry Copy & Context Menus**: Every log entry in the Activity Log, Integrated Terminal Output, and Server Log Search includes an inline **Copy** button (`Copied ✓`) and right-click context actions (**Copy Entry**, **Copy Message Only**), alongside panel-level **Copy All / Copy Filtered**.
- **Export Logs (`.txt` & `.json`) (`LogExportService`)**: Click **Export Logs** in the Activity Log panel to save all current session logs — or the active filter — including system events, Git activity, service checks, and deployment terminal output to a timestamped `.txt` or `.json` file via macOS `NSSavePanel` (always secret-redacted).
- **Server Log Search (`grep` / Regex)**: Search `~/beaconmac/server.log` directly from BeaconMac (inline or full-height modal) with Extended Regex (`-E`), fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, and per-line copy.
- **Persistent macOS Log Paths & `Terminal.app` Handoff**: Supervisor logs write to `~/beaconmac/server.log` and per-app logs write to `~/beaconmac/logs/<slug>-<port>.log`, with one-click **Open Terminal**, **Watch Live Logs / Tail Log**, and **Copy Cmd**.

## 7. GitHub Keychain Account & Local Ollama LLM Monitor
- **GitHub PAT (macOS Keychain)**: Paste your Personal Access Token once inside the **GitHub Account** card — stored encrypted in **macOS Keychain** (`Security.framework`, service `com.beaconmac.app`), used to list repositories for quick-fill and poll branches for auto-deploy.
- **Ollama Loopback Monitor**: Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`) for latency, loaded VRAM vs. macOS unified memory, installed model count, one-click model switching, and 1-click **Expose via Cloudflare** Quick Tunnel.

## 8. Native macOS `launchd` Daemon & Sleep Prevention
- **Apple `launchd` Background Supervisor (`~/Library/LaunchAgents`)**: Install, load (`launchctl load -w` / `bootstrap`), inspect live PID status, and stop (`launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`) directly from BeaconMac or the Menu Bar via `beacon-launchd.sh`.
- **Launch at macOS Login (`SMAppService.mainApp`)**: App-Store-compliant native login item toggle for the BeaconMac GUI app.
- **Keep Mac Awake (IOKit + `caffeinate -s` + System Settings)**:
  - **In-App Native IOKit Assertion**: Uses `IOPMAssertionCreateWithName` (`kIOPMAssertionTypePreventUserIdleSystemSleep`) inside the App Sandbox so local apps remain reachable even when the display sleeps.
  - **Headless `caffeinate -s` under `launchd`**: When the `launchd` supervisor runs with Prevent Sleep enabled, `beacon-startup.sh` holds `caffeinate -s` in the foreground so `launchctl unload` cleanly stops both the daemon and sleep assertion.
  - **One-Click Energy Settings**: Jump straight to *System Settings → Energy / Battery / Displays* or copy `caffeinate -s` from the UI.

## 9. Local-First Privacy, Flat-File Storage & Menu Bar Extra
- **Zero-Tracking Privacy**: Ships with an Apple Privacy Manifest (`NSPrivacyTracking = false`), built-in **Privacy Policy** viewer, zero analytics, and zero third-party log transmission.
- **Zero-Database Persistence**: Settings persist atomically to `config.json` and logs append to `activity.log` (auto-rotated at 2 MB) with automatic regex secret redaction.
- **Menu Bar Companion**: Displays aggregate green/amber/red status plus every managed local app, Built-In Node Host status, active Cloudflare Tunnels, GitHub & Ollama status, real-time White/Dark theme toggle, **Install Dependencies…**, `launchd` controls, and sleep toggle right in the macOS menu bar.
