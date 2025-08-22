#!/usr/bin/env bash
set -Eeuo pipefail
#  set -x (tracing: print each command before executing)

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

# Colors for output
RED='\033[0;35m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN} Starting Workspace...${NC}"

# Shell cosmetics for better UX
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc || true

# System snapshot for debugging
echo -e "${CYAN}=== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========${NC}"
coder stat || true
echo -e "${CYAN}=========================================${NC}"

# Create necessary directories, bootstrap, SSH, deps (first boot only)
if [ "$BOOT_MODE" = "first" ]; then
  echo -e "${YELLOW}📁 Creating directory structure...${NC}"
  # Create data directories
  sudo mkdir -p \
    /home/coder/data/postgres \
    /home/coder/data/pgadmin \
    /home/coder/data/backups \
    /home/coder/logs \
    /home/coder/data/pids 
  sudo chown -R coder:coder /home/coder/data
  # Create srv directories 
  sudo mkdir -p \
    /home/coder/srv/apps/{a,b,c,d,e} \
    /home/coder/srv/scripts \
    /home/coder/srv/admin 
  sudo chown -R coder:coder /home/coder/srv  
  
  # Note: there may be some duplication here since 
  # the bootstrap files below will also create some directories in /home/coder/srv
  echo -e "${YELLOW}📋 Setting up bootstrap files...${NC}"
  if [ ! -f "/home/coder/srv/admin/server.js" ] && [ -d "/opt/bootstrap/srv" ]; then
    cp -r /opt/bootstrap/srv/* /home/coder/srv/ 2>/dev/null || true
  fi
  chmod +x /home/coder/srv/scripts/*.sh 2>/dev/null || true

  echo -e "${YELLOW}🔑 Setting up SSH access...${NC}"
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
    echo -e "${GREEN}  ✅ SSH private key configured${NC}"
  fi
  # TODO: Seed other useful  known_hosts (e.g. bender.sheridanc.on.ca)

  # PostgreSQL initdb on first boot only (startup is handled below for both modes)
  echo -e "${CYAN}🐘 Initializing PostgreSQL 17...${NC}"
  if [ ! -f "/home/coder/data/postgres/PG_VERSION" ]; then
    echo -e "${YELLOW}  📊 Creating new PostgreSQL database cluster...${NC}"
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
    echo -e "${GREEN}  ✅ PostgreSQL 17 initialized${NC}"
  else
    echo -e "${GREEN}  ✅ PostgreSQL 17 already initialized${NC}"
  fi
fi

# Ensure PostgreSQL running (both modes), then DB/user ensure on first boot
echo -e "${YELLOW}  🚀 Starting PostgreSQL 17 server...${NC}"


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
    echo -e "${YELLOW}  ⚠️  pg_ctl start failed (rc=$start_rc). Tail of log:${NC}"
    tail -n 100 "/home/coder/logs/postgres.log" || true
  fi
fi

echo -e "${YELLOW}  ⏳ Waiting for PostgreSQL to be ready...${NC}"
for i in $(seq 1 30); do
  if /usr/lib/postgresql/17/bin/pg_isready -h "$PGREADY_HOST" -p "$PGPORT" >/dev/null 2>&1; then
    echo -e "${GREEN}  ✅ PostgreSQL 17 is ready on $PGREADY_HOST:$PGPORT${NC}"
    break
  fi
  sleep 1
done

if [ "$BOOT_MODE" = "first" ]; then
  echo -e "${YELLOW}  👤 Setting up workspace database...${NC}"
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
  echo -e "${GREEN}  ✅ Workspace database configured${NC}"
fi

# Mark completion on first boot
if [ "$BOOT_MODE" = "first" ]; then
  touch /home/coder/.startup_complete
  echo -e "${GREEN}✅ Startup complete!${NC}"
else
  echo -e "${GREEN}🔁 Quick rehydrate mode${NC}"
fi

exit 0