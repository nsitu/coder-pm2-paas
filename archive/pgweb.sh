#!/usr/bin/env bash
set -Eeuo pipefail

# Detach from Coder pipes
exec </dev/null >/dev/null 2>&1

LOG_DIR="/home/coder/logs"
PID_DIR="/home/coder/data/pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

echo "Starting PGWeb service..." >> "$LOG_DIR/pgweb.log"

# Defaults for local Postgres (overridable via env)
POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-coder}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-coder_dev_password}"
POSTGRES_DB="${POSTGRES_DB:-workspace_db}"

PGWEB_PORT="${PGWEB_PORT:-8081}"

# If already running, do nothing
if lsof -ti :"$PGWEB_PORT" >/dev/null 2>&1; then
  exit 0
fi

# Wait for PostgreSQL to accept connections (best-effort 60s)
echo "Waiting for PostgreSQL to be available at ${POSTGRES_HOST}:${POSTGRES_PORT}..." >> "$LOG_DIR/pgweb.log"
for i in $(seq 1 60); do
  if pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Set PGWEB_DATABASE_URL to auto-connect (avoids connection prompt)
export PGWEB_DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"

# Unset deprecated DATABASE_URL to avoid warning
unset DATABASE_URL || true

# Launch pgweb with environment variable (no connection flags needed)
setsid pgweb \
  --bind="0.0.0.0" \
  --listen="${PGWEB_PORT}" \
  --skip-open \
  --sessions \
  --log-level="info" >> "$LOG_DIR/pgweb.log" 2>&1 &

echo $! > "$PID_DIR/pgweb.pid"

exit 0