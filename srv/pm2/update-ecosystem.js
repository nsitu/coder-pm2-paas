// /home/coder/srv/pm2/update-ecosystem.js
const fs = require('fs');

const path = process.env.NODE_ECOSYSTEM || '/home/coder/srv/pm2/ecosystem.config.js';
const name = process.env.REPO_NAME;
const cwd = process.env.APP_DIR;
const port = String(process.env.PORT || '3000');
const base = `/${name}`;

if (!name || !cwd) {
    console.error('Missing REPO_NAME or APP_DIR');
    process.exit(2);
}

let mod = { apps: [] };
if (fs.existsSync(path)) {
    try {
        mod = require(path);
    } catch {
        mod = { apps: [] }; // tolerate corrupt/empty file and rebuild
    }
}
if (!Array.isArray(mod.apps)) mod.apps = [];

mod.apps = mod.apps.filter(a => a && a.name !== name);
mod.apps.push({
    name: name,
    script: "npm",
    args: "start",
    cwd: cwd,
    env: { PORT: port, BASE_PATH: base },
    max_memory_restart: "250M",
    instances: 1,
    exec_mode: "fork",
    restart_delay: 2000
});

fs.writeFileSync(path, "module.exports=" + JSON.stringify(mod, null, 2));
