set -e
 
# Shell cosmetics
echo 'export PS1="\[\033[01;34m\]\w\[\033[00m\] $ "' >> ~/.bashrc

# Optional template fallback
if [ "${CODE_TEMPLATE:-}" = "default" ]; then
  GIT_REPO="https://bender.sheridanc.on.ca/sikkemha/html-css-js"
fi

# Snapshot
echo "======== System Snapshot $(date '+%a %b %d %Y, %I:%M%p') ========"
coder stat || true
echo "==============================================================="

# --- Persistent base path for everything ---
BASE="/home/coder/srv"
NGINX_CONF="$BASE/nginx/nginx.conf"

# Create base directories if they don't exist
sudo mkdir -p "$BASE" "$BASE"/{apps,deploy,docs,nginx/conf.d,pm2,webhook}
sudo mkdir -p "$BASE"/nginx/tmp/{client,proxy,fastcgi,uwsgi,scgi}
sudo chown -R coder:coder "$BASE"


# Seed from image once
if [ ! -f "$BASE/nginx/nginx.conf" ] && [ -d /opt/bootstrap/srv ]; then
  cp -r /opt/bootstrap/srv/* "$BASE"/
fi

# --- Install Express for webhook ---
cd "$BASE/webhook"
npm install --omit=dev

# --- SSH setup for git@ clones (optional) ---
if [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
fi

# Seed known_hosts from ALLOWED_REPOS (JSON array or CSV)
if [ -n "${ALLOWED_REPOS:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh

  # Remove wrapping brackets/quotes if JSON
  CLEANED=$(echo "$ALLOWED_REPOS" | sed 's/[][]//g' | tr -d '"' | tr ',' '\n')

  echo "$CLEANED" | while read -r entry; do
    entry=$(echo "$entry" | xargs) # trim
    [ -z "$entry" ] && continue

    # Normalize forms: git@host:owner/repo.git, https://host/owner/repo, owner/repo
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

# --- Nginx up ---
nginx -t -c "$NGINX_CONF" \
  && (nginx -s reload -c "$NGINX_CONF" || nginx -c "$NGINX_CONF") \
  || { echo "Nginx config error"; exit 1; }

# --- PM2 up & webhook ---
export PM2_HOME="${PM2_HOME:-$BASE/.pm2}"
if [ -f "$PM2_HOME/dump.pm2" ]; then pm2 resurrect || true; fi
if ! pm2 describe webhook >/dev/null 2>&1; then
  pm2 start "$BASE/pm2/ecosystem.config.js" --only webhook || pm2 start "$BASE/pm2/ecosystem.config.js"
fi
pm2 save || true

# --- Optional first-boot auto-deploy (demo) ---
if [ ! -s "$BASE/deploy/ports.map" ] && [ -n "${GIT_REPO:-}" ]; then
  REPO_NAME="$(basename -s .git "$(echo "$GIT_REPO" | sed 's#.*[:/]\([^/]*\)\.git$#\1#')")"
  "$BASE/deploy/deploy.sh" "$REPO_NAME" "$GIT_REPO" "${DEFAULT_BRANCH:-main}" || echo "initial deploy failed"
  pm2 save || true
fi

echo "Startup complete. Public URL: ${PUBLIC_URL}"
