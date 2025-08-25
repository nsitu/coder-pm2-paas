#!/usr/bin/env bash
set -Eeuo pipefail

# Detach this script from Coder pipes so spawned daemons cannot inherit them
exec </dev/null >/dev/null 2>&1

mkdir -p /home/coder/logs /home/coder/data/logs/pm2

# Gate on PostgreSQL readiness (best-effort, 30s)
PGPORT="${PGPORT:-5432}"
for i in $(seq 1 30); do
  /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 -p "$PGPORT" >/dev/null 2>&1 && break
  sleep 1
done

# Ensure PM2 daemon is running
pm2 ping >/dev/null 2>&1 || {
  # Start PM2 daemon if not running
  pm2 status >/dev/null 2>&1
  sleep 1
}

# Start PM2 ecosystem if not already running
if [ -f "/home/coder/ecosystem.config.js" ]; then
  # Check if admin-server is already running
  if ! pm2 describe admin-server >/dev/null 2>&1; then
    # Start all processes from ecosystem config
    pm2 start /home/coder/ecosystem.config.js
    # Save PM2 configuration for persistence
    pm2 save >/dev/null 2>&1
  fi
fi

exit 0
