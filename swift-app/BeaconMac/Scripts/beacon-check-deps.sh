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
