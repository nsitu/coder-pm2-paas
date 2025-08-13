#!/usr/bin/env bash
set -euo pipefail

# --- shell cosmetics (optional) ---
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc || true

# --- Demo template ---
GIT_REPO="https://github.com/nsitu/express-hello-world"

# --- snapshot ---
echo "======== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========"
coder stat || true
echo "==============================================================="

# --- persistent base paths ---
BASE="/home/coder/srv"
NGINX_CONF="$BASE/nginx/nginx.conf"
PID="$BASE/nginx/nginx.pid"

# --- create base directories (idempotent) ---
sudo mkdir -p "$BASE" \
  "$BASE/apps" \
  "$BASE/deploy" \
  "$BASE/docs" \
  "$BASE/nginx/conf.d" \
  "$BASE/nginx/tmp/client" "$BASE/nginx/tmp/proxy" "$BASE/nginx/tmp/fastcgi" "$BASE/nginx/tmp/uwsgi" "$BASE/nginx/tmp/scgi" \
  "$BASE/pm2" \
  "$BASE/webhook"
sudo chown -R coder:coder "$BASE"

# --- seed from image once ---
if [ ! -f "$BASE/nginx/nginx.conf" ] && [ -d /opt/bootstrap/srv ]; then
  cp -r /opt/bootstrap/srv/* "$BASE"/
fi

# --- ensure deploy script is executable ---
chmod +x "$BASE/deploy/deploy.sh" || true

# --- webhook deps (express) ---
if [ -f "$BASE/webhook/package.json" ]; then
  (cd "$BASE/webhook" && npm install --omit=dev) || true
fi

# --- SSH for git@ clones (optional) ---
if [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
fi

# Seed known_hosts from ALLOWED_REPOS (JSON array or CSV)
if [ -n "${ALLOWED_REPOS:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  CLEANED=$(echo "$ALLOWED_REPOS" | sed 's/[][]//g' | tr -d '"' | tr ',' '\n')

  echo "$CLEANED" | while read -r entry; do
    entry=$(echo "$entry" | xargs) # trim
    [ -z "$entry" ] && continue

    # Normalize host from: git@host:owner/repo(.git) | https?://host/owner/repo(.git) | owner/repo
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
    echo "Seeding SSH known_hosts for $host"
    ssh-keyscan "$host" >> ~/.ssh/known_hosts 2>/dev/null || true
  done
  chmod 644 ~/.ssh/known_hosts 2>/dev/null || true
fi

# --- nginx up (idempotent, fixes empty/stale PID) ---
if nginx -t -c "$NGINX_CONF" >/dev/null 2>&1; then
  if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload -c "$NGINX_CONF" >/dev/null 2>&1 || nginx -c "$NGINX_CONF" >/dev/null 2>&1
  else
    rm -f "$PID"
    nginx -c "$NGINX_CONF" >/dev/null 2>&1
  fi
else
  echo "Nginx config error"; exit 1
fi

# --- pm2 up & webhook ---
export PM2_HOME="${PM2_HOME:-$BASE/.pm2}"
if [ -f "$PM2_HOME/dump.pm2" ]; then pm2 resurrect >/dev/null 2>&1 || true; fi
if ! pm2 describe webhook >/dev/null 2>&1; then
  pm2 start "$BASE/pm2/ecosystem.config.js" --only webhook >/dev/null 2>&1 || pm2 start "$BASE/pm2/ecosystem.config.js" >/dev/null 2>&1
fi
pm2 save >/dev/null 2>&1 || true

# --- optional first-boot auto-deploy (demo) ---
if [ ! -s "$BASE/deploy/ports.map" ] && [ -n "${GIT_REPO:-}" ]; then
  REPO_NAME="$(basename -s .git "$(echo "$GIT_REPO" | sed 's#.*[:/]\([^/]*\)\.git$#\1#')")"
  "$BASE/deploy/deploy.sh" "$REPO_NAME" "$GIT_REPO" "${DEFAULT_BRANCH:-main}" >/dev/null 2>&1 || echo "initial deploy failed"
  pm2 save >/dev/null 2>&1 || true
fi

echo "Startup complete. Public URL: ${PUBLIC_URL}"
