#!/usr/bin/env bash
# /home/coder/srv/deploy/deploy.sh
set -euo pipefail

REPO_NAME="${1:?repo name required}"
GIT_URL="${2:?git url required}"
BRANCH="${3:-main}"

BASE="/home/coder/srv"
APPS_DIR="$BASE/apps"
PORTS_FILE="$BASE/deploy/ports.map"

NGINX_CONF_DIR="$BASE/nginx/conf.d"
NGINX_MAIN="$BASE/nginx/nginx.conf"
NGINX_PID_FILE="$BASE/nginx/nginx.pid"

PM2_DIR="$BASE/.pm2"
ECOSYSTEM="$BASE/pm2/ecosystem.config.js"
ECOSYSTEM_HELPER="$BASE/pm2/update-ecosystem.js"

LOG_DIR="$BASE/logs"
NGINX_DEPLOY_LOG="$LOG_DIR/nginx-deploy.log"
PM2_DEPLOY_LOG="$LOG_DIR/pm2-deploy.log"

mkdir -p "$APPS_DIR" "$NGINX_CONF_DIR" "$BASE/docs" "$LOG_DIR" "$PM2_DIR"
: > "$PORTS_FILE"   # ensure file exists (no-op if already exists)
touch "$ECOSYSTEM"  # ensure ecosystem exists (helper will populate)
APP_DIR="${APPS_DIR}/${REPO_NAME}"

# ---------- stable port per app ----------
get_port () {
  if grep -q "^${REPO_NAME}:" "$PORTS_FILE"; then
    awk -F: -v app="$REPO_NAME" '$1==app{print $2}' "$PORTS_FILE"
  else
    local PORT=3001
    while lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1 || grep -q ":$PORT$" "$PORTS_FILE"; do
      PORT=$((PORT+1))
    done
    echo "${REPO_NAME}:$PORT" >> "$PORTS_FILE"
    echo "$PORT"
  fi
}
PORT="$(get_port)"
BASE_PATH="/${REPO_NAME}"

# ---------- checkout/update ----------
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch origin "$BRANCH" --depth=1
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" --depth=1 "$GIT_URL" "$APP_DIR"
fi

# ---------- install & optional build ----------
if [ -f "$APP_DIR/package.json" ]; then
  cd "$APP_DIR"
  if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    npm ci --omit=dev || npm ci || npm install --omit=dev
  else
    npm install --omit=dev
  fi
  if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
    npm run build
  fi
fi

# ---------- write nginx location ----------
cat > "${NGINX_CONF_DIR}/${REPO_NAME}.conf" <<EOF
location ^~ ${BASE_PATH}/ {
  proxy_http_version 1.1;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection \$connection_upgrade;
  proxy_set_header X-Forwarded-Prefix ${BASE_PATH};
  proxy_set_header X-Forwarded-Host \$host;
  rewrite ^${BASE_PATH}/(.*)\$ /\$1 break;
  proxy_pass http://127.0.0.1:${PORT};
}
EOF

# ---------- update PM2 ecosystem  ----------
# Requires $ECOSYSTEM_HELPER to exist (srv/pm2/update-ecosystem.js).
NODE_ECOSYSTEM="$ECOSYSTEM" \
REPO_NAME="$REPO_NAME" \
APP_DIR="$APP_DIR" \
PORT="$PORT" \
node "$ECOSYSTEM_HELPER"

# ---------- reload nginx using workspace config (idempotent) ----------
if nginx -t -c "$NGINX_MAIN" >>"$NGINX_DEPLOY_LOG" 2>&1; then
  if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload >>"$NGINX_DEPLOY_LOG" 2>&1 || {
      echo "nginx reload failed; attempting reopen" >>"$NGINX_DEPLOY_LOG"
      nginx -s reopen >>"$NGINX_DEPLOY_LOG" 2>&1 || true
    }
  else
    rm -f "$NGINX_PID_FILE"
    nginx -c "$NGINX_MAIN" >>"$NGINX_DEPLOY_LOG" 2>&1
  fi
else
  echo "Nginx config test failed. See $NGINX_DEPLOY_LOG" >&2
  exit 1
fi

# ---------- pm2 start/reload app ----------
export PM2_HOME="${PM2_HOME:-$PM2_DIR}"
pm2 startOrReload "$ECOSYSTEM" --only "$REPO_NAME" >>"$PM2_DEPLOY_LOG" 2>&1 \
  || pm2 start "$ECOSYSTEM" --only "$REPO_NAME" >>"$PM2_DEPLOY_LOG" 2>&1
pm2 save >>"$PM2_DEPLOY_LOG" 2>&1 || true

echo "Deployed ${REPO_NAME} on port ${PORT} at base path ${BASE_PATH}"
