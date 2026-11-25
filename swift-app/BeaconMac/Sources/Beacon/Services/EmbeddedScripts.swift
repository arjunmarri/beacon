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
        "beacon-launchd.sh",
        "beacon-node-server.sh",
        "beacon-node-host.mjs",
        "beacon-nginx.sh",
        "beacon-cloudflared.sh"
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
        panel.message = "Select \"\(targetDir.lastPathComponent)\" (or \"Application Scripts\") and click \"Install Scripts\" to install BeaconMac's \(requiredScriptNames.count) helper scripts."
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
        "beacon-launchd.sh": launchdScript,
        "beacon-node-server.sh": nodeServerScript,
        "beacon-node-host.mjs": nodeHostScript,
        "beacon-nginx.sh": nginxScript,
        "beacon-cloudflared.sh": cloudflaredScript
    ]

    // MARK: - Embedded Script Bodies

    private static let checkDepsScript = #"""
#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-check-deps.sh
# Audits required macOS runtime tools and project dependencies, OR when invoked with
# `--install [workdir] [tools_csv] [strategy]`, performs a silent, non-interactive
# installation of missing runtimes (node, bun, pnpm, yarn, python3, uv, go, git)
# via Homebrew or verified direct official downloads, plus auto-detected project dependencies.
set -euo pipefail

export NONINTERACTIVE=1
export CI=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export PNPM_HOME="$HOME/Library/pnpm"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$HOME/.cargo/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

INSTALL_STRATEGY="auto"

can_use_brew() {
  [ "$INSTALL_STRATEGY" != "direct" ] && command -v brew >/dev/null 2>&1
}

can_use_direct() {
  [ "$INSTALL_STRATEGY" != "homebrew" ]
}

install_node_direct() {
  local arch
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64)        arch="x64" ;;
    *)
      echo "[beacon-deps] ERROR: Unsupported CPU architecture $(uname -m) for direct Node.js download." >&2
      return 1
      ;;
  esac

  echo "[beacon-deps] Downloading official Node.js LTS binary for darwin-${arch}..."
  local version
  version=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c '
import json, sys
for entry in json.load(sys.stdin):
    if entry.get("lts"):
        print(entry["version"])
        break
')
  if [ -z "$version" ]; then
    echo "[beacon-deps] ERROR: Could not resolve latest Node.js LTS version from nodejs.org." >&2
    return 1
  fi

  local tarball="node-${version}-darwin-${arch}.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' RETURN

  curl -fsSL "https://nodejs.org/dist/${version}/${tarball}" -o "${tmp_dir}/${tarball}"
  curl -fsSL "https://nodejs.org/dist/${version}/SHASUMS256.txt" -o "${tmp_dir}/SHASUMS256.txt"

  local expected_sha actual_sha
  expected_sha=$(awk -v f="$tarball" '$2 == f {print $1}' "${tmp_dir}/SHASUMS256.txt" | head -n 1)
  actual_sha=$(shasum -a 256 "${tmp_dir}/${tarball}" | awk '{print $1}')
  if [ -z "$expected_sha" ] || [ "$expected_sha" != "$actual_sha" ]; then
    echo "[beacon-deps] ERROR: Node.js SHA-256 verification failed for ${tarball}." >&2
    return 1
  fi

  mkdir -p "$HOME/.local/node" "$HOME/.local/bin"
  rm -rf "$HOME/.local/node"/*
  tar -xzf "${tmp_dir}/${tarball}" --strip-components=1 -C "$HOME/.local/node"
  for bin in node npm npx corepack; do
    if [ -x "$HOME/.local/node/bin/$bin" ]; then
      ln -sf "$HOME/.local/node/bin/$bin" "$HOME/.local/bin/$bin"
    fi
  done
  export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$PATH"
  echo "[beacon-deps] Installed Node.js $(node -v) directly into $HOME/.local/node (SHA-256 verified)."
}

install_runtime_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "[beacon-deps] $tool is already installed ($("$tool" --version 2>/dev/null | head -n 1 || echo "ready"))."
    return 0
  fi

  echo "[beacon-deps] Silently installing missing tool '$tool' (strategy: $INSTALL_STRATEGY)..."
  case "$tool" in
    node|npm)
      if can_use_brew; then
        brew install --quiet node
      elif can_use_direct; then
        install_node_direct
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    pnpm)
      if can_use_brew; then
        brew install --quiet pnpm
      elif can_use_direct; then
        if command -v corepack >/dev/null 2>&1; then
          corepack enable >/dev/null 2>&1 || true
          corepack prepare pnpm@latest --activate
        else
          echo "[beacon-deps] Downloading standalone pnpm via official installer..."
          curl -fsSL https://get.pnpm.io/install.sh | SHELL=/bin/zsh sh - >/dev/null
          export PATH="$HOME/Library/pnpm:$HOME/.local/share/pnpm:$PATH"
        fi
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    yarn)
      if can_use_brew; then
        brew install --quiet yarn
      elif can_use_direct; then
        if ! command -v node >/dev/null 2>&1; then
          install_node_direct
        fi
        if command -v corepack >/dev/null 2>&1; then
          corepack enable >/dev/null 2>&1 || true
          corepack prepare yarn@stable --activate
        elif command -v npm >/dev/null 2>&1; then
          npm install -g --silent yarn
        else
          echo "[beacon-deps] ERROR: Unable to install yarn without Node.js or Homebrew." >&2
          return 1
        fi
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    bun)
      if can_use_brew; then
        brew install --quiet oven-sh/tap/bun
      elif can_use_direct; then
        echo "[beacon-deps] Downloading Bun via official installer (https://bun.sh/install)..."
        curl -fsSL https://bun.sh/install | bash >/dev/null
        export PATH="$HOME/.bun/bin:$PATH"
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    python3)
      if can_use_brew; then
        brew install --quiet python
      else
        echo "[beacon-deps] ERROR: Homebrew is required for silent python3 installation (install Homebrew or Xcode Command Line Tools)." >&2
        return 1
      fi
      ;;
    uv)
      if can_use_brew; then
        brew install --quiet uv
      elif can_use_direct; then
        echo "[beacon-deps] Downloading uv via official installer..."
        curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
        export PATH="$HOME/.local/bin:$PATH"
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    go)
      if can_use_brew; then
        brew install --quiet go
      else
        echo "[beacon-deps] ERROR: Homebrew is required for silent Go installation." >&2
        return 1
      fi
      ;;
    cargo|rust)
      if can_use_brew; then
        brew install --quiet rust
      elif can_use_direct; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null
        export PATH="$HOME/.cargo/bin:$PATH"
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    git)
      if can_use_brew; then
        brew install --quiet git
      else
        xcode-select --install >/dev/null 2>&1 || true
      fi
      ;;
    nginx)
      if can_use_brew; then
        brew install --quiet nginx
      else
        echo "[beacon-deps] ERROR: Homebrew is required for silent NGINX installation on macOS. Install Homebrew from https://brew.sh first." >&2
        return 1
      fi
      ;;
    cloudflared)
      if can_use_brew; then
        brew install --quiet cloudflared
      elif can_use_direct; then
        local cf_arch
        case "$(uname -m)" in
          arm64|aarch64) cf_arch="arm64" ;;
          x86_64)        cf_arch="amd64" ;;
          *)
            echo "[beacon-deps] ERROR: Unsupported CPU architecture $(uname -m) for direct cloudflared download." >&2
            return 1
            ;;
        esac
        local cf_tmp
        cf_tmp=$(mktemp -d)
        echo "[beacon-deps] Downloading official Cloudflare Tunnel binary (cloudflared-darwin-${cf_arch}.tgz)..."
        if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-${cf_arch}.tgz" -o "${cf_tmp}/cloudflared.tgz"; then
          mkdir -p "$HOME/.local/bin"
          tar -xzf "${cf_tmp}/cloudflared.tgz" -C "$cf_tmp"
          if [ -f "${cf_tmp}/cloudflared" ]; then
            mv -f "${cf_tmp}/cloudflared" "$HOME/.local/bin/cloudflared"
            chmod +x "$HOME/.local/bin/cloudflared"
            export PATH="$HOME/.local/bin:$PATH"
            echo "[beacon-deps] Installed cloudflared directly into $HOME/.local/bin/cloudflared."
          else
            rm -rf "$cf_tmp"
            echo "[beacon-deps] ERROR: Downloaded archive did not contain cloudflared binary." >&2
            return 1
          fi
        else
          rm -rf "$cf_tmp"
          echo "[beacon-deps] ERROR: Failed to download cloudflared from GitHub releases." >&2
          return 1
        fi
        rm -rf "$cf_tmp"
      else
        echo "[beacon-deps] ERROR: Homebrew is not installed and direct download is disabled." >&2
        return 1
      fi
      ;;
    *)
      echo "[beacon-deps] Skipping unknown runtime '$tool'."
      ;;
  esac

  if command -v "$tool" >/dev/null 2>&1; then
    echo "[beacon-deps] Ready: $tool ($("$tool" --version 2>/dev/null | head -n 1 || echo "installed"))"
  fi
}

install_js_project_dir() {
  local dir="$1"
  cd "$dir"

  local pm="npm"
  if [ -f "bun.lock" ] || [ -f "bun.lockb" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"bun@' package.json 2>/dev/null; then
    pm="bun"
  elif [ -f "pnpm-lock.yaml" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@' package.json 2>/dev/null; then
    pm="pnpm"
  elif [ -f "yarn.lock" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"yarn@' package.json 2>/dev/null; then
    pm="yarn"
  fi

  if [ "$pm" != "bun" ]; then
    install_runtime_tool node
  fi
  if [ "$pm" != "npm" ]; then
    install_runtime_tool "$pm"
  fi

  echo "[beacon-deps] Installing JavaScript dependencies in $dir via $pm install..."
  case "$pm" in
    bun)  bun install ;;
    pnpm) pnpm install --frozen-lockfile || pnpm install ;;
    yarn) yarn install ;;
    *)    npm install ;;
  esac
}

if [ "${1:-}" = "--install" ]; then
  WORKDIR="${2:-}"
  TOOLS_CSV="${3:-}"
  RAW_STRATEGY="${4:-auto}"
  case "$RAW_STRATEGY" in
    auto|homebrew|direct) INSTALL_STRATEGY="$RAW_STRATEGY" ;;
    *) INSTALL_STRATEGY="auto" ;;
  esac

  if [ -n "$TOOLS_CSV" ] && [ "$TOOLS_CSV" != "auto" ]; then
    IFS=',' read -ra REQ_TOOLS <<< "$TOOLS_CSV"
    for t in "${REQ_TOOLS[@]}"; do
      t=$(echo "$t" | tr -d '[:space:]')
      [ -n "$t" ] && install_runtime_tool "$t"
    done
  fi

  if [ -n "$WORKDIR" ]; then
    if [ ! -d "$WORKDIR" ]; then
      echo "[beacon-deps] ERROR: Project directory not found: $WORKDIR" >&2
      exit 2
    fi

    FOUND_MANIFEST=0

    if [ -f "$WORKDIR/package.json" ]; then
      FOUND_MANIFEST=1
      install_js_project_dir "$WORKDIR"
    else
      SUB_PKGS=$(find "$WORKDIR" -maxdepth 2 -mindepth 2 -name "package.json" -not -path "*/node_modules/*" 2>/dev/null || true)
      if [ -n "$SUB_PKGS" ]; then
        FOUND_MANIFEST=1
        while IFS= read -r pkg_file; do
          [ -n "$pkg_file" ] && install_js_project_dir "$(dirname "$pkg_file")"
        done <<< "$SUB_PKGS"
      fi
    fi

    if [ -f "$WORKDIR/uv.lock" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool python3
      install_runtime_tool uv
      echo "[beacon-deps] Syncing Python dependencies via uv sync..."
      (cd "$WORKDIR" && uv sync)
    elif [ -f "$WORKDIR/requirements.txt" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool python3
      echo "[beacon-deps] Installing Python dependencies from requirements.txt..."
      if [ -x "$WORKDIR/.venv/bin/pip" ]; then
        "$WORKDIR/.venv/bin/pip" install -q -r "$WORKDIR/requirements.txt"
      else
        (cd "$WORKDIR" && python3 -m pip install -q --user -r requirements.txt)
      fi
    elif [ -f "$WORKDIR/pyproject.toml" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool python3
      echo "[beacon-deps] Installing Python project from pyproject.toml..."
      if [ -x "$WORKDIR/.venv/bin/pip" ]; then
        "$WORKDIR/.venv/bin/pip" install -q -e "$WORKDIR"
      else
        (cd "$WORKDIR" && python3 -m pip install -q --user -e .)
      fi
    elif [ -f "$WORKDIR/Pipfile" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool python3
      if command -v pipenv >/dev/null 2>&1; then
        echo "[beacon-deps] Installing Python dependencies via pipenv install..."
        (cd "$WORKDIR" && pipenv install)
      fi
    fi

    if [ -f "$WORKDIR/go.mod" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool go
      echo "[beacon-deps] Downloading Go modules via go mod download..."
      (cd "$WORKDIR" && go mod download)
    fi

    if [ -f "$WORKDIR/Cargo.toml" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool cargo
      echo "[beacon-deps] Fetching Rust crates via cargo fetch..."
      (cd "$WORKDIR" && cargo fetch)
    fi

    if [ -f "$WORKDIR/Gemfile" ] && command -v bundle >/dev/null 2>&1; then
      FOUND_MANIFEST=1
      echo "[beacon-deps] Installing Ruby gems via bundle install..."
      (cd "$WORKDIR" && bundle install)
    fi

    if [ "$FOUND_MANIFEST" -eq 0 ]; then
      echo "[beacon-deps] Selected runtime tools are ready (no package.json or manifest found in $WORKDIR)."
    else
      echo "[beacon-deps] All required tools and project dependencies are installed."
    fi
  else
    echo "[beacon-deps] Silent tool installation completed."
  fi
  exit 0
fi

WORKDIR="${1:-}"

check_bin() {
  local name="$1"
  local mode="${2:-required}"
  if command -v "$name" >/dev/null 2>&1; then
    local ver
    if [ "$name" = "nginx" ]; then
      ver=$("$name" -v 2>&1 | sed 's/nginx version: //' | head -n 1 || echo "installed")
    else
      ver=$("$name" --version 2>/dev/null | head -n 1 || echo "installed")
    fi
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
check_bin python3 optional
check_bin uv optional
check_bin go optional
check_bin nginx optional
check_bin cloudflared optional

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
        echo "APP:DEPS:MISSING:node_modules not found in root (click Install Dependencies)"
      fi
    fi
  elif [ -f "$WORKDIR/requirements.txt" ] || [ -f "$WORKDIR/pyproject.toml" ]; then
    echo "APP:DEPS:OK:Python manifest detected (click Install Dependencies to sync)"
  elif [ -f "$WORKDIR/go.mod" ]; then
    echo "APP:DEPS:OK:go.mod detected"
  elif [ -f "$WORKDIR/Cargo.toml" ]; then
    echo "APP:DEPS:OK:Cargo.toml detected"
  else
    SUB_NM=$(find "$WORKDIR" -maxdepth 2 -mindepth 2 -type d -name "node_modules" 2>/dev/null | head -n 1 || true)
    if [ -n "$SUB_NM" ]; then
      PKG_COUNT=$(find "$SUB_NM" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
      SUB_NAME=$(basename "$(dirname "$SUB_NM")")
      echo "APP:DEPS:OK:$PKG_COUNT packages installed ($SUB_NAME/node_modules)"
    else
      echo "APP:DEPS:NONE:no package.json or manifest found"
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

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
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

detect_pm() {
  if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
    echo "pnpm"
  elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    echo "yarn"
  elif { [ -f "bun.lock" ] || [ -f "bun.lockb" ]; } && command -v bun >/dev/null 2>&1; then
    echo "bun"
  else
    echo "npm"
  fi
}

pkg_has_script() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 && node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, process.argv[1]) ? 0 : 1);
    } catch { process.exit(1); }
  ' "$1" 2>/dev/null
}

pkg_script_value() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const val = pkg.scripts && pkg.scripts[process.argv[1]];
      if (typeof val === "string") process.stdout.write(val);
    } catch {}
  ' "$1" 2>/dev/null || true
}

pkg_script_names() {
  if [ ! -f "package.json" ]; then
    echo "none (no package.json)"
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const keys = pkg.scripts && typeof pkg.scripts === "object" ? Object.keys(pkg.scripts) : [];
      process.stdout.write(keys.length ? keys.join(", ") : "none");
    } catch { process.stdout.write("unreadable"); }
  ' 2>/dev/null || echo "unknown"
}

pkg_main_entry() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      if (typeof pkg.main === "string" && pkg.main.trim()) process.stdout.write(pkg.main.trim());
    } catch {}
  ' 2>/dev/null || true
}

resolve_auto_start_cmd() {
  local pm="$1"
  local port="$2"
  if [ -f "package.json" ]; then
    if pkg_has_script dev; then
      local dev_val
      dev_val=$(pkg_script_value dev)
      if echo "$dev_val" | grep -qiE '(vite|astro|nuxt|svelte-kit)'; then
        echo "$pm run dev -- --port $port"
      elif echo "$dev_val" | grep -qiE '(^|[[:space:]])next([[:space:]]|$)'; then
        echo "$pm run dev -- -p $port"
      else
        echo "$pm run dev"
      fi
      return 0
    elif pkg_has_script start; then
      echo "$pm start"
      return 0
    elif pkg_has_script serve; then
      echo "$pm run serve"
      return 0
    elif pkg_has_script preview; then
      local prev_val
      prev_val=$(pkg_script_value preview)
      if echo "$prev_val" | grep -qi 'vite'; then
        echo "$pm run preview -- --port $port"
      else
        echo "$pm run preview"
      fi
      return 0
    fi
    local main_entry
    main_entry=$(pkg_main_entry)
    if [ -n "$main_entry" ] && [ -f "$main_entry" ]; then
      echo "node \"$main_entry\""
      return 0
    fi
  fi
  for candidate in server.js index.js app.js main.js; do
    if [ -f "$candidate" ]; then
      echo "node $candidate"
      return 0
    fi
  done
  return 1
}

PM=$(detect_pm)

if [ -f "package.json" ]; then
  NEEDS_INSTALL=0
  if [ ! -d "node_modules" ]; then
    NEEDS_INSTALL=1
  elif [ "package.json" -nt "node_modules" ]; then
    NEEDS_INSTALL=1
  fi

  if [ "$INSTALL_CMD" != "skip" ] && [ "$NEEDS_INSTALL" -eq 1 -o "$INSTALL_CMD" != "auto" ]; then
    if [ "$INSTALL_CMD" = "auto" ] || [ -z "$INSTALL_CMD" ]; then
      case "$PM" in
        pnpm)
          echo "[beacon-deploy] Installing dependencies via pnpm install..."
          pnpm install --frozen-lockfile || pnpm install
          ;;
        yarn)
          echo "[beacon-deploy] Installing dependencies via yarn install..."
          yarn install
          ;;
        bun)
          echo "[beacon-deploy] Installing dependencies via bun install..."
          bun install
          ;;
        *)
          echo "[beacon-deploy] Installing dependencies via npm install..."
          npm install
          ;;
      esac
    else
      echo "[beacon-deploy] Running install command: $INSTALL_CMD"
      /bin/bash -c "$INSTALL_CMD"
    fi
  else
    echo "[beacon-deploy] Dependencies up to date (node_modules present)."
  fi
fi

BUILD_CMD_TRIMMED=$(printf '%s' "$BUILD_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -n "$BUILD_CMD_TRIMMED" ] && [ "$BUILD_CMD_TRIMMED" != "skip" ]; then
  if [ "$BUILD_CMD_TRIMMED" = "auto" ]; then
    if pkg_has_script build; then
      echo "[beacon-deploy] Auto-detected \"build\" script — running: $PM run build"
      "$PM" run build
    else
      echo "[beacon-deploy] No \"build\" script in package.json (available: $(pkg_script_names)) — skipping build step."
    fi
  elif printf '%s' "$BUILD_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?build([[:space:]]|$)' \
       && [ -f "package.json" ] && ! pkg_has_script build; then
    echo "[beacon-deploy] WARNING: \"$BUILD_CMD_TRIMMED\" requested, but package.json has no \"build\" script (available: $(pkg_script_names)). Skipping build step."
  else
    echo "[beacon-deploy] Building application: $BUILD_CMD_TRIMMED"
    /bin/bash -c "$BUILD_CMD_TRIMMED"
  fi
fi

LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
PID_DIR="$HOME/beaconmac/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
PID_FILE="$PID_DIR/${LOG_SLUG:-app}-${PORT}.pid"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[beacon-deploy] Stopping previous tracked instance (PID $OLD_PID)..."
    kill -TERM -- "-$OLD_PID" 2>/dev/null || true
    pkill -TERM -P "$OLD_PID" 2>/dev/null || true
    kill -TERM "$OLD_PID" 2>/dev/null || true
    sleep 0.6
    if kill -0 "$OLD_PID" 2>/dev/null; then
      kill -KILL -- "-$OLD_PID" 2>/dev/null || true
      kill -KILL "$OLD_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
fi

EXISTING_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
  echo "[beacon-deploy] Stopping previous process on port $PORT (PID $EXISTING_PID)..."
  kill -TERM $EXISTING_PID 2>/dev/null || true
  sleep 1
fi

START_CMD_TRIMMED=$(printf '%s' "$START_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
FINAL_START_CMD=""

if [ -z "$START_CMD_TRIMMED" ] || [ "$START_CMD_TRIMMED" = "auto" ]; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-deploy] ERROR: Could not auto-detect a start command in $WORKDIR (package.json scripts: $(pkg_script_names)). Open Edit App in BeaconMac and set a custom Start Command." >&2
    exit 16
  fi
  echo "[beacon-deploy] Auto-detected start command on port $PORT: $FINAL_START_CMD"
elif printf '%s' "$START_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+dev([[:space:]]|$)' \
     && [ -f "package.json" ] && ! pkg_has_script dev; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-deploy] ERROR: package.json has no \"dev\" script (available: $(pkg_script_names)). Open Edit App in BeaconMac and set a valid Start Command." >&2
    exit 16
  fi
  echo "[beacon-deploy] WARNING: package.json has no \"dev\" script (available: $(pkg_script_names)) — falling back to: $FINAL_START_CMD"
else
  FINAL_START_CMD="$START_CMD_TRIMMED"
  echo "[beacon-deploy] Starting app on port $PORT: $FINAL_START_CMD"
fi

echo "=== [beacon-deploy] $(date -u +"%Y-%m-%dT%H:%M:%SZ") starting (PORT=$PORT): $FINAL_START_CMD ===" >> "$APP_LOG"
if [ -x /usr/bin/perl ]; then
  PORT="$PORT" nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  PORT="$PORT" nohup /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
fi

NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"
disown "$NEW_PID" 2>/dev/null || true

EXITED_EARLY=0
for _ in 1 2 3 4 5 6 7 8; do
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    EXITED_EARLY=1
    break
  fi
  sleep 0.25
done

if [ "$EXITED_EARLY" -eq 1 ]; then
  rm -f "$PID_FILE"
  sleep 0.25
  echo "[beacon-deploy] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 25 "$APP_LOG" 2>/dev/null >&2 || true
  exit 15
fi

BOUND_PORTS=$(lsof -Pan -p "$NEW_PID" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -u | tr '\n' ' ' || true)
CHILD_PIDS=$(pgrep -P "$NEW_PID" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
if [ -n "$CHILD_PIDS" ]; then
  CHILD_PORTS=$(lsof -Pan -p "$CHILD_PIDS" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -u | tr '\n' ' ' || true)
  BOUND_PORTS="$BOUND_PORTS $CHILD_PORTS"
fi
BOUND_PORTS=$(echo "$BOUND_PORTS" | xargs 2>/dev/null || true)
if [ -n "$BOUND_PORTS" ] && ! echo " $BOUND_PORTS " | grep -q " $PORT "; then
  echo "[beacon-deploy] NOTE: App is listening on port(s) [$BOUND_PORTS] instead of configured port $PORT. Check if your server hardcodes its port or update Monitor URL in Edit App."
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

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
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
  kill -TERM $EXISTING_PID 2>/dev/null || true
  sleep 1
fi

cd "$WORKDIR"

detect_pm() {
  if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
    echo "pnpm"
  elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    echo "yarn"
  elif { [ -f "bun.lock" ] || [ -f "bun.lockb" ]; } && command -v bun >/dev/null 2>&1; then
    echo "bun"
  else
    echo "npm"
  fi
}

pkg_has_script() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 && node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, process.argv[1]) ? 0 : 1);
    } catch { process.exit(1); }
  ' "$1" 2>/dev/null
}

pkg_script_value() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const val = pkg.scripts && pkg.scripts[process.argv[1]];
      if (typeof val === "string") process.stdout.write(val);
    } catch {}
  ' "$1" 2>/dev/null || true
}

pkg_script_names() {
  if [ ! -f "package.json" ]; then
    echo "none (no package.json)"
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const keys = pkg.scripts && typeof pkg.scripts === "object" ? Object.keys(pkg.scripts) : [];
      process.stdout.write(keys.length ? keys.join(", ") : "none");
    } catch { process.stdout.write("unreadable"); }
  ' 2>/dev/null || echo "unknown"
}

pkg_main_entry() {
  [ -f "package.json" ] && command -v node >/dev/null 2>&1 || return 0
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      if (typeof pkg.main === "string" && pkg.main.trim()) process.stdout.write(pkg.main.trim());
    } catch {}
  ' 2>/dev/null || true
}

resolve_auto_start_cmd() {
  local pm="$1"
  local port="$2"
  if [ -f "package.json" ]; then
    if pkg_has_script dev; then
      local dev_val
      dev_val=$(pkg_script_value dev)
      if echo "$dev_val" | grep -qiE '(vite|astro|nuxt|svelte-kit)'; then
        echo "$pm run dev -- --port $port"
      elif echo "$dev_val" | grep -qiE '(^|[[:space:]])next([[:space:]]|$)'; then
        echo "$pm run dev -- -p $port"
      else
        echo "$pm run dev"
      fi
      return 0
    elif pkg_has_script start; then
      echo "$pm start"
      return 0
    elif pkg_has_script serve; then
      echo "$pm run serve"
      return 0
    elif pkg_has_script preview; then
      local prev_val
      prev_val=$(pkg_script_value preview)
      if echo "$prev_val" | grep -qi 'vite'; then
        echo "$pm run preview -- --port $port"
      else
        echo "$pm run preview"
      fi
      return 0
    fi
    local main_entry
    main_entry=$(pkg_main_entry)
    if [ -n "$main_entry" ] && [ -f "$main_entry" ]; then
      echo "node \"$main_entry\""
      return 0
    fi
  fi
  for candidate in server.js index.js app.js main.js; do
    if [ -f "$candidate" ]; then
      echo "node $candidate"
      return 0
    fi
  done
  return 1
}

LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
LOG_DIR="$HOME/beaconmac/logs"
PID_DIR="$HOME/beaconmac/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"
APP_LOG="$LOG_DIR/${LOG_SLUG:-app}-${PORT}.log"
PID_FILE="$PID_DIR/${LOG_SLUG:-app}-${PORT}.pid"
SERVER_LOG="$HOME/beaconmac/server.log"

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill -TERM -- "-$OLD_PID" 2>/dev/null || true
    pkill -TERM -P "$OLD_PID" 2>/dev/null || true
    kill -TERM "$OLD_PID" 2>/dev/null || true
    sleep 0.6
    if kill -0 "$OLD_PID" 2>/dev/null; then
      kill -KILL -- "-$OLD_PID" 2>/dev/null || true
      kill -KILL "$OLD_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
fi

PM=$(detect_pm)
CUSTOM_CMD_TRIMMED=$(printf '%s' "$CUSTOM_CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
FINAL_START_CMD=""

if [ -z "$CUSTOM_CMD_TRIMMED" ] || [ "$CUSTOM_CMD_TRIMMED" = "auto" ]; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-restart] ERROR: Could not auto-detect a start command in $WORKDIR (package.json scripts: $(pkg_script_names)). Open Edit App in BeaconMac and set a custom Start Command." >&2
    exit 16
  fi
  echo "[beacon-restart] Auto-detected start command on port $PORT: $FINAL_START_CMD"
elif printf '%s' "$CUSTOM_CMD_TRIMMED" | grep -qE '^(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+dev([[:space:]]|$)' \
     && [ -f "package.json" ] && ! pkg_has_script dev; then
  FINAL_START_CMD=$(resolve_auto_start_cmd "$PM" "$PORT" || true)
  if [ -z "$FINAL_START_CMD" ]; then
    echo "[beacon-restart] ERROR: package.json has no \"dev\" script (available: $(pkg_script_names)). Open Edit App in BeaconMac and set a valid Start Command." >&2
    exit 16
  fi
  echo "[beacon-restart] WARNING: package.json has no \"dev\" script (available: $(pkg_script_names)) — falling back to: $FINAL_START_CMD"
else
  FINAL_START_CMD="$CUSTOM_CMD_TRIMMED"
fi

echo "=== [beacon-restart] $(date -u +"%Y-%m-%dT%H:%M:%SZ") starting (PORT=$PORT): $FINAL_START_CMD ===" >> "$APP_LOG"
if [ -x /usr/bin/perl ]; then
  PORT="$PORT" nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
else
  PORT="$PORT" nohup /bin/bash -c "$FINAL_START_CMD" </dev/null >>"$APP_LOG" 2>&1 &
fi

NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"
disown "$NEW_PID" 2>/dev/null || true

EXITED_EARLY=0
for _ in 1 2 3 4 5 6 7 8; do
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    EXITED_EARLY=1
    break
  fi
  sleep 0.25
done

if [ "$EXITED_EARLY" -eq 1 ]; then
  rm -f "$PID_FILE"
  sleep 0.25
  echo "[beacon-restart] ERROR: Process exited immediately on port $PORT. Recent output from $APP_LOG:" >&2
  tail -n 25 "$APP_LOG" 2>/dev/null >&2 || true
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
WORKDIR="${2:-}"

if [ -z "$PORT" ]; then
  echo "Port number required" >&2
  exit 1
fi

PID_DIR="$HOME/beaconmac/pids"
STOPPED_ANY=0

kill_tree_term() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  pkill -TERM -P "$pid" 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
}

kill_tree_kill() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -KILL -- "-$pid" 2>/dev/null || true
  pkill -KILL -P "$pid" 2>/dev/null || true
  kill -KILL "$pid" 2>/dev/null || true
}

TRACKED_PIDS=()
if [ -d "$PID_DIR" ]; then
  if [ -n "$WORKDIR" ]; then
    LOG_SLUG=$(basename "$WORKDIR" | tr -cd '[:alnum:]-_')
    CAND_FILE="$PID_DIR/${LOG_SLUG:-app}-${PORT}.pid"
    if [ -f "$CAND_FILE" ]; then
      TPID=$(cat "$CAND_FILE" 2>/dev/null || true)
      if [ -n "$TPID" ]; then
        TRACKED_PIDS+=("$TPID")
      fi
      rm -f "$CAND_FILE"
    fi
  fi
  for pfile in "$PID_DIR"/*-"${PORT}.pid"; do
    [ -f "$pfile" ] || continue
    TPID=$(cat "$pfile" 2>/dev/null || true)
    if [ -n "$TPID" ]; then
      TRACKED_PIDS+=("$TPID")
    fi
    rm -f "$pfile"
  done
fi

for pid in "${TRACKED_PIDS[@]:-}"; do
  [ -n "$pid" ] || continue
  if kill -0 "$pid" 2>/dev/null; then
    kill_tree_term "$pid"
    STOPPED_ANY=1
  fi
done

PORT_PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$PORT_PIDS" ]; then
  for pid in $PORT_PIDS; do
    PPID_VAL=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    PGID_VAL=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    kill_tree_term "$pid"
    if [ -n "$PPID_VAL" ] && [ "$PPID_VAL" -gt 1 ] 2>/dev/null; then
      PCOMM=$(ps -o command= -p "$PPID_VAL" 2>/dev/null || true)
      if echo "$PCOMM" | grep -qiE '(bun|npm|pnpm|yarn|tsx|nodemon|vite|next|node)'; then
        kill_tree_term "$PPID_VAL"
      fi
    fi
    if [ -n "$PGID_VAL" ] && [ "$PGID_VAL" -gt 1 ] 2>/dev/null; then
      MY_PGID=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)
      if [ "$PGID_VAL" != "$MY_PGID" ]; then
        kill -TERM -- "-$PGID_VAL" 2>/dev/null || true
      fi
    fi
    STOPPED_ANY=1
  done
fi

if [ "$STOPPED_ANY" -eq 1 ]; then
  for _ in 1 2 3 4 5 6 7 8; do
    STILL_PORT=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    STILL_TRACKED=""
    for pid in "${TRACKED_PIDS[@]:-}"; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        STILL_TRACKED="$STILL_TRACKED $pid"
      fi
    done
    if [ -z "$STILL_PORT" ] && [ -z "$STILL_TRACKED" ]; then
      break
    fi
    sleep 0.25
  done

  for pid in "${TRACKED_PIDS[@]:-}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill_tree_kill "$pid"
    fi
  done

  REMAINING=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$REMAINING" ]; then
    for pid in $REMAINING; do
      kill_tree_kill "$pid"
    done
  fi
  echo "Stopped process(es) on port $PORT"
else
  echo "No process listening on port $PORT"
fi
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

    private static let nodeServerScript = #"""
#!/bin/bash
set -euo pipefail

ACTION="${1:-status}"
PORT="${2:-4173}"
REGISTRY="${3:-$HOME/Library/Application Support/Beacon/builtin-server-apps.json}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.local/node/bin:$HOME/Library/pnpm:$HOME/.local/share/pnpm:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_SCRIPT="$SCRIPTS_DIR/beacon-node-host.mjs"
LOG_DIR="$HOME/beaconmac"
mkdir -p "$LOG_DIR/logs"
HOST_LOG="$LOG_DIR/logs/builtin-node-host.log"
PID_FILE="$LOG_DIR/builtin-node-host.pid"

stop_host() {
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill -TERM "$OLD_PID" 2>/dev/null || true
      sleep 0.5
    fi
    rm -f "$PID_FILE"
  fi
  LISTENER_PID=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$LISTENER_PID" ]; then
    CMDLINE=$(ps -p "$LISTENER_PID" -o command= 2>/dev/null || true)
    if echo "$CMDLINE" | grep -q "beacon-node-host.mjs"; then
      kill -TERM "$LISTENER_PID" 2>/dev/null || true
      sleep 0.5
    fi
  fi
}

case "$ACTION" in
  start|restart)
    if ! command -v node >/dev/null 2>&1; then
      echo "[beacon-node-server] ERROR: Node.js is not installed. Click 'Install Dependencies' in BeaconMac to install Node.js silently." >&2
      exit 12
    fi
    if [ ! -f "$HOST_SCRIPT" ]; then
      echo "[beacon-node-server] ERROR: Missing $HOST_SCRIPT." >&2
      exit 13
    fi

    stop_host

    OCCUPIED=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$OCCUPIED" ]; then
      echo "[beacon-node-server] ERROR: Port $PORT is already in use by another process (PID $OCCUPIED). Choose a different port." >&2
      exit 14
    fi

    nohup node "$HOST_SCRIPT" --port "$PORT" --registry "$REGISTRY" --pidfile "$PID_FILE" </dev/null >>"$HOST_LOG" 2>&1 &
    NEW_PID=$!
    disown "$NEW_PID" 2>/dev/null || true
    sleep 0.8

    if ! kill -0 "$NEW_PID" 2>/dev/null; then
      echo "[beacon-node-server] ERROR: Built-in Node.js host exited immediately. Recent log:" >&2
      tail -n 15 "$HOST_LOG" 2>/dev/null >&2 || true
      exit 15
    fi

    NODE_VER=$(node -v 2>/dev/null || echo "unknown")
    echo "NODEHOST:RUNNING:YES:$NEW_PID"
    echo "NODEHOST:NODE:$NODE_VER:http://127.0.0.1:$PORT"
    echo "[beacon-node-server] Started built-in Node.js server on http://127.0.0.1:$PORT (PID $NEW_PID, Node $NODE_VER)"
    ;;

  stop)
    stop_host
    echo "NODEHOST:RUNNING:NO:stopped"
    echo "[beacon-node-server] Stopped built-in Node.js server on port $PORT"
    ;;

  status)
    RUNNING_PID=""
    if [ -f "$PID_FILE" ]; then
      CAND=$(cat "$PID_FILE" 2>/dev/null || true)
      if [ -n "$CAND" ] && kill -0 "$CAND" 2>/dev/null; then
        RUNNING_PID="$CAND"
      fi
    fi
    if [ -n "$RUNNING_PID" ]; then
      echo "NODEHOST:RUNNING:YES:$RUNNING_PID"
    else
      echo "NODEHOST:RUNNING:NO:stopped"
    fi
    ;;

  *)
    echo "[beacon-node-server] Unknown action: $ACTION (expected start|stop|restart|status)" >&2
    exit 2
    ;;
esac
"""#

    private static let nodeHostScript = #"""
#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const out = { port: 4173, registry: "", pidfile: "" };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--port" && argv[i + 1]) {
      const parsed = Number.parseInt(argv[++i], 10);
      if (Number.isInteger(parsed) && parsed >= 1024 && parsed <= 65535) {
        out.port = parsed;
      }
    } else if (arg === "--registry" && argv[i + 1]) {
      out.registry = argv[++i];
    } else if (arg === "--pidfile" && argv[i + 1]) {
      out.pidfile = argv[++i];
    }
  }
  return out;
}

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".cjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wasm": "application/wasm",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".pdf": "application/pdf",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".mp3": "audio/mpeg",
};

function escapeHtml(raw) {
  return String(raw ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function detectServeRoot(folderPath) {
  if (!folderPath || typeof folderPath !== "string") return null;
  const resolved = path.resolve(folderPath);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) return null;

  for (const candidate of ["dist", "build", "out", "public"]) {
    const subDir = path.join(resolved, candidate);
    if (fs.existsSync(path.join(subDir, "index.html"))) {
      return { rootDir: subDir, detectedSubdir: candidate };
    }
  }
  return { rootDir: resolved, detectedSubdir: "" };
}

const config = parseArgs(process.argv);
const startedAt = Date.now();

let cachedMtimeMs = -1;
let cachedRegistry = { activeRootSlug: null, apps: [] };

function loadRegistry() {
  if (!config.registry) return cachedRegistry;
  try {
    const stat = fs.statSync(config.registry);
    if (stat.mtimeMs !== cachedMtimeMs) {
      const raw = JSON.parse(fs.readFileSync(config.registry, "utf8"));
      const apps = Array.isArray(raw.apps)
        ? raw.apps
            .filter((a) => a && typeof a.slug === "string" && /^[a-z0-9][a-z0-9-]*$/.test(a.slug))
            .map((a) => ({
              id: String(a.id || a.slug),
              name: String(a.name || a.slug),
              slug: String(a.slug),
              mode: a.mode === "proxy" ? "proxy" : "static",
              folderPath: typeof a.folderPath === "string" ? a.folderPath : "",
              proxyPort:
                Number.isInteger(a.proxyPort) && a.proxyPort >= 1 && a.proxyPort <= 65535
                  ? a.proxyPort
                  : null,
              spaFallback: a.spaFallback !== false,
            }))
        : [];
      const activeRootSlug =
        typeof raw.activeRootSlug === "string" && apps.some((a) => a.slug === raw.activeRootSlug)
          ? raw.activeRootSlug
          : null;
      cachedRegistry = { activeRootSlug, apps };
      cachedMtimeMs = stat.mtimeMs;
    }
  } catch {
  }
  return cachedRegistry;
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(body);
}

function renderDashboardHtml(registry) {
  const activeSlug = registry.activeRootSlug || (registry.apps.length === 1 ? registry.apps[0].slug : null);
  const cards = registry.apps.length
    ? registry.apps
        .map((app) => {
          const isRoot = app.slug === activeSlug;
          const info =
            app.mode === "proxy"
              ? `Proxy → 127.0.0.1:${escapeHtml(app.proxyPort ?? "—")}`
              : (() => {
                  const detected = detectServeRoot(app.folderPath);
                  if (!detected) return "Folder not found";
                  return detected.detectedSubdir
                    ? `${escapeHtml(path.basename(app.folderPath))}/${escapeHtml(detected.detectedSubdir)}`
                    : escapeHtml(path.basename(app.folderPath));
                })();
          const href = isRoot ? "/" : `/apps/${encodeURIComponent(app.slug)}/`;
          return `
            <div class="card">
              <div class="row">
                <div>
                  <div class="title">${escapeHtml(app.name)} ${isRoot ? '<span class="tag">ACTIVE ROOT /</span>' : ""}</div>
                  <div class="meta">${escapeHtml(app.mode.toUpperCase())} · ${info} · /apps/${escapeHtml(app.slug)}/</div>
                </div>
                <a class="btn" href="${href}">Open App →</a>
              </div>
            </div>`;
        })
        .join("\n")
    : `<div class="empty">No apps loaded yet. Click <strong>Load App Folder</strong> inside BeaconMac to mount any HTML, Vite, React, or local app directly into this built-in Node.js server.</div>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>BeaconMac Built-In Node.js Server</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #0b0e14; color: #e6edf3; }
    .wrap { max-width: 780px; margin: 48px auto; padding: 0 24px; }
    h1 { font-size: 22px; margin: 0 0 6px; letter-spacing: -0.02em; }
    .sub { color: #8b949e; font-size: 13px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; margin-bottom: 24px; }
    .card { background: #131820; border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; padding: 16px 18px; margin-bottom: 12px; }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    .title { font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
    .meta { font-size: 12px; color: #8b949e; margin-top: 4px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .tag { font-size: 10px; font-weight: 700; color: #34d399; background: rgba(52,211,153,0.12); border: 1px solid rgba(52,211,153,0.3); padding: 2px 7px; border-radius: 6px; }
    .btn { text-decoration: none; color: #fff; background: #2563eb; padding: 8px 14px; border-radius: 7px; font-size: 12.5px; font-weight: 600; white-space: nowrap; }
    .btn:hover { background: #1d4ed8; }
    .empty { background: #131820; border: 1px dashed rgba(255,255,255,0.14); border-radius: 10px; padding: 24px; color: #9ca3af; font-size: 13.5px; line-height: 1.5; }
    .foot { margin-top: 28px; color: #6b7280; font-size: 11.5px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>BeaconMac Built-In Node.js Server</h1>
    <div class="sub">127.0.0.1:${config.port} · Node ${escapeHtml(process.version)} · ${registry.apps.length} loaded app(s)</div>
    ${cards}
    <div class="foot">Loopback-only local host · Health: /_beacon/health · Apps JSON: /_beacon/apps</div>
  </div>
</body>
</html>`;
}

function isBlockedDotPath(relPath) {
  const segments = relPath.split("/");
  return segments.some((seg) => seg.startsWith(".") && seg !== ".well-known");
}

function serveStaticApp(app, relPathname, req, res) {
  const detected = detectServeRoot(app.folderPath);
  if (!detected) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`App folder not found for "${app.name}".`);
    return;
  }

  let rootReal;
  try {
    rootReal = fs.realpathSync(detected.rootDir);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`Unable to access app directory for "${app.name}".`);
    return;
  }

  let decoded;
  try {
    decoded = decodeURIComponent(relPathname || "/");
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  if (decoded.includes("\0")) {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  const normalizedRel = decoded.replace(/^\/+/, "");
  if (isBlockedDotPath(normalizedRel)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  const candidate = path.resolve(rootReal, normalizedRel);
  if (candidate !== rootReal && !candidate.startsWith(rootReal + path.sep)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  let fileToServe = candidate;
  try {
    const stat = fs.statSync(fileToServe);
    if (stat.isDirectory()) {
      fileToServe = path.join(fileToServe, "index.html");
    }
  } catch {
  }

  let existsAndFile = false;
  try {
    existsAndFile = fs.statSync(fileToServe).isFile();
  } catch {
    existsAndFile = false;
  }

  if (!existsAndFile && app.spaFallback) {
    const indexFallback = path.join(rootReal, "index.html");
    if (fs.existsSync(indexFallback) && fs.statSync(indexFallback).isFile()) {
      fileToServe = indexFallback;
      existsAndFile = true;
    }
  }

  if (!existsAndFile) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`Not Found: /${normalizedRel}`);
    return;
  }

  let realTarget;
  try {
    realTarget = fs.realpathSync(fileToServe);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not Found");
    return;
  }

  if (realTarget !== rootReal && !realTarget.startsWith(rootReal + path.sep)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  const ext = path.extname(realTarget).toLowerCase();
  const contentType = MIME_TYPES[ext] || "application/octet-stream";
  const stat = fs.statSync(realTarget);

  res.writeHead(200, {
    "Content-Type": contentType,
    "Content-Length": stat.size,
    "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=60",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  });

  if (req.method === "HEAD") {
    res.end();
    return;
  }

  const stream = fs.createReadStream(realTarget);
  stream.on("error", () => {
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    }
    res.end("Internal Server Error");
  });
  stream.pipe(res);
}

function proxyLocalApp(app, relPathWithQuery, req, res) {
  if (!app.proxyPort) {
    res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(`App "${app.name}" has no valid local proxy port configured.`);
    return;
  }

  const headers = { ...req.headers, host: `127.0.0.1:${app.proxyPort}` };
  delete headers["connection"];

  const proxyReq = http.request(
    {
      hostname: "127.0.0.1",
      port: app.proxyPort,
      method: req.method,
      path: relPathWithQuery.startsWith("/") ? relPathWithQuery : `/${relPathWithQuery}`,
      headers,
      timeout: 15000,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res);
    }
  );

  proxyReq.on("error", (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    }
    res.end(`BeaconMac Proxy: 127.0.0.1:${app.proxyPort} is unreachable (${err.code || err.message}).`);
  });

  proxyReq.on("timeout", () => {
    proxyReq.destroy();
    if (!res.headersSent) {
      res.writeHead(504, { "Content-Type": "text/plain; charset=utf-8" });
    }
    res.end(`BeaconMac Proxy: 127.0.0.1:${app.proxyPort} timed out.`);
  });

  req.pipe(proxyReq);
}

function dispatchToApp(app, relPathname, search, req, res) {
  if (app.mode === "proxy") {
    proxyLocalApp(app, `${relPathname}${search}`, req, res);
  } else {
    serveStaticApp(app, relPathname, req, res);
  }
}

const server = http.createServer((req, res) => {
  const registry = loadRegistry();
  const rawUrlPath = (req.url || "/").split("?")[0];
  let rawDecoded = rawUrlPath;
  try {
    rawDecoded = decodeURIComponent(rawUrlPath);
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }
  if (rawDecoded.includes("\0") || rawDecoded.split(/[\\/]/).includes("..")) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end("Forbidden");
    return;
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(req.url || "/", `http://127.0.0.1:${config.port}`);
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  const pathname = parsedUrl.pathname;
  const search = parsedUrl.search || "";

  if (pathname === "/_beacon/health") {
    sendJson(res, 200, {
      ok: true,
      pid: process.pid,
      port: config.port,
      nodeVersion: process.version,
      activeRootSlug: registry.activeRootSlug,
      appCount: registry.apps.length,
      uptimeSec: Math.floor((Date.now() - startedAt) / 1000),
    });
    return;
  }

  if (pathname === "/_beacon/apps") {
    sendJson(res, 200, {
      port: config.port,
      activeRootSlug: registry.activeRootSlug,
      apps: registry.apps.map((a) => ({
        id: a.id,
        name: a.name,
        slug: a.slug,
        mode: a.mode,
        mountPath: `/apps/${a.slug}/`,
        proxyPort: a.proxyPort,
      })),
    });
    return;
  }

  if (pathname === "/_beacon" || pathname === "/_beacon/") {
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    res.end(renderDashboardHtml(registry));
    return;
  }

  const mountMatch = pathname.match(/^\/apps\/([a-z0-9][a-z0-9-]*)(\/.*)?$/);
  if (mountMatch) {
    const slug = mountMatch[1];
    const rest = mountMatch[2];
    const targetApp = registry.apps.find((a) => a.slug === slug);
    if (!targetApp) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end(`App "${slug}" is not currently loaded in BeaconMac's built-in Node.js server.`);
      return;
    }
    if (!rest) {
      res.writeHead(302, { Location: `/apps/${slug}/${search}` });
      res.end();
      return;
    }
    dispatchToApp(targetApp, rest, search, req, res);
    return;
  }

  const rootApp =
    (registry.activeRootSlug && registry.apps.find((a) => a.slug === registry.activeRootSlug)) ||
    (registry.apps.length === 1 ? registry.apps[0] : null);

  if (rootApp) {
    dispatchToApp(rootApp, pathname, search, req, res);
    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(renderDashboardHtml(registry));
});

server.listen(config.port, "127.0.0.1", () => {
  if (config.pidfile) {
    try {
      fs.mkdirSync(path.dirname(config.pidfile), { recursive: true });
      fs.writeFileSync(config.pidfile, String(process.pid), "utf8");
    } catch {}
  }
  console.log(`[beacon-node-host] Listening on http://127.0.0.1:${config.port} (PID ${process.pid}, Node ${process.version})`);
});

function shutdown() {
  if (config.pidfile) {
    try {
      fs.unlinkSync(config.pidfile);
    } catch {}
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 500).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
"""#

    private static let nginxScript = #"""
#!/bin/bash
# Manages BeaconMac's built-in NGINX reverse proxy instance using a dedicated
# user-space nginx.conf, PID file, and temp/log directories under ~/beaconmac/nginx.
# Never requires sudo and never modifies Homebrew's system nginx.conf.
#
# Arguments:
#   $1 = action ("start" | "stop" | "restart" | "reload" | "test" | "status")
#   $2 = path to generated nginx.conf
#   $3 = listen port (default: 8080)
set -euo pipefail

ACTION="${1:-status}"
CONF_PATH="${2:-$HOME/Library/Application Support/Beacon/nginx/nginx.conf}"
PORT="${3:-8080}"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$PATH"

NGINX_DIR="$HOME/beaconmac/nginx"
PID_FILE="$NGINX_DIR/nginx.pid"
ERROR_LOG="$NGINX_DIR/error.log"
ACCESS_LOG="$NGINX_DIR/access.log"

mkdir -p "$NGINX_DIR/client_body" "$NGINX_DIR/proxy_temp" "$NGINX_DIR/fastcgi_temp" "$NGINX_DIR/uwsgi_temp" "$NGINX_DIR/scgi_temp"

find_nginx_bin() {
  for candidate in \
    "$(command -v nginx 2>/dev/null || true)" \
    "/opt/homebrew/bin/nginx" \
    "/opt/homebrew/sbin/nginx" \
    "/usr/local/bin/nginx" \
    "/usr/local/sbin/nginx" \
    "$HOME/.local/bin/nginx"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

NGINX_BIN=$(find_nginx_bin || true)

read_pid() {
  if [ -f "$PID_FILE" ]; then
    local p
    p=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  fi
  return 1
}

stop_nginx() {
  local running_pid
  running_pid=$(read_pid || true)
  if [ -n "$running_pid" ]; then
    if [ -n "$NGINX_BIN" ] && [ -f "$CONF_PATH" ]; then
      "$NGINX_BIN" -p "$NGINX_DIR/" -c "$CONF_PATH" -s quit >/dev/null 2>&1 || true
      sleep 0.5
    fi
    if kill -0 "$running_pid" 2>/dev/null; then
      kill -TERM "$running_pid" 2>/dev/null || true
      sleep 0.4
    fi
    if kill -0 "$running_pid" 2>/dev/null; then
      kill -KILL "$running_pid" 2>/dev/null || true
      sleep 0.2
    fi
  fi
  rm -f "$PID_FILE"

  # Clean up any orphaned beacon nginx process listening on this port
  local listener_pids
  listener_pids=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$listener_pids" ]; then
    for lpid in $listener_pids; do
      local cmdline
      cmdline=$(ps -p "$lpid" -o command= 2>/dev/null || true)
      if echo "$cmdline" | grep -q "Beacon/nginx/nginx.conf"; then
        kill -TERM "$lpid" 2>/dev/null || true
        sleep 0.3
      fi
    done
  fi
}

nginx_version_str() {
  if [ -n "$NGINX_BIN" ]; then
    "$NGINX_BIN" -v 2>&1 | sed 's/nginx version: //' | head -n 1 || echo "nginx"
  else
    echo "missing"
  fi
}

case "$ACTION" in
  status)
    VER=$(nginx_version_str)
    if [ -z "$NGINX_BIN" ]; then
      echo "NGINX:INSTALLED:NO:not found"
      echo "NGINX:RUNNING:NO:not installed"
      exit 0
    fi
    echo "NGINX:INSTALLED:YES:$VER"
    if "$NGINX_BIN" -V 2>&1 | grep -q "http_stub_status_module"; then
      echo "NGINX:STUB_STATUS:YES:http_stub_status_module"
    else
      echo "NGINX:STUB_STATUS:NO:unsupported"
    fi
    RUNNING_PID=$(read_pid || true)
    if [ -n "$RUNNING_PID" ]; then
      echo "NGINX:RUNNING:YES:$RUNNING_PID"
    else
      echo "NGINX:RUNNING:NO:stopped"
    fi
    ;;

  test)
    if [ -z "$NGINX_BIN" ]; then
      echo "[beacon-nginx] ERROR: NGINX is not installed. Click 'Install NGINX' in BeaconMac (installs silently via Homebrew)." >&2
      exit 12
    fi
    if [ ! -f "$CONF_PATH" ]; then
      echo "[beacon-nginx] ERROR: Config file not found at $CONF_PATH." >&2
      exit 13
    fi
    "$NGINX_BIN" -t -p "$NGINX_DIR/" -c "$CONF_PATH" 2>&1
    echo "NGINX:TEST:OK:$CONF_PATH"
    ;;

  start|restart)
    if [ -z "$NGINX_BIN" ]; then
      echo "[beacon-nginx] ERROR: NGINX is not installed. Click 'Install NGINX' in BeaconMac to install it silently via Homebrew." >&2
      exit 12
    fi
    if [ ! -f "$CONF_PATH" ]; then
      echo "[beacon-nginx] ERROR: Missing NGINX configuration at $CONF_PATH." >&2
      exit 13
    fi

    # Validate config before touching running process
    if ! TEST_OUT=$("$NGINX_BIN" -t -p "$NGINX_DIR/" -c "$CONF_PATH" 2>&1); then
      echo "[beacon-nginx] ERROR: nginx.conf validation failed:" >&2
      echo "$TEST_OUT" >&2
      exit 16
    fi

    stop_nginx

    OCCUPIED=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
    if [ -n "$OCCUPIED" ]; then
      echo "[beacon-nginx] ERROR: Port $PORT is already in use by another process (PID $OCCUPIED). Choose a different NGINX listen port." >&2
      exit 14
    fi

    "$NGINX_BIN" -p "$NGINX_DIR/" -c "$CONF_PATH" 2>&1
    sleep 0.5

    NEW_PID=$(read_pid || true)
    if [ -z "$NEW_PID" ]; then
      echo "[beacon-nginx] ERROR: NGINX failed to start on port $PORT. Recent error log:" >&2
      tail -n 20 "$ERROR_LOG" 2>/dev/null >&2 || true
      exit 15
    fi

    VER=$(nginx_version_str)
    echo "NGINX:INSTALLED:YES:$VER"
    echo "NGINX:RUNNING:YES:$NEW_PID"
    echo "[beacon-nginx] Started NGINX reverse proxy ($VER) on port $PORT (PID $NEW_PID)"
    ;;

  reload)
    if [ -z "$NGINX_BIN" ]; then
      echo "[beacon-nginx] ERROR: NGINX is not installed." >&2
      exit 12
    fi
    if [ ! -f "$CONF_PATH" ]; then
      echo "[beacon-nginx] ERROR: Missing NGINX configuration at $CONF_PATH." >&2
      exit 13
    fi

    if ! TEST_OUT=$("$NGINX_BIN" -t -p "$NGINX_DIR/" -c "$CONF_PATH" 2>&1); then
      echo "[beacon-nginx] ERROR: nginx.conf validation failed — keeping previous routes active:" >&2
      echo "$TEST_OUT" >&2
      exit 16
    fi

    RUNNING_PID=$(read_pid || true)
    if [ -n "$RUNNING_PID" ]; then
      "$NGINX_BIN" -p "$NGINX_DIR/" -c "$CONF_PATH" -s reload 2>&1
      sleep 0.3
      VER=$(nginx_version_str)
      echo "NGINX:INSTALLED:YES:$VER"
      echo "NGINX:RUNNING:YES:$RUNNING_PID"
      echo "[beacon-nginx] Reloaded NGINX reverse proxy configuration (PID $RUNNING_PID)"
    else
      "$NGINX_BIN" -p "$NGINX_DIR/" -c "$CONF_PATH" 2>&1
      sleep 0.5
      NEW_PID=$(read_pid || true)
      if [ -z "$NEW_PID" ]; then
        echo "[beacon-nginx] ERROR: NGINX failed to start during reload." >&2
        tail -n 20 "$ERROR_LOG" 2>/dev/null >&2 || true
        exit 15
      fi
      VER=$(nginx_version_str)
      echo "NGINX:INSTALLED:YES:$VER"
      echo "NGINX:RUNNING:YES:$NEW_PID"
      echo "[beacon-nginx] Started NGINX reverse proxy ($VER) on port $PORT (PID $NEW_PID)"
    fi
    ;;

  stop)
    stop_nginx
    echo "NGINX:RUNNING:NO:stopped"
    echo "[beacon-nginx] Stopped NGINX reverse proxy on port $PORT"
    ;;

  *)
    echo "[beacon-nginx] Unknown action: $ACTION (expected start|stop|restart|reload|test|status)" >&2
    exit 2
    ;;
esac
"""#

    private static let cloudflaredScript = #"""
#!/bin/bash
# Manages BeaconMac's one-click Cloudflare Tunnels (`cloudflared`) supporting:
#   1. Dynamic Cloudflare API named tunnels via generated `config.yml` (`start-config`)
#      or secure Keychain-provisioned token files (`start-token`, passed via env, never CLI args)
#   2. Zero-config Quick Tunnels (`start`, `*.trycloudflare.com`)
#
# Per-tunnel PID, URL, mode, and log files are stored under ~/beaconmac/tunnels/<tunnel_id>.
# Never requires sudo.
#
# Arguments:
#   $1 = action ("status" | "start" | "start-config" | "start-token" | "stop" | "stop-all")
#   $2 = tunnel_id (alphanumeric/dash/underscore, or "all" for status)
#   $3 = target_url (for "start") | config_yml_path (for "start-config") | token_file_path (for "start-token")
#   $4 = protocol (for "start") | public_url (for "start-config" / "start-token")
#   $5 = target_url (for "start-config" / "start-token")
set -euo pipefail

ACTION="${1:-status}"
TUNNEL_ID="${2:-all}"
ARG3="${3:-}"
ARG4="${4:-auto}"
ARG5="${5:-}"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$PATH"

TUNNELS_ROOT="$HOME/beaconmac/tunnels"
mkdir -p "$TUNNELS_ROOT"

find_cloudflared_bin() {
  for candidate in \
    "$(command -v cloudflared 2>/dev/null || true)" \
    "/opt/homebrew/bin/cloudflared" \
    "/usr/local/bin/cloudflared" \
    "$HOME/.local/bin/cloudflared"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

CF_BIN=$(find_cloudflared_bin || true)

cf_version_str() {
  if [ -n "$CF_BIN" ]; then
    "$CF_BIN" --version 2>&1 | head -n 1 | sed 's/cloudflared version //' | awk '{print $1}' || echo "installed"
  else
    echo "missing"
  fi
}

sanitize_id() {
  local raw="$1"
  local cleaned
  cleaned=$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9_-')
  printf '%s' "${cleaned:0:80}"
}

read_pid_for_dir() {
  local dir="$1"
  local pf="$dir/tunnel.pid"
  if [ -f "$pf" ]; then
    local p
    p=$(tr -d '[:space:]' < "$pf" 2>/dev/null || true)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  fi
  return 1
}

extract_public_url() {
  local logfile="$1"
  if [ -f "$logfile" ]; then
    grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$logfile" 2>/dev/null | head -n 1 || true
  fi
}

stop_tunnel_dir() {
  local dir="$1"
  local running_pid
  running_pid=$(read_pid_for_dir "$dir" || true)
  if [ -n "$running_pid" ]; then
    kill -TERM "$running_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$running_pid" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if kill -0 "$running_pid" 2>/dev/null; then
      kill -KILL "$running_pid" 2>/dev/null || true
      sleep 0.1
    fi
  fi
  rm -f "$dir/tunnel.pid" "$dir/public.url" "$dir/mode.txt"
}

wait_for_named_tunnel() {
  local new_pid="$1"
  local logfile="$2"
  local connected=0
  for _ in $(seq 1 50); do
    if ! kill -0 "$new_pid" 2>/dev/null; then
      echo "[beacon-cloudflared] ERROR: cloudflared exited before registering the tunnel connection. Recent output:" >&2
      tail -n 20 "$logfile" 2>/dev/null >&2 || true
      return 1
    fi
    if grep -qiE 'Registered tunnel connection|Connection .* registered' "$logfile" 2>/dev/null; then
      connected=1
      break
    fi
    sleep 0.35
  done
  # Even if log verbosity varies, if process is still healthy after waiting, verify alive
  if [ "$connected" -eq 0 ] && ! kill -0 "$new_pid" 2>/dev/null; then
    echo "[beacon-cloudflared] ERROR: cloudflared failed to maintain connection. Recent output:" >&2
    tail -n 20 "$logfile" 2>/dev/null >&2 || true
    return 1
  fi
  return 0
}

case "$ACTION" in
  status)
    VER=$(cf_version_str)
    if [ -z "$CF_BIN" ]; then
      echo "CLOUDFLARED:INSTALLED:NO:not found"
      exit 0
    fi
    echo "CLOUDFLARED:INSTALLED:YES:$VER"

    if [ "$TUNNEL_ID" = "all" ] || [ -z "$TUNNEL_ID" ]; then
      for dir in "$TUNNELS_ROOT"/*; do
        [ -d "$dir" ] || continue
        tid=$(basename "$dir")
        rpid=$(read_pid_for_dir "$dir" || true)
        if [ -n "$rpid" ]; then
          pub_url=""
          if [ -f "$dir/public.url" ]; then
            pub_url=$(tr -d '[:space:]' < "$dir/public.url" 2>/dev/null || true)
          fi
          if [ -z "$pub_url" ]; then
            pub_url=$(extract_public_url "$dir/tunnel.log")
            [ -n "$pub_url" ] && printf '%s\n' "$pub_url" > "$dir/public.url"
          fi
          tgt_url=""
          if [ -f "$dir/target.url" ]; then
            tgt_url=$(tr -d '[:space:]' < "$dir/target.url" 2>/dev/null || true)
          fi
          mode="quick"
          if [ -f "$dir/mode.txt" ]; then
            mode=$(tr -d '[:space:]' < "$dir/mode.txt" 2>/dev/null || echo "quick")
          fi
          echo "TUNNEL:ENTRY:$tid:$rpid:$pub_url|$tgt_url|$mode"
        else
          rm -f "$dir/tunnel.pid" "$dir/public.url" "$dir/mode.txt"
        fi
      done
    else
      SAFE_ID=$(sanitize_id "$TUNNEL_ID")
      TDIR="$TUNNELS_ROOT/$SAFE_ID"
      rpid=$(read_pid_for_dir "$TDIR" || true)
      if [ -n "$rpid" ]; then
        pub_url=""
        if [ -f "$TDIR/public.url" ]; then
          pub_url=$(tr -d '[:space:]' < "$TDIR/public.url" 2>/dev/null || true)
        fi
        if [ -z "$pub_url" ]; then
          pub_url=$(extract_public_url "$TDIR/tunnel.log")
          [ -n "$pub_url" ] && printf '%s\n' "$pub_url" > "$TDIR/public.url"
        fi
        echo "TUNNEL:RUNNING:YES:$rpid:$pub_url"
      else
        echo "TUNNEL:RUNNING:NO:stopped:"
      fi
    fi
    ;;

  start)
    TARGET_URL="$ARG3"
    PROTOCOL="$ARG4"
    if [ -z "$CF_BIN" ]; then
      echo "CLOUDFLARED:INSTALLED:NO:not found"
      echo "[beacon-cloudflared] ERROR: cloudflared is not installed." >&2
      exit 12
    fi

    SAFE_ID=$(sanitize_id "$TUNNEL_ID")
    if [ -z "$SAFE_ID" ] || [ "$SAFE_ID" = "all" ]; then
      echo "[beacon-cloudflared] ERROR: Invalid tunnel ID." >&2
      exit 13
    fi

    if ! printf '%s' "$TARGET_URL" | grep -qE '^https?://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?(/.*)?$'; then
      echo "[beacon-cloudflared] ERROR: Target URL must be a local loopback address (http://127.0.0.1:<port> or http://localhost:<port>)." >&2
      exit 14
    fi

    case "$PROTOCOL" in
      auto|http2|quic) ;;
      *) PROTOCOL="auto" ;;
    esac

    TDIR="$TUNNELS_ROOT/$SAFE_ID"
    mkdir -p "$TDIR"
    stop_tunnel_dir "$TDIR"

    LOG_FILE="$TDIR/tunnel.log"
    : > "$LOG_FILE"
    printf '%s\n' "$TARGET_URL" > "$TDIR/target.url"
    printf '%s\n' "quick" > "$TDIR/mode.txt"

    if [ "$PROTOCOL" = "auto" ]; then
      nohup "$CF_BIN" tunnel --url "$TARGET_URL" --no-autoupdate > "$LOG_FILE" 2>&1 < /dev/null &
    else
      nohup "$CF_BIN" tunnel --url "$TARGET_URL" --protocol "$PROTOCOL" --no-autoupdate > "$LOG_FILE" 2>&1 < /dev/null &
    fi
    NEW_PID=$!
    printf '%s\n' "$NEW_PID" > "$TDIR/tunnel.pid"

    PUBLIC_URL=""
    for _ in $(seq 1 60); do
      if ! kill -0 "$NEW_PID" 2>/dev/null; then
        echo "[beacon-cloudflared] ERROR: cloudflared exited unexpectedly before establishing a tunnel. Recent output:" >&2
        tail -n 20 "$LOG_FILE" 2>/dev/null >&2 || true
        rm -f "$TDIR/tunnel.pid" "$TDIR/public.url"
        exit 15
      fi
      PUBLIC_URL=$(extract_public_url "$LOG_FILE")
      if [ -n "$PUBLIC_URL" ]; then
        break
      fi
      sleep 0.35
    done

    if [ -z "$PUBLIC_URL" ]; then
      echo "[beacon-cloudflared] ERROR: Timed out waiting for Cloudflare Quick Tunnel URL. Recent output:" >&2
      tail -n 20 "$LOG_FILE" 2>/dev/null >&2 || true
      stop_tunnel_dir "$TDIR"
      exit 16
    fi

    printf '%s\n' "$PUBLIC_URL" > "$TDIR/public.url"
    VER=$(cf_version_str)
    echo "CLOUDFLARED:INSTALLED:YES:$VER"
    echo "TUNNEL:RUNNING:YES:$NEW_PID:$PUBLIC_URL"
    echo "[beacon-cloudflared] Live Quick Tunnel ready: $PUBLIC_URL -> $TARGET_URL (PID $NEW_PID)"
    ;;

  start-config)
    CONFIG_PATH="$ARG3"
    PUBLIC_URL="$ARG4"
    TARGET_URL="$ARG5"
    if [ -z "$CF_BIN" ]; then
      echo "CLOUDFLARED:INSTALLED:NO:not found"
      echo "[beacon-cloudflared] ERROR: cloudflared is not installed." >&2
      exit 12
    fi

    SAFE_ID=$(sanitize_id "$TUNNEL_ID")
    if [ -z "$SAFE_ID" ] || [ "$SAFE_ID" = "all" ]; then
      echo "[beacon-cloudflared] ERROR: Invalid tunnel ID." >&2
      exit 13
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
      echo "[beacon-cloudflared] ERROR: Generated cloudflared config.yml not found at $CONFIG_PATH." >&2
      exit 17
    fi

    TDIR="$TUNNELS_ROOT/$SAFE_ID"
    mkdir -p "$TDIR"
    stop_tunnel_dir "$TDIR"

    LOG_FILE="$TDIR/tunnel.log"
    : > "$LOG_FILE"
    printf '%s\n' "$TARGET_URL" > "$TDIR/target.url"
    printf '%s\n' "$PUBLIC_URL" > "$TDIR/public.url"
    printf '%s\n' "api" > "$TDIR/mode.txt"

    nohup "$CF_BIN" tunnel --config "$CONFIG_PATH" --no-autoupdate run > "$LOG_FILE" 2>&1 < /dev/null &
    NEW_PID=$!
    printf '%s\n' "$NEW_PID" > "$TDIR/tunnel.pid"

    if ! wait_for_named_tunnel "$NEW_PID" "$LOG_FILE"; then
      stop_tunnel_dir "$TDIR"
      exit 18
    fi

    VER=$(cf_version_str)
    echo "CLOUDFLARED:INSTALLED:YES:$VER"
    echo "TUNNEL:RUNNING:YES:$NEW_PID:$PUBLIC_URL"
    echo "[beacon-cloudflared] Live Cloudflare API Named Tunnel ready: $PUBLIC_URL -> $TARGET_URL (PID $NEW_PID, config: $CONFIG_PATH)"
    ;;

  start-token)
    TOKEN_FILE="$ARG3"
    PUBLIC_URL="$ARG4"
    TARGET_URL="$ARG5"
    if [ -z "$CF_BIN" ]; then
      echo "CLOUDFLARED:INSTALLED:NO:not found"
      echo "[beacon-cloudflared] ERROR: cloudflared is not installed." >&2
      exit 12
    fi

    SAFE_ID=$(sanitize_id "$TUNNEL_ID")
    if [ -z "$SAFE_ID" ] || [ "$SAFE_ID" = "all" ]; then
      echo "[beacon-cloudflared] ERROR: Invalid tunnel ID." >&2
      exit 13
    fi

    if [ ! -f "$TOKEN_FILE" ]; then
      echo "[beacon-cloudflared] ERROR: Temporary tunnel token file not found." >&2
      exit 19
    fi

    RAW_TOKEN=$(tr -d '\r\n' < "$TOKEN_FILE")
    rm -f "$TOKEN_FILE"
    if [ -z "$RAW_TOKEN" ]; then
      echo "[beacon-cloudflared] ERROR: Empty Cloudflare tunnel token." >&2
      exit 20
    fi

    TDIR="$TUNNELS_ROOT/$SAFE_ID"
    mkdir -p "$TDIR"
    stop_tunnel_dir "$TDIR"

    LOG_FILE="$TDIR/tunnel.log"
    : > "$LOG_FILE"
    printf '%s\n' "$TARGET_URL" > "$TDIR/target.url"
    printf '%s\n' "$PUBLIC_URL" > "$TDIR/public.url"
    printf '%s\n' "api" > "$TDIR/mode.txt"

    # Pass token via TUNNEL_TOKEN environment variable so it never appears in ps/process arguments
    TUNNEL_TOKEN="$RAW_TOKEN" nohup "$CF_BIN" tunnel --no-autoupdate run > "$LOG_FILE" 2>&1 < /dev/null &
    NEW_PID=$!
    unset RAW_TOKEN
    printf '%s\n' "$NEW_PID" > "$TDIR/tunnel.pid"

    if ! wait_for_named_tunnel "$NEW_PID" "$LOG_FILE"; then
      stop_tunnel_dir "$TDIR"
      exit 21
    fi

    VER=$(cf_version_str)
    echo "CLOUDFLARED:INSTALLED:YES:$VER"
    echo "TUNNEL:RUNNING:YES:$NEW_PID:$PUBLIC_URL"
    echo "[beacon-cloudflared] Live Cloudflare API Tunnel ready: $PUBLIC_URL -> $TARGET_URL (PID $NEW_PID)"
    ;;

  stop)
    SAFE_ID=$(sanitize_id "$TUNNEL_ID")
    if [ -n "$SAFE_ID" ] && [ -d "$TUNNELS_ROOT/$SAFE_ID" ]; then
      stop_tunnel_dir "$TUNNELS_ROOT/$SAFE_ID"
    fi
    echo "TUNNEL:RUNNING:NO:stopped:"
    echo "[beacon-cloudflared] Stopped Cloudflare tunnel '$SAFE_ID'"
    ;;

  stop-all)
    COUNT=0
    for dir in "$TUNNELS_ROOT"/*; do
      [ -d "$dir" ] || continue
      if read_pid_for_dir "$dir" >/dev/null 2>&1; then
        COUNT=$((COUNT + 1))
      fi
      stop_tunnel_dir "$dir"
    done
    echo "TUNNEL:STOPPED_ALL:$COUNT"
    echo "[beacon-cloudflared] Stopped $COUNT active Cloudflare tunnel(s)"
    ;;

  *)
    echo "[beacon-cloudflared] Unknown action: $ACTION (expected status|start|start-config|start-token|stop|stop-all)" >&2
    exit 2
    ;;
esac
"""#
}
