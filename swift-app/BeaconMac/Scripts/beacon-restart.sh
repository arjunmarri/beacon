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

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

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

detect_pm() {
  if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
    echo "pnpm"
  elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    echo "yarn"
  elif { [ -f "bun.lock" ] || [ -f "bun.lockb" ]; } && command -v bun >/dev/null 2>&1; then
    echo "bun"
  else
    echo "npm"
  fi
}

pkg_has_script() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 && node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, process.argv[1]) ? 0 : 1);
    } catch { process.exit(1); }
  ' "$1" 2>/dev/null
}

pkg_script_value() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const val = pkg.scripts && pkg.scripts[process.argv[1]];
      if (typeof val === "string") process.stdout.write(val);
    } catch {}
  ' "$1" 2>/dev/null || true
}

pkg_script_names() {
  if [ ! -f "package.json" ]; then
    echo "none (no package.json)"
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const keys = pkg.scripts && typeof pkg.scripts === "object" ? Object.keys(pkg.scripts) : [];
      process.stdout.write(keys.length ? keys.join(", ") : "none");
    } catch { process.stdout.write("unreadable"); }
  ' 2>/dev/null || echo "unknown"
}

pkg_main_entry() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      if (typeof pkg.main === "string" && pkg.main.trim()) process.stdout.write(pkg.main.trim());
    } catch {}
  ' 2>/dev/null || true
}

resolve_auto_start_cmd() {
  local pm="$1"
  local port="$2"
  if [ -f "package.json" ]; then
    if pkg_has_script dev; then
      local dev_val
      dev_val=$(pkg_script_value dev)
      if echo "$dev_val" | grep -qiE '(vite|astro|nuxt|svelte-kit)'; then
        echo "$pm run dev -- --port $port"
      elif echo "$dev_val" | grep -qiE '(^|[[:space:]])next([[:space:]]|$)'; then
        echo "$pm run dev -- -p $port"
      else
        echo "$pm run dev"
      fi
      return 0
    elif pkg_has_script start; then
      echo "$pm start"
      return 0
    elif pkg_has_script serve; then
      echo "$pm run serve"
      return 0
    elif pkg_has_script preview; then
      local prev_val
      prev_val=$(pkg_script_value preview)
      if echo "$prev_val" | grep -qi 'vite'; then
        echo "$pm run preview -- --port $port"
      else
        echo "$pm run preview"
      fi
      return 0
    fi
    local main_entry
    main_entry=$(pkg_main_entry)
    if [ -n "$main_entry" ] && [ -f "$main_entry" ]; then
      echo "node \"$main_entry\""
      return 0
    fi
  fi
  for candidate in server.js index.js app.js main.js; do
    if [ -f "$candidate" ]; then
      echo "node $candidate"
      return 0
    fi
  done
  return 1
}

LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
SERVER_LOG="$HOME/beaconmac/server.log"

PM=$(detect_pm)
CUSTOM_CMD_TRIMMED=$(printf '%s' "$CUSTOM_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
FINAL_START_CMD=""

if [ -z "$CUSTOM_CMD_TRIMMED" ] || [ "$CUSTOM_CMD_TRIMMED" = "auto" ]; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-restart] ERROR: Could not auto-detect a start command in $WORKDIR (package.json scripts: $(pkg_script_names)). Open Edit App in BeaconMac and set a custom Start Command." >&2
    exit 16
  fi
  echo "[beacon-restart] Auto-detected start command on port $PORT: $FINAL_START_CMD"
elif printf '%s' "$CUSTOM_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+dev([[:space:]]|$)' \
     && [ -f "package.json" ] && ! pkg_has_script dev; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-restart] ERROR: package.json has no \"dev\" script (available: $(pkg_script_names)). Open Edit App in BeaconMac and set a valid Start Command." >&2
    exit 16
  fi
  echo "[beacon-restart] WARNING: package.json has no \"dev\" script (available: $(pkg_script_names)) — falling back to: $FINAL_START_CMD"
else
  FINAL_START_CMD="$CUSTOM_CMD_TRIMMED"
fi

PORT="$PORT" nohup /bin/zsh -lc "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
sleep 1
if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "[beacon-restart] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 15 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi
SUMMARY="Restarted target local app in $WORKDIR on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [beacon-restart] $SUMMARY" >> "$SERVER_LOG"
