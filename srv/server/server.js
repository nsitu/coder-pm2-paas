const express = require('express');
const path = require('path');
const fs = require('fs');
const compression = require('compression');

class SlotWebServer {
    constructor() {
        this.servers = new Map(); // port -> server instance
        // slots.json lives under admin/config
        this.configPath = path.join(__dirname, '..', 'admin', 'config', 'slots.json');
        // placeholder assets still live under srv/placeholders
        this.placeholderBase = path.join(__dirname, '..', 'placeholders');
        this.slotsConfig = {};
        this.runningPorts = new Set();
    }

    loadSlotsConfig() {
        try {
            const configData = fs.readFileSync(this.configPath, 'utf8');
            this.slotsConfig = JSON.parse(configData);
            console.log('📋 Slots configuration loaded');
        } catch (error) {
            console.error('❌ Failed to load slots configuration:', error);
            process.exit(1);
        }
    }

    // Compute desired servers: placeholder (empty/error) or static (deployed + detected static)
    getManagedEntries() {
        const entries = [];
        const cfg = this.slotsConfig?.slots || {};
        for (const [slotName, slot] of Object.entries(cfg)) {
            const port = slot.port;
            const status = slot.status;
            const type = slot.type || (status === 'empty' || status === 'error' ? 'placeholder' : 'nodejs');
            // Robust static detection: treat as static if explicitly marked OR if a valid static_root exists
            const staticRoot = slot.static_root;
            const hasStaticRoot = staticRoot && fs.existsSync(staticRoot) && fs.existsSync(path.join(staticRoot, 'index.html'));

            if (status === 'empty' || status === 'error') {
                entries.push({ mode: 'placeholder', slot: slotName, port });
            } else if (status === 'deployed' && (type === 'static' || hasStaticRoot)) {
                entries.push({ mode: 'static', slot: slotName, port, staticRoot: staticRoot, spa: !!slot.spa_mode });
            }
        }
        return entries;
    }

    createAppForEntry(entry) {
        const app = express();
        app.disable('x-powered-by');
        app.use(compression());

        if (entry.mode === 'static') {
            const staticRoot = entry.staticRoot;
            if (!staticRoot || !fs.existsSync(staticRoot)) {
                console.warn(`⚠️ Static root missing for slot ${entry.slot}: ${staticRoot}`);
            }

            app.use(express.static(staticRoot, {
                dotfiles: 'ignore',
                index: 'index.html',
                fallthrough: true,
                redirect: false,
                setHeaders: (res, filePath) => {
                    if (/\.(js|mjs|css|png|jpg|jpeg|gif|svg|webp|ico|woff2?|ttf|map)$/i.test(filePath)) {
                        res.setHeader('Cache-Control', 'public, max-age=3600, immutable');
                    } else {
                        res.setHeader('Cache-Control', 'no-cache');
                    }
                }
            }));

            if (entry.spa) {
                app.get('*', (req, res, next) => {
                    const indexPath = path.join(staticRoot, 'index.html');
                    if (fs.existsSync(indexPath)) return res.sendFile(indexPath);
                    return next();
                });
            }
        } else {
            // placeholder mode
            const slotStaticDir = path.join(this.placeholderBase, 'slots', entry.slot);
            app.use(express.static(slotStaticDir));

            app.get('/', (req, res) => {
                const slotIndex = path.join(slotStaticDir, 'index.html');
                if (fs.existsSync(slotIndex)) return res.sendFile(slotIndex);
                res.status(404).send(`Placeholder assets not found for slot "${entry.slot}" at ${slotStaticDir}`);
            });

            app.get('*', (req, res) => {
                const slotIndex = path.join(slotStaticDir, 'index.html');
                if (fs.existsSync(slotIndex)) return res.sendFile(slotIndex);
                res.status(404).send(`Placeholder assets not found for slot "${entry.slot}" at ${slotStaticDir}`);
            });
        }

        app.get('/health', (_req, res) => {
            res.json({ status: 'healthy', slot: entry.slot, port: entry.port, type: entry.mode, timestamp: new Date().toISOString() });
        });

        return app;
    }

    startServer(entry) {
        if (this.servers.has(entry.port)) return;
        const app = this.createAppForEntry(entry);
        const server = app.listen(entry.port, () => {
            console.log(`📍 ${entry.mode === 'static' ? 'Static site' : 'Placeholder'} for slot ${entry.slot} on port ${entry.port}`);
        });
        server.on('error', (error) => {
            if (error.code === 'EADDRINUSE') {
                console.log(`🔄 Port ${entry.port} in use (slot ${entry.slot})`);
            } else {
                console.error(`❌ Error on port ${entry.port}:`, error);
            }
        });
        this.servers.set(entry.port, { server, slotName: entry.slot });
        this.runningPorts.add(entry.port);
    }

    stopServer(port) {
        const info = this.servers.get(port);
        if (!info) return;
        info.server.close(() => {
            console.log(`🛑 Released port ${port} (slot ${info.slotName})`);
        });
        this.servers.delete(port);
        this.runningPorts.delete(port);
    }

    reconcile() {
        this.loadSlotsConfig();
        const desired = this.getManagedEntries();
        const desiredPorts = new Set(desired.map(d => d.port));

        // stop unmanaged
        for (const [port] of this.servers.entries()) {
            if (!desiredPorts.has(port)) this.stopServer(port);
        }

        // start required
        for (const entry of desired) {
            if (!this.servers.has(entry.port)) this.startServer(entry);
        }
    }

    async start() {
        console.log('🚀 Starting Slot Web Server');
        this.reconcile();

        if (fs.existsSync(this.configPath)) {
            fs.watchFile(this.configPath, { interval: 1000 }, () => {
                console.log('📋 Configuration changed, reconciling...');
                this.reconcile();
            });
        }

        if (process.env.NODE_ENV !== 'production') {
            setInterval(() => {
                const mem = process.memoryUsage();
                console.log(`💾 Mem: ${Math.round(mem.heapUsed / 1024 / 1024)}MB heap (${this.servers.size} ports)`);
            }, 30000);
        }

        console.log(`✅ Slot Web Server online; managing ${this.servers.size} port(s)`);
    }

    async stop() {
        console.log('🛑 Stopping Slot Web Server...');
        for (const [port] of this.servers.entries()) this.stopServer(port);
        if (fs.existsSync(this.configPath)) fs.unwatchFile(this.configPath);
        console.log('✅ Shutdown complete');
    }
}

const server = new SlotWebServer();

process.on('SIGTERM', async () => { await server.stop(); process.exit(0); });
process.on('SIGINT', async () => { await server.stop(); process.exit(0); });
process.on('uncaughtException', (err) => { console.error('❌ Uncaught Exception:', err); server.stop().then(() => process.exit(1)); });
process.on('unhandledRejection', (reason, p) => { console.error('❌ Unhandled Rejection at:', p, 'reason:', reason); server.stop().then(() => process.exit(1)); });

server.start().catch(err => { console.error('❌ Failed to start Slot Web Server:', err); process.exit(1); });
