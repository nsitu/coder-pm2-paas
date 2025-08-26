#!/usr/bin/env bash
set -Eeuo pipefail

# ensure we report the full context in case of errors
trap 'src="${BASH_SOURCE[0]:-?}"; line="${LINENO:-?}"; cmd="${BASH_COMMAND:-?}"; echo "ERROR at ${src}:${line}: ${cmd}" >&2' ERR

# redirect standard input (stdin) from /dev/null
# ensures the script is non-interactive and doesn't hang waiting for input
exec </dev/null
 
# Decide mode: first boot vs rehydrate
BOOT_MODE="first"
if [ -f /home/coder/.startup_complete ]; then
  echo "Detected restart; running quick rehydrate."
  BOOT_MODE="rehydrate"
fi

echo "Starting Workspace..."

# Shell cosmetics for better UX
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc || true

# System snapshot for debugging
echo "=== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========"
coder stat || true 
echo "========================================="

# Create necessary directories, bootstrap, SSH, deps (first boot only)
if [ "$BOOT_MODE" = "first" ]; then
  echo "📁 Creating directory structure..."
  # Create data directories
  sudo mkdir -p \
    /home/coder/data/postgres \
    /home/coder/data/backups \
    /home/coder/logs \
    /home/coder/data/pids 
  sudo chown -R coder:coder /home/coder/data /home/coder/logs
  # Create srv directories 
  sudo mkdir -p \
    /home/coder/srv/apps/{a,b,c,d,e} \
    /home/coder/srv/scripts \
    /home/coder/srv/admin 
  sudo chown -R coder:coder /home/coder/srv
  
  # Bootstrap files setup
  echo "📋 Setting up bootstrap files..."
  if [ -d "/opt/bootstrap" ]; then
    # Copy srv files if they don't exist
    if [ ! -f "/home/coder/srv/admin/server.js" ] && [ -d "/opt/bootstrap/srv" ]; then
      cp -r /opt/bootstrap/srv/* /home/coder/srv/ 2>/dev/null || true
      chmod +x /home/coder/srv/scripts/*.sh 2>/dev/null || true
    fi
    # Copy build metadata to user home directory
    if [ -f "/opt/build-info.md" ]; then
      cp /opt/build-info.md /home/coder/build-info.md 2>/dev/null || true
      echo "  ✅ Build metadata copied to /home/coder/build-info.md"
    fi
  fi

  echo "📋 Setting up PM2 ecosystem configuration..."
  # Create PM2 logs directory
  mkdir -p /home/coder/logs/pm2
  
  # Copy static ecosystem configuration from bootstrap
  if [ -f "/opt/bootstrap/ecosystem.config.js" ]; then
    cp /opt/bootstrap/ecosystem.config.js /home/coder/ecosystem.config.js
    echo "  ✅ PM2 ecosystem configuration copied from bootstrap"
  else
    echo "  ❌ PM2 ecosystem configuration not found in bootstrap"
    exit 1
  fi

# Docker image build information
echo ""
echo "🐳 Docker Image Build Information:"
if [ -f "/home/coder/build-info.md" ]; then
  cat /home/coder/build-info.md | sed 's/^/  /'
else
  echo "  Build metadata not available"
fi

  echo "🔑 Setting up SSH access..."
  # ensure ~/.ssh exists in the mounted home and seed github.com known_hosts
  mkdir -p ~/.ssh && chmod 700 ~/.ssh || true
  if [ ! -f ~/.ssh/known_hosts ] || ! grep -q 'github.com' ~/.ssh/known_hosts 2>/dev/null; then
    ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    chmod 644 ~/.ssh/known_hosts || true
  fi
  # TODO: investigate the workflow for GIT_SSH_PRIVATE_KEY 
  if [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    echo "  ✅ SSH private key configured"
  fi
  # TODO: Seed other useful  known_hosts (e.g. bender.sheridanc.on.ca)

  # PostgreSQL initdb on first boot only (startup is handled below for both modes)
  echo "🐘 Initializing PostgreSQL 17..."
  if [ ! -f "/home/coder/data/postgres/PG_VERSION" ]; then
    echo "  📊 Creating new PostgreSQL database cluster..."
    sudo install -d -m 0750 -o coder -g coder /home/coder/data/postgres
    /usr/lib/postgresql/17/bin/initdb -D /home/coder/data/postgres
    # Ensure socket in /tmp and listen on loopback
    {
      echo "unix_socket_directories = '/tmp'"
      echo "listen_addresses = '127.0.0.1'"
    } >> /home/coder/data/postgres/postgresql.conf
    # Ensure TCP auth from localhost
    if ! grep -q '127.0.0.1/32' /home/coder/data/postgres/pg_hba.conf; then
      echo "host all all 127.0.0.1/32 scram-sha-256" >> /home/coder/data/postgres/pg_hba.conf
    fi
    echo "  ✅ PostgreSQL 17 initialized"
  else
    echo "  ✅ PostgreSQL 17 already initialized"
  fi
fi

# Generate static placeholders early (both first boot and rehydrate)
if command -v node >/dev/null 2>&1 && [ -f "/home/coder/srv/scripts/generate-placeholders.js" ]; then
  echo "⚙️  Generating static placeholders for slots..."
  set +e
  node /home/coder/srv/scripts/generate-placeholders.js generate
  gen_rc=$?
  set -e
  if [ $gen_rc -ne 0 ]; then
    echo "  ⚠️  Placeholder generation reported errors (rc=$gen_rc). Continuing startup."
  else
    echo "  ✅ Placeholders generated at /home/coder/srv/placeholders/slots"
  fi
else
  echo "  ⚠️  Skipping placeholder generation (node or script not available)"
fi

# Ensure PostgreSQL running (both modes), then DB/user ensure on first boot
echo "  🚀 Starting PostgreSQL 17 server..."

# Ensure logs directory exists and is writable
mkdir -p /home/coder/logs
chown coder:coder /home/coder/logs

PGDATA="/home/coder/data/postgres"
PGPORT="${PGPORT:-5432}"
PGREADY_HOST="${PGREADY_HOST:-127.0.0.1}"   

# Ownership and permissions for persistent PGDATA tree
chown -R coder:coder "$(dirname "$PGDATA")" || true
chmod 750 "$(dirname "$PGDATA")" || true
[ -d "$PGDATA" ] && chmod 700 "$PGDATA" || true

# Prefer pg_ctl status over pgrep to avoid false positives
if /usr/lib/postgresql/17/bin/pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
  echo "PostgreSQL already running for PGDATA=$PGDATA"
elif lsof -tiTCP:"$PGPORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Another process is listening on port $PGPORT; skipping pg_ctl start."
  lsof -iTCP:"$PGPORT" -sTCP:LISTEN -n -P || true
else
  if [ -f "$PGDATA/postmaster.pid" ] && ! /usr/lib/postgresql/17/bin/pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
    echo "Found stale postmaster.pid; removing"
    rm -f "$PGDATA/postmaster.pid" || true
  fi
  set +e
  /usr/lib/postgresql/17/bin/pg_ctl -D "$PGDATA" -o "-p $PGPORT -k /tmp" -l "/home/coder/logs/postgres.log" -w -t 20 start
  start_rc=$?
  set -e
  if [ $start_rc -ne 0 ]; then
    echo "  ⚠️  pg_ctl start failed (rc=$start_rc). Tail of log:"
    tail -n 100 "/home/coder/logs/postgres.log" || true
  fi
fi

echo "  ⏳ Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  if /usr/lib/postgresql/17/bin/pg_isready -h "$PGREADY_HOST" -p "$PGPORT" -d postgres >/dev/null 2>&1; then
    echo "  ✅ PostgreSQL 17 is ready on $PGREADY_HOST:$PGPORT"
    break
  fi
  sleep 1
done

if [ "$BOOT_MODE" = "first" ]; then
  echo "  👤 Setting up workspace database..."
  # Use TCP and connect to the default postgres DB (not "coder")
  PSQL="/usr/lib/postgresql/17/bin/psql -h $PGREADY_HOST -p $PGPORT -d postgres -U coder"
  $PSQL -tc "SELECT 1 FROM pg_roles WHERE rolname='coder';" | grep -q 1 || \
    $PSQL -c "CREATE ROLE coder LOGIN SUPERUSER;"
  $PSQL -c "ALTER ROLE coder WITH PASSWORD 'coder_dev_password';"
  $PSQL -tc "SELECT 1 FROM pg_database WHERE datname='workspace_db';" | grep -q 1 || \
    $PSQL -c "CREATE DATABASE workspace_db OWNER coder;" 
  
  # Initialize a simple test table and insert a success row
  # Connect to the newly ensured workspace_db using the same TCP params
  PSQL_WS="$PSQL -d workspace_db"
  # Create table: id (serial PK), datetime (timestamp with time zone), status (text)
  $PSQL_WS -c "CREATE TABLE IF NOT EXISTS test ( id SERIAL PRIMARY KEY,  datetime TIMESTAMPTZ NOT NULL DEFAULT now(), status TEXT NOT NULL );" || true
  # Insert a success row with current timestamp
  $PSQL_WS -c "INSERT INTO test (datetime, status) VALUES (CURRENT_TIMESTAMP, 'success');" || true
  echo "  ✅ Workspace database configured"
fi

# Start PM2 ecosystem (both first boot and rehydrate modes)
echo "🚀 Starting PM2 services..."
mkdir -p /home/coder/logs /home/coder/logs/pm2
chown -R coder:coder /home/coder/logs /home/coder/logs

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
    if pm2 start /home/coder/ecosystem.config.js; then
      pm2 save >/dev/null 2>&1
      echo "  ✅ PM2 ecosystem services started"
      # Show PM2 status for debugging
      pm2 list
    else
      echo "  ❌ Failed to start PM2 ecosystem"
      pm2 logs --lines 5
    fi
  else
    echo "  ✅ PM2 services already running"
    pm2 list
  fi
fi

# Mark completion on first boot
if [ "$BOOT_MODE" = "first" ]; then
  touch /home/coder/.startup_complete
  echo "✅ Startup complete!"
else
  echo "🔁 Quick rehydrate mode"
fi

exit 0
