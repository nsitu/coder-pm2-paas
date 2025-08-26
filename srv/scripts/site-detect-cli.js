#!/usr/bin/env node
const path = require('path');
const { detectSiteType, detectOutputDir, detectSpa } = require('./utils/site-detect');

async function main() {
    const cwd = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
    const type = await detectSiteType(cwd);
    const outputDir = await detectOutputDir(cwd);
    const spa = await detectSpa(outputDir || cwd);
    process.stdout.write(JSON.stringify({ type, outputDir, spa }));
}

main().catch((err) => { console.error(err); process.exit(1); });
