#!/usr/bin/env bash
# Simple deployment script - no PM2 or NGINX needed
set -euo pipefail

SLOT="${1:?slot name required (a-e)}"
REPO_URL="${2:?git url required}"
BRANCH="${3:-main}"

BASE="/home/harold/coder-pm2-paas/srv"
DATA_DIR="/home/harold/coder-pm2-paas/data"
APP_DIR="$BASE/apps/$SLOT"
CONFIG_FILE="$BASE/admin/config/slots.json"

# Port mapping: a=3001, b=3002, c=3003, d=3004, e=3005
PORT=$((3000 + $(echo "$SLOT" | tr 'abcde' '12345')))

echo "🚀 Deploying slot $SLOT on port $PORT"

# Stop existing process if running
echo "🛑 Stopping existing app..."
pkill -f "PORT=$PORT" 2>/dev/null || true
sleep 2

# Clone or update repository
echo "📥 Fetching code..."
if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  git fetch origin "$BRANCH" --depth=1
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  rm -rf "$APP_DIR"
  git clone --branch "$BRANCH" --depth=1 "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

# Install dependencies
echo "📦 Installing dependencies..."
if [ -f package.json ]; then
  if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    npm ci --omit=dev || npm install --omit=dev
  else
    npm install --omit=dev
  fi
  
  # Run build script if it exists
  if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
    echo "🔨 Building application..."
    npm run build
  fi
else
  echo "⚠️ No package.json found"
fi

# Load environment variables from config
ENV_VARS=""
if [ -f "$CONFIG_FILE" ]; then
  # Extract environment variables from slot config
  ENV_JSON=$(jq -r ".slots.$SLOT.environment // {}" "$CONFIG_FILE" 2>/dev/null || echo "{}")
  if [ "$ENV_JSON" != "{}" ]; then
    ENV_VARS=$(echo "$ENV_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | tr '\n' ' ')
  fi
fi

# Start the application
echo "🚀 Starting application..."
if [ -f package.json ] && jq -e '.scripts.start' package.json >/dev/null 2>&1; then
  # Use npm start if available
  env PORT=$PORT \
      SLOT_NAME=$SLOT \
      DATABASE_URL="postgresql://coder:coder_dev_password@localhost:5432/workspace_db" \
      POSTGRES_HOST=localhost \
      POSTGRES_PORT=5432 \
      POSTGRES_DB=workspace_db \
      POSTGRES_USER=coder \
      POSTGRES_PASSWORD=coder_dev_password \
      NODE_ENV=development \
      $ENV_VARS \
      nohup npm start > "$DATA_DIR/logs/slot-$SLOT.log" 2>&1 &
else
  # Try to find main file
  MAIN_FILE="index.js"
  if [ -f package.json ]; then
    MAIN_FILE=$(jq -r '.main // "index.js"' package.json)
  fi
  
  if [ ! -f "$MAIN_FILE" ] && [ -f "app.js" ]; then
    MAIN_FILE="app.js"
  elif [ ! -f "$MAIN_FILE" ] && [ -f "server.js" ]; then
    MAIN_FILE="server.js"
  fi
  
  if [ -f "$MAIN_FILE" ]; then
    env PORT=$PORT \
        SLOT_NAME=$SLOT \
        DATABASE_URL="postgresql://coder:coder_dev_password@localhost:5432/workspace_db" \
        POSTGRES_HOST=localhost \
        POSTGRES_PORT=5432 \
        POSTGRES_DB=workspace_db \
        POSTGRES_USER=coder \
        POSTGRES_PASSWORD=coder_dev_password \
        NODE_ENV=development \
        $ENV_VARS \
        nohup node "$MAIN_FILE" > "$DATA_DIR/logs/slot-$SLOT.log" 2>&1 &
  else
    echo "❌ No startable file found (index.js, app.js, server.js, or npm start script)"
    exit 1
  fi
fi

# Wait a moment and check if it started
sleep 3
if curl -s "http://localhost:$PORT/health" >/dev/null 2>&1 || curl -s "http://localhost:$PORT/" >/dev/null 2>&1; then
  echo "✅ Deployment successful!"
  echo "🌐 App running on port $PORT"
  
  # Update status in config if possible
  if [ -f "$CONFIG_FILE" ]; then
    jq ".slots.$SLOT.status = \"deployed\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" 2>/dev/null || true
  fi
else
  echo "❌ Application failed to start - check logs: $DATA_DIR/logs/slot-$SLOT.log"
  exit 1
fi
