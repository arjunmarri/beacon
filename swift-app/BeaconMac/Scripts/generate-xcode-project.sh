#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is not installed. Installing via Homebrew..."
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "Please install Homebrew (https://brew.sh) or run: open Package.swift"
    exit 1
  fi
fi

echo "Generating BeaconMac.xcodeproj..."
xcodegen generate
echo "Opening BeaconMac.xcodeproj in Xcode..."
open BeaconMac.xcodeproj
