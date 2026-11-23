#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-git-pull.sh
# Called safely by Beacon via Apple's App-Sandbox-approved NSUserUnixTask API.
# Arguments passed by Beacon:
#   $1 = Working directory path
#   $2 = Git branch name (e.g. main)
set -euo pipefail

WORKDIR="${1:-$HOME}"
BRANCH="${2:-main}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ ! -d "$WORKDIR/.git" ]; then
  echo "No .git repository found in $WORKDIR" >&2
  exit 1
fi

cd "$WORKDIR"
git fetch origin -- "$BRANCH"
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  git pull --ff-only origin "$BRANCH"
else
  git checkout -B "$BRANCH" "origin/$BRANCH"
fi
echo "Synced $(git rev-parse --short HEAD) on branch $BRANCH"
