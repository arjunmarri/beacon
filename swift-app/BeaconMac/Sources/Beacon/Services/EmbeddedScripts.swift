import AppKit
import Foundation

/// Embeds all 7 BeaconMac shell hook scripts inside the Swift binary so that:
/// 1. Non-sandboxed launches (swift run, local builds, Developer ID DMG) auto-install
///    the scripts automatically on boot with zero manual Terminal setup.
/// 2. Mac App Store App-Sandboxed launches offer a 1-click in-app NSOpenPanel installer
///    that writes all scripts directly into ~/Library/Application Scripts/<bundle-id>/.
public enum EmbeddedScripts {
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    public static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.beaconmac.app"
    }

    /// Exact directory Apple's NSUserUnixTask expects for this process.
    public static func targetScriptsDirectoryURL() -> URL {
        if let dir = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            return dir
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Scripts/\(bundleID)", isDirectory: true)
    }

    /// Secondary fallback directory (handles `swift run` where bundleIdentifier is nil
    /// while the user installed scripts under `com.beaconmac.app`).
    public static func fallbackScriptsDirectoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Scripts/com.beaconmac.app", isDirectory: true)
    }

    /// Writable fallback directory inside Application Support used outside App Sandbox
    /// if ~/Library/Application Scripts is restricted or unavailable.
    public static func appSupportScriptsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Beacon/scripts", isDirectory: true)
    }

    public static let requiredScriptNames: [String] = [
        "beacon-check-deps.sh",
        "beacon-deploy.sh",
        "beacon-restart.sh",
        "beacon-stop.sh",
        "beacon-git-pull.sh",
        "beacon-startup.sh",
        "beacon-launchd.sh"
    ]

    public static func areScriptsInstalled() -> Bool {
        if isSandboxed {
            let primary = targetScriptsDirectoryURL()
            // Inside macOS App Sandbox, FileManager.fileExists(atPath:) can return false for
            // ~/Library/Application Scripts/<bundle-id> even when scripts exist. Apple's
            // NSUserUnixTask(url:) initializer validates existence and permissions via UserScriptService.
            return requiredScriptNames.allSatisfy { name in
                let url = primary.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return true
                }
                return (try? NSUserUnixTask(url: url)) != nil
            }
        }

        let candidates: [URL] = [
            targetScriptsDirectoryURL(),
            fallbackScriptsDirectoryURL(),
            appSupportScriptsDirectoryURL()
        ]
        return candidates.contains { dir in
            requiredScriptNames.allSatisfy {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
        }
    }

    /// When running outside the Mac App Store App Sandbox (`swift run`, local Xcode run, or DMG),
    /// automatically install all 7 embedded scripts so BeaconMac works immediately out of the box.
    @discardableResult
    public static func autoInstallIfNotSandboxed() -> Bool {
        guard !isSandboxed else { return areScriptsInstalled() }
        let primaryDir = targetScriptsDirectoryURL()
        if (try? writeAllScripts(to: primaryDir)) != nil {
            return true
        }
        let cacheDir = appSupportScriptsDirectoryURL()
        if (try? writeAllScripts(to: cacheDir)) != nil {
            return true
        }
        return areScriptsInstalled()
    }

    /// Apple App-Sandbox-compliant 1-click installer using NSOpenPanel so the user
    /// grants write access to ~/Library/Application Scripts/<bundle-id>/ directly from BeaconMac.
    @MainActor
    public static func installViaOpenPanel() -> (ok: Bool, detail: String) {
        let targetDir = targetScriptsDirectoryURL()

        // If already writable (e.g. non-sandboxed or already granted), write immediately.
        if !isSandboxed {
            do {
                try writeAllScripts(to: targetDir)
                return (true, "Installed all \(requiredScriptNames.count) hook scripts into \(targetDir.path).")
            } catch {
                // Fall through to NSOpenPanel if permission denied
            }
        }

        let panel = NSOpenPanel()
        panel.title = "Install BeaconMac Hook Scripts"
        panel.message = "Select \"\(targetDir.lastPathComponent)\" (or \"Application Scripts\") and click \"Install Scripts\" to install BeaconMac's 7 helper scripts."
        panel.prompt = "Install Scripts"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true

        // Powerbox (NSOpenPanel) runs out-of-process and can navigate to Application Scripts
        // even when FileManager.fileExists returns false inside App Sandbox.
        panel.directoryURL = targetDir

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return (false, "Hook script installation cancelled.")
        }

        let didStartAccess = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL: URL
        if selectedURL.lastPathComponent == targetDir.lastPathComponent {
            destinationURL = selectedURL
        } else {
            destinationURL = selectedURL.appendingPathComponent(targetDir.lastPathComponent, isDirectory: true)
        }

        do {
            try writeAllScripts(to: destinationURL)
            return (true, "Installed all \(requiredScriptNames.count) hook scripts into \(destinationURL.path).")
        } catch {
            return (false, "Could not write scripts to \(destinationURL.path): \(error.localizedDescription)")
        }
    }

    public static func writeAllScripts(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, content) in allScripts {
            let dest = directory.appendingPathComponent(name)
            try content.write(to: dest, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        }
    }

    public static var terminalInstallOneLiner: String {
        "./swift-app/BeaconMac/Scripts/install-sandbox-scripts.sh \(bundleID)"
    }

    public static let allScripts: [String: String] = [
        "beacon-check-deps.sh": checkDepsScript,
        "beacon-deploy.sh": deployScript,
        "beacon-restart.sh": restartScript,
        "beacon-stop.sh": stopScript,
        "beacon-git-pull.sh": gitPullScript,
        "beacon-startup.sh": startupScript,
        "beacon-launchd.sh": launchdScript
    ]

    // MARK: - Embedded Script Bodies

    private static let checkDepsScript = #"""
#!/bin/bash
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
"""#

    private static let deployScript = #"""
#!/bin/bash
set -euo pipefail

REPO_URL="${1:-}"
BRANCH="${2:-main}"
WORKDIR="${3:-}"
PORT="${4:-5173}"
INSTALL_CMD="${5:-auto}"
BUILD_CMD="${6:-}"
START_CMD="${7:-}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

echo "[beacon-deploy] Checking required developer tools..."
for bin in git node; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[beacon-deploy] ERROR: Required tool '$bin' is not installed or not in PATH." >&2
    exit 12
  fi
done
echo "[beacon-deploy] Found git $(git --version | awk '{print $3}'), node $(node -v)"

if [ -z "$WORKDIR" ]; then
  echo "[beacon-deploy] ERROR: Local target folder is required." >&2
  exit 13
fi

if [ ! -d "$WORKDIR/.git" ]; then
  if [ -z "$REPO_URL" ]; then
    echo "[beacon-deploy] ERROR: No local .git repo at $WORKDIR and no remote repository URL provided." >&2
    exit 14
  fi
  echo "[beacon-deploy] Cloning $REPO_URL (branch: $BRANCH) into $WORKDIR..."
  mkdir -p "$(dirname "$WORKDIR")"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$WORKDIR"
else
  echo "[beacon-deploy] Fetching updates for branch '$BRANCH' in $WORKDIR..."
  cd "$WORKDIR"
  if [ -n "$REPO_URL" ]; then
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin -- "$REPO_URL"
    else
      git remote add origin -- "$REPO_URL"
    fi
  fi
  git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git checkout "$BRANCH" 2>/dev/null || git checkout -B "$BRANCH" "origin/$BRANCH"
    git pull --ff-only origin "$BRANCH"
  else
    git checkout -B "$BRANCH" "origin/$BRANCH"
  fi
fi

cd "$WORKDIR"
CURRENT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "[beacon-deploy] Repository ready at commit $CURRENT_SHA"

if [ -f "package.json" ]; then
  NEEDS_INSTALL=0
  if [ ! -d "node_modules" ]; then
    NEEDS_INSTALL=1
  elif [ "package.json" -nt "node_modules" ]; then
    NEEDS_INSTALL=1
  fi

  if [ "$INSTALL_CMD" != "skip" ] && [ "$NEEDS_INSTALL" -eq 1 -o "$INSTALL_CMD" != "auto" ]; then
    if [ "$INSTALL_CMD" = "auto" ] || [ -z "$INSTALL_CMD" ]; then
      if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
        echo "[beacon-deploy] Installing dependencies via pnpm install..."
        pnpm install --frozen-lockfile || pnpm install
      elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
        echo "[beacon-deploy] Installing dependencies via yarn install..."
        yarn install
      elif [ -f "bun.lock" ] || [ -f "bun.lockb" ]; then
        if command -v bun >/dev/null 2>&1; then
          echo "[beacon-deploy] Installing dependencies via bun install..."
          bun install
        else
          echo "[beacon-deploy] Installing dependencies via npm install..."
          npm install
        fi
      else
        echo "[beacon-deploy] Installing dependencies via npm install..."
        npm install
      fi
    else
      echo "[beacon-deploy] Running install command: $INSTALL_CMD"
      /bin/zsh -lc "$INSTALL_CMD"
    fi
  else
    echo "[beacon-deploy] Dependencies up to date (node_modules present)."
  fi
fi

if [ -n "$BUILD_CMD" ]; then
  echo "[beacon-deploy] Building application: $BUILD_CMD"
  /bin/zsh -lc "$BUILD_CMD"
fi

EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  echo "[beacon-deploy] Stopping previous process on port $PORT (PID $EXISTING_PID)..."
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi

LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -n "$START_CMD" ]; then
  echo "[beacon-deploy] Starting app on port $PORT: $START_CMD"
  PORT="$PORT" nohup /bin/zsh -lc "$START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  echo "[beacon-deploy] Starting Vite/Node dev server on port $PORT..."
  PORT="$PORT" nohup npm run dev -- --port "$PORT" </dev/null >>"$APP_LOG" 2>&1 &
fi

NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
sleep 1
if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "[beacon-deploy] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 15 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi
SUMMARY="[beacon-deploy] Deployed commit $CURRENT_SHA on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $SUMMARY" >> "$SERVER_LOG"
"""#

    private static let restartScript = #"""
#!/bin/bash
set -euo pipefail

WORKDIR="${1:-}"
PORT="${2:-3000}"
CUSTOM_CMD="${3:-}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
  echo "Target app working directory not found: $WORKDIR" >&2
  exit 1
fi

EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 1
fi

cd "$WORKDIR"
LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
mkdir -p "$LOG_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -n "$CUSTOM_CMD" ]; then
  PORT="$PORT" nohup /bin/zsh -lc "$CUSTOM_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  PORT="$PORT" nohup npm run dev -- --port "$PORT" </dev/null >>"$APP_LOG" 2>&1 &
fi
NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
sleep 1
if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "[beacon-restart] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 15 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi
SUMMARY="Restarted target local app in $WORKDIR on port $PORT (PID $NEW_PID, log: $APP_LOG)"
echo "$SUMMARY"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [beacon-restart] $SUMMARY" >> "$SERVER_LOG"
"""#

    private static let stopScript = #"""
#!/bin/bash
set -euo pipefail

PORT="${1:-}"
if [ -z "$PORT" ]; then
  echo "Port number required" >&2
  exit 1
fi

PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -z "$PIDS" ]; then
  echo "No process listening on port $PORT"
  exit 0
fi

kill -TERM $PIDS 2>/dev/null || true
echo "Sent SIGTERM to process(es) on port $PORT: $PIDS"
"""#

    private static let gitPullScript = #"""
#!/bin/bash
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
"""#

    private static let startupScript = #"""
#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LAUNCHD_MODE=0
if [ "${1:-}" = "--launchd" ]; then
  LAUNCHD_MODE=1
fi

BUNDLE_ID="${BEACONMAC_BUNDLE_ID:-com.beaconmac.app}"
PREVENT_SLEEP="${BEACONMAC_PREVENT_SLEEP:-1}"
CONFIG_PATH="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Beacon/config.json"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/beaconmac"
SERVER_LOG="$LOG_DIR/server.log"

mkdir -p "$LOG_DIR/logs"

log_line() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [beacon-startup] $1" | tee -a "$SERVER_LOG"
}

if [ ! -f "$CONFIG_PATH" ]; then
  CONFIG_PATH="$HOME/Library/Application Support/Beacon/config.json"
fi

if [ ! -f "$CONFIG_PATH" ]; then
  log_line "No config.json found at $CONFIG_PATH"
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  log_line "ERROR: Node.js is required to parse startup apps from config.json" >&2
  exit 1
fi

log_line "Starting BeaconMac launchd supervisor (bundle: $BUNDLE_ID, preventSleep: $PREVENT_SLEEP)"

node -e '
const fs = require("fs");
const { execFileSync } = require("child_process");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const scriptsDir = process.argv[2];
const apps = Array.isArray(cfg.managedApps) ? cfg.managedApps : [];
let started = 0;
for (const app of apps) {
  if (!app.runOnStartup) continue;
  started++;
  const deployScript = scriptsDir + "/beacon-deploy.sh";
  const restartScript = scriptsDir + "/beacon-restart.sh";
  const useDeploy = Boolean(cfg.startupSchedule?.autoDeployOnStartup && app.repoURL);
  const script = useDeploy ? deployScript : restartScript;
  const args = useDeploy
    ? [app.repoURL || "", app.branch || "main", app.localPath || "", String(app.port || 5173), app.installCommand || "auto", app.buildCommand || "", app.startCommand || ""]
    : [app.localPath || "", String(app.port || 5173), app.startCommand || ""];
  console.log("[beacon-startup] Launching", app.name, "via", script);
  try {
    execFileSync(script, args, { stdio: "inherit" });
  } catch (err) {
    console.error("[beacon-startup] Failed for", app.name, err.message);
  }
}
if (started === 0) {
  console.log("[beacon-startup] No apps currently marked runOnStartup=true.");
}
' "$CONFIG_PATH" "$SCRIPTS_DIR" 2>&1 | tee -a "$SERVER_LOG"

if [ "$LAUNCHD_MODE" -eq 1 ] && [ "$PREVENT_SLEEP" = "1" ] && command -v caffeinate >/dev/null 2>&1; then
  log_line "Holding macOS system sleep assertion via caffeinate -s (stop via launchctl unload)"
  exec /usr/bin/caffeinate -s
fi
"""#

    private static let launchdScript = #"""
#!/bin/bash
set -euo pipefail

ACTION="${1:-status}"
BUNDLE_ID="${2:-com.beaconmac.app}"
PREVENT_SLEEP="${3:-1}"

LABEL="${BUNDLE_ID}.supervisor"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$AGENTS_DIR/${LABEL}.plist"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
STARTUP_SCRIPT="$SCRIPTS_DIR/beacon-startup.sh"
LOG_DIR="$HOME/beaconmac"
SERVER_LOG="$LOG_DIR/server.log"

if [ "$ACTION" != "grep" ]; then
  mkdir -p "$AGENTS_DIR" "$LOG_DIR/logs"
fi

write_plist() {
  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${STARTUP_SCRIPT}</string>
        <string>--launchd</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>BEACONMAC_BUNDLE_ID</key>
        <string>${BUNDLE_ID}</string>
        <key>BEACONMAC_PREVENT_SLEEP</key>
        <string>${PREVENT_SLEEP}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${SERVER_LOG}</string>
    <key>StandardErrorPath</key>
    <string>${SERVER_LOG}</string>
</dict>
</plist>
EOF
}

case "$ACTION" in
  install)
    if [ ! -x "$STARTUP_SCRIPT" ]; then
      echo "[beacon-launchd] ERROR: Missing executable $STARTUP_SCRIPT." >&2
      exit 10
    fi
    write_plist
    echo "[beacon-launchd] Wrote LaunchAgent plist: $PLIST_PATH"
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    if launchctl load -w "$PLIST_PATH" 2>/dev/null; then
      echo "[beacon-launchd] Loaded $LABEL into launchd (RunAtLoad=true, preventSleep=$PREVENT_SLEEP)"
    else
      launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
      echo "[beacon-launchd] Bootstrapped $LABEL into launchd gui/$(id -u)"
    fi
    echo "LAUNCHD:INSTALLED:YES:$PLIST_PATH"
    echo "LAUNCHD:LOADED:YES:$LABEL"
    ;;

  stop)
    if [ -f "$PLIST_PATH" ]; then
      launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    fi
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    echo "[beacon-launchd] Unloaded launchd service $LABEL ($PLIST_PATH)"
    echo "LAUNCHD:INSTALLED:$([ -f "$PLIST_PATH" ] && echo YES || echo NO):$PLIST_PATH"
    echo "LAUNCHD:LOADED:NO:$LABEL"
    ;;

  status)
    if [ -f "$PLIST_PATH" ]; then
      echo "LAUNCHD:INSTALLED:YES:$PLIST_PATH"
    else
      echo "LAUNCHD:INSTALLED:NO:$PLIST_PATH"
    fi

    if launchctl list "$LABEL" >/dev/null 2>&1; then
      PID=$(launchctl list | awk -v lbl="$LABEL" '$3 == lbl {print $1}')
      echo "LAUNCHD:LOADED:YES:${PID:-running}"
    else
      echo "LAUNCHD:LOADED:NO:unloaded"
    fi

    if pgrep -f "caffeinate -s" >/dev/null 2>&1; then
      echo "LAUNCHD:CAFFEINATE:YES:active"
    else
      echo "LAUNCHD:CAFFEINATE:NO:inactive"
    fi
    echo "LAUNCHD:LOG:OK:$SERVER_LOG"
    ;;

  grep)
    PATTERN="${2:-}"
    MODE="${3:-E}"
    CASE_FLAG="${4:-i}"
    CTX_LINES="${5:-0}"
    MAX_MATCHES="${6:-500}"
    if [ ! -f "$SERVER_LOG" ]; then
      echo "Log file not found at $SERVER_LOG. Start the launchd supervisor or deploy an app to generate server logs." >&2
      exit 3
    fi
    GREP_ARGS=(-n -m "$MAX_MATCHES")
    if [ "$MODE" = "F" ]; then
      GREP_ARGS+=(-F)
    else
      GREP_ARGS+=(-E)
    fi
    if [ "$CASE_FLAG" = "i" ]; then
      GREP_ARGS+=(-i)
    fi
    if [ "$CTX_LINES" = "2" ]; then
      GREP_ARGS+=(-C 2)
    fi
    set +e
    /usr/bin/grep "${GREP_ARGS[@]}" -- "$PATTERN" "$SERVER_LOG"
    RC=$?
    set -e
    if [ "$RC" -eq 1 ]; then
      exit 0
    fi
    exit "$RC"
    ;;

  *)
    echo "[beacon-launchd] Unknown action: $ACTION (expected install|stop|status|grep)" >&2
    exit 2
    ;;
esac
"""#
}
