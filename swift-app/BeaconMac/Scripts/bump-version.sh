#!/bin/bash
# Bumps BeaconMac version across version.json, project.yml, releases/releases.json, and CHANGELOG.md.
# Usage:
#   ./swift-app/BeaconMac/Scripts/bump-version.sh 1.0.1 "Fix port detection and add startup retry"
set -euo pipefail

NEW_VERSION="${1:-}"
RELEASE_NOTE="${2:-Maintenance release}"

if [ -z "$NEW_VERSION" ] || ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <MAJOR.MINOR.PATCH> [\"Release note summary\"]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VERSION_FILE="$REPO_ROOT/version.json"
RELEASES_FILE="$REPO_ROOT/releases/releases.json"
PROJECT_YML="$REPO_ROOT/swift-app/BeaconMac/project.yml"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

node -e '
const fs = require("fs");
const [versionFile, releasesFile, projectYml, changelogFile, newVer, note] = process.argv.slice(1);

const verData = JSON.parse(fs.readFileSync(versionFile, "utf8"));
const nextBuild = (Number(verData.build) || 0) + 1;
const dmgFilename = `BeaconMac-${newVer}-universal.dmg`;
const repo = verData.githubRepo || "arjunmarri/beacon";
const today = new Date().toISOString().slice(0, 10);

verData.version = newVer;
verData.build = nextBuild;
verData.dmgFilename = dmgFilename;
fs.writeFileSync(versionFile, JSON.stringify(verData, null, 2) + "\n");

if (fs.existsSync(projectYml)) {
  let yml = fs.readFileSync(projectYml, "utf8");
  yml = yml.replace(/MARKETING_VERSION:\s*"[^"]*"/, `MARKETING_VERSION: "${newVer}"`);
  yml = yml.replace(/CURRENT_PROJECT_VERSION:\s*"[^"]*"/, `CURRENT_PROJECT_VERSION: "${nextBuild}"`);
  yml = yml.replace(/CFBundleShortVersionString:\s*"[^"]*"/, `CFBundleShortVersionString: "${newVer}"`);
  yml = yml.replace(/CFBundleVersion:\s*"[^"]*"/, `CFBundleVersion: "${nextBuild}"`);
  fs.writeFileSync(projectYml, yml);
}

const manifest = JSON.parse(fs.readFileSync(releasesFile, "utf8"));
manifest.latest = newVer;
const filtered = (manifest.releases || []).filter((r) => r.version !== newVer);
filtered.unshift({
  version: newVer,
  build: nextBuild,
  date: today,
  minMacOS: verData.minMacOS || "14.0",
  architecture: verData.architecture || "Universal (Apple Silicon + Intel)",
  dmgFilename,
  githubDownloadUrl: `https://github.com/${repo}/releases/download/v${newVer}/${dmgFilename}`,
  sha256: null,
  sizeBytes: null,
  notes: [note]
});
manifest.releases = filtered;
fs.writeFileSync(releasesFile, JSON.stringify(manifest, null, 2) + "\n");

if (fs.existsSync(changelogFile)) {
  const existing = fs.readFileSync(changelogFile, "utf8");
  if (!existing.includes(`## [${newVer}]`)) {
    const entry = `\n## [${newVer}] — ${today}\n\n### Changed\n- ${note}\n`;
    const updated = existing.replace("---\n", `---\n${entry}`);
    fs.writeFileSync(changelogFile, updated);
  }
}

console.log(`Bumped BeaconMac to v${newVer} (build ${nextBuild}) -> ${dmgFilename}`);
' "$VERSION_FILE" "$RELEASES_FILE" "$PROJECT_YML" "$CHANGELOG_FILE" "$NEW_VERSION" "$RELEASE_NOTE"

echo ""
echo "Next steps to publish the signed/universal DMG:"
echo "  git add version.json releases/releases.json swift-app/BeaconMac/project.yml CHANGELOG.md"
echo "  git commit -m \"Release v${NEW_VERSION}\""
echo "  git tag v${NEW_VERSION} && git push origin main --tags"
