set -e

# --- Basics / context ---
echo "Public URL: ${PUBLIC_URL}"
echo "Editor URL: ${EDITOR_URL}"
echo "Settings URL: ${SETTINGS_URL}"
echo "PORT is: ${PORT}"

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
sudo mkdir -p "$BASE" && sudo chown -R coder:coder "$BASE"
sudo mkdir -p "$BASE"/{apps,deploy,docs,nginx/conf.d,pm2,webhook}

# Seed from image once
if [ ! -f "$BASE/nginx/nginx.conf" ] && [ -d /opt/bootstrap/srv ]; then
  cp -r /opt/bootstrap/srv/* "$BASE"/
fi

# --- SSH setup for git@ clones (optional) ---
if [ -n "${GIT_SSH_PRIVATE_KEY:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  printf '%s\n' "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
fi
REPO_HOST="$(echo "${GIT_REPO:-}" | sed -E 's#(git@|https?://)([^/:]+).*#\2#')"
[ -n "$REPO_HOST" ] && ssh-keyscan "$REPO_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
chmod 644 ~/.ssh/known_hosts 2>/dev/null || true

# --- Nginx up ---
nginx -t && (nginx -s reload || nginx) || { echo "Nginx config error"; exit 1; }

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
