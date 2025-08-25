const express = require('express');
const path = require('path');
const fs = require('fs');
const { spawn, exec } = require('child_process');

const app = express();
const port = 9000;

// Path helper function - works in both local dev and Coder workspace
function getScriptPath(scriptName) {
    // Check if we're in Coder workspace
    if (fs.existsSync('/home/coder/srv/scripts')) {
        return path.join('/home/coder/srv/scripts', scriptName);
    }
    // Local development - relative to admin directory
    return path.join(__dirname, '..', 'scripts', scriptName);
}

// Helper function to restart placeholder server
function restartPlaceholderServer() {
    return new Promise((resolve, reject) => {
        // With PM2 individual placeholders, we just ensure all slot placeholders are running
        exec('pm2 restart slot-a slot-b slot-c slot-d slot-e', (error, stdout, stderr) => {
            if (error) {
                console.error('Failed to restart placeholder slots:', error.message);
                reject(error);
            } else {
                console.log('All placeholder slots restarted successfully');
                resolve(stdout);
            }
        });
    });
}

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static('public'));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Configuration file path
const configPath = path.join(__dirname, 'config', 'slots.json');

// Initialize default configuration if it doesn't exist
function initializeConfig() {
    const defaultConfig = {
        slots: {
            a: {
                subdomain: process.env.SLOT_A_SUBDOMAIN || 'a',
                repository: '',
                branch: 'main',
                environment: {},
                status: 'empty',
                port: 3001
            },
            b: {
                subdomain: process.env.SLOT_B_SUBDOMAIN || 'b',
                repository: '',
                branch: 'main',
                environment: {},
                status: 'empty',
                port: 3002
            },
            c: {
                subdomain: process.env.SLOT_C_SUBDOMAIN || 'c',
                repository: '',
                branch: 'main',
                environment: {},
                status: 'empty',
                port: 3003
            },
            d: {
                subdomain: process.env.SLOT_D_SUBDOMAIN || 'd',
                repository: '',
                branch: 'main',
                environment: {},
                status: 'empty',
                port: 3004
            },
            e: {
                subdomain: process.env.SLOT_E_SUBDOMAIN || 'e',
                repository: '',
                branch: 'main',
                environment: {},
                status: 'empty',
                port: 3005
            }
        }
    };

    if (!fs.existsSync(path.dirname(configPath))) {
        fs.mkdirSync(path.dirname(configPath), { recursive: true });
    }

    if (!fs.existsSync(configPath)) {
        fs.writeFileSync(configPath, JSON.stringify(defaultConfig, null, 2));
    }
}

// Load configuration
function loadConfig() {
    try {
        return JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (error) {
        console.error('Error loading config:', error);
        initializeConfig();
        return JSON.parse(fs.readFileSync(configPath, 'utf8'));
    }
}

// Save configuration
function saveConfig(config) {
    try {
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
        return true;
    } catch (error) {
        console.error('Error saving config:', error);
        return false;
    }
}

// Routes
app.get('/', (req, res) => {
    const config = loadConfig();
    res.render('dashboard', { slots: config.slots });
});

// Slot configuration page
app.get('/config/:slot', (req, res) => {
    const config = loadConfig();
    const slotId = req.params.slot;
    const slot = config.slots[slotId];

    if (!slot) {
        return res.status(404).send('Slot not found');
    }

    res.render('slot-config', { slotId, slot });
});

// Logs page
app.get('/logs/:slot', (req, res) => {
    const slotId = req.params.slot;
    res.render('logs', { slotId });
});

// Helper function to get slot URL from environment variables
function getSlotUrl(slotId, slot) {
    // Use pre-built URLs from Terraform environment variables
    const urlEnvVar = `SLOT_${slotId.toUpperCase()}_URL`;
    return process.env[urlEnvVar] || `http://localhost:${3000 + (slotId.charCodeAt(0) - 96)}`;
}

app.get('/api/slots', (req, res) => {
    const config = loadConfig();

    // Enhance each slot with its properly formed URL
    const enhancedSlots = {};
    Object.entries(config.slots).forEach(([slotId, slot]) => {
        enhancedSlots[slotId] = {
            ...slot,
            url: getSlotUrl(slotId, slot)
        };
    });

    res.json(enhancedSlots);
});

app.get('/api/slots/:slot', (req, res) => {
    const config = loadConfig();
    const slotId = req.params.slot;
    const slot = config.slots[slotId];

    if (!slot) {
        return res.status(404).json({ error: 'Slot not found' });
    }

    // Include the properly formed URL
    const enhancedSlot = {
        ...slot,
        url: getSlotUrl(slotId, slot)
    };

    res.json(enhancedSlot);
});

app.put('/api/slots/:slot', (req, res) => {
    const config = loadConfig();
    const slotId = req.params.slot;

    if (!config.slots[slotId]) {
        return res.status(404).json({ error: 'Slot not found' });
    }

    // Update slot configuration
    const { repository, branch, environment } = req.body;

    if (repository !== undefined) config.slots[slotId].repository = repository;
    if (branch !== undefined) config.slots[slotId].branch = branch;
    if (environment !== undefined) config.slots[slotId].environment = environment;

    if (saveConfig(config)) {
        res.json({ success: true, slot: config.slots[slotId] });
    } else {
        res.status(500).json({ error: 'Failed to save configuration' });
    }
});

app.post('/api/deploy/:slot', (req, res) => {
    const slotId = req.params.slot;
    const config = loadConfig();
    const slot = config.slots[slotId];

    if (!slot || !slot.repository) {
        return res.status(400).json({ error: 'Slot not configured with repository' });
    }

    // Use enhanced deployment script
    const deployScript = getScriptPath('slot-deploy.sh');
    const child = spawn('bash', [deployScript, slotId, slot.repository, slot.branch || 'main'], {
        stdio: 'pipe',
        env: { ...process.env, PATH: process.env.PATH }
    });

    let output = '';
    let error = '';

    child.stdout.on('data', (data) => {
        output += data.toString();
    });

    child.stderr.on('data', (data) => {
        error += data.toString();
        output += data.toString(); // Include stderr in output for debugging
    });

    child.on('close', (code) => {
        if (code === 0) {
            // Update status
            config.slots[slotId].status = 'deployed';
            config.slots[slotId].last_deploy = new Date().toISOString();
            config.slots[slotId].deploy_count = (config.slots[slotId].deploy_count || 0) + 1;
            saveConfig(config);

            res.json({
                success: true,
                message: `Deployment successful for slot ${slotId}`,
                output: output,
                deployment_info: {
                    slot: slotId,
                    repository: slot.repository,
                    branch: slot.branch,
                    port: slot.port,
                    deployed_at: config.slots[slotId].last_deploy
                }
            });
        } else {
            // Update status to error
            config.slots[slotId].status = 'error';
            saveConfig(config);

            res.status(500).json({
                error: `Deployment failed for slot ${slotId}`,
                output: output,
                stderr: error,
                exit_code: code
            });
        }
    });

    child.on('error', (err) => {
        res.status(500).json({
            error: `Failed to start deployment process: ${err.message}`
        });
    });
});

app.post('/api/restart/:slot', (req, res) => {
    const slotId = req.params.slot;
    const config = loadConfig();
    const slot = config.slots[slotId];

    if (!slot) {
        return res.status(404).json({ error: 'Slot not found' });
    }

    exec(`pm2 restart slot-${slotId}`, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: `Failed to restart slot ${slotId}`,
                details: error.message,
                stderr: stderr
            });
        } else {
            res.json({
                success: true,
                message: `Slot ${slotId} restarted successfully`,
                output: stdout
            });
        }
    });
});

app.post('/api/deploy-all', (req, res) => {
    const config = loadConfig();
    const promises = [];

    Object.entries(config.slots).forEach(([slotId, slot]) => {
        if (slot.repository) {
            promises.push(new Promise((resolve) => {
                const deployScript = getScriptPath('slot-deploy.sh');
                const child = spawn('bash', [deployScript, slotId, slot.repository, slot.branch || 'main']);
                child.on('close', (code) => resolve({ slot: slotId, success: code === 0 }));
            }));
        }
    });

    Promise.all(promises).then(results => {
        res.json({
            message: 'Batch deployment completed',
            results: results
        });
    });
});

app.get('/api/logs/:slot', (req, res) => {
    const slotId = req.params.slot;
    const logFile = path.join(__dirname, '../../logs/', `slot-${slotId}.log`);

    try {
        if (fs.existsSync(logFile)) {
            const logs = fs.readFileSync(logFile, 'utf8').split('\n').slice(-100); // Last 100 lines
            res.json({ logs: logs });
        } else {
            res.json({ logs: ['No logs available for this slot yet'] });
        }
    } catch (error) {
        res.status(500).json({ error: 'Failed to read logs' });
    }
});

app.post('/webhook', (req, res) => {
    // Simple webhook handler - match repository to slot and deploy
    const repoUrl = req.body?.repository?.clone_url || req.body?.repository?.html_url;

    if (!repoUrl) {
        return res.status(400).json({ error: 'No repository URL in webhook' });
    }

    const config = loadConfig();

    // Find matching slot
    const matchingSlot = Object.entries(config.slots).find(([_, slot]) =>
        slot.repository === repoUrl || slot.repository === req.body?.repository?.ssh_url
    );

    if (matchingSlot) {
        const [slotId, slot] = matchingSlot;
        const branch = req.body?.ref?.replace('refs/heads/', '') || slot.branch || 'main';

        // Deploy the matching slot using enhanced script
        const deployScript = getScriptPath('slot-deploy.sh');
        const child = spawn('bash', [deployScript, slotId, slot.repository, branch]);

        child.on('close', (code) => {
            console.log(`Webhook deployment for slot ${slotId}: ${code === 0 ? 'success' : 'failed'}`);
        });

        res.json({
            message: `Webhook deployment triggered for slot ${slotId}`,
            repository: repoUrl,
            branch: branch,
            triggered_at: new Date().toISOString()
        });
    } else {
        res.json({
            message: 'No matching slot found for repository',
            repository: repoUrl,
            available_slots: Object.keys(config.slots).filter(key => !config.slots[key].repository)
        });
    }
});

// New API endpoints for enhanced process management

// Get detailed process information
app.get('/api/processes', (req, res) => {
    exec('pm2 jlist', (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: 'Failed to get PM2 processes',
                details: error.message
            });
        } else {
            try {
                const processes = JSON.parse(stdout);

                // Enhance with additional info
                const enhancedProcesses = processes.map(proc => ({
                    name: proc.name,
                    status: proc.pm2_env?.status,
                    cpu: proc.monit?.cpu || 0,
                    memory: proc.monit?.memory || 0,
                    uptime: proc.pm2_env?.pm_uptime,
                    restarts: proc.pm2_env?.restart_time || 0,
                    pid: proc.pid,
                    type: proc.name.startsWith('slot-') ? 'slot' : 'system'
                }));

                res.json({
                    processes: enhancedProcesses,
                    total: processes.length,
                    online: processes.filter(p => p.pm2_env?.status === 'online').length
                });
            } catch (parseError) {
                res.status(500).json({
                    error: 'Failed to parse PM2 output',
                    details: parseError.message
                });
            }
        }
    });
});

// Get detailed information for a specific slot
app.get('/api/processes/:slot', (req, res) => {
    const slotId = req.params.slot;

    exec(`pm2 describe slot-${slotId} --format json`, (error, stdout, stderr) => {
        if (error) {
            return res.status(404).json({ error: 'Slot not found or not running' });
        }

        try {
            const processInfo = JSON.parse(stdout)[0];
            const config = loadConfig();
            const slotConfig = config.slots?.[slotId] || {};

            // Determine if this is a deployed app or placeholder
            const isPlaceholder = processInfo.pm2_env?.cwd?.includes('/placeholders');

            res.json({
                pm2: {
                    name: processInfo.name,
                    status: processInfo.pm2_env?.status,
                    cpu: processInfo.monit?.cpu || 0,
                    memory: processInfo.monit?.memory || 0,
                    uptime: processInfo.pm2_env?.pm_uptime,
                    restarts: processInfo.pm2_env?.restart_time || 0,
                    pid: processInfo.pid
                },
                slot: {
                    repository: slotConfig.repository || null,
                    branch: slotConfig.branch || null,
                    status: slotConfig.status || 'empty',
                    lastDeployment: slotConfig.last_deploy || null,
                    port: processInfo.pm2_env?.env?.PORT
                },
                type: isPlaceholder ? 'placeholder' : 'deployed',
                url: process.env[`SLOT_${slotId.toUpperCase()}_URL`] || `http://localhost:${processInfo.pm2_env?.env?.PORT}`
            });
        } catch (parseError) {
            res.status(500).json({ error: 'Failed to parse PM2 output' });
        }
    });
});

// Stop a specific slot
app.post('/api/processes/:slot/stop', (req, res) => {
    const slotId = req.params.slot;

    // Use the stop_slot helper function to restore placeholder
    exec(`source /home/coder/srv/scripts/pm2-helper.sh && stop_slot ${slotId}`, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: `Failed to stop slot ${slotId}`,
                details: error.message,
                stderr: stderr
            });
        } else {
            // Update slot status
            const config = loadConfig();
            if (config.slots[slotId]) {
                config.slots[slotId].status = 'empty';
                saveConfig(config);
            }

            res.json({
                success: true,
                message: `Slot ${slotId} stopped and restored to placeholder`,
                output: stdout
            });
        }
    });
});

// Get enhanced status information for a specific slot  
app.get('/api/processes/:slot/status', (req, res) => {
    const slotId = req.params.slot;

    exec(`pm2 describe slot-${slotId} --format json`, (error, stdout, stderr) => {
        if (error) {
            return res.status(404).json({ error: 'Slot not found or not running' });
        }

        try {
            const processInfo = JSON.parse(stdout)[0];
            const config = loadConfig();
            const slotConfig = config.slots?.[slotId] || {};

            // Determine if this is a deployed app or placeholder
            const isPlaceholder = processInfo.pm2_env?.cwd?.includes('/placeholders');

            res.json({
                pm2: {
                    name: processInfo.name,
                    status: processInfo.pm2_env?.status,
                    cpu: processInfo.monit?.cpu || 0,
                    memory: processInfo.monit?.memory || 0,
                    uptime: processInfo.pm2_env?.pm_uptime,
                    restarts: processInfo.pm2_env?.restart_time || 0,
                    pid: processInfo.pid
                },
                slot: {
                    repository: slotConfig.repository || null,
                    branch: slotConfig.branch || null,
                    status: slotConfig.status || 'empty',
                    lastDeployment: slotConfig.last_deploy || null,
                    port: processInfo.pm2_env?.env?.PORT
                },
                type: isPlaceholder ? 'placeholder' : 'deployed',
                url: process.env[`SLOT_${slotId.toUpperCase()}_URL`] || `http://localhost:${processInfo.pm2_env?.env?.PORT}`
            });
        } catch (parseError) {
            res.status(500).json({ error: 'Failed to parse PM2 output' });
        }
    });
});

// Get deployment history and statistics
app.get('/api/deployments/history', (req, res) => {
    const config = loadConfig();
    const history = [];

    Object.entries(config.slots).forEach(([slotId, slot]) => {
        if (slot.last_deploy) {
            history.push({
                slot: slotId,
                repository: slot.repository,
                branch: slot.branch,
                status: slot.status,
                deployed_at: slot.last_deploy,
                deploy_count: slot.deploy_count || 0
            });
        }
    });

    // Sort by deployment time, most recent first
    history.sort((a, b) => new Date(b.deployed_at) - new Date(a.deployed_at));

    res.json({
        deployments: history,
        total_deployments: history.reduce((sum, dep) => sum + dep.deploy_count, 0),
        active_slots: history.filter(dep => dep.status === 'deployed').length,
        last_deployment: history[0]?.deployed_at || null
    });
});

// Bulk operations
app.post('/api/deploy-all', (req, res) => {
    const config = loadConfig();
    const deployments = [];

    Object.entries(config.slots).forEach(([slotId, slot]) => {
        if (slot.repository) {
            deployments.push({
                slot: slotId,
                repository: slot.repository,
                branch: slot.branch || 'main'
            });
        }
    });

    if (deployments.length === 0) {
        return res.json({
            message: 'No slots configured for deployment',
            results: []
        });
    }

    const results = [];
    let completed = 0;

    deployments.forEach(({ slot, repository, branch }) => {
        const deployScript = getScriptPath('slot-deploy.sh');
        const child = spawn('bash', [deployScript, slot, repository, branch]);

        child.on('close', (code) => {
            results.push({
                slot,
                success: code === 0,
                repository,
                branch
            });
            completed++;

            if (completed === deployments.length) {
                const successCount = results.filter(r => r.success).length;
                res.json({
                    message: `Batch deployment completed: ${successCount}/${deployments.length} successful`,
                    results: results,
                    summary: {
                        total: deployments.length,
                        successful: successCount,
                        failed: deployments.length - successCount
                    }
                });
            }
        });
    });
});

// Initialize configuration on startup
initializeConfig();

app.listen(port, '0.0.0.0', () => {
    console.log(`⚙️ Admin panel listening on port ${port}`);
});