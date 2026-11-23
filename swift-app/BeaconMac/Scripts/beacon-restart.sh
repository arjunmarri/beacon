#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-restart.sh
# Called safely by Beacon via Apple's App-Sandbox-approved NSUserUnixTask API.
# Arguments passed by Beacon:
#   $1 = Working directory path
#   $2 = Port number (e.g. 5173)
set -euo pipefail

WORKDIR="${1:-$HOME}"
PORT="${2:-5173}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ ! -d "$WORKDIR" ]; then
  echo "Working directory not found: $WORKDIR" >&2
  exit 1
fi

# Stop any existing listener on the target port
EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi

cd "$WORKDIR"
nohup npm run dev -- --port "$PORT" >/tmp/beacon-vite-"$PORT".log 2>&1 &
echo "Restarted Vite dev server in $WORKDIR on port $PORT (PID $!)"
