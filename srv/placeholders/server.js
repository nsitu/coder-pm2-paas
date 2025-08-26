const express = require('express');
const path = require('path');
const fs = require('fs');

class MultiPortPlaceholderServer {
    constructor() {
        this.servers = new Map(); // port -> server instance
        this.configPath = path.join(__dirname, '../admin/config/slots.json');
        this.slotsConfig = {};
        this.runningPorts = new Set();
    }

    // Load slots configuration
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

    // Get ports that should show placeholders (empty slots)
    getPlaceholderPorts() {
        const placeholderPorts = [];

        if (this.slotsConfig.slots) {
            Object.entries(this.slotsConfig.slots).forEach(([slotName, config]) => {
                if (config.status === 'empty' || config.status === 'error') {
                    placeholderPorts.push({
                        port: config.port,
                        slot: slotName,
                        status: config.status
                    });
                }
            });
        }

        return placeholderPorts;
    }

    // Create Express app for a specific slot
    createSlotApp(slotName, port) {
        const app = express();

        // Serve slot-specific static assets generated under /srv/placeholders/slots/<slot>
        const slotStaticDir = path.join(__dirname, 'slots', slotName);

        // Static middleware for this slot
        app.use(express.static(slotStaticDir));

        // Main placeholder page: serve slot-specific index.html if present
        app.get('/', (req, res) => {
            const slotIndex = path.join(slotStaticDir, 'index.html');
            if (fs.existsSync(slotIndex)) {
                res.sendFile(slotIndex);
            } else {
                res.status(404).send(`Placeholder assets not found for slot "${slotName}" at ${slotStaticDir}`);
            }
        });

        // Health check endpoint
        app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                slot: slotName,
                port: port,
                timestamp: new Date().toISOString(),
                type: 'placeholder'
            });
        });

        // Catch-all route: serve the same index for simple routing support
        app.get('*', (req, res) => {
            const slotIndex = path.join(slotStaticDir, 'index.html');
            if (fs.existsSync(slotIndex)) {
                res.sendFile(slotIndex);
            } else {
                res.status(404).send(`Placeholder assets not found for slot "${slotName}" at ${slotStaticDir}`);
            }
        });

        return app;
    }

    // Start server on a specific port
    startPlaceholderServer(slotName, port) {
        if (this.servers.has(port)) {
            console.log(`📍 Placeholder already running on port ${port} for slot ${slotName}`);
            return;
        }

        const app = this.createSlotApp(slotName, port);

        const server = app.listen(port, () => {
            console.log(`📍 Placeholder for slot ${slotName} listening on port ${port}`);
        });

        server.on('error', (error) => {
            if (error.code === 'EADDRINUSE') {
                console.log(`🔄 Port ${port} is in use by deployed app (slot ${slotName})`);
            } else {
                console.error(`❌ Error starting placeholder on port ${port}:`, error);
            }
        });

        this.servers.set(port, { server, slotName });
        this.runningPorts.add(port);
    }

    // Stop server on a specific port
    stopPlaceholderServer(port) {
        const serverInfo = this.servers.get(port);
        if (serverInfo) {
            serverInfo.server.close(() => {
                console.log(`🛑 Stopped placeholder for slot ${serverInfo.slotName} on port ${port}`);
            });
            this.servers.delete(port);
            this.runningPorts.delete(port);
        }
    }

    // Update running placeholders based on current config
    updatePlaceholders() {
        this.loadSlotsConfig();
        const placeholderPorts = this.getPlaceholderPorts();
        const neededPorts = new Set(placeholderPorts.map(p => p.port));

        // Stop placeholders that are no longer needed
        for (const [port, serverInfo] of this.servers.entries()) {
            if (!neededPorts.has(port)) {
                console.log(`🔄 Stopping placeholder on port ${port} (slot ${serverInfo.slotName} now has deployed app)`);
                this.stopPlaceholderServer(port);
            }
        }

        // Start placeholders for newly empty slots
        for (const { port, slot } of placeholderPorts) {
            if (!this.servers.has(port)) {
                console.log(`🆕 Starting placeholder on port ${port} for empty slot ${slot}`);
                this.startPlaceholderServer(slot, port);
            }
        }
    }

    // Start initial placeholders and set up monitoring
    async start() {
        console.log('🚀 Starting Multi-Port Placeholder Server');

        this.loadSlotsConfig();
        this.updatePlaceholders();

        // Watch for configuration changes
        if (fs.existsSync(this.configPath)) {
            fs.watchFile(this.configPath, { interval: 1000 }, () => {
                console.log('📋 Configuration changed, updating placeholders...');
                this.updatePlaceholders();
            });
        }

        // Log memory usage periodically
        if (process.env.NODE_ENV !== 'production') {
            setInterval(() => {
                const memUsage = process.memoryUsage();
                const runningCount = this.servers.size;
                console.log(`💾 Memory: ${Math.round(memUsage.heapUsed / 1024 / 1024)}MB heap, ${Math.round(memUsage.rss / 1024 / 1024)}MB RSS (${runningCount} placeholders)`);
            }, 30000);
        }

        console.log(`📍 Multi-port placeholder server started with ${this.servers.size} placeholders`);
        console.log(`💾 Initial memory usage: ~${Math.round(process.memoryUsage().heapUsed / 1024 / 1024)}MB`);
    }

    // Graceful shutdown
    async stop() {
        console.log('🛑 Shutting down Multi-Port Placeholder Server...');

        // Stop all servers
        for (const [port] of this.servers.entries()) {
            this.stopPlaceholderServer(port);
        }

        // Unwatch config file
        if (fs.existsSync(this.configPath)) {
            fs.unwatchFile(this.configPath);
        }

        console.log('✅ Shutdown complete');
    }
}

// Create and start the multi-port server
const placeholderServer = new MultiPortPlaceholderServer();

// Graceful shutdown handlers
process.on('SIGTERM', async () => {
    await placeholderServer.stop();
    process.exit(0);
});

process.on('SIGINT', async () => {
    await placeholderServer.stop();
    process.exit(0);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    console.error('❌ Uncaught Exception:', error);
    placeholderServer.stop().then(() => process.exit(1));
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
    placeholderServer.stop().then(() => process.exit(1));
});

// Start the server
placeholderServer.start().catch(error => {
    console.error('❌ Failed to start placeholder server:', error);
    process.exit(1);
});