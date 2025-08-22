/* Simplified placeholder server for slots A–E using a single Express app
 * - Listens on ports 3001–3005 in one process
 * - Detects slot by req.socket.localPort
 * - Renders slot page for any path except /healthz
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

// All other routes → slot placeholder, based on local port
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
