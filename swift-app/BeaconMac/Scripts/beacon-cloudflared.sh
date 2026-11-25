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
#   $5 = optional http_host_header (for "start") | target_url (for "start-config" / "start-token")
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
    HTTP_HOST_HEADER="$ARG5"
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

    if [ -n "$HTTP_HOST_HEADER" ]; then
      HTTP_HOST_HEADER=$(printf '%s' "$HTTP_HOST_HEADER" | tr -cd 'A-Za-z0-9.:-')
    fi

    TDIR="$TUNNELS_ROOT/$SAFE_ID"
    mkdir -p "$TDIR"
    stop_tunnel_dir "$TDIR"

    LOG_FILE="$TDIR/tunnel.log"
    : > "$LOG_FILE"
    printf '%s\n' "$TARGET_URL" > "$TDIR/target.url"
    printf '%s\n' "quick" > "$TDIR/mode.txt"

    CF_ARGS=(tunnel --url "$TARGET_URL" --no-autoupdate)
    if [ "$PROTOCOL" != "auto" ]; then
      CF_ARGS+=(--protocol "$PROTOCOL")
    fi
    if [ -n "$HTTP_HOST_HEADER" ]; then
      CF_ARGS+=(--http-host-header "$HTTP_HOST_HEADER")
    fi
    nohup "$CF_BIN" "${CF_ARGS[@]}" > "$LOG_FILE" 2>&1 < /dev/null &
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
