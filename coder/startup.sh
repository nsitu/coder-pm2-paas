#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Coder PM2 PaaS Workspace...${NC}"

# Shell cosmetics for better UX
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc || true

# System snapshot for debugging
echo -e "${BLUE}======== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========${NC}"
coder stat || true
echo -e "${BLUE}===============================================================${NC}"

# Create necessary directories
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

# Copy bootstrap files (idempotent)
echo -e "${YELLOW}📋 Setting up bootstrap files...${NC}"
if [ ! -f "/home/coder/srv/admin/server.js" ] && [ -d "/opt/bootstrap/srv" ]; then
  cp -r /opt/bootstrap/srv/* /home/coder/srv/ 2>/dev/null || true
fi
chmod +x /home/coder/srv/scripts/*.sh 2>/dev/null || true

# SSH setup for private repositories
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
  
  # Parse ALLOWED_REPOS (JSON array or CSV)
  CLEANED=$(echo "$ALLOWED_REPOS" | sed 's/[][]//g' | tr -d '"' | tr ',' '\n')
  
  echo "$CLEANED" | while read -r entry; do
    entry=$(echo "$entry" | xargs) # trim whitespace
    [ -z "$entry" ] && continue

    # Extract host from different URL formats
    if [[ "$entry" =~ ^git@([^:]+): ]]; then
      host="${BASH_REMATCH[1]}"
    elif [[ "$entry" =~ ^https?://([^/]+)/ ]]; then
      host="${BASH_REMATCH[1]}"
    elif [[ "$entry" =~ ^[^/]+/[^/]+$ ]]; then
      host="github.com"
    else
      continue
    fi
    
    host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
    echo -e "${YELLOW}    📡 Adding $host to known_hosts${NC}"
    ssh-keyscan "$host" >> ~/.ssh/known_hosts 2>/dev/null || true
  done
  
  chmod 644 ~/.ssh/known_hosts 2>/dev/null || true
  echo -e "${GREEN}  ✅ SSH known_hosts configured${NC}"
fi

# Install admin dependencies (idempotent)
echo -e "${YELLOW}📦 Installing admin dependencies...${NC}"
cd /home/coder/srv/admin
if [ ! -d "node_modules" ] && [ -f "package.json" ]; then
  npm install --omit=dev --silent
  echo -e "${GREEN}  ✅ Admin dependencies installed${NC}"
fi

# Initialize PostgreSQL (idempotent)
echo -e "${BLUE}🐘 Initializing PostgreSQL 17...${NC}"
if [ ! -d "/home/coder/data/postgres/data" ]; then
  echo -e "${YELLOW}  📊 Creating new PostgreSQL database cluster...${NC}"
  sudo -u postgres /usr/lib/postgresql/17/bin/initdb -D /home/coder/data/postgres/data
  sudo chown -R coder:coder /home/coder/data/postgres
  echo -e "${GREEN}  ✅ PostgreSQL 17 initialized${NC}"
else
  echo -e "${GREEN}  ✅ PostgreSQL 17 already initialized${NC}"
fi

# Start PostgreSQL (idempotent)
echo -e "${YELLOW}  🚀 Starting PostgreSQL 17 server...${NC}"
if ! pgrep -f "postgres.*5432" > /dev/null; then
  sudo -u postgres /usr/lib/postgresql/17/bin/postgres -D /home/coder/data/postgres/data -p 5432 &
  POSTGRES_PID=$!
  echo $POSTGRES_PID > /home/coder/data/pids/postgres.pid
  echo -e "${GREEN}  ✅ PostgreSQL 17 started with PID: $POSTGRES_PID${NC}"
  
  # Wait for PostgreSQL to be ready
  echo -e "${YELLOW}  ⏳ Waiting for PostgreSQL to be ready...${NC}"
  for i in {1..30}; do
    if sudo -u postgres /usr/lib/postgresql/17/bin/psql -lqt > /dev/null 2>&1; then
      echo -e "${GREEN}  ✅ PostgreSQL 17 is ready!${NC}"
      break
    fi
    sleep 1
  done
  
  # Create workspace database and user (idempotent)
  echo -e "${YELLOW}  👤 Setting up workspace database...${NC}"
  sudo -u postgres /usr/lib/postgresql/17/bin/psql -c "CREATE USER coder WITH PASSWORD 'coder_dev_password';" 2>/dev/null || true
  sudo -u postgres /usr/lib/postgresql/17/bin/psql -c "CREATE DATABASE workspace_db OWNER coder;" 2>/dev/null || true
  sudo -u postgres /usr/lib/postgresql/17/bin/psql -c "GRANT ALL PRIVILEGES ON DATABASE workspace_db TO coder;" 2>/dev/null || true
  echo -e "${GREEN}  ✅ Workspace database configured${NC}"
else
  echo -e "${GREEN}  ✅ PostgreSQL already running${NC}"
fi

# Start PGAdmin4 (idempotent)
echo -e "${BLUE}🔧 Starting PGAdmin4...${NC}"
if ! pgrep -f "pgadmin4" > /dev/null; then
  export PGADMIN_DEFAULT_EMAIL="admin@localhost"
  export PGADMIN_DEFAULT_PASSWORD="admin123" 
  export PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION="False"
  export PGADMIN_LISTEN_PORT=5050
  export PGADMIN_LISTEN_ADDRESS="0.0.0.0"

  pgadmin4 &
  PGADMIN_PID=$!
  echo $PGADMIN_PID > /home/coder/data/pids/pgadmin.pid
  echo -e "${GREEN}✅ PGAdmin4 started with PID: $PGADMIN_PID${NC}"
else
  echo -e "${GREEN}✅ PGAdmin4 already running${NC}"
fi

# Start main documentation server (idempotent)
echo -e "${BLUE}📖 Starting main documentation server...${NC}"
if ! pgrep -f "python3.*8080" > /dev/null; then
  cd /home/coder/srv/docs
  python3 -m http.server 8080 &
  DOCS_PID=$!
  echo $DOCS_PID > /home/coder/data/pids/docs.pid
  echo -e "${GREEN}✅ Documentation server started with PID: $DOCS_PID${NC}"
else
  echo -e "${GREEN}✅ Documentation server already running${NC}"
fi

# Start admin application (idempotent)
echo -e "${BLUE}⚙️ Starting admin application...${NC}"
if ! pgrep -f "node.*server.js" > /dev/null; then
  cd /home/coder/srv/admin
  node server.js &
  ADMIN_PID=$!
  echo $ADMIN_PID > /home/coder/data/pids/admin.pid
  echo -e "${GREEN}✅ Admin application started with PID: $ADMIN_PID${NC}"
else
  echo -e "${GREEN}✅ Admin application already running${NC}"
fi

# Start default slot servers (placeholder documentation) - idempotent
echo -e "${BLUE}🎰 Starting slot placeholder servers...${NC}"
cd /home/coder/srv/docs

for slot in {1..5}; do
  port=$((3000 + slot))
  slot_name=$(echo "abcde" | cut -c$slot)
  
  if ! pgrep -f "python3.*$port" > /dev/null; then
    python3 -m http.server $port &
    SLOT_PID=$!
    echo $SLOT_PID > /home/coder/data/pids/slot_${slot_name}.pid
    echo -e "${GREEN}✅ Slot ${slot_name^^} placeholder started with PID: $SLOT_PID${NC}"
  else
    echo -e "${GREEN}✅ Slot ${slot_name^^} already running${NC}"
  fi
done

# Health check script setup
echo -e "${BLUE}🏥 Setting up health monitoring...${NC}"
if [ -f "/home/coder/srv/scripts/health-check.sh" ]; then
  cp /home/coder/srv/scripts/health-check.sh /home/coder/data/health-check.sh
  chmod +x /home/coder/data/health-check.sh
  echo -e "${GREEN}✅ Health monitoring configured${NC}"
fi

# Wait for services to stabilize
echo -e "${YELLOW}⏳ Allowing services to stabilize...${NC}"
sleep 3

# Run initial health check
echo -e "${BLUE}🔍 Running initial health check...${NC}"
/home/coder/data/health-check.sh 2>/dev/null || echo -e "${YELLOW}Health check script not available${NC}"

# Create convenience aliases (idempotent)
if ! grep -q "health-check" ~/.bashrc 2>/dev/null; then
  echo 'alias health-check="/home/coder/data/health-check.sh"' >> ~/.bashrc
  echo 'alias admin-logs="tail -f /home/coder/data/logs/admin.log"' >> ~/.bashrc
  echo 'alias slot-status="ps aux | grep -E \"(node|python3).*30[0-9][0-9]\""' >> ~/.bashrc
  echo -e "${GREEN}✅ Convenience aliases added${NC}"
fi

echo
echo -e "${GREEN}🎉 Coder PM2 PaaS Workspace is ready!${NC}"
echo -e "${BLUE}📋 Available Commands:${NC}"
echo -e "  ${YELLOW}health-check${NC} - Run system health check"
echo -e "  ${YELLOW}admin-logs${NC} - View admin application logs"  
echo -e "  ${YELLOW}slot-status${NC} - Check slot process status"
echo -e "  ${YELLOW}cd ~/srv/scripts && ./slot-deploy.sh${NC} - Manual deployment"
echo
echo -e "${BLUE}🌐 Access URLs:${NC}"
echo -e "  ${YELLOW}Main: ${PUBLIC_URL:-https://public--workspace--user.domain}${NC}"
echo -e "  ${YELLOW}Admin: https://admin--workspace--user.domain${NC}"
echo -e "  ${YELLOW}PGAdmin: https://pgadmin--workspace--user.domain${NC}"
echo

echo -e "${GREEN}✅ Startup complete! All services are running.${NC}"