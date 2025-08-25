#!/usr/bin/env node
/**
 * Remove slot from PM2 ecosystem configuration (multi-port placeholder will handle empty slots)
 * Usage: node remove-slot.js <slot> <port>
 */

const fs = require('fs');

// Validate arguments
if (process.argv.length < 4) {
    console.error('Usage: node remove-slot.js <slot> <port>');
    process.exit(1);
}

// Get parameters from command line arguments
const slot = process.argv[2];
const port = process.argv[3];

const ecosystemPath = '/home/coder/ecosystem.config.js';

try {
    // Validate slot name
    if (!/^[a-e]$/.test(slot)) {
        throw new Error(`Invalid slot name: ${slot}. Must be one of: a, b, c, d, e`);
    }

    // Validate ecosystem config exists
    if (!fs.existsSync(ecosystemPath)) {
        console.log(`Ecosystem config not found: ${ecosystemPath} - nothing to clean up`);
        process.exit(0);
    }

    // Read current ecosystem config
    delete require.cache[ecosystemPath];
    const config = require(ecosystemPath);

    // Find and remove the slot app configuration
    const slotIndex = config.apps.findIndex(app => app.name === `slot-${slot}`);
    if (slotIndex >= 0) {
        config.apps.splice(slotIndex, 1);

        // Write updated config
        const output = 'module.exports = ' + JSON.stringify(config, null, 2) + ';';
        fs.writeFileSync(ecosystemPath, output);

        console.log(`Removed slot-${slot} from PM2 ecosystem (will be handled by multi-port placeholder)`);
    } else {
        console.log(`Slot ${slot} not found in ecosystem config - already clean`);
    }

    process.exit(0);
} catch (error) {
    console.error('Failed to remove slot from ecosystem config:', error.message);
    process.exit(1);
}
