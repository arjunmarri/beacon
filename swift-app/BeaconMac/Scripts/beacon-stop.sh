#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-stop.sh
# Cleanly and completely stops whichever local app is tracked or listening on the specified port
# (including parent runners/watchers like bun, npm, tsx, or vite so the app does not respawn).
# Arguments:
#   $1 = Target port number
#   $2 = Optional target app working directory
set -euo pipefail

PORT="${1:-}"
WORKDIR="${2:-}"

if [ -z "$PORT" ]; then
  echo "Port number required" >&2
  exit 1
fi

PID_DIR="$HOME/beaconmac/pids"
STOPPED_ANY=0

kill_tree_term() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  # Terminate entire process group if pid is a group leader, plus direct children and pid itself
  kill -TERM -- "-$pid" 2>/dev/null || true
  pkill -TERM -P "$pid" 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
}

kill_tree_kill() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -KILL -- "-$pid" 2>/dev/null || true
  pkill -KILL -P "$pid" 2>/dev/null || true
  kill -KILL "$pid" 2>/dev/null || true
}

# 1. Stop any tracked process group saved by beacon-deploy.sh / beacon-restart.sh
TRACKED_PIDS=()
if [ -d "$PID_DIR" ]; then
  if [ -n "$WORKDIR" ]; then
    LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
    CAND_FILE="$PID_DIR/${LOG_SLUG:-app}-${PORT}.pid"
    if [ -f "$CAND_FILE" ]; then
      TPID=$(cat "$CAND_FILE" 2>/dev/null || true)
      if [ -n "$TPID" ]; then
        TRACKED_PIDS+=("$TPID")
      fi
      rm -f "$CAND_FILE"
    fi
  fi
  for pfile in "$PID_DIR"/*-"${PORT}.pid"; do
    [ -f "$pfile" ] || continue
    TPID=$(cat "$pfile" 2>/dev/null || true)
    if [ -n "$TPID" ]; then
      TRACKED_PIDS+=("$TPID")
    fi
    rm -f "$pfile"
  done
fi

for pid in "${TRACKED_PIDS[@]:-}"; do
  [ -n "$pid" ] || continue
  if kill -0 "$pid" 2>/dev/null; then
    kill_tree_term "$pid"
    STOPPED_ANY=1
  fi
done

# 2. Stop any process currently listening on $PORT (and its dev runner parent if applicable)
PORT_PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$PORT_PIDS" ]; then
  for pid in $PORT_PIDS; do
    PPID_VAL=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    PGID_VAL=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    kill_tree_term "$pid"
    if [ -n "$PPID_VAL" ] && [ "$PPID_VAL" -gt 1 ] 2>/dev/null; then
      PCOMM=$(ps -o command= -p "$PPID_VAL" 2>/dev/null || true)
      if echo "$PCOMM" | grep -qiE '(bun|npm|pnpm|yarn|tsx|nodemon|vite|next|node)'; then
        kill_tree_term "$PPID_VAL"
      fi
    fi
    if [ -n "$PGID_VAL" ] && [ "$PGID_VAL" -gt 1 ] 2>/dev/null; then
      MY_PGID=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)
      if [ "$PGID_VAL" != "$MY_PGID" ]; then
        kill -TERM -- "-$PGID_VAL" 2>/dev/null || true
      fi
    fi
    STOPPED_ANY=1
  done
fi

# 3. Wait up to 2 seconds for clean shutdown, then escalate to SIGKILL if anything survives
if [ "$STOPPED_ANY" -eq 1 ]; then
  for _ in 1 2 3 4 5 6 7 8; do
    STILL_PORT=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    STILL_TRACKED=""
    for pid in "${TRACKED_PIDS[@]:-}"; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        STILL_TRACKED="$STILL_TRACKED $pid"
      fi
    done
    if [ -z "$STILL_PORT" ] && [ -z "$STILL_TRACKED" ]; then
      break
    fi
    sleep 0.25
  done

  for pid in "${TRACKED_PIDS[@]:-}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill_tree_kill "$pid"
    fi
  done

  REMAINING=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$REMAINING" ]; then
    for pid in $REMAINING; do
      kill_tree_kill "$pid"
    done
  fi
  echo "Stopped process(es) on port $PORT"
else
  echo "No process listening on port $PORT"
fi
