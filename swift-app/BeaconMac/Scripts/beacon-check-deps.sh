#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-check-deps.sh
# Audits required macOS runtime tools (git, node, npm, pnpm, yarn, bun) and
# verifies whether a target app folder has its required libraries installed.
# Arguments:
#   $1 = Optional target app working directory
set -euo pipefail

WORKDIR="${1:-}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tail -n 1)/bin:$PATH"

check_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local ver
    ver=$("$name" --version 2>/dev/null | head -n 1 || echo "installed")
    echo "TOOL:$name:OK:$ver"
  else
    echo "TOOL:$name:MISSING:not found in PATH"
  fi
}

check_bin git
check_bin node
check_bin npm
check_bin pnpm
check_bin yarn
check_bin bun

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
      echo "APP:DEPS:MISSING:node_modules missing (install required)"
    fi
  else
    echo "APP:DEPS:NONE:no package.json found"
  fi
fi
