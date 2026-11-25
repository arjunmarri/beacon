#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-deploy.sh
# Full Clone -> Pull -> Dependency Audit/Install -> Build -> Local Deploy pipeline
# invoked safely by BeaconMac via Apple's NSUserUnixTask API.
#
# Arguments:
#   $1 = Remote Git repository URL (https://... or git@...)
#   $2 = Git branch (e.g. main)
#   $3 = Local target folder path
#   $4 = Target port number (e.g. 5173)
#   $5 = Install command (optional; "auto" detects npm/pnpm/yarn/bun)
#   $6 = Build command (optional; blank skips build)
#   $7 = Start command (optional; defaults to npm run dev -- --port $PORT)
set -euo pipefail

REPO_URL="${1:-}"
BRANCH="${2:-main}"
WORKDIR="${3:-}"
PORT="${4:-5173}"
INSTALL_CMD="${5:-auto}"
BUILD_CMD="${6:-}"
START_CMD="${7:-}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

echo "[beacon-deploy] Checking required developer tools..."
for bin in git node; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[beacon-deploy] ERROR: Required tool '$bin' is not installed or not in PATH." >&2
    exit 12
  fi
done
echo "[beacon-deploy] Found git $(git --version | awk '{print $3}'), node $(node -v)"

if [ -z "$WORKDIR" ]; then
  echo "[beacon-deploy] ERROR: Local target folder is required." >&2
  exit 13
fi

# 1. Clone remote repository if not present, otherwise fetch & pull latest
if [ ! -d "$WORKDIR/.git" ]; then
  if [ -z "$REPO_URL" ]; then
    echo "[beacon-deploy] ERROR: No local .git repo at $WORKDIR and no remote repository URL provided." >&2
    exit 14
  fi
  echo "[beacon-deploy] Cloning $REPO_URL (branch: $BRANCH) into $WORKDIR..."
  mkdir -p "$(dirname "$WORKDIR")"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$WORKDIR"
else
  echo "[beacon-deploy] Fetching updates for branch '$BRANCH' in $WORKDIR..."
  cd "$WORKDIR"
  if [ -n "$REPO_URL" ]; then
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin -- "$REPO_URL"
    else
      git remote add origin -- "$REPO_URL"
    fi
  fi
  git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git checkout "$BRANCH" 2>/dev/null || git checkout -B "$BRANCH" "origin/$BRANCH"
    git pull --ff-only origin "$BRANCH"
  else
    git checkout -B "$BRANCH" "origin/$BRANCH"
  fi
fi

cd "$WORKDIR"
CURRENT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "[beacon-deploy] Repository ready at commit $CURRENT_SHA"

# 2. Detect package manager & package.json script helpers
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

PM=$(detect_pm)

# 3. Check & install required project libraries (Vite / Node / Bun / pnpm / Yarn)
if [ -f "package.json" ]; then
  NEEDS_INSTALL=0
  if [ ! -d "node_modules" ]; then
    NEEDS_INSTALL=1
  elif [ "package.json" -nt "node_modules" ]; then
    NEEDS_INSTALL=1
  fi

  if [ "$INSTALL_CMD" != "skip" ] && [ "$NEEDS_INSTALL" -eq 1 -o "$INSTALL_CMD" != "auto" ]; then
    if [ "$INSTALL_CMD" = "auto" ] || [ -z "$INSTALL_CMD" ]; then
      case "$PM" in
        pnpm)
          echo "[beacon-deploy] Installing dependencies via pnpm install..."
          pnpm install --frozen-lockfile || pnpm install
          ;;
        yarn)
          echo "[beacon-deploy] Installing dependencies via yarn install..."
          yarn install
          ;;
        bun)
          echo "[beacon-deploy] Installing dependencies via bun install..."
          bun install
          ;;
        *)
          echo "[beacon-deploy] Installing dependencies via npm install..."
          npm install
          ;;
      esac
    else
      echo "[beacon-deploy] Running install command: $INSTALL_CMD"
      /bin/bash -c "$INSTALL_CMD"
    fi
  else
    echo "[beacon-deploy] Dependencies up to date (node_modules present)."
  fi
fi

# 4. Build application if configured (safely skips when package.json has no "build" script)
BUILD_CMD_TRIMMED=$(printf '%s' "$BUILD_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -n "$BUILD_CMD_TRIMMED" ] && [ "$BUILD_CMD_TRIMMED" != "skip" ]; then
  if [ "$BUILD_CMD_TRIMMED" = "auto" ]; then
    if pkg_has_script build; then
      echo "[beacon-deploy] Auto-detected \"build\" script — running: $PM run build"
      "$PM" run build
    else
      echo "[beacon-deploy] No \"build\" script in package.json (available: $(pkg_script_names)) — skipping build step."
    fi
  elif printf '%s' "$BUILD_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?build([[:space:]]|$)' \
       && [ -f "package.json" ] && ! pkg_has_script build; then
    echo "[beacon-deploy] WARNING: \"$BUILD_CMD_TRIMMED\" requested, but package.json has no \"build\" script (available: $(pkg_script_names)). Skipping build step."
  else
    echo "[beacon-deploy] Building application: $BUILD_CMD_TRIMMED"
    /bin/bash -c "$BUILD_CMD_TRIMMED"
  fi
fi

# 5. Stop any previous instance (tracked PID group or listener on target port)
LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
PID_DIR="$HOME/beaconmac/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
PID_FILE="$PID_DIR/${LOG_SLUG:-app}-${PORT}.pid"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[beacon-deploy] Stopping previous tracked instance (PID $OLD_PID)..."
    kill -TERM -- "-$OLD_PID" 2>/dev/null || true
    pkill -TERM -P "$OLD_PID" 2>/dev/null || true
    kill -TERM "$OLD_PID" 2>/dev/null || true
    sleep 0.6
    if kill -0 "$OLD_PID" 2>/dev/null; then
      kill -KILL -- "-$OLD_PID" 2>/dev/null || true
      kill -KILL "$OLD_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
fi

EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  echo "[beacon-deploy] Stopping previous process on port $PORT (PID $EXISTING_PID)..."
  kill -TERM $EXISTING_PID 2>/dev/null || true
  sleep 1
fi

START_CMD_TRIMMED=$(printf '%s' "$START_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
FINAL_START_CMD=""

if [ -z "$START_CMD_TRIMMED" ] || [ "$START_CMD_TRIMMED" = "auto" ]; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-deploy] ERROR: Could not auto-detect a start command in $WORKDIR (package.json scripts: $(pkg_script_names)). Open Edit App in BeaconMac and set a custom Start Command." >&2
    exit 16
  fi
  echo "[beacon-deploy] Auto-detected start command on port $PORT: $FINAL_START_CMD"
elif printf '%s' "$START_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+dev([[:space:]]|$)' \
     && [ -f "package.json" ] && ! pkg_has_script dev; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-deploy] ERROR: package.json has no \"dev\" script (available: $(pkg_script_names)). Open Edit App in BeaconMac and set a valid Start Command." >&2
    exit 16
  fi
  echo "[beacon-deploy] WARNING: package.json has no \"dev\" script (available: $(pkg_script_names)) — falling back to: $FINAL_START_CMD"
else
  FINAL_START_CMD="$START_CMD_TRIMMED"
  echo "[beacon-deploy] Starting app on port $PORT: $FINAL_START_CMD"
fi

echo "=== [beacon-deploy] $(date -u +"%Y-%m-%dT%H:%M:%SZ") starting (PORT=$PORT): $FINAL_START_CMD ===" >> "$APP_LOG"
if [ -x /usr/bin/perl ]; then
  PORT="$PORT" nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  PORT="$PORT" nohup /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
fi

NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"
disown "$NEW_PID" 2>/dev/null || true

# Poll up to 2 seconds to catch immediate exits and allow stdout/stderr buffers to flush
EXITED_EARLY=0
for _ in 1 2 3 4 5 6 7 8; do
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    EXITED_EARLY=1
    break
  fi
  sleep 0.25
done

if [ "$EXITED_EARLY" -eq 1 ]; then
  rm -f "$PID_FILE"
  sleep 0.25
  echo "[beacon-deploy] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 25 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi

# Detect if the launched app actually bound to a different local port than $PORT
BOUND_PORTS=$(lsof -Pan -p "$NEW_PID" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -u | tr '\n' ' ' || true)
CHILD_PIDS=$(pgrep -P "$NEW_PID" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
if [ -n "$CHILD_PIDS" ]; then
  CHILD_PORTS=$(lsof -Pan -p "$CHILD_PIDS" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -u | tr '\n' ' ' || true)
  BOUND_PORTS="$BOUND_PORTS $CHILD_PORTS"
fi
BOUND_PORTS=$(echo "$BOUND_PORTS" | xargs 2>/dev/null || true)
if [ -n "$BOUND_PORTS" ] && ! echo " $BOUND_PORTS " | grep -q " $PORT "; then
  echo "[beacon-deploy] NOTE: App is listening on port(s) [$BOUND_PORTS] instead of configured port $PORT. Check if your server hardcodes its port or update Monitor URL in Edit App."
fi

SUMMARY="[beacon-deploy] Deployed commit $CURRENT_SHA on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $SUMMARY" >> "$SERVER_LOG"
