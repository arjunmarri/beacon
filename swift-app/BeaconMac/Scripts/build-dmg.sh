#!/bin/bash
# Builds a Universal (Apple Silicon + Intel) BeaconMac.app bundle on macOS and packages
# it into a signed, notarized, drag-to-Applications compressed DMG:
#   releases/BeaconMac-<version>-universal.dmg
#
# Usage (run on macOS 14+ with Xcode 15.4+):
#   ./swift-app/BeaconMac/Scripts/build-dmg.sh
#
# Required for public releases / CI (enforced when REQUIRE_SIGNING=1 or CI=true):
#   APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   And EITHER:
#     APPLE_NOTARY_PROFILE="BeaconMacNotary"   # created via `xcrun notarytool store-credentials`
#   OR:
#     APPLE_ID="you@example.com"
#     APPLE_TEAM_ID="ABCDE12345"
#     APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#
# Entitlements selection:
#   Default (Direct Developer ID DMG): Sources/Beacon/Resources/Beacon-DMG.entitlements
#     (Hardened Runtime, com.apple.security.app-sandbox = false — explicitly documented for
#      direct DMG distribution so local toolchains and verified self-updates work.)
#   Optional Sandboxed DMG (BEACONMAC_SANDBOX_DMG=1): Sources/Beacon/Resources/Beacon.entitlements
#     (com.apple.security.app-sandbox = true, matching Mac App Store builds.)
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: Building a real macOS .app and .dmg requires macOS (Darwin) with Xcode/Swift and hdiutil." >&2
  echo "Tip: Push a Git tag (e.g. git tag v1.1.0 && git push origin v1.1.0) to let GitHub Actions (macos-14) build, sign, notarize, and publish the DMG automatically." >&2
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

# Select entitlements explicitly — NEVER sign without --entitlements
if [ "${BEACONMAC_SANDBOX_DMG:-0}" = "1" ]; then
  ENTITLEMENTS_REL="Sources/Beacon/Resources/Beacon.entitlements"
  ENABLE_SANDBOX_FLAG="YES"
else
  ENTITLEMENTS_REL="Sources/Beacon/Resources/Beacon-DMG.entitlements"
  ENABLE_SANDBOX_FLAG="NO"
fi
ENTITLEMENTS_PATH="$SWIFT_DIR/$ENTITLEMENTS_REL"

if [ ! -f "$ENTITLEMENTS_PATH" ]; then
  echo "ERROR: Missing entitlements file at $ENTITLEMENTS_PATH" >&2
  exit 1
fi

# Enforce Developer ID signing & notarization in CI or whenever REQUIRE_SIGNING=1
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
if [ "${CI:-false}" = "true" ]; then
  REQUIRE_SIGNING="1"
fi

HAS_NOTARY_PROFILE=0
HAS_NOTARY_CREDS=0
if [ -n "${APPLE_NOTARY_PROFILE:-}" ]; then
  HAS_NOTARY_PROFILE=1
fi
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  HAS_NOTARY_CREDS=1
fi

if [ "$REQUIRE_SIGNING" = "1" ]; then
  if [ -z "${APPLE_SIGN_IDENTITY:-}" ]; then
    echo "ERROR: APPLE_SIGN_IDENTITY is required for release builds (REQUIRE_SIGNING=1 / CI=true)." >&2
    echo "Refusing to ship an ad-hoc signed DMG. Configure Developer ID Application signing credentials." >&2
    exit 1
  fi
  if [ "$HAS_NOTARY_PROFILE" -eq 0 ] && [ "$HAS_NOTARY_CREDS" -eq 0 ]; then
    echo "ERROR: Apple notarization credentials are required for release builds (REQUIRE_SIGNING=1 / CI=true)." >&2
    echo "Set APPLE_NOTARY_PROFILE or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi
fi

BUILD_ROOT="$SWIFT_DIR/.dmg-build"
STAGE_DIR="$BUILD_ROOT/dmg-stage"
APP_BUNDLE="$STAGE_DIR/BeaconMac.app"

rm -rf "$BUILD_ROOT"
mkdir -p "$STAGE_DIR" "$RELEASES_DIR"

echo "==> Building BeaconMac v${VERSION} (build ${BUILD_NUM}) Universal binary (arm64 + x86_64)..."
echo "    Entitlements: $ENTITLEMENTS_REL (App Sandbox: $ENABLE_SANDBOX_FLAG)"
cd "$SWIFT_DIR"

if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  xcodegen generate --spec project.yml
  # Build unsigned first because bundled scripts are copied into Contents/Resources/Scripts
  # before the final verified codesign pass with --entitlements and --options runtime.
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
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_REL" \
    ENABLE_HARDENED_RUNTIME=YES \
    ENABLE_APP_SANDBOX="$ENABLE_SANDBOX_FLAG" \
    CODE_SIGNING_ALLOWED=NO \
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

# Bundle helper scripts inside BeaconMac.app/Contents/Resources/Scripts BEFORE code signing
mkdir -p "$APP_BUNDLE/Contents/Resources/Scripts"
cp "$SWIFT_DIR/Scripts/"*.sh "$APP_BUNDLE/Contents/Resources/Scripts/"
cp "$SWIFT_DIR/Scripts/"*.mjs "$APP_BUNDLE/Contents/Resources/Scripts/" 2>/dev/null || true
chmod +x "$APP_BUNDLE/Contents/Resources/Scripts/"*.sh

# Code signing — ALWAYS pass --entitlements and --options runtime on every signing path
if [ -n "${APPLE_SIGN_IDENTITY:-}" ]; then
  echo "==> Signing BeaconMac.app with Developer ID: $APPLE_SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$APPLE_SIGN_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "WARNING: Applying local dev ad-hoc signature with entitlements ($ENTITLEMENTS_REL)."
  echo "         Do NOT distribute this DMG publicly; set APPLE_SIGN_IDENTITY and notary credentials for releases."
  codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign - \
    "$APP_BUNDLE"
fi

echo "==> Verifying BeaconMac.app signature & entitlements..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" >/dev/null

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
  echo "==> Signing DMG with Developer ID..."
  codesign --force --timestamp --sign "$APPLE_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"

  if [ "$HAS_NOTARY_PROFILE" -eq 1 ]; then
    echo "==> Notarizing $DMG_NAME via Apple notarytool (keychain profile)..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
  elif [ "$HAS_NOTARY_CREDS" -eq 1 ]; then
    echo "==> Notarizing $DMG_NAME via Apple notarytool (Apple ID credentials)..."
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
  fi

  if [ "$HAS_NOTARY_PROFILE" -eq 1 ] || [ "$HAS_NOTARY_CREDS" -eq 1 ]; then
    echo "==> Stapling & validating notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    echo "==> Verifying Gatekeeper (spctl) on packaged BeaconMac.app..."
    VERIFY_MOUNT="$BUILD_ROOT/verify-mount"
    mkdir -p "$VERIFY_MOUNT"
    hdiutil attach -nobrowse -readonly -mountpoint "$VERIFY_MOUNT" "$DMG_PATH" >/dev/null
    trap 'hdiutil detach "$VERIFY_MOUNT" -quiet 2>/dev/null || true' EXIT
    codesign --verify --deep --strict --verbose=2 "$VERIFY_MOUNT/BeaconMac.app"
    spctl -a -t exec -vv "$VERIFY_MOUNT/BeaconMac.app"
    hdiutil detach "$VERIFY_MOUNT" -quiet
    trap - EXIT
  fi
fi

# Generate SHA-256 checksum AFTER signing & stapling so it matches the exact shipped bytes
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
