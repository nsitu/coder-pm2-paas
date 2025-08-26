# PaaS Enhancement Plan (Final): Static Site Deployment via Slot Web Server

This plan finalizes support for deploying static sites to slots alongside Node.js apps. The existing placeholder server will evolve into a single multi-port Slot Web Server that handles both placeholders and static content per slot.

## Goals

- Each slot can be in one of: empty (placeholder), nodejs (PM2 app), static (served by Slot Web Server).
- Auto-detect static vs nodejs during deployment with a simple heuristic.
- Keep PM2 model unchanged for Node.js apps; serve static sites from single node process running an Express app per slot port.
- Single source of truth: `srv/admin/config/slots.json` with minimal additive fields.

Out of scope (for now)
- SSR frameworks and Next.js (including next export). We will not detect or support Next for this phase.

## Slot configuration schema changes

Add the following fields under each `slots.<slot>` entry in `srv/admin/config/slots.json`:

- type: "placeholder" | "nodejs" | "static" (default inferred from status if missing)
- static_root: absolute path to the folder served when type = "static" (e.g., /home/coder/srv/static/a/current)
- spa_mode: boolean, default true; when true, serve index.html for unknown routes
- last_status_change: ISO timestamp string when status or type changed

We keep existing fields (status, port, restart_policy, build, etc.). Example after a static deploy:

```json
{
  "a": {
    "subdomain": "a",
    "repository": "https://github.com/user/site",
    "branch": "main",
    "environment": {},
    "status": "deployed",
    "type": "static",
    "port": 3001,
    "static_root": "/home/coder/srv/static/a/current",
    "spa_mode": true,
    "last_status_change": "2025-08-26T12:00:00Z",
    "build": { "enabled": true, "command": "npm run build", "cache": true },
    "deployment": { "strategy": "rolling", "backup": true },
    "monitoring": { "enabled": true },
    "created_at": "2025-08-14T15:09:41.946Z",
    "last_deploy": "2025-08-26T12:00:00Z",
    "deploy_count": 1
  }
}
```

Note: If `type` is omitted, the runtime infers `placeholder` when `status` is "empty"/"error", otherwise treats as `nodejs`.

## Utilities (new JS modules)

Create small, reusable Node.js utilities under `srv/scripts/` to standardize JSON IO and detection. All CLIs should be idempotent and exit with non-zero on errors.

1) json-utils.js
- readJson(file): Promise<object> — safe read with JSON.parse and helpful errors
- writeJsonAtomic(file, data): Promise<void> — write to `${file}.tmp` then rename, preserve mode/owner if possible
- updateJsonAtomic(file, mutatorFn): Promise<void> — read-modify-write with atomic rename
- withLock(file, fn, opts?): Promise<any> — create `${file}.lock` (O_EXCL), run fn, finally remove; timeout and retry with backoff

2) slots-config.js
- getSlots(file = slots.json): Promise<{version, slots, ...}>
- setSlot(file, slot, patch): Promise<void> — shallow-merge patch into `slots[slot]` with `last_status_change`
- setSlotStatus(file, slot, status, extra?): Promise<void> — update status/type and `last_status_change`
- getSlotPort(file, slot): Promise<number>

3) site-detect.js
- detectSiteType(cwd): Promise<"static"|"nodejs"> — heuristic:
  - if package.json exists and has a build script, treat as static; else nodejs
  - if no package.json and has index.html or a dist/build/public folder, static; else nodejs
- detectOutputDir(cwd): Promise<string> — first existing in ["dist", "build", "public", "out", "_site"], else cwd if has index.html; else ""
- detectSpa(cwd): Promise<boolean> — true by default; false if there are explicit server-side routes or a 404.html present

4) slots-json-cli.js (optional convenience CLI)
- get/set helpers for admin and scripts: `node slots-json-cli.js get a`, `... set a '{"type":"static"}'`

## Slot Web Server changes (moved to srv/server)

Elevate the placeholder server into a multi-port Slot Web Server that handles both placeholders and static sites, and relocate it to `srv/server` for clarity and maintainability. The `srv/placeholders` directory remains as the source for placeholder assets only.

- Location and entrypoint:
  - New path: `/home/coder/srv/server/server.js`
  - New PM2 app name: `slot-web-server` (renamed from `placeholder-server`)
  - Config path resolution updated to: `/home/coder/srv/admin/config/slots.json`

- Parse `slots.json` and compute the set of ports to manage:
  - Manage ports when status is "empty" or "error" (placeholder mode)
  - Manage ports when type is "static" and status is "deployed" (static mode)
- For each managed port, start an Express app:
  - placeholder mode: serve `/srv/placeholders/slots/<slot>` as before
  - static mode: serve `static_root` with compression, cache headers; SPA fallback if `spa_mode`
- Health endpoint `/health` on all managed ports returns `{status:'healthy', slot, port, type}`
- File watching on `slots.json` triggers reconciliation: start/stop per port
- If a Node app takes the port (EADDRINUSE), log and skip; the Node app owns that port
- Security and perf: `app.disable('x-powered-by')`, `compression()`, `express.static` with dotfiles ignored, immutable cache for fingerprinted assets, no directory listing

Notes on placeholder assets
- Keep generated placeholder pages under `srv/placeholders/slots/<slot>` and shared CSS under `srv/placeholders/public/style.css`. The Slot Web Server will reference these paths when a slot is empty/error.

## Deployment script changes (srv/scripts/slot-deploy.sh)

Add a branch for static sites; reuse current flow for Node.js apps.

- After cloning, call `site-detect.js` from the repo root to get `{type, outputDir, spa}`
- Install dependencies:
  - static: include devDependencies (npm ci/install without `--omit=dev`), then run `npm run build` if present
  - nodejs: production-only install (use `--omit=dev`)
- For static:
  - Detect output directory; validate it contains an `index.html`
  - Sync to `/home/coder/srv/static/<slot>/current` via rsync (atomic by syncing to `tmp` then rename)
  - Ensure no PM2 app is holding the port (stop if exists)
  - Update `slots.json` with `{ type: 'static', status: 'deployed', static_root, spa_mode }`
  - Slot Web Server will pick up and serve it
- For nodejs:
  - Keep existing PM2 behavior

## Path impacts and required updates

This move impacts several files and references. Apply the following changes:

1) PM2 ecosystem config (`ecosystem.config.js`)
- Rename app entry from `placeholder-server` to `slot-web-server`
- Update script path to `/home/coder/srv/server/server.js`
- Update log filenames to `slot-web-server-*.log`

2) Admin backend (`srv/admin/views/server.js`)
- Any code that references or restarts the placeholder server should target the new PM2 name:
  - Replace `pm2 ... placeholder-server` with `pm2 ... slot-web-server`
- Process type detection currently checks `pm2_env.cwd.includes('/placeholders')`; update to detect the slot web server by process name `slot-web-server` or cwd `'/srv/server'`
- No change needed to admin public UI paths, but status labels should include the new `type` when available

3) Helper scripts (`srv/scripts/pm2-helper.sh` and others)
- Update occurrences of `placeholder-server` to `slot-web-server` in stop/restart logic
- Ensure `stop_slot` and related functions do not remove the Slot Web Server; they only stop slot PM2 apps
- `generate-placeholders.js` continues to write to `/home/coder/srv/placeholders`; no path change required

4) Dockerfile
- Ensure the new server folder is copied into the image build context and any local dependencies installed:
  - Add `COPY --chown=coder:coder srv/server/ /opt/bootstrap/srv/server/`
  - Create a minimal `srv/server/package.json` declaring dependencies: `express`, `compression`
  - Run `(cd /opt/bootstrap/srv/server && npm ci || npm install)` during build, or install at startup
- Keep placeholder assets copying as part of `COPY srv/ ...` (already present). Verify that both `srv/server` and `srv/placeholders` are included

5) Slot Web Server internal paths
- Update config path to `/home/coder/srv/admin/config/slots.json`
- Update placeholder assets base to `/home/coder/srv/placeholders`

6) Health checks and ports
- No change to `/health` endpoint paths
- PM2 app for Slot Web Server continues to be single instance; it binds multiple ports internally

7) Logs and observability
- Create pm2 logs under `/home/coder/logs/pm2/slot-web-server-*.log`
- Keep per-slot deployment logs unchanged

## Admin dashboard updates (minimal)

- Show type badge per slot: Empty / Static / Node.js
- Allow manual override to Static or Node.js (optional future step)
- For static slots, show `static_root` and SPA flag

Optional future admin updates
- Add an action to restart the Slot Web Server explicitly (calls `pm2 restart slot-web-server`)

## Detection rules (no SSR/Next in this phase)

We will not attempt to detect or support Next.js or other SSR frameworks in this phase. Static site detection targets:
- Plain HTML/CSS/JS
- Vite / CRA / Angular build artifacts (dist/build/public)
- Gatsby (public) — treated as plain static output

## Edge cases and error handling

- Build fails → set status: "error" and keep previously running app (or placeholder if none)
- `static_root` missing → fall back to placeholder and mark error
- Port conflicts → if EADDRINUSE, assume Node app is running; the web server logs and moves on
- Concurrent edits to `slots.json` → use `json-utils.withLock` for all writers

## Quality gates

- Lint: `node -c` style checks not built-in; basic `node -e 'require("./...")'` sanity during CI
- Unit smoke tests for utils: read/write/update JSON round-trip
- Runtime smoke: deploy a sample static repo to slot A and ensure `/health` and index load

## Rollout steps

1) Add utils: `srv/scripts/utils/json-utils.js`, `srv/scripts/utils/slots-config.js`, `srv/scripts/utils/site-detect.js` (and optional `slots-json-cli.js`)
2) Move server to `srv/server/server.js`, implement static + placeholder mux, update internal paths
3) Update PM2 `ecosystem.config.js` (rename to `slot-web-server`, new script path, logs)
4) Update helper scripts and admin backend references (new PM2 name and detection)
5) Update Dockerfile to copy `srv/server` and install server deps (`express`, `compression`)
6) Update `srv/scripts/slot-deploy.sh` to branch for static vs nodejs
7) Light admin UI tweak to show type/status
8) Verify with a sample static repo and a Node app side-by-side

## Acceptance criteria

- Empty slot serves placeholder on its port
- Deploying a static site updates `slots.json` and serves content on the slot port without PM2 app
- Deploying a Node app preempts the Slot Web Server on that port (via EADDRINUSE) and the app is reachable
- Health checks pass for both static and placeholder modes

## Quick reference: files to touch in this change

- `srv/server/server.js` (new location; refactor from `srv/placeholders/server.js`)
- `srv/placeholders/` (kept for assets; no server code here)
- `ecosystem.config.js` (rename app + path + logs)
- `srv/scripts/pm2-helper.sh` (rename placeholder-server -> slot-web-server)
- `srv/admin/views/server.js` (process detection + optional restart action)
- `Dockerfile` (ensure `srv/server` copied and deps installed)

Notes
- Keep Dockerfile and base image unchanged for this plan. Ensure the deployment path installs devDependencies for static builds (no `--omit=dev`).
