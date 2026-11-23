#!/bin/bash
set -euo pipefail

# Ensure Homebrew & standard macOS Node paths are available
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tail -n 1)/bin:$PATH"
export CSC_IDENTITY_AUTO_DISCOVERY=false

cd "$(dirname "$0")"

# Clear macOS browser-download quarantine attribute from this kit folder
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine . 2>/dev/null || true
fi

echo "=== Building Beacon macOS .dmg Installer ==="

if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js 20+ is required. Install from https://nodejs.org or via 'brew install node'."
  exit 1
fi

echo "Node version: $(node -v)"
echo "1/2 Installing Electron packager..."
npm install --no-audit --no-fund

echo "2/2 Packaging Beacon .dmg for this Mac ($(uname -m))..."
npm run dist:mac

# Ensure the generated .dmg and .app are not quarantined on this Mac
if command -v xattr >/dev/null 2>&1 && [ -d "./release" ]; then
  xattr -dr com.apple.quarantine ./release 2>/dev/null || true
fi

echo ""
echo "Success! Your macOS .dmg installer is ready in ./release/"
ls -lh ./release/*.dmg || true
open ./release || true
