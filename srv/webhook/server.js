// /home/coder/srv/webhook/server.js
const express = require('express');
const { spawn } = require('child_process');

const app = express();
app.use(express.json({ type: '*/*' })); // GitHub sends various content-types

// Keep a simple allowlist so random repos can't deploy your box during PoC
const ALLOWED_REPOS = JSON.parse(process.env.ALLOWED_REPOS || '[]'); // ["owner/repo"]
const DEPLOY = process.env.DEPLOY_SCRIPT || '/home/coder/srv/deploy/deploy.sh';
const DEPLOYED_SHAS = new Set(); // de-dupe pushes

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

app.post('/webhook/github', async (req, res) => {
    try {
        // No signature verification; accept only "push" for PoC
        const event = req.get('x-github-event');
        if (event !== 'push') return res.status(202).json({ status: `ignored:${event}` });

        const repoFull = req.body?.repository?.full_name;   // "owner/repo"
        const branchRef = req.body?.ref;                     // "refs/heads/main"
        const afterSha = req.body?.after;
        if (!repoFull || !branchRef || !afterSha)
            return res.status(400).json({ error: 'missing fields' });

        if (ALLOWED_REPOS.length && !ALLOWED_REPOS.includes(repoFull))
            return res.status(403).json({ error: 'repo not allowed' });

        if (DEPLOYED_SHAS.has(afterSha))
            return res.status(202).json({ status: 'ignored:duplicate' });

        const repoName = repoFull.split('/')[1];
        const branch = branchRef.replace('refs/heads/', '');
        const gitUrl = `git@github.com:${repoFull}.git`;

        await runDeploy(repoName, gitUrl, branch);
        DEPLOYED_SHAS.add(afterSha);
        return res.json({ status: 'deployed', repo: repoName, branch, sha: afterSha });
    } catch (e) {
        const code = e.message === 'deploy-in-progress' ? 429 : 500;
        return res.status(code).json({ error: e.message });
    }
});

const port = process.env.WEBHOOK_PORT || 4600;
app.listen(port, '127.0.0.1', () => {
    console.log(`webhook listening on ${port}`);
});
