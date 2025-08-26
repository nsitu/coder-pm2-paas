const path = require('path');
const { readJson, writeJsonAtomic, updateJsonAtomic, withLock } = require('./json-utils');

const DEFAULT_CONFIG = '/home/coder/srv/admin/config/slots.json';

async function getSlots(file = DEFAULT_CONFIG) {
    return readJson(file);
}

async function setSlot(file, slot, patch) {
    const ts = new Date().toISOString();
    await withLock(file, async () => {
        await updateJsonAtomic(file, (cfg) => {
            cfg.slots = cfg.slots || {};
            cfg.slots[slot] = { ...(cfg.slots[slot] || {}), ...patch, last_status_change: ts };
            cfg.last_updated = ts;
            return cfg;
        });
    });
}

async function setSlotStatus(file, slot, status, extra = {}) {
    const ts = new Date().toISOString();
    await withLock(file, async () => {
        await updateJsonAtomic(file, (cfg) => {
            cfg.slots = cfg.slots || {};
            const s = cfg.slots[slot] || {};
            s.status = status;
            Object.assign(s, extra);
            s.last_status_change = ts;
            cfg.slots[slot] = s;
            cfg.last_updated = ts;
            return cfg;
        });
    });
}

async function getSlotPort(file, slot) {
    const cfg = await readJson(file);
    return cfg?.slots?.[slot]?.port;
}

module.exports = { DEFAULT_CONFIG, getSlots, setSlot, setSlotStatus, getSlotPort };
