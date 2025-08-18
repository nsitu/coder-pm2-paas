/* Dynamic placeholder server for slots A–E using a single Express app
 * - Listens on ports 3001–3005 in one process
 * - Detects slot by req.socket.localPort
 * - Renders overview at '/' and slot page for any other path
 * - ADMIN_URL from env or derived from Host; fallback http://localhost:9000
 * - SLOT_[A–E]_SUBDOMAIN env vars with defaults a–e
 */

const http = require('http');
const express = require('express');

const SLOTS = [
    { letter: 'A', port: 3001, env: 'SLOT_A_SUBDOMAIN', defaultSub: 'a' },
    { letter: 'B', port: 3002, env: 'SLOT_B_SUBDOMAIN', defaultSub: 'b' },
    { letter: 'C', port: 3003, env: 'SLOT_C_SUBDOMAIN', defaultSub: 'c' },
    { letter: 'D', port: 3004, env: 'SLOT_D_SUBDOMAIN', defaultSub: 'd' },
    { letter: 'E', port: 3005, env: 'SLOT_E_SUBDOMAIN', defaultSub: 'e' },
];

const slotByPort = new Map(SLOTS.map((s) => [s.port, s]));
const subdomains = Object.fromEntries(
    SLOTS.map((s) => [s.letter, process.env[s.env] || s.defaultSub])
);

function deriveAdminUrl(req) {
    if (process.env.ADMIN_URL) return process.env.ADMIN_URL;
    const host = (req.headers.host || '').split(':')[0];
    // Derive admin URL for Coder-style multi-subdomain: sub--workspace--user.domain
    if (host.includes('--')) {
        const parts = host.split('--');
        if (parts.length >= 3) {
            return `https://admin--${parts.slice(1).join('--')}`;
        }
    }
    return 'http://localhost:9000';
}

function indexHtml(adminUrl) {
    return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Slot Overview</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;margin:0;padding:20px;background:#f8f9fa;}
.container{max-width:800px;margin:0 auto;background:white;padding:40px;border-radius:12px;box-shadow:0 4px 6px rgba(0,0,0,.1);} 
h1{color:#2c3e50;margin-bottom:10px;}
.subtitle{color:#7f8c8d;font-size:1.2em;margin-bottom:30px;}
.slots-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:30px 0;}
.slot-card{background:#f8f9fa;padding:20px;border-radius:8px;text-align:center;border:2px solid #e9ecef;transition:all .3s ease;}
.slot-card:hover{border-color:#3498db;transform:translateY(-2px);} 
.slot-card a{text-decoration:none;color:#2c3e50;}
.admin-link{display:inline-block;background:#3498db;color:white;padding:12px 24px;text-decoration:none;border-radius:6px;margin:20px 0;}
.admin-link:hover{background:#2980b9;}
</style></head>
<body><div class="container">
<h1>NodeJS App Server</h1>
<p class="subtitle">Platform for Node.js Applications</p>
<a href="${adminUrl}" class="admin-link">🔧 Open Admin Panel</a>
<h2>Available Deployment Slots</h2>
<div class="slots-grid">
${SLOTS.map(
        (s) => `
  <div class="slot-card">
    <a href="http://localhost:${s.port}">
      <h3>🎰 Slot ${s.letter}</h3>
      <p>Port ${s.port}</p>
    </a>
  </div>`
    ).join('')}
</div>
</div></body></html>`;
}

function slotHtml(slot, adminUrl) {
    const sub = subdomains[slot.letter];
    return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Slot ${slot.letter} - Empty</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;margin:0;padding:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;}
.container{text-align:center;padding:40px;background:rgba(255,255,255,.1);border-radius:20px;backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,.2);max-width:500px;}
.slot-icon{font-size:4rem;margin-bottom:20px;opacity:.8;}
h1{margin:0 0 10px 0;font-size:2.5rem;font-weight:300;}
.subtitle{opacity:.8;margin-bottom:30px;font-size:1.1rem;}
.admin-link{display:inline-block;background:rgba(255,255,255,.2);color:white;text-decoration:none;padding:15px 30px;border-radius:50px;border:1px solid rgba(255,255,255,.3);transition:all .3s ease;font-weight:500;}
.admin-link:hover{background:rgba(255,255,255,.3);transform:translateY(-2px);} 
.slot-info{margin-top:30px;padding:20px;background:rgba(0,0,0,.2);border-radius:10px;font-size:.9rem;opacity:.9;}
</style></head>
<body><div class="container">
<div class="slot-icon">🎰</div>
<h1>Slot ${slot.letter}</h1>
<p class="subtitle">This slot is currently empty</p>
<a href="${adminUrl}" class="admin-link">🔧 Configure & Deploy</a>
<div class="slot-info">
<strong>Port:</strong> ${slot.port}<br>
<strong>Status:</strong> Available for deployment<br>
<strong>Subdomain:</strong> ${sub}
</div>
</div></body></html>`;
}

const app = express();

// Health for probes
app.get('/healthz', (_req, res) => res.status(200).send('ok'));

// Overview on root for every port
app.get('/', (req, res) => {
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.send(indexHtml(deriveAdminUrl(req)));
});

// Everything else → slot placeholder, based on local port
app.get('*', (req, res) => {
    const port = req.socket.localPort;
    const slot = slotByPort.get(port);
    res.set('Content-Type', 'text/html; charset=utf-8');
    if (!slot) return res.status(404).send('Unknown slot');
    res.send(slotHtml(slot, deriveAdminUrl(req)));
});

// Start one process listening on all placeholder ports
SLOTS.forEach(({ port }) => {
    const server = http.createServer(app);
    server.on('error', (err) => {
        if (err && err.code === 'EADDRINUSE') {
            console.error(`[placeholders] Port ${port} in use; skipping`);
        } else {
            console.error(`[placeholders] Error on port ${port}:`, err);
        }
    });
    server.listen(port, '0.0.0.0', () => {
        console.log(`[placeholders] Listening on ${port}`);
    });
});
