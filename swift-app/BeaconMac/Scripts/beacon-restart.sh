#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-restart.sh
# Called safely by BeaconMac via Apple's App-Sandbox-approved NSUserUnixTask API
# to restart whichever local app you configured BeaconMac to monitor.
# Arguments passed by BeaconMac:
#   $1 = Target app working directory path
#   $2 = Target app port number (e.g. 3000, 5173, 8080)
#   $3 = Optional custom start command (defaults to: npm run dev -- --port "$PORT")
set -euo pipefail

WORKDIR="${1:-}"
PORT="${2:-3000}"
CUSTOM_CMD="${3:-}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
  echo "Target app working directory not found: $WORKDIR" >&2
  exit 1
fi

# Stop any existing listener on the target app's port
EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi

cd "$WORKDIR"
LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -n "$CUSTOM_CMD" ]; then
  PORT="$PORT" nohup /bin/zsh -lc "$CUSTOM_CMD" >>"$APP_LOG" 2>&1 &
else
  PORT="$PORT" nohup npm run dev -- --port "$PORT" >>"$APP_LOG" 2>&1 &
fi
NEW_PID=$!
SUMMARY="Restarted target local app in $WORKDIR on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [beacon-restart] $SUMMARY" >> "$SERVER_LOG"
