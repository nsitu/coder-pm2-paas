#!/usr/bin/env bash
set -Eeuo pipefail

# Detach this script from Coder pipes so spawned daemons cannot inherit them
exec </dev/null >/dev/null 2>&1

mkdir -p /home/coder/data/logs /home/coder/data/pids

# Gate on PostgreSQL readiness (best-effort, 30s)
PGPORT="${PGPORT:-5432}"
for i in $(seq 1 30); do
  /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 -p "$PGPORT" >/dev/null 2>&1 && break
  sleep 1
done

# Start Admin panel on port 9000 if not already running
if ! lsof -ti :9000 >/dev/null 2>&1; then
  if [ -f "/home/coder/srv/admin/server.js" ]; then
    # Start in own session; write real PID then exec node
    setsid sh -c 'cd /home/coder/srv/admin; echo $$ > /home/coder/data/pids/admin.pid; exec node server.js >> /home/coder/data/logs/admin.log 2>&1' </dev/null >/dev/null 2>&1 &
  fi
fi

exit 0
