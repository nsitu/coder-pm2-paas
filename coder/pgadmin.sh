#!/usr/bin/env bash
set -Eeuo pipefail

# Detach from Coder pipes
exec </dev/null >/dev/null 2>&1

mkdir -p /home/coder/data/pgadmin/sessions /home/coder/data/pgadmin/storage /home/coder/data/logs/pgadmin

# Defaults (overridable via env)
export PGADMIN_DEFAULT_EMAIL="${PGADMIN_DEFAULT_EMAIL:-admin@local}"
export PGADMIN_DEFAULT_PASSWORD="${PGADMIN_DEFAULT_PASSWORD:-admin}"
export PGADMIN_SETUP_EMAIL="$PGADMIN_DEFAULT_EMAIL"
export PGADMIN_SETUP_PASSWORD="$PGADMIN_DEFAULT_PASSWORD"
export PGADMIN_LISTEN_ADDRESS="0.0.0.0"
export PGADMIN_LISTEN_PORT="5050"
export PGADMIN_CONFIG_SERVER_MODE="True"
export PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED="False"
export PGADMIN_CONFIG_CONSOLE_LOG_LEVEL="10"
export PGADMIN_CONFIG_LOG_FILE="/home/coder/data/logs/pgadmin/pgadmin.log"
export PGADMIN_CONFIG_SQLITE_PATH="/home/coder/data/pgadmin/pgadmin.db"
export PGADMIN_CONFIG_SESSION_DB_PATH="/home/coder/data/pgadmin/sessions"
export PGADMIN_CONFIG_STORAGE_DIR="/home/coder/data/pgadmin/storage"

# Gate admin HTTP to enrich links later (best-effort)
for i in $(seq 1 10); do
  curl -fsS http://localhost:9000/ >/dev/null 2>&1 && break
  sleep 1
done

# Start pgAdmin if not listening
if ! lsof -ti :5050 >/dev/null 2>&1; then
  if command -v pgadmin4 >/dev/null 2>&1; then
    setsid sh -c 'exec pgadmin4 >> /home/coder/data/logs/pgadmin/pgadmin4.out 2>&1' </dev/null >/dev/null 2>&1 &
  elif [ -x "/opt/pgadmin-venv/bin/pgadmin4" ]; then
    setsid sh -c 'exec /opt/pgadmin-venv/bin/pgadmin4 >> /home/coder/data/logs/pgadmin/pgadmin4.out 2>&1' </dev/null >/dev/null 2>&1 &
  fi
fi

exit 0
