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

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
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

# 2. Check & install required project libraries (Vite / Node)
if [ -f "package.json" ]; then
  NEEDS_INSTALL=0
  if [ ! -d "node_modules" ]; then
    NEEDS_INSTALL=1
  elif [ "package.json" -nt "node_modules" ]; then
    NEEDS_INSTALL=1
  fi

  if [ "$INSTALL_CMD" != "skip" ] && [ "$NEEDS_INSTALL" -eq 1 -o "$INSTALL_CMD" != "auto" ]; then
    if [ "$INSTALL_CMD" = "auto" ] || [ -z "$INSTALL_CMD" ]; then
      if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
        echo "[beacon-deploy] Installing dependencies via pnpm install..."
        pnpm install --frozen-lockfile || pnpm install
      elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
        echo "[beacon-deploy] Installing dependencies via yarn install..."
        yarn install
      elif [ -f "bun.lock" ] || [ -f "bun.lockb" ]; then
        if command -v bun >/dev/null 2>&1; then
          echo "[beacon-deploy] Installing dependencies via bun install..."
          bun install
        else
          echo "[beacon-deploy] Installing dependencies via npm install..."
          npm install
        fi
      else
        echo "[beacon-deploy] Installing dependencies via npm install..."
        npm install
      fi
    else
      echo "[beacon-deploy] Running install command: $INSTALL_CMD"
      /bin/zsh -lc "$INSTALL_CMD"
    fi
  else
    echo "[beacon-deploy] Dependencies up to date (node_modules present)."
  fi
fi

# 3. Build application if configured
if [ -n "$BUILD_CMD" ]; then
  echo "[beacon-deploy] Building application: $BUILD_CMD"
  /bin/zsh -lc "$BUILD_CMD"
fi

# 4. Restart / deploy process locally on target port
EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  echo "[beacon-deploy] Stopping previous process on port $PORT (PID $EXISTING_PID)..."
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi

LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -n "$START_CMD" ]; then
  echo "[beacon-deploy] Starting app on port $PORT: $START_CMD"
  PORT="$PORT" nohup /bin/zsh -lc "$START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  echo "[beacon-deploy] Starting Vite/Node dev server on port $PORT..."
  PORT="$PORT" nohup npm run dev -- --port "$PORT" </dev/null >>"$APP_LOG" 2>&1 &
fi

NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
sleep 1
if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "[beacon-deploy] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 15 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi
SUMMARY="[beacon-deploy] Deployed commit $CURRENT_SHA on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $SUMMARY" >> "$SERVER_LOG"
