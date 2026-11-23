#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-startup.sh
# Runs via Apple's native launchd (~/Library/LaunchAgents/<BUNDLE_ID>.supervisor.plist)
# or @reboot cron to start/deploy all BeaconMac apps marked "runOnStartup": true.
# Logs stream to ~/beaconmac/server.log (watch with: tail -f ~/beaconmac/server.log).
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LAUNCHD_MODE=0
if [ "${1:-}" = "--launchd" ]; then
  LAUNCHD_MODE=1
fi

BUNDLE_ID="${BEACONMAC_BUNDLE_ID:-com.beaconmac.app}"
PREVENT_SLEEP="${BEACONMAC_PREVENT_SLEEP:-1}"
CONFIG_PATH="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Beacon/config.json"
SCRIPTS_DIR="$HOME/Library/Application Scripts/$BUNDLE_ID"
LOG_DIR="$HOME/beaconmac"
SERVER_LOG="$LOG_DIR/server.log"

mkdir -p "$LOG_DIR/logs"

log_line() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [beacon-startup] $1" | tee -a "$SERVER_LOG"
}

# Fallback to non-sandboxed Application Support if run via SwiftPM
if [ ! -f "$CONFIG_PATH" ]; then
  CONFIG_PATH="$HOME/Library/Application Support/Beacon/config.json"
fi

if [ ! -f "$CONFIG_PATH" ]; then
  log_line "No config.json found at $CONFIG_PATH"
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  log_line "ERROR: Node.js is required to parse startup apps from config.json" >&2
  exit 1
fi

log_line "Starting BeaconMac launchd supervisor (bundle: $BUNDLE_ID, preventSleep: $PREVENT_SLEEP)"

node -e '
const fs = require("fs");
const { execFileSync } = require("child_process");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const scriptsDir = process.argv[2];
const apps = Array.isArray(cfg.managedApps) ? cfg.managedApps : [];
let started = 0;
for (const app of apps) {
  if (!app.runOnStartup) continue;
  started++;
  const deployScript = scriptsDir + "/beacon-deploy.sh";
  const restartScript = scriptsDir + "/beacon-restart.sh";
  const useDeploy = Boolean(cfg.startupSchedule?.autoDeployOnStartup && app.repoURL);
  const script = useDeploy ? deployScript : restartScript;
  const args = useDeploy
    ? [app.repoURL || "", app.branch || "main", app.localPath || "", String(app.port || 5173), app.installCommand || "auto", app.buildCommand || "", app.startCommand || ""]
    : [app.localPath || "", String(app.port || 5173), app.startCommand || ""];
  console.log("[beacon-startup] Launching", app.name, "via", script);
  try {
    execFileSync(script, args, { stdio: "inherit" });
  } catch (err) {
    console.error("[beacon-startup] Failed for", app.name, err.message);
  }
}
if (started === 0) {
  console.log("[beacon-startup] No apps currently marked runOnStartup=true.");
}
' "$CONFIG_PATH" "$SCRIPTS_DIR" 2>&1 | tee -a "$SERVER_LOG"

# When running under launchd with Prevent Sleep enabled, hold a native caffeinate -s
# assertion in the foreground so launchd tracks the supervisor PID and `launchctl unload`
# cleanly releases the sleep assertion when stopping the background service.
if [ "$LAUNCHD_MODE" -eq 1 ] && [ "$PREVENT_SLEEP" = "1" ] && command -v caffeinate >/dev/null 2>&1; then
  log_line "Holding macOS system sleep assertion via caffeinate -s (stop via launchctl unload)"
  exec /usr/bin/caffeinate -s
fi
