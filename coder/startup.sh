#!/usr/bin/env bash
set -Eeuxo pipefail
trap 'src="${BASH_SOURCE[0]:-?}"; line="${LINENO:-?}"; cmd="${BASH_COMMAND:-?}"; echo "ERROR at ${src}:${line}: ${cmd}" >&2' ERR
exec </dev/null

# Debug logging (keep this for now)
echo "=== STARTUP DEBUG ===" >> /tmp/startup_debug.log
echo "Time: $(date)" >> /tmp/startup_debug.log
echo "PID: $$" >> /tmp/startup_debug.log
echo "PPID: $PPID" >> /tmp/startup_debug.log
echo "Parent command: $(ps -p $PPID -o comm=)" >> /tmp/startup_debug.log
echo "Full parent: $(ps -p $PPID -o args=)" >> /tmp/startup_debug.log
echo "===================" >> /tmp/startup_debug.log


# Better xtrace prefix: timestamp + pid + lineno
# export PS4='+ [${EPOCHREALTIME}] pid=$$ line=${LINENO}: '

# Use flock for atomic locking
LOCKFILE="/tmp/startup.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "Startup script already running. Exiting."
    exit 0
fi
echo "Acquired lock on FD200: $(readlink -f /proc/$$/fd/200 || true)"

# Decide mode: first boot vs rehydrate
BOOT_MODE="first"
if [ -f /home/coder/.startup_complete ]; then
  echo "Detected restart; running quick rehydrate."
  BOOT_MODE="rehydrate"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE} Starting Workspace...${NC}"

# Shell cosmetics for better UX
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc || true

# System snapshot for debugging
echo -e "${BLUE}======== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========${NC}"
coder stat || true
echo -e "${BLUE}===============================================================${NC}"

# Create necessary directories, bootstrap, SSH, deps (first boot only)
if [ "$BOOT_MODE" = "first" ]; then
  echo -e "${YELLOW}📁 Creating directory structure...${NC}"
  sudo mkdir -p \
    /home/coder/data/postgres \
    /home/coder/data/pgadmin \
    /home/coder/data/backups \
    /home/coder/data/logs \
    /home/coder/data/pids \
    /home/coder/srv/apps/{a,b,c,d,e} \
    /home/coder/srv/scripts \
    /home/coder/srv/admin \
    /home/coder/srv/docs
  sudo chown -R coder:coder /home/coder/srv /home/coder/data

  echo -e "${YELLOW}📋 Setting up bootstrap files...${NC}"
  if [ ! -f "/home/coder/srv/admin/server.js" ] && [ -d "/opt/bootstrap/srv" ]; then
    cp -r /opt/bootstrap/srv/* /home/coder/srv/ 2>/dev/null || true
  fi
  chmod +x /home/coder/srv/scripts/*.sh 2>/dev/null || true

  echo -e "${YELLOW}🔑 Setting up SSH access...${NC}"
  if [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    echo -e "${GREEN}  ✅ SSH private key configured${NC}"
  fi

  # Seed known_hosts from ALLOWED_REPOS
  if [ -n "${ALLOWED_REPOS:-}" ]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo -e "${YELLOW}  🌐 Seeding SSH known_hosts...${NC}"
    CLEANED=$(echo "$ALLOWED_REPOS" | sed 's/[][]//g' | tr -d '"' | tr ',' '\n')
    echo "$CLEANED" | while read -r entry; do
      entry=$(echo "$entry" | xargs); [ -z "$entry" ] && continue
      if [[ "$entry" =~ ^git@([^:]+): ]]; then host="${BASH_REMATCH[1]}";
      elif [[ "$entry" =~ ^https?://([^/]+)/ ]]; then host="${BASH_REMATCH[1]}";
      elif [[ "$entry" =~ ^[^/]+/[^/]+$ ]]; then host="github.com";
      else continue; fi
      host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
      ssh-keyscan "$host" >> ~/.ssh/known_hosts 2>/dev/null || true
    done
    chmod 644 ~/.ssh/known_hosts 2>/dev/null || true
    echo -e "${GREEN}  ✅ SSH known_hosts configured${NC}"
  fi

  echo -e "${YELLOW}📦 Installing admin dependencies...${NC}"
  cd /home/coder/srv/admin
  if [ ! -d "node_modules" ] && [ -f "package.json" ]; then
    npm install --omit=dev --silent
    echo -e "${GREEN}  ✅ Admin dependencies installed${NC}"
  fi

  # PostgreSQL initdb on first boot only (startup is handled below for both modes)
  echo -e "${BLUE}🐘 Initializing PostgreSQL 17...${NC}"
  if [ ! -f "/home/coder/data/postgres/data/PG_VERSION" ]; then
    echo -e "${YELLOW}  📊 Creating new PostgreSQL database cluster...${NC}"
    sudo install -d -m 0750 -o coder -g coder /home/coder/data/postgres
    /usr/lib/postgresql/17/bin/initdb -D /home/coder/data/postgres/data
    # Ensure socket in /tmp and listen on loopback
    {
      echo "unix_socket_directories = '/tmp'"
      echo "listen_addresses = '127.0.0.1'"
    } >> /home/coder/data/postgres/data/postgresql.conf
    # Ensure TCP auth from localhost
    if ! grep -q '127.0.0.1/32' /home/coder/data/postgres/data/pg_hba.conf; then
      echo "host all all 127.0.0.1/32 scram-sha-256" >> /home/coder/data/postgres/data/pg_hba.conf
    fi
    echo -e "${GREEN}  ✅ PostgreSQL 17 initialized${NC}"
  else
    echo -e "${GREEN}  ✅ PostgreSQL 17 already initialized${NC}"
  fi
fi

# Ensure PostgreSQL running (both modes), then DB/user ensure on first boot
echo -e "${YELLOW}  🚀 Starting PostgreSQL 17 server...${NC}"
mkdir -p /home/coder/data/logs

PGDATA="/home/coder/data/postgres/data"
PGPORT="${PGPORT:-5432}"
PGREADY_HOST="${PGREADY_HOST:-127.0.0.1}"

PGLOG_DIR="/home/coder/data/logs/postgres"
PGLOG="$PGLOG_DIR/postgres.log"
mkdir -p "$PGLOG_DIR"
chown coder:coder "$PGLOG_DIR"

# Fix ownership and permissions for persistent PGDATA tree
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
  /usr/lib/postgresql/17/bin/pg_ctl -D "$PGDATA" -o "-p $PGPORT -k /tmp" -l "$PGLOG" -w -t 20 start
  start_rc=$?
  set -e
  if [ $start_rc -ne 0 ]; then
    echo -e "${YELLOW}  ⚠️  pg_ctl start failed (rc=$start_rc). Tail of log:${NC}"
    tail -n 100 "$PGLOG" || true
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
  # Optional: also create a convenience 'coder' database
  # $PSQL -tc "SELECT 1 FROM pg_database WHERE datname='coder';" | grep -q 1 || \
  #   $PSQL -c "CREATE DATABASE coder OWNER coder;"
  echo -e "${GREEN}  ✅ Workspace database configured${NC}"
fi

# Mark completion on first boot
if [ "$BOOT_MODE" = "first" ]; then
  touch /home/coder/.startup_complete
  echo -e "${GREEN}✅ Startup complete!${NC}"
else
  echo -e "${GREEN}🔁 Quick rehydrate mode${NC}"
fi

exec 200>&-  # Close the lock file descriptor before exiting
exit 0