# /home/coder/srv/deploy/deploy.sh
#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="${1:?repo name required}"
GIT_URL="${2:?git url required}"
BRANCH="${3:-main}"
BASE_PATH="/${REPO_NAME}"
BASE="/home/coder/srv"
APPS_DIR="$BASE/apps"
PORTS_FILE="$BASE/deploy/ports.map"
NGINX_CONF_DIR="$BASE/nginx/conf.d"
ECOSYSTEM="$BASE/pm2/ecosystem.config.js"

mkdir -p "$APPS_DIR" "$NGINX_CONF_DIR" "$BASE/docs"
touch "$PORTS_FILE" "$ECOSYSTEM"

APP_DIR="${APPS_DIR}/${REPO_NAME}"

# allocate a stable port per app
get_port () {
  if grep -q "^${REPO_NAME}:" "$PORTS_FILE"; then
    awk -F: -v app="$REPO_NAME" '$1==app{print $2}' "$PORTS_FILE"
  else
    PORT=3001
    while lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1 || grep -q ":$PORT$" "$PORTS_FILE"; do
      PORT=$((PORT+1))
    done
    echo "${REPO_NAME}:$PORT" >> "$PORTS_FILE"
    echo "$PORT"
  fi
}
PORT="$(get_port)"

# checkout/update
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch origin "$BRANCH" --depth=1
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" --depth=1 "$GIT_URL" "$APP_DIR"
fi

# install & build
if [ -f "$APP_DIR/package.json" ]; then
  cd "$APP_DIR"
  npm ci --omit=dev || npm install --omit=dev
  if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
    npm run build
  fi
fi

# nginx location
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

# ensure pm2 app entry exists/updated (pass path via env explicitly)
NODE_ECOSYSTEM="$ECOSYSTEM" node - <<'EOF'
const fs = require('fs');
const path = process.env.NODE_ECOSYSTEM || '/home/coder/srv/pm2/ecosystem.config.js';
let mod = { apps: [] };
if (fs.existsSync(path)) { mod = require(path); }
mod.apps = (mod.apps || []).filter(a => a.name !== "__REPO__");
mod.apps.push({
  name: "__REPO__",
  script: "npm",
  args: "start",
  cwd: "__CWD__",
  env: { PORT: "__PORT__", BASE_PATH: "/__REPO__" },
  max_memory_restart: "250M",
  instances: 1,
  exec_mode: "fork",
  restart_delay: 2000
});
fs.writeFileSync(path, "module.exports=" + JSON.stringify(mod, null, 2));
EOF
# replace placeholders
sed -i "s#__REPO__#${REPO_NAME}#g;s#__CWD__#${APP_DIR}#g;s#__PORT__#${PORT}#g" "$ECOSYSTEM"

# reload services
nginx -t
nginx -s reload || nginx -s reopen

pm2 start "$ECOSYSTEM"
pm2 reload "${REPO_NAME}" || true
pm2 save
