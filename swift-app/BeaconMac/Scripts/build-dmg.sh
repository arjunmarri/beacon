#!/bin/bash
# Builds a Universal (Apple Silicon + Intel) BeaconMac.app bundle on macOS and packages
# it into a drag-to-Applications compressed DMG: releases/BeaconMac-<version>-universal.dmg
#
# Usage (run on macOS 14+ with Xcode 15.4+):
#   ./swift-app/BeaconMac/Scripts/build-dmg.sh
#
# Optional signing & notarization environment variables:
#   APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   APPLE_NOTARY_PROFILE="BeaconMacNotary"   # created via `xcrun notarytool store-credentials`
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: Building a real macOS .app and .dmg requires macOS (Darwin) with Xcode/Swift and hdiutil." >&2
  echo "Tip: Push a Git tag (e.g. git tag v1.0.0 && git push origin v1.0.0) to let GitHub Actions (macos-14) build and publish the DMG automatically." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SWIFT_DIR/../.." && pwd)"
VERSION_FILE="$REPO_ROOT/version.json"
RELEASES_DIR="$REPO_ROOT/releases"
RELEASES_JSON="$RELEASES_DIR/releases.json"

VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['version'])")
BUILD_NUM=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['build'])")
BUNDLE_ID="${BEACONMAC_BUNDLE_ID:-com.beaconmac.app}"
DMG_NAME="BeaconMac-${VERSION}-universal.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"

BUILD_ROOT="$SWIFT_DIR/.dmg-build"
STAGE_DIR="$BUILD_ROOT/dmg-stage"
APP_BUNDLE="$STAGE_DIR/BeaconMac.app"

rm -rf "$BUILD_ROOT"
mkdir -p "$STAGE_DIR" "$RELEASES_DIR"

echo "==> Building BeaconMac v${VERSION} (build ${BUILD_NUM}) Universal binary (arm64 + x86_64)..."
cd "$SWIFT_DIR"

if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  xcodegen generate --spec project.yml
  xcodebuild \
    -project BeaconMac.xcodeproj \
    -scheme BeaconMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_ROOT/DerivedData" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:--}" \
    CODE_SIGNING_REQUIRED=NO \
    clean build

  BUILT_APP="$BUILD_ROOT/DerivedData/Build/Products/Release/BeaconMac.app"
  cp -R "$BUILT_APP" "$APP_BUNDLE"
else
  echo "==> xcodegen not found; building Universal binary via Swift Package Manager..."
  swift build -c release --arch arm64 --arch x86_64
  BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/BeaconMac"

  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
  cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/BeaconMac"
  chmod +x "$APP_BUNDLE/Contents/MacOS/BeaconMac"

  sed \
    -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
    -e "s/\$(EXECUTABLE_NAME)/BeaconMac/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUM/g" \
    "$SWIFT_DIR/Sources/Beacon/Resources/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
fi

# Bundle helper scripts inside BeaconMac.app/Contents/Resources/Scripts for easy one-click access
mkdir -p "$APP_BUNDLE/Contents/Resources/Scripts"
cp "$SWIFT_DIR/Scripts/"*.sh "$APP_BUNDLE/Contents/Resources/Scripts/"
chmod +x "$APP_BUNDLE/Contents/Resources/Scripts/"*.sh

# Code signing (Developer ID if provided, otherwise ad-hoc local sign)
if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
  echo "==> Signing BeaconMac.app with: $APPLE_SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$SWIFT_DIR/Sources/Beacon/Resources/Beacon.entitlements" \
    --sign "$APPLE_SIGN_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "==> Applying ad-hoc signature (set APPLE_SIGN_IDENTITY for Developer ID distribution)..."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

# Create standard drag-to-Applications DMG staging layout
ln -s /Applications "$STAGE_DIR/Applications"
cp "$REPO_ROOT/README.md" "$STAGE_DIR/README.txt"

rm -f "$DMG_PATH"
echo "==> Packaging $DMG_PATH..."
hdiutil create \
  -volname "BeaconMac ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$APPLE_SIGN_IDENTITY" "$DMG_PATH"
  if [ -n "${APPLE_NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing $DMG_NAME via Apple notarytool..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
  fi
fi

# Generate SHA-256 checksum and record file size in releases/releases.json
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
SIZE_BYTES=$(stat -f%z "$DMG_PATH")
echo "${SHA256}  ${DMG_NAME}" > "${DMG_PATH}.sha256"

python3 - "$RELEASES_JSON" "$VERSION" "$SHA256" "$SIZE_BYTES" <<'PY'
import json, sys
path, ver, sha, size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
data = json.load(open(path))
for rel in data.get("releases", []):
    if rel.get("version") == ver:
        rel["sha256"] = sha
        rel["sizeBytes"] = size
        break
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

rm -rf "$BUILD_ROOT"
echo ""
echo "==> Built: $DMG_PATH"
echo "    Size:   $SIZE_BYTES bytes"
echo "    SHA256: $SHA256"
