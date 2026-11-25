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
