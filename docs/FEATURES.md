# BeaconMac Features

BeaconMac brings XAMPP-style traffic-light clarity to modern macOS local development — combining **multi-app Git clone/build/local deployment**, **Vite & Node.js dependency verification**, **Terminal integration**, **macOS startup & cron automation**, **local Ollama LLM monitoring**, and **Claude API verification** in one lightweight native SwiftUI app.

---

## 1. Multi-App Local Monitoring & Deployment Hub
- **Monitor & Manage Unlimited Local Apps**: Add any number of locally deployed apps (each with its own name, stack preset, remote Git repo URL, branch, local folder, and local monitor URL such as `http://localhost:5173`, `http://127.0.0.1:3000`, `http://myapp.local:8080`, etc.). BeaconMac never assumes or monitors itself.
- **Stack Presets for Vite & Node**: Built-in presets for **Vite + Node**, **Node.js Server**, **Next.js**, and **Custom** automatically fill sensible install, build, and port-bound start commands — all editable per app.
- **Full Clone → Dependency Check → Build → Local Deploy Pipeline (`beacon-deploy.sh`)**:
  1. Verifies required system runtimes (`git`, `node`) on `PATH` (including Homebrew `/opt/homebrew/bin`, `/usr/local/bin`, NVM, Volta, fnm).
  2. Clones the remote Git repository automatically if the target local folder is empty or missing, or fetches/pulls updates safely on existing clones (including freshly initialized repos with unborn `HEAD`).
  3. Inspects `package.json` and `node_modules`, auto-detecting `pnpm`, `yarn`, `bun`, or `npm` (or running your custom install command) to install missing libraries.
  4. Runs your build command (e.g. `npm run build`), gracefully stops any existing listener on the app's port, and launches the local app while streaming logs to `/tmp/beaconmac-<slug>-<port>.log`.
- **Live Traffic-Light Telemetry & Crash Recovery**: Polls every configured local app every 3 seconds for HTTP status, latency (ms), and uptime. After 3 consecutive failures, dispatches a macOS alert and automatically restarts the app if `Auto-restart on crash` is enabled.
- **Per-App Git Auto-Deploy**: Polls each GitHub-connected app's branch and triggers a fresh pull, dependency check, rebuild, and restart whenever new commits are pushed.

## 2. System & Project Dependency Auditing (`beacon-check-deps.sh`)
- **Runtime Toolchain Status Bar**: Audits `git`, `node`, `npm`, `pnpm`, `yarn`, and `bun` across standard macOS & Homebrew paths and displays live version availability at the top of the Managed Local Apps hub.
- **Per-App Library Verification**: Clicking **Check Deps** inspects each app's local directory, `.git` clone status, `package.json`, and `node_modules` presence before deploying.

## 3. Integrated Terminal Output & Persistent Live Logs
- **In-App Live Console**: Streams redacted stdout and stderr from every `git clone`, `npm install`, `npm run build`, dependency audit, `launchd` action, and deploy command right inside BeaconMac with **Copy Output**, **Clear**, and **Collapse/Expand**.
- **Persistent macOS Log Paths**: Supervisor and startup logs stream to `~/beaconmac/server.log` and per-app logs stream to `~/beaconmac/logs/<slug>-<port>.log`.
- **Native `Terminal.app` Handoff**:
  - **Open Terminal**: Launches macOS `Terminal.app` directly inside any app's local folder via App-Sandbox-safe `NSWorkspace`.
  - **Watch Live Logs / Tail Log**: Opens `Terminal.app` and copies `tail -f ~/beaconmac/server.log` (or `tail -f ~/beaconmac/logs/<slug>-<port>.log`) straight to your clipboard.
  - **Copy Cmd**: Copies the exact shell-escaped `beacon-deploy.sh` command for manual terminal execution.

## 4. Native macOS `launchd` Daemon & Sleep Prevention
- **Apple `launchd` Background Supervisor (`~/Library/LaunchAgents`)**: Install, load (`launchctl load -w` / `bootstrap`), check live PID status, and stop (`launchctl unload ~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist`) directly from BeaconMac or the Menu Bar via `beacon-launchd.sh`.
- **Launch at macOS Login (`SMAppService.mainApp`)**: App-Store-compliant native login item toggle for the BeaconMac GUI app.
- **Keep Mac Awake (IOKit + `caffeinate -s` + System Settings)**:
  - **In-App Native IOKit Assertion**: Uses `IOPMAssertionCreateWithName` (`kIOPMAssertionTypePreventUserIdleSystemSleep`) inside the App Sandbox so local apps remain reachable even when the display sleeps.
  - **Headless `caffeinate -s` under `launchd`**: When the `launchd` supervisor runs with Prevent Sleep enabled, `beacon-startup.sh` holds `caffeinate -s` in the foreground so `launchctl unload` cleanly stops both the daemon and sleep assertion.
  - **One-Click Energy Settings**: Jump straight to *System Settings → Energy / Battery / Displays* or copy `caffeinate -s` from the UI.
- **Optional Legacy `crontab`**: Collapsible section still available for users who prefer custom time-based cron expressions.

## 5. GitHub Account Sync (Encrypted Keychain)
- **Direct In-App Key Paste**: Paste a GitHub Personal Access Token (`ghp_...` or `github_pat_...`) directly inside BeaconMac — stored encrypted in **macOS Keychain** (`Security.framework`).
- **Quick-Pick Repositories**: Connected repositories populate the quick-fill dropdown inside **+ Add Local App** and power automatic commit polling across all apps.

## 6. Local LLM (Ollama) & Claude API Health Checkers
- **Ollama Loopback Monitor**: Probes `http://127.0.0.1:11434` (`/api/tags` & `/api/ps`) for latency, loaded VRAM vs. macOS unified memory, installed model count, and one-click model switching.
- **Claude API Health Checker**: Paste your Anthropic key (`sk-ant-...`) into macOS Keychain to verify API reachability, HTTP status, latency, and available models via `GET https://api.anthropic.com/v1/models` at zero inference token cost.

## 7. Flat-File Activity Log & Native Menu Bar Extra
- **Zero-Database Persistence**: Settings persist atomically to `config.json` and logs append to `activity.log` (auto-rotated at 2 MB) with automatic regex secret redaction.
- **Menu Bar Companion**: Displays aggregate green/amber/red status plus every managed local app and platform service right in the macOS menu bar.
