#!/bin/bash
# Place in: ~/Library/Application Scripts/<YOUR_BUNDLE_ID>/beacon-check-deps.sh
# Audits required macOS runtime tools and project dependencies, OR when invoked with
# `--install [workdir] [tools_csv]`, installs missing runtimes (node, bun, pnpm, yarn,
# python3, uv, go, git) and auto-detected project dependencies from package.json,
# lockfiles, requirements.txt, pyproject.toml, go.mod, Cargo.toml, or Gemfile.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.volta/bin:$HOME/.fnm/current/bin:$HOME/.local/share/mise/shims:$HOME/.asdf/shims:$HOME/.bun/bin:$HOME/.cargo/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ]; then
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
  fi
fi

install_runtime_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "[beacon-deps] $tool is already installed ($("$tool" --version 2>/dev/null | head -n 1 || echo "ready"))."
    return 0
  fi

  echo "[beacon-deps] Installing prerequisite '$tool'..."
  case "$tool" in
    node|npm)
      if command -v brew >/dev/null 2>&1; then
        brew install node
      else
        echo "[beacon-deps] ERROR: Homebrew not found. Install Homebrew from https://brew.sh or Node.js from https://nodejs.org." >&2
        return 1
      fi
      ;;
    pnpm)
      if command -v brew >/dev/null 2>&1; then
        brew install pnpm
      elif command -v corepack >/dev/null 2>&1; then
        corepack enable && corepack prepare pnpm@latest --activate
      elif command -v npm >/dev/null 2>&1; then
        npm install -g pnpm
      else
        echo "[beacon-deps] ERROR: Install Node.js or Homebrew first to install pnpm." >&2
        return 1
      fi
      ;;
    yarn)
      if command -v brew >/dev/null 2>&1; then
        brew install yarn
      elif command -v npm >/dev/null 2>&1; then
        npm install -g yarn
      else
        echo "[beacon-deps] ERROR: Install Node.js or Homebrew first to install yarn." >&2
        return 1
      fi
      ;;
    bun)
      if command -v brew >/dev/null 2>&1; then
        brew install oven-sh/tap/bun
      else
        curl -fsSL https://bun.sh/install | bash
        export PATH="$HOME/.bun/bin:$PATH"
      fi
      ;;
    python3)
      if command -v brew >/dev/null 2>&1; then
        brew install python
      else
        echo "[beacon-deps] ERROR: Homebrew not found to install python3." >&2
        return 1
      fi
      ;;
    uv)
      if command -v brew >/dev/null 2>&1; then
        brew install uv
      else
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
      fi
      ;;
    go)
      if command -v brew >/dev/null 2>&1; then
        brew install go
      else
        echo "[beacon-deps] ERROR: Homebrew not found to install go." >&2
        return 1
      fi
      ;;
    cargo|rust)
      if command -v brew >/dev/null 2>&1; then
        brew install rust
      else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        export PATH="$HOME/.cargo/bin:$PATH"
      fi
      ;;
    git)
      if command -v brew >/dev/null 2>&1; then
        brew install git
      else
        xcode-select --install || true
      fi
      ;;
    *)
      echo "[beacon-deps] Skipping unknown runtime '$tool'."
      ;;
  esac
}

install_js_project_dir() {
  local dir="$1"
  cd "$dir"
  install_runtime_tool node

  local pm="npm"
  if [ -f "bun.lock" ] || [ -f "bun.lockb" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"bun@' package.json 2>/dev/null; then
    pm="bun"
  elif [ -f "pnpm-lock.yaml" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@' package.json 2>/dev/null; then
    pm="pnpm"
  elif [ -f "yarn.lock" ] || grep -qE '"packageManager"[[:space:]]*:[[:space:]]*"yarn@' package.json 2>/dev/null; then
    pm="yarn"
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
        "$WORKDIR/.venv/bin/pip" install -r "$WORKDIR/requirements.txt"
      else
        (cd "$WORKDIR" && python3 -m pip install --user -r requirements.txt)
      fi
    elif [ -f "$WORKDIR/pyproject.toml" ]; then
      FOUND_MANIFEST=1
      install_runtime_tool python3
      echo "[beacon-deps] Installing Python project from pyproject.toml..."
      if [ -x "$WORKDIR/.venv/bin/pip" ]; then
        "$WORKDIR/.venv/bin/pip" install -e "$WORKDIR"
      else
        (cd "$WORKDIR" && python3 -m pip install --user -e .)
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
      echo "[beacon-deps] No package.json, requirements.txt, pyproject.toml, go.mod, Cargo.toml, or Gemfile found in $WORKDIR."
    else
      echo "[beacon-deps] All detected prerequisites and project dependencies are installed."
    fi
  else
    echo "[beacon-deps] System prerequisites check/installation completed."
  fi
  exit 0
fi

WORKDIR="${1:-}"

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
check_bin python3 optional
check_bin uv optional
check_bin go optional

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
        echo "APP:DEPS:MISSING:node_modules not found in root (click Install Deps)"
      fi
    fi
  elif [ -f "$WORKDIR/requirements.txt" ] || [ -f "$WORKDIR/pyproject.toml" ]; then
    echo "APP:DEPS:OK:Python manifest detected (click Install Deps to sync)"
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
