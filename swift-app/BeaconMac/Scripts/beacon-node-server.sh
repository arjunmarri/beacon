#!/bin/bash
# Starts, stops, or checks BeaconMac's built-in Node.js App Host server (127.0.0.1).
# Arguments:
#   $1 = action ("start" | "stop" | "restart" | "status")
#   $2 = port (default: 4173)
#   $3 = registry JSON file path
set -euo pipefail

ACTION="${1:-status}"
PORT="${2:-4173}"
REGISTRY="${3:-$HOME/Library/Application Support/Beacon/builtin-server-apps.json}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_SCRIPT="$SCRIPTS_DIR/beacon-node-host.mjs"
LOG_DIR="$HOME/beaconmac"
mkdir -p "$LOG_DIR/logs"
HOST_LOG="$LOG_DIR/logs/builtin-node-host.log"
PID_FILE="$LOG_DIR/builtin-node-host.pid"

stop_host() {
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill -TERM "$OLD_PID" 2>/dev/null || true
      sleep 0.5
    fi
    rm -f "$PID_FILE"
  fi
  LISTENER_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$LISTENER_PID" ]; then
    CMDLINE=$(ps -p "$LISTENER_PID" -o command= 2>/dev/null || true)
    if echo "$CMDLINE" | grep -q "beacon-node-host.mjs"; then
      kill -TERM "$LISTENER_PID" 2>/dev/null || true
      sleep 0.5
    fi
  fi
}

case "$ACTION" in
  start|restart)
    if ! command -v node >/dev/null 2>&1; then
      echo "[beacon-node-server] ERROR: Node.js is not installed. Click 'Install Dependencies' in BeaconMac to install Node.js silently." >&2
      exit 12
    fi
    if [ ! -f "$HOST_SCRIPT" ]; then
      echo "[beacon-node-server] ERROR: Missing $HOST_SCRIPT." >&2
      exit 13
    fi

    stop_host

    OCCUPIED=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$OCCUPIED" ]; then
      echo "[beacon-node-server] ERROR: Port $PORT is already in use by another process (PID $OCCUPIED). Choose a different port." >&2
      exit 14
    fi

    nohup node "$HOST_SCRIPT" --port "$PORT" --registry "$REGISTRY" --pidfile "$PID_FILE" </dev/null >>"$HOST_LOG" 2>&1 &
    NEW_PID=$!
    disown "$NEW_PID" 2>/dev/null || true
    sleep 0.8

    if ! kill -0 "$NEW_PID" 2>/dev/null; then
      echo "[beacon-node-server] ERROR: Built-in Node.js host exited immediately. Recent log:" >&2
      tail -n 15 "$HOST_LOG" 2>/dev/null >&2 || true
      exit 15
    fi

    NODE_VER=$(node -v 2>/dev/null || echo "unknown")
    echo "NODEHOST:RUNNING:YES:$NEW_PID"
    echo "NODEHOST:NODE:$NODE_VER:http://127.0.0.1:$PORT"
    echo "[beacon-node-server] Started built-in Node.js server on http://127.0.0.1:$PORT (PID $NEW_PID, Node $NODE_VER)"
    ;;

  stop)
    stop_host
    echo "NODEHOST:RUNNING:NO:stopped"
    echo "[beacon-node-server] Stopped built-in Node.js server on port $PORT"
    ;;

  status)
    RUNNING_PID=""
    if [ -f "$PID_FILE" ]; then
      CAND=$(cat "$PID_FILE" 2>/dev/null || true)
      if [ -n "$CAND" ] && kill -0 "$CAND" 2>/dev/null; then
        RUNNING_PID="$CAND"
      fi
    fi
    if [ -n "$RUNNING_PID" ]; then
      echo "NODEHOST:RUNNING:YES:$RUNNING_PID"
    else
      echo "NODEHOST:RUNNING:NO:stopped"
    fi
    ;;

  *)
    echo "[beacon-node-server] Unknown action: $ACTION (expected start|stop|restart|status)" >&2
    exit 2
    ;;
esac
