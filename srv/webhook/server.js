// /home/coder/srv/webhook/server.js
const express = require('express');
const { spawn } = require('child_process');

const app = express();
app.use(express.json({ type: '*/*' })); // GitHub sends various content-types

// ---------- helpers: parse + normalize ----------
function splitEnvList(raw) {
    if (!raw || typeof raw !== 'string') return [];
    // Try JSON first
    try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) return parsed.map(String);
    } catch {/* fall through */ }
    // CSV / newline fallback (mirrors Bash sed/tr transformations)
    return raw
        .replace(/^\s*\[/, '').replace(/\]\s*$/, '') // strip brackets if present
        .replace(/"/g, '')
        .split(/[, \n\r]+/) // commas or whitespace/newlines
        .map(s => s.trim())
        .filter(Boolean);
}

// Normalize any of: git@host:owner/repo(.git), https?://host/owner/repo(.git), owner/repo
// -> canonical: https://host/owner/repo  (owner/repo lowercased, host lowercased, no .git, no trailing slash)
function normalizeEntry(entry) {
    if (!entry || typeof entry !== 'string') return null;
    const s = entry.trim();

    // SSH form
    let m = s.match(/^git@([^:]+):([^/]+)\/([^/]+?)(?:\.git)?\/?$/i);
    if (m) {
        const host = m[1].toLowerCase();
        const owner = m[2].toLowerCase();
        const repo = m[3].replace(/\.git$/i, '').toLowerCase();
        return `https://${host}/${owner}/${repo}`;
    }

    // HTTP(S) form
    try {
        const u = new URL(s);
        const host = u.host.toLowerCase();
        const parts = u.pathname.replace(/\/+$/, '').split('/').filter(Boolean);
        if (parts.length >= 2) {
            const owner = parts[0].toLowerCase();
            const repo = parts[1].replace(/\.git$/i, '').toLowerCase();
            return `https://${host}/${owner}/${repo}`;
        }
    } catch {/* not a URL */ }

    // owner/repo short form -> assume github.com
    if (/^[^/\s]+\/[^/\s]+$/.test(s)) {
        const [owner, repoRaw] = s.split('/');
        const ownerLC = owner.toLowerCase();
        const repoLC = repoRaw.replace(/\.git$/i, '').toLowerCase();
        return `https://github.com/${ownerLC}/${repoLC}`;
    }

    return null;
}

// Build canonical from any GitHub push payload
function canonicalFromPayload(body) {
    const tryFields = [
        body?.repository?.html_url,
        body?.repository?.clone_url,
        body?.repository?.ssh_url,
        body?.repository?.full_name, // owner/repo
    ];
    for (const v of tryFields) {
        const canon = normalizeEntry(v);
        if (canon) return canon;
    }
    return null;
}

// ---------- config ----------
const RAW_ALLOWED = splitEnvList(process.env.ALLOWED_REPOS || '');
const ALLOWED_REPOS = Array.from(
    new Set(RAW_ALLOWED.map(normalizeEntry).filter(Boolean))
);

const DEPLOY = process.env.DEPLOY_SCRIPT || '/home/coder/srv/deploy/deploy.sh';
const DEPLOYED_SHAS = new Set(); // per-process de-dupe

console.log("Allowed repos (normalized):", ALLOWED_REPOS);

// ---------- deploy runner with per-repo lock ----------
function runDeploy(repoName, gitUrl, branch) {
    return new Promise((resolve, reject) => {
        const lock = spawn('bash', ['-lc', `
      set -e
      LOCK="/tmp/deploy_${repoName}.lock"
      exec 9>"$LOCK"
      flock -n 9 || { echo "busy"; exit 99; }
      "${DEPLOY}" "${repoName}" "${gitUrl}" "${branch}"
    `], { stdio: ['ignore', 'pipe', 'pipe'] });

        let out = '', err = '';
        lock.stdout.on('data', d => out += d.toString());
        lock.stderr.on('data', d => err += d.toString());
        lock.on('close', code => {
            if (code === 0) resolve(out || 'ok');
            else if (code === 99) reject(new Error('deploy-in-progress'));
            else reject(new Error(err || `deploy failed (${code})`));
        });
    });
}

// ---------- webhook ----------
app.post('/webhook/github', async (req, res) => {
    try {
        const event = req.get('x-github-event');
        if (event !== 'push') return res.status(202).json({ status: `ignored:${event}` });

        const canonical = canonicalFromPayload(req.body);
        const branchRef = req.body?.ref;                     // "refs/heads/main"
        const branch = branchRef ? branchRef.replace(/^refs\/heads\//, '') : 'main';
        const afterSha = req.body?.after;

        if (!canonical || !afterSha) {
            return res.status(400).json({ error: 'missing repo or sha' });
        }

        // Allowlist check (if empty, allow all for PoC)
        if (ALLOWED_REPOS.length && !ALLOWED_REPOS.includes(canonical)) {
            return res.status(403).json({ error: 'repo not allowed', repo: canonical });
        }

        if (DEPLOYED_SHAS.has(afterSha)) {
            return res.status(202).json({ status: 'ignored:duplicate' });
        }

        // Extract owner/repo from canonical for naming + SSH clone URL
        const u = new URL(canonical);
        const [owner, repo] = u.pathname.replace(/^\//, '').split('/');
        const repoName = repo;
        const gitUrl = `git@${u.host}:${owner}/${repo}.git`;

        await runDeploy(repoName, gitUrl, branch);
        DEPLOYED_SHAS.add(afterSha);
        return res.json({ status: 'deployed', repo: repoName, host: u.host, branch, sha: afterSha });
    } catch (e) {
        const code = e.message === 'deploy-in-progress' ? 429 : 500;
        return res.status(code).json({ error: e.message });
    }
});

const port = process.env.WEBHOOK_PORT || 4600;
app.listen(port, '127.0.0.1', () => {
    console.log(`webhook listening on ${port}`);
});
