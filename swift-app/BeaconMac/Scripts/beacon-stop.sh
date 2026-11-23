#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-stop.sh
# Cleanly stops whichever local app is listening on the specified port.
# Arguments:
#   $1 = Target port number
set -euo pipefail

PORT="${1:-}"
if [ -z "$PORT" ]; then
  echo "Port number required" >&2
  exit 1
fi

PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -z "$PIDS" ]; then
  echo "No process listening on port $PORT"
  exit 0
fi

kill -TERM $PIDS 2>/dev/null || true
echo "Sent SIGTERM to process(es) on port $PORT: $PIDS"
