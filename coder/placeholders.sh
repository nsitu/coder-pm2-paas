#!/usr/bin/env bash
set -Eeuo pipefail

# Detach from Coder pipes
exec </dev/null >/dev/null 2>&1

LOG_DIR="/home/coder/logs"
PID_DIR="/home/coder/data/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

# ADMIN_URL is already set in the environment by the main.tf
WAIT_URL="http://localhost:9000"
PLACEHOLDER_DIR="/home/coder/srv/placeholders"
PLACEHOLDER_SERVER_JS="$PLACEHOLDER_DIR/server.js"
LOG_FILE="$LOG_DIR/placeholder-server.log"
PID_FILE="$PID_DIR/placeholder-server.pid"

# Wait for Admin to be up (best-effort 60s)
for i in $(seq 1 60); do
  if curl -fsS "$WAIT_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

start_placeholder_server() {
  # If already running, do nothing
  if [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    exit 0
  fi

  # Best-effort install if node_modules missing
  if [ -f "$PLACEHOLDER_DIR/package.json" ] && [ ! -d "$PLACEHOLDER_DIR/node_modules" ]; then
    (cd "$PLACEHOLDER_DIR" && npm install --omit=dev >> "$LOG_FILE" 2>&1) || true
  fi

  if [ -f "$PLACEHOLDER_SERVER_JS" ]; then
    # One process binds 3001–3005 and skips ports in use
    # Set ADMIN_URL in the shell, then exec node
    setsid sh -c "ADMIN_URL=\"$ADMIN_URL\" exec node \"$PLACEHOLDER_SERVER_JS\" >> \"$LOG_FILE\" 2>&1" </dev/null >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
  fi
}

start_placeholder_server
exit 0
