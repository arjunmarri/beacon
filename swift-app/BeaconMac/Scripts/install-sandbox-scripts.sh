#!/bin/bash
# Installs BeaconMac's App-Sandbox-approved NSUserUnixTask scripts into
# ~/Library/Application Scripts/<BUNDLE_ID>/ (and ~/Library/Application Scripts/BeaconMac/
# for SwiftPM `swift run` launches) so BeaconMac can clone repos, check/install Node
# dependencies, build Vite/Node apps, manage launchd, and start/stop apps locally.
set -euo pipefail

BUNDLE_ID="${1:-com.beaconmac.app}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TARGETS=(
  "$HOME/Library/Application Scripts/$BUNDLE_ID"
  "$HOME/Library/Application Scripts/BeaconMac"
)

for TARGET_DIR in "${TARGETS[@]}"; do
  mkdir -p "$TARGET_DIR"
  for file in beacon-deploy.sh beacon-check-deps.sh beacon-restart.sh beacon-stop.sh beacon-git-pull.sh beacon-startup.sh beacon-launchd.sh; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
      cp "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
      chmod +x "$TARGET_DIR/$file"
    fi
  done
  echo "Installed all 7 BeaconMac scripts into: $TARGET_DIR"
done

echo ""
echo "Done! BeaconMac is ready to clone, check deps, build, deploy, and manage launchd."
