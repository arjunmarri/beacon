# BeaconMac Features

BeaconMac brings XAMPP-style traffic-light clarity to modern macOS local development — combining process monitoring, Git auto-deployment, local LLM management, and Claude API verification in one lightweight SwiftUI desktop and menu-bar app.

---

## 1. Vite / Node.js Localhost Watchdog
- **Multi-Port Localhost Monitoring**: Enter any loopback URL (`http://localhost:5173`, `http://localhost:3000`, `http://127.0.0.1:4173`, etc.) directly inside the service card to switch between multiple local apps.
- **Live HTTP Telemetry**: Tracks HTTP status code, response latency (ms), healthy uptime, and cumulative restart count every 3 seconds.
- **Automated Crash Recovery**: Detects 3 consecutive failed probes, dispatches a macOS alert, and triggers automatic restart via Apple's App-Sandbox-approved `NSUserUnixTask` script (`beacon-restart.sh`).
- **One-Click Controls**: Toggle auto-restart on/off, run an immediate probe, or manually restart your local server.

## 2. Git Auto-Deploy Watcher
- **Direct In-App Key Paste**: Paste a GitHub Personal Access Token (`ghp_...` or `github_pat_...`) directly inside the Git card — stored encrypted in **macOS Keychain** (never written to plaintext files).
- **Masked Key Display & Replacement**: Displays only a safe masked hint (e.g. `ghp_••••4a1f`) with one-click **Replace Key** and **Clear** controls.
- **Repository & Branch Selector**: Automatically fetches accessible repositories from GitHub (`owner/repo`) and monitors the selected branch for new commits.
- **Automated Pull & Redeploy**: Polls remote commits on a configurable interval and triggers `beacon-git-pull.sh` + local server restart when updates are pushed.

## 3. Local LLM (Ollama) Monitor & Model Switcher
- **Loopback Health Probing**: Probes `http://127.0.0.1:11434` (`/api/tags` and `/api/ps`) every 15 seconds.
- **Hardware & Runtime Metrics**: Displays live response latency, loaded VRAM vs. total macOS unified memory, and count of installed local models.
- **Instant Local Model Switcher**: Pick any locally installed Ollama model from the dropdown to warm-load it via `POST /api/generate` (`keep_alive: "10m"`).

## 4. Claude API Health Checker
- **Direct In-App Key Paste**: Paste your Anthropic API key (`sk-ant-...`) directly in the Claude card — saved encrypted in **macOS Keychain**.
- **Zero-Token-Cost Verification**: Probes `GET https://api.anthropic.com/v1/models` with `x-api-key` and `anthropic-version: 2023-06-01` to confirm key validity, HTTP status, and round-trip latency without spending inference tokens.
- **Accessible Model List**: Automatically lists the Claude models available to your key and checks health periodically in the background.

## 5. Flat-File Activity Log & Configuration (No Database, No Login)
- **Zero-Database Persistence**: All activity is written to `activity.log` (auto-rotated at 2 MB) and settings to `config.json` inside the app's sandboxed `Application Support/Beacon/` folder.
- **Real-Time Filtering & Export**: Filter logs by source (`vite`, `git`, `ollama`, `claude`, `email`, `system`) or search text, clear logs, or export `.log` files via macOS `NSSavePanel`.
- **Automatic Secret Redaction**: Any token pattern matching GitHub (`ghp_`, `github_pat_`, etc.) or Anthropic (`sk-ant-...`) keys is scrubbed before writing to disk.

## 6. Native macOS Menu Bar & Notifications
- **Menu Bar Extra**: Shows an aggregate green/amber/red status indicator right in the macOS menu bar with quick status readout and one-click **Check All** / **Restart Server** actions.
- **Native System Alerts**: Dispatches alerts via `UserNotifications` for server crashes, Git deployments, and Ollama outages.
