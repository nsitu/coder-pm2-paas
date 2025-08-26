#!/usr/bin/env node
/**
 * Update slot fields in slots.json atomically.
 * Usage examples:
 *   node update-slot.js --slot a --status deployed --last-deploy now --inc-deploy-count
 *   node update-slot.js --slot b --type static --static-root /path --spa-mode true
 *   node update-slot.js --slot c --status empty
 */

const path = require('path');
const fs = require('fs');
const { readJson, writeJsonAtomic, updateJsonAtomic, withLock } = require('./utils/json-utils');

function parseArgs(argv) {
    const args = {};
    for (let i = 2; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--inc-deploy-count') {
            args.incDeployCount = true;
            continue;
        }
        if (a.startsWith('--')) {
            const key = a.slice(2);
            const val = argv[i + 1];
            if (val === undefined || val.startsWith('--')) {
                throw new Error(`Missing value for ${a}`);
            }
            args[key.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = val;
            i++;
        }
    }
    return args;
}

function toBool(v) {
    if (typeof v === 'boolean') return v;
    if (v === undefined) return undefined;
    const s = String(v).toLowerCase();
    if (s === 'true') return true;
    if (s === 'false') return false;
    return undefined;
}

async function ensureConfig(file) {
    if (!fs.existsSync(file)) {
        const dir = path.dirname(file);
        await fs.promises.mkdir(dir, { recursive: true });
        await writeJsonAtomic(file, { slots: {} });
    }
}

async function main() {
    const args = parseArgs(process.argv);
    const slot = args.slot;
    if (!slot || !/^[a-e]$/.test(slot)) {
        console.error('Error: --slot is required and must be one of a-e');
        process.exit(1);
    }

    const config = args.config || '/home/coder/srv/admin/config/slots.json';
    await ensureConfig(config);

    // Build patch
    const patch = {};
    if (args.status) patch.status = args.status;
    if (args.type) patch.type = args.type;
    if (args.staticRoot) patch.static_root = args.staticRoot;
    const spa = toBool(args.spaMode);
    if (typeof spa === 'boolean') patch.spa_mode = spa;
    if (args.port) patch.port = Number(args.port);
    if (args.lastDeploy) {
        patch.last_deploy = args.lastDeploy === 'now' ? new Date().toISOString() : args.lastDeploy;
    } else if (args.status) {
        // When status changes and lastDeploy not set explicitly, set it to now
        patch.last_deploy = new Date().toISOString();
    }

    await withLock(config, async () => {
        await updateJsonAtomic(config, (cfg) => {
            cfg.slots = cfg.slots || {};
            const s = cfg.slots[slot] || {};
            // Merge fields
            Object.assign(s, patch);
            if (args.incDeployCount) {
                s.deploy_count = (s.deploy_count || 0) + 1;
            }
            cfg.slots[slot] = s;
            cfg.last_updated = new Date().toISOString();
            return cfg;
        });
    });

    process.exit(0);
}

main().catch((err) => { console.error(err.message || String(err)); process.exit(1); });
