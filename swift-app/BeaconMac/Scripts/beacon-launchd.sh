#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-launchd.sh
# Manages Apple's native launchd background supervisor (~/Library/LaunchAgents/<BUNDLE_ID>.supervisor.plist)
# invoked safely by BeaconMac via Apple's App-Sandbox-approved NSUserUnixTask API.
#
# Arguments:
#   $1 = action: "install" | "stop" | "status"
#   $2 = bundle ID (default: com.beaconmac.app)
#   $3 = preventSleep: "1" | "0" (default: "1" -> keeps Mac awake with caffeinate -s under launchd)
set -euo pipefail

ACTION="${1:-status}"
BUNDLE_ID="${2:-com.beaconmac.app}"
PREVENT_SLEEP="${3:-1}"

LABEL="${BUNDLE_ID}.supervisor"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$AGENTS_DIR/${LABEL}.plist"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
STARTUP_SCRIPT="$SCRIPTS_DIR/beacon-startup.sh"
LOG_DIR="$HOME/beaconmac"
SERVER_LOG="$LOG_DIR/server.log"

if [ "$ACTION" != "grep" ]; then
  mkdir -p "$AGENTS_DIR" "$LOG_DIR/logs"
fi

write_plist() {
  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${STARTUP_SCRIPT}</string>
        <string>--launchd</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>BEACONMAC_BUNDLE_ID</key>
        <string>${BUNDLE_ID}</string>
        <key>BEACONMAC_PREVENT_SLEEP</key>
        <string>${PREVENT_SLEEP}</string>
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
    <string>${SERVER_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${SERVER_LOG}</string>
</dict>
</plist>
EOF
}

case "$ACTION" in
  install)
    if [ ! -x "$STARTUP_SCRIPT" ]; then
      echo "[beacon-launchd] ERROR: Missing executable $STARTUP_SCRIPT. Run ./Scripts/install-sandbox-scripts.sh $BUNDLE_ID first." >&2
      exit 10
    fi
    write_plist
    echo "[beacon-launchd] Wrote LaunchAgent plist: $PLIST_PATH"
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    if launchctl load -w "$PLIST_PATH" 2>/dev/null; then
      echo "[beacon-launchd] Loaded $LABEL into launchd (RunAtLoad=true, preventSleep=$PREVENT_SLEEP)"
    else
      launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
      echo "[beacon-launchd] Bootstrapped $LABEL into launchd gui/$(id -u)"
    fi
    echo "LAUNCHD:INSTALLED:YES:$PLIST_PATH"
    echo "LAUNCHD:LOADED:YES:$LABEL"
    ;;

  stop)
    if [ -f "$PLIST_PATH" ]; then
      launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    fi
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    echo "[beacon-launchd] Unloaded launchd service $LABEL ($PLIST_PATH)"
    echo "LAUNCHD:INSTALLED:$([ -f "$PLIST_PATH" ] && echo YES || echo NO):$PLIST_PATH"
    echo "LAUNCHD:LOADED:NO:$LABEL"
    ;;

  status)
    if [ -f "$PLIST_PATH" ]; then
      echo "LAUNCHD:INSTALLED:YES:$PLIST_PATH"
    else
      echo "LAUNCHD:INSTALLED:NO:$PLIST_PATH"
    fi

    if launchctl list "$LABEL" >/dev/null 2>&1; then
      PID=$(launchctl list | awk -v lbl="$LABEL" '$3 == lbl {print $1}')
      echo "LAUNCHD:LOADED:YES:${PID:-running}"
    else
      echo "LAUNCHD:LOADED:NO:unloaded"
    fi

    if pgrep -f "caffeinate -s" >/dev/null 2>&1; then
      echo "LAUNCHD:CAFFEINATE:YES:active"
    else
      echo "LAUNCHD:CAFFEINATE:NO:inactive"
    fi
    echo "LAUNCHD:LOG:OK:$SERVER_LOG"
    ;;

  grep)
    PATTERN="${2:-}"
    MODE="${3:-E}"
    CASE_FLAG="${4:-i}"
    CTX_LINES="${5:-0}"
    MAX_MATCHES="${6:-500}"
    if [ ! -f "$SERVER_LOG" ]; then
      echo "Log file not found at $SERVER_LOG. Start the launchd supervisor or deploy an app to generate server logs." >&2
      exit 3
    fi
    GREP_ARGS=(-n -m "$MAX_MATCHES")
    if [ "$MODE" = "F" ]; then
      GREP_ARGS+=(-F)
    else
      GREP_ARGS+=(-E)
    fi
    if [ "$CASE_FLAG" = "i" ]; then
      GREP_ARGS+=(-i)
    fi
    if [ "$CTX_LINES" = "2" ]; then
      GREP_ARGS+=(-C 2)
    fi
    set +e
    /usr/bin/grep "${GREP_ARGS[@]}" -- "$PATTERN" "$SERVER_LOG"
    RC=$?
    set -e
    if [ "$RC" -eq 1 ]; then
      exit 0
    fi
    exit "$RC"
    ;;

  *)
    echo "[beacon-launchd] Unknown action: $ACTION (expected install|stop|status|grep)" >&2
    exit 2
    ;;
esac
