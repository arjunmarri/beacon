# BeaconMac Features

BeaconMac brings XAMPP-style traffic-light clarity to modern macOS local development — combining **multi-app Git clone/build/local deployment**, **in-app silent dependency installation by project type**, **Terminal integration**, **Server Log Search & AI Help troubleshooting**, **native macOS `launchd` & sleep prevention**, **verified self-updates**, **local Ollama LLM monitoring**, and **Claude API verification** in one lightweight native SwiftUI app.

---

## 1. Multi-App Local Monitoring & Deployment Hub
- **Monitor & Manage Unlimited Local Apps**: Add any number of locally deployed apps (each with its own name, stack preset, remote Git repo URL, branch, local folder, and local monitor URL such as `http://localhost:5173`, `http://127.0.0.1:3000`, `http://myapp.local:8080`, etc.). BeaconMac never assumes or monitors itself.
- **Stack Presets for Vite & Node**: Built-in presets for **Vite + Node**, **Node.js Server**, **Next.js**, and **Custom** automatically fill sensible install, build, and port-bound start commands — all editable per app.
- **Full Clone → Dependency Check → Build → Local Deploy Pipeline (`beacon-deploy.sh`)**:
  1. Verifies required system runtimes (`git`, `node`) on `PATH` (including Homebrew `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.local/node/bin`, `~/Library/pnpm`, `~/.bun/bin`, NVM, Volta, fnm).
  2. Clones the remote Git repository automatically if the target local folder is empty or missing, or fetches/pulls updates safely on existing clones (including freshly initialized repos with unborn `HEAD`).
  3. Inspects `package.json` and `node_modules`, auto-detecting `pnpm`, `yarn`, `bun`, or `npm` (or running your custom install command) to install missing libraries.
  4. Runs your build command (e.g. `npm run build`), gracefully stops any existing listener on the app's port, and launches the local app while streaming logs to `~/beaconmac/logs/<slug>-<port>.log`.
- **Reliable Localhost Health Probing & Crash Recovery**: Uses a silent POSIX loopback TCP pre-check, bypasses macOS HTTP proxies, probes IPv4/IPv6 loopback directly without redirect loops, and supports local HTTPS fallback. Polls every 3 seconds and, after 3 consecutive failures, dispatches a macOS alert and automatically restarts the app if `Auto-restart on crash` is enabled.
- **Per-App Git Auto-Deploy**: Polls each GitHub-connected app's branch and triggers a fresh pull, dependency check, rebuild, and restart whenever new commits are pushed.

## 2. In-App Silent Dependency Installer & Auditing (`beacon-check-deps.sh`)
- **One-Click `Install Dependencies` Button**: Available in the top bar, Managed Local Apps header, each app row, and the Menu Bar.
- **Project Type Presets**: Pick **Node.js (npm)**, **Node.js + pnpm**, **Node.js + Yarn**, **Bun**, **Full JS / TS (Node, pnpm, Yarn, Bun)**, **Python (python3 + uv)**, **Go**, or **Custom Selection** to highlight installed vs. missing tools (`Will install`).
- **Silent Background Installation (Homebrew or Direct Download)**: Runs non-interactively (`NONINTERACTIVE=1`, `HOMEBREW_NO_AUTO_UPDATE=1`) with **Auto (Homebrew, fallback to Direct Download)**, **Homebrew (silent)**, or **Direct Official Download (no Homebrew)**. Direct downloads install SHA-256–verified Node.js LTS tarballs into `~/.local/node`, standalone `pnpm` (`get.pnpm.io` / Corepack), `yarn` (Corepack / `npm`), `bun` (`bun.sh`), and `uv` (`astral.sh`) without leaving BeaconMac.
- **Project Manifest Syncing**: Optionally installs project packages for a selected managed app (`package.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `requirements.txt`, `pyproject.toml`, `uv.lock`, `go.mod`, `Cargo.toml`, `Gemfile`).

## 3. Integrated Terminal, Server Log Search & AI Help Troubleshooting
- **In-App Live Console & Easy Copying**: Streams redacted stdout and stderr from every deploy, dependency install, and `launchd` action inside BeaconMac with one-click **Copy All** / **Copy Filtered** (`"Copied ✓"` feedback), right-click context menus, **Clear**, and **Collapse/Expand**.
- **Server Log Search (`grep` / Regex)**: Search `~/beaconmac/server.log` directly from BeaconMac (inline or in a full-height modal) with Extended Regex (`-E`), fixed-string (`-F`), case-sensitivity toggle, `±2` context lines, and one-click copy.
- **AI Help Log Troubleshooting (`AILogHelpSheet`)**: Click **AI Help** on Terminal Output, Activity Logs, Server Log Search results, Prerequisite Installer output, or any failing app card to diagnose redacted logs directly using your connected **Local Ollama** model or **Claude API** (with a copy-ready prompt fallback when offline).
- **Persistent macOS Log Paths & `Terminal.app` Handoff**: Supervisor logs write to `~/beaconmac/server.log` and per-app logs write to `~/beaconmac/logs/<slug>-<port>.log`, with one-click **Open Terminal**, **Watch Live Logs / Tail Log**, and **Copy Cmd**.

## 4. Native macOS `launchd` Daemon & Sleep Prevention
- **Apple `launchd` Background Supervisor (`~/Library/LaunchAgents`)**: Install, load (`launchctl load -w` / `bootstrap`), inspect live PID status, and stop (`launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`) directly from BeaconMac or the Menu Bar via `beacon-launchd.sh`.
- **Launch at macOS Login (`SMAppService.mainApp`)**: App-Store-compliant native login item toggle for the BeaconMac GUI app.
- **Keep Mac Awake (IOKit + `caffeinate -s` + System Settings)**:
  - **In-App Native IOKit Assertion**: Uses `IOPMAssertionCreateWithName` (`kIOPMAssertionTypePreventUserIdleSystemSleep`) inside the App Sandbox so local apps remain reachable even when the display sleeps.
  - **Headless `caffeinate -s` under `launchd`**: When the `launchd` supervisor runs with Prevent Sleep enabled, `beacon-startup.sh` holds `caffeinate -s` in the foreground so `launchctl unload` cleanly stops both the daemon and sleep assertion.
  - **One-Click Energy Settings**: Jump straight to *System Settings → Energy / Battery / Displays* or copy `caffeinate -s` from the UI.

## 5. Verified Self-Updates & Signed Universal DMG Releases
- **Cryptographically Verified Updates (`AppUpdateService`)**: Checks the pinned `arjunmarri/beacon` GitHub Releases feed, restricts downloads and CDN redirects strictly to official GitHub release hosts, verifies the published `.sha256` checksum via `CryptoKit` before mounting, validates the staged app's Apple Developer ID signature & matching Team ID via `SecStaticCodeCheckValidity`, `codesign --verify --deep --strict`, and Gatekeeper (`spctl --assess`), preserves `com.apple.quarantine`, and requires explicit user confirmation before swapping and relaunching.

## 6. GitHub Account Sync, Local LLM (Ollama) & Claude API Health Checkers
- **GitHub Account (Keychain)**: Paste a GitHub PAT (`ghp_...` or `github_pat_...`) stored encrypted in **macOS Keychain** (`Security.framework`) to list repositories for quick-fill and poll for new commits.
- **Ollama Loopback Monitor**: Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`) for latency, loaded VRAM vs. macOS unified memory, installed model count, one-click model switching, and offline **AI Help** log diagnostics.
- **Claude API Health Checker**: Paste your Anthropic key (`sk-ant-...`) into macOS Keychain to verify reachability, HTTP status, latency, and available models via `GET https://api.anthropic.com/v1/models` at zero inference token cost, and power optional cloud **AI Help** log diagnostics.

## 7. Flat-File Activity Log & Native Menu Bar Extra
- **Zero-Database Persistence**: Settings persist atomically to `config.json` and logs append to `activity.log` (auto-rotated at 2 MB) with automatic regex secret redaction.
- **Menu Bar Companion**: Displays aggregate green/amber/red status plus every managed local app, platform service, **Install Dependencies…**, `launchd` controls, sleep toggle, and **Check for Updates…** right in the macOS menu bar.
