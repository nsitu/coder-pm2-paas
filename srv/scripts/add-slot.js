#!/usr/bin/env node
/**
 * Add slot to PM2 ecosystem configuration for deployment
 * Usage: node add-slot.js <slot> <appDir> <startCmd> <port> <configFile>
 */

const fs = require('fs');

// Validate arguments
if (process.argv.length < 7) {
    console.error('Usage: node add-slot.js <slot> <appDir> <startCmd> <port> <configFile>');
    process.exit(1);
}

// Get parameters from command line arguments
const slot = process.argv[2];
const appDir = process.argv[3];
const startCmd = process.argv[4];
const port = process.argv[5];
const configFile = process.argv[6];

const ecosystemPath = '/home/coder/ecosystem.config.js';

try {
    // Validate slot name
    if (!/^[a-e]$/.test(slot)) {
        throw new Error(`Invalid slot name: ${slot}. Must be one of: a, b, c, d, e`);
    }

    // Validate app directory exists
    if (!fs.existsSync(appDir)) {
        throw new Error(`App directory not found: ${appDir}`);
    }

    // Read current ecosystem config
    delete require.cache[ecosystemPath];
    const config = require(ecosystemPath);

    // Read slot configuration for user-defined environment variables
    let userEnvVars = {};
    if (fs.existsSync(configFile)) {
        try {
            const slotsConfig = JSON.parse(fs.readFileSync(configFile, 'utf8'));
            userEnvVars = slotsConfig.slots?.[slot]?.environment || {};
        } catch (err) {
            console.warn('Failed to read slot configuration:', err.message);
        }
    }

    // Find or create the slot app configuration
    let slotApp = config.apps.find(app => app.name === `slot-${slot}`);
    if (!slotApp) {
        // Create new slot configuration if it doesn't exist
        slotApp = {
            name: `slot-${slot}`,
            instances: 1,
            autorestart: true,
            watch: false,
            max_restarts: 3,
            error_file: `/home/coder/data/logs/pm2/slot-${slot}-error.log`,
            out_file: `/home/coder/data/logs/pm2/slot-${slot}-out.log`,
            log_file: `/home/coder/data/logs/pm2/slot-${slot}.log`,
            time: true
        };
        config.apps.push(slotApp);
        console.log(`Created new slot configuration for slot-${slot}`);
    }

    // Build environment variables - merge system defaults with user-defined
    const envVars = {
        // System environment variables (always present)
        PORT: port,
        SLOT_NAME: slot,
        NODE_ENV: 'development',
        // User-defined environment variables (override system defaults if conflicts)
        ...userEnvVars
    };

    // Determine the correct script path
    let scriptPath;
    if (startCmd.startsWith('npm ')) {
        // For npm commands, we need to run them from the app directory
        scriptPath = startCmd;
    } else if (startCmd.startsWith('node ')) {
        // For node commands, make sure we have the full path
        const nodeFile = startCmd.replace('node ', '');
        if (nodeFile.startsWith('/')) {
            scriptPath = startCmd; // Already absolute path
        } else {
            scriptPath = `node ${appDir}/${nodeFile}`;
        }
    } else {
        // Default fallback
        scriptPath = startCmd;
    }

    // Update slot configuration to use deployed app
    slotApp.script = scriptPath;
    slotApp.cwd = appDir;
    slotApp.env = envVars;
    slotApp.max_restarts = 3; // Lower restart limit for deployed apps

    // Write updated config
    const output = 'module.exports = ' + JSON.stringify(config, null, 2) + ';';
    fs.writeFileSync(ecosystemPath, output);

    console.log(`Updated ecosystem config for slot ${slot} with deployed app`);
    console.log(`Script: ${scriptPath}`);
    console.log(`CWD: ${appDir}`);
    console.log('Environment variables:', Object.keys(envVars).join(', '));

    process.exit(0);
} catch (error) {
    console.error('Failed to update ecosystem config:', error.message);
    process.exit(1);
}
