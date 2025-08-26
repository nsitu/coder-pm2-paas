const fs = require('fs');
const path = require('path');

function fileExists(p) { try { return fs.existsSync(p); } catch { return false; } }

function hasBuildScript(pkg) { return !!(pkg.scripts && pkg.scripts.build); }

async function detectSiteType(cwd) {
    const pkgPath = path.join(cwd, 'package.json');
    if (fileExists(pkgPath)) {
        try {
            const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
            if (hasBuildScript(pkg)) return 'static';
            return 'nodejs';
        } catch {
            // fall through
        }
    } else {
        if (fileExists(path.join(cwd, 'index.html'))) return 'static';
        for (const d of ['dist', 'build', 'public', 'out', '_site']) {
            if (fileExists(path.join(cwd, d))) return 'static';
        }
    }
    return 'nodejs';
}

async function detectOutputDir(cwd) {
    for (const d of ['dist', 'build', 'public', 'out', '_site']) {
        if (fileExists(path.join(cwd, d))) return path.join(cwd, d);
    }
    if (fileExists(path.join(cwd, 'index.html'))) return cwd;
    return '';
}

async function detectSpa(cwd) {
    // default to SPA true unless 404.html exists (some static sites rely on 404 handling instead)
    return !fileExists(path.join(cwd, '404.html'));
}

module.exports = { detectSiteType, detectOutputDir, detectSpa };
