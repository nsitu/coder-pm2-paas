#!/usr/bin/env node
/**
 * Generate slot-specific placeholder files using JavaScript template literals
 * Uses Terraform environment variables for slot URLs
 */

const fs = require('fs');
const path = require('path');

// Configuration
const PLACEHOLDERS_DIR = '/home/coder/srv/placeholders';
const SLOTS_DIR = path.join(PLACEHOLDERS_DIR, 'slots');
const SHARED_CSS_PATH = path.join(PLACEHOLDERS_DIR, 'public', 'style.css');

// Ensure directories exist
function ensureDirectories() {
    if (!fs.existsSync(SLOTS_DIR)) {
        fs.mkdirSync(SLOTS_DIR, { recursive: true });
    }
}

// Generate HTML using template literals
function generateSlotHTML(slotName, slotUrl, adminUrl, port) {
    const timestamp = new Date().toISOString();

    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Slot ${slotName.toUpperCase()} - Ready for Deployment</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <h1 class="slot-name">Slot ${slotName.toUpperCase()}</h1>
        <p class="status">This slot is ready for deployment</p>
        <p>Deploy your Node.js application to this slot to make it accessible.</p>

        <div class="url-info">
            <p><strong>This slot will be available at:</strong></p>
            <p><a href="${slotUrl}" target="_blank">${slotUrl}</a></p>
        </div>

        <a href="${adminUrl}" class="deploy-btn">Configure & Deploy Application</a>
         
    </div>

    <!-- Health check endpoint simulation -->
    <script>
        // Provide a simple way to verify the placeholder is working
        if (window.location.pathname === '/health') {
            document.body.innerHTML = JSON.stringify({
                status: 'healthy',
                slot: '${slotName}',
                port: ${port},
                type: 'placeholder',
                timestamp: new Date().toISOString()
            }, null, 2);
            document.body.style.fontFamily = 'monospace';
            document.body.style.whiteSpace = 'pre';
        }
    </script>
</body>
</html>`;
}

// Generate placeholder for a specific slot
function generateSlotPlaceholder(slot) {
    const slotUpper = slot.toUpperCase();
    const port = 3000 + (slot.charCodeAt(0) - 96); // a=1, b=2, etc.

    // Get URLs from environment variables set by Terraform
    const slotUrlVar = `SLOT_${slotUpper}_URL`;
    const slotUrl = process.env[slotUrlVar] || `http://localhost:${port}`;
    const adminUrl = process.env.ADMIN_URL || 'http://localhost:9000';

    // Create slot directory
    const slotDir = path.join(SLOTS_DIR, slot);
    if (!fs.existsSync(slotDir)) {
        fs.mkdirSync(slotDir, { recursive: true });
    }

    // Generate HTML file
    const htmlContent = generateSlotHTML(slot, slotUrl, adminUrl, port);
    const htmlPath = path.join(slotDir, 'index.html');
    fs.writeFileSync(htmlPath, htmlContent, 'utf8');

    // Copy CSS file
    if (fs.existsSync(SHARED_CSS_PATH)) {
        const cssDestPath = path.join(slotDir, 'style.css');
        fs.copyFileSync(SHARED_CSS_PATH, cssDestPath);
    } else {
        console.warn(`Shared CSS file not found: ${SHARED_CSS_PATH}`);
        // Create a basic CSS file as fallback
        const basicCSS = createBasicCSS();
        fs.writeFileSync(path.join(slotDir, 'style.css'), basicCSS, 'utf8');
    }

    console.log(`Generated placeholder for slot ${slot}: ${htmlPath}`);
    return htmlPath;
}

// Create basic CSS if shared CSS is not available
function createBasicCSS() {
    return `body {
    font-family: system-ui, -apple-system, sans-serif;
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem;
    text-align: center;
    background: #f8f9fa;
}

.container {
    background: white;
    padding: 3rem;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

.slot-name {
    color: #0066cc;
    font-size: 2.5rem;
    margin-bottom: 1rem;
}

.status {
    color: #666;
    font-size: 1.2rem;
    margin-bottom: 2rem;
}

.deploy-btn {
    display: inline-block;
    background: #0066cc;
    color: white;
    padding: 1rem 2rem;
    text-decoration: none;
    border-radius: 5px;
    font-weight: 500;
    transition: background 0.2s;
}

.deploy-btn:hover {
    background: #0052a3;
}

.info {
    margin-top: 2rem;
    color: #666;
    font-size: 0.9rem;
}

.url-info {
    background: #f8f9fa;
    padding: 1rem;
    border-radius: 5px;
    margin: 1rem 0;
}

.url-info a {
    color: #0066cc;
    text-decoration: none;
}

.url-info a:hover {
    text-decoration: underline;
}`;
}

// Generate placeholders for all slots
function generateAllPlaceholders() {
    console.log('Generating placeholder files from Terraform environment variables...');

    ensureDirectories();

    const slots = ['a', 'b', 'c', 'd', 'e'];
    const results = [];

    for (const slot of slots) {
        try {
            const htmlPath = generateSlotPlaceholder(slot);
            results.push({ slot, success: true, path: htmlPath });
        } catch (error) {
            console.error(`Failed to generate placeholder for slot ${slot}:`, error.message);
            results.push({ slot, success: false, error: error.message });
        }
    }

    // Summary
    const successful = results.filter(r => r.success).length;
    const failed = results.length - successful;

    console.log(`Placeholder generation complete: ${successful} successful, ${failed} failed`);

    if (failed > 0) {
        console.error('Failed slots:', results.filter(r => !r.success).map(r => r.slot).join(', '));
        process.exit(1);
    }

    return results;
}

// Clean up generated placeholders
function cleanPlaceholders() {
    console.log('Cleaning up generated placeholder files...');

    if (fs.existsSync(SLOTS_DIR)) {
        fs.rmSync(SLOTS_DIR, { recursive: true, force: true });
        console.log('Placeholder files cleaned');
    } else {
        console.log('No placeholder files to clean');
    }
}

// Show current placeholder status
function showStatus() {
    console.log('Placeholder Generation Status:');
    console.log(`Output Directory: ${SLOTS_DIR}`);
    console.log(`Shared CSS: ${SHARED_CSS_PATH}`);
    console.log('');

    if (fs.existsSync(SLOTS_DIR)) {
        const slots = fs.readdirSync(SLOTS_DIR, { withFileTypes: true })
            .filter(dirent => dirent.isDirectory())
            .map(dirent => dirent.name)
            .sort();

        if (slots.length > 0) {
            console.log('Generated Slots:');
            for (const slot of slots) {
                const htmlFile = path.join(SLOTS_DIR, slot, 'index.html');
                if (fs.existsSync(htmlFile)) {
                    const stats = fs.statSync(htmlFile);
                    console.log(`  Slot ${slot}: ${htmlFile} (Modified: ${stats.mtime.toISOString()})`);
                } else {
                    console.log(`  Slot ${slot}: Missing index.html`);
                }
            }
        } else {
            console.log('No generated slots found');
        }
    } else {
        console.log('Slots directory does not exist');
    }

    console.log('');
    console.log('Environment Variables:');
    ['SLOT_A_URL', 'SLOT_B_URL', 'SLOT_C_URL', 'SLOT_D_URL', 'SLOT_E_URL', 'ADMIN_URL'].forEach(envVar => {
        const value = process.env[envVar];
        console.log(`  ${envVar}: ${value || '(not set)'}`);
    });
}

// Main command handling
function main() {
    const command = process.argv[2] || 'help';

    switch (command) {
        case 'generate':
            generateAllPlaceholders();
            break;

        case 'generate-slot':
            const slot = process.argv[3];
            if (!slot || !/^[a-e]$/.test(slot)) {
                console.error('Usage: node generate-placeholders.js generate-slot <slot>');
                console.error('Slot must be one of: a, b, c, d, e');
                process.exit(1);
            }
            generateSlotPlaceholder(slot);
            break;

        case 'clean':
            cleanPlaceholders();
            break;

        case 'status':
            showStatus();
            break;

        default:
            console.log('Usage: node generate-placeholders.js {generate|generate-slot|clean|status}');
            console.log('');
            console.log('Commands:');
            console.log('  generate      - Generate placeholder files for all slots');
            console.log('  generate-slot - Generate placeholder for specific slot');
            console.log('  clean         - Remove all generated placeholder files');
            console.log('  status        - Show current placeholder generation status');
            console.log('');
            console.log('Environment Variables Used:');
            console.log('  SLOT_A_URL, SLOT_B_URL, SLOT_C_URL, SLOT_D_URL, SLOT_E_URL');
            console.log('  ADMIN_URL');
            process.exit(command === 'help' ? 0 : 1);
    }
}

// Handle errors gracefully
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error.message);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    process.exit(1);
});

// Run main function
if (require.main === module) {
    main();
}

module.exports = {
    generateAllPlaceholders,
    generateSlotPlaceholder,
    cleanPlaceholders,
    showStatus
};
