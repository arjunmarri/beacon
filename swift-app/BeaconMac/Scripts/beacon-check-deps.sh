#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-check-deps.sh
# Audits required macOS runtime tools (git, node, npm, pnpm, yarn, bun) and
# verifies whether a target app folder has its required libraries installed.
# Arguments:
#   $1 = Optional target app working directory
set -euo pipefail

WORKDIR="${1:-}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

check_bin() {
  local name="$1"
  local mode="${2:-required}"
  if command -v "$name" >/dev/null 2>&1; then
    local ver
    ver=$("$name" --version 2>/dev/null | head -n 1 || echo "installed")
    echo "TOOL:$name:OK:$ver"
  elif [ "$mode" = "optional" ]; then
    echo "TOOL:$name:OPTIONAL:not installed (optional)"
  else
    echo "TOOL:$name:MISSING:not found in PATH"
  fi
}

check_bin git required
check_bin node required
check_bin npm required
check_bin pnpm optional
check_bin yarn optional
check_bin bun optional

if [ -n "$WORKDIR" ]; then
  if [ ! -d "$WORKDIR" ]; then
    echo "APP:FOLDER:MISSING:$WORKDIR does not exist yet (will clone on deploy)"
    exit 0
  fi
  if [ -d "$WORKDIR/.git" ]; then
    SHA=$(git -C "$WORKDIR" rev-parse --short HEAD 2>/dev/null || echo "unborn")
    echo "APP:GIT:OK:$SHA"
  else
    echo "APP:GIT:MISSING:no .git directory"
  fi
  if [ -f "$WORKDIR/package.json" ]; then
    if [ -d "$WORKDIR/node_modules" ]; then
      PKG_COUNT=$(find "$WORKDIR/node_modules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      echo "APP:DEPS:OK:$PKG_COUNT packages installed"
    else
      SUB_NM=$(find "$WORKDIR" -maxdepth 2 -mindepth 2 -type d -name "node_modules" 2>/dev/null | head -n 1 || true)
      if [ -n "$SUB_NM" ]; then
        PKG_COUNT=$(find "$SUB_NM" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        SUB_NAME=$(basename "$(dirname "$SUB_NM")")
        echo "APP:DEPS:OK:$PKG_COUNT packages installed ($SUB_NAME/node_modules)"
      elif ! grep -qE '"(dependencies|devDependencies)"[[:space:]]*:[[:space:]]*\{[[:space:]]*"' "$WORKDIR/package.json" 2>/dev/null; then
        echo "APP:DEPS:OK:no external npm packages required"
      else
        echo "APP:DEPS:MISSING:node_modules not found in root (run npm install if needed)"
      fi
    fi
  else
    SUB_NM=$(find "$WORKDIR" -maxdepth 2 -mindepth 2 -type d -name "node_modules" 2>/dev/null | head -n 1 || true)
    if [ -n "$SUB_NM" ]; then
      PKG_COUNT=$(find "$SUB_NM" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      SUB_NAME=$(basename "$(dirname "$SUB_NM")")
      echo "APP:DEPS:OK:$PKG_COUNT packages installed ($SUB_NAME/node_modules)"
    else
      echo "APP:DEPS:NONE:no package.json found"
    fi
  fi
fi
