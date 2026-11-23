#!/bin/bash
# Installs BeaconMac's App-Sandbox-approved NSUserUnixTask scripts into
# ~/Library/Application Scripts/<BUNDLE_ID>/ so BeaconMac can clone repos,
# check/install Node dependencies, build Vite/Node apps, and start/stop them locally.
set -euo pipefail

BUNDLE_ID="${1:-com.beaconmac.app}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/Library/Application Scripts/$BUNDLE_ID"

mkdir -p "$TARGET_DIR"

for file in beacon-deploy.sh beacon-check-deps.sh beacon-restart.sh beacon-stop.sh beacon-git-pull.sh beacon-startup.sh beacon-launchd.sh; do
  if [ -f "$SCRIPT_DIR/$file" ]; then
    cp "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
    chmod +x "$TARGET_DIR/$file"
    echo "Installed $TARGET_DIR/$file"
  fi
done

echo ""
echo "All BeaconMac sandbox hook scripts installed for bundle ID: $BUNDLE_ID"
