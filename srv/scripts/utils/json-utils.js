const fs = require('fs');
const path = require('path');

async function readJson(file) {
    try {
        const data = await fs.promises.readFile(file, 'utf8');
        return JSON.parse(data);
    } catch (err) {
        err.message = `readJson(${file}): ${err.message}`;
        throw err;
    }
}

async function writeJsonAtomic(file, obj) {
    const dir = path.dirname(file);
    await fs.promises.mkdir(dir, { recursive: true });
    const tmp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`);
    const data = JSON.stringify(obj, null, 2);
    await fs.promises.writeFile(tmp, data, 'utf8');
    await fs.promises.rename(tmp, file);
}

async function updateJsonAtomic(file, mutator) {
    const current = await readJson(file);
    const updated = await mutator(current);
    await writeJsonAtomic(file, updated);
}

async function withLock(file, fn, { retries = 30, delayMs = 100 } = {}) {
    const lock = `${file}.lock`;
    let attempt = 0;
    while (attempt < retries) {
        try {
            const fd = fs.openSync(lock, 'wx');
            try {
                const res = await fn();
                return res;
            } finally {
                try { fs.closeSync(fd); } catch { }
                try { fs.unlinkSync(lock); } catch { }
            }
        } catch (e) {
            await new Promise(r => setTimeout(r, delayMs));
            attempt++;
        }
    }
    throw new Error(`withLock: failed to acquire lock ${lock}`);
}

module.exports = { readJson, writeJsonAtomic, updateJsonAtomic, withLock };
