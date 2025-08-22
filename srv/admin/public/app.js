// Admin Panel JavaScript
class AdminPanel {
    constructor() {
        this.currentTab = 'dashboard';
        this.loadingStates = new Set();
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadSlotConfigurations();
        this.initializeTabs();
    }

    setupEventListeners() {
        // Tab navigation
        document.querySelectorAll('.nav-tab').forEach(tab => {
            tab.addEventListener('click', (e) => {
                this.switchTab(e.target.dataset.tab);
            });
        });

        // Auto-save form changes
        document.addEventListener('input', (e) => {
            if (e.target.closest('.slot-form')) {
                this.debounce(() => {
                    const slotId = e.target.closest('.slot-card').dataset.slot;
                    this.autoSaveSlot(slotId);
                }, 1000)();
            }
        });

        // Global keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey || e.metaKey) {
                switch (e.key) {
                    case 's':
                        e.preventDefault();
                        this.saveAllSlots();
                        break;
                    case 'd':
                        e.preventDefault();
                        this.deployAll();
                        break;
                }
            }
        });
    }

    // Tab Management
    initializeTabs() {
        this.switchTab('dashboard');
    }

    switchTab(tabName) {
        // Update nav tabs
        document.querySelectorAll('.nav-tab').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

        // Update tab content
        document.querySelectorAll('.tab-content').forEach(content => {
            content.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`).classList.add('active');

        this.currentTab = tabName;

        // Load tab-specific data
        switch (tabName) {
            case 'dashboard':
                this.loadSlotConfigurations();
                break;
            case 'logs':
                this.loadLogsView();
                break;
            case 'settings':
                this.loadSettings();
                break;
        }
    }

    // Configuration Management
    async loadSlotConfigurations() {
        try {
            const response = await fetch('/api/slots');
            const slots = await response.json();
            this.renderSlots(slots);
        } catch (error) {
            this.showAlert('Error loading slot configurations: ' + error.message, 'danger');
        }
    }

    renderSlots(slots) {
        const container = document.getElementById('slots-container');
        if (!container) return;

        container.innerHTML = '';

        Object.entries(slots).forEach(([slotId, slot]) => {
            const slotCard = this.createSlotCard(slotId, slot);
            container.appendChild(slotCard);
        });
    }

    createSlotCard(slotId, slot) {
        const card = document.createElement('div');
        card.className = 'slot-card';
        card.dataset.slot = slotId;

        // Use the URL provided by the backend
        const slotUrl = slot.url || '#';

        card.innerHTML = `
            <div class="slot-header">
                <div>
                    <h3 class="slot-title">Slot ${slotId.toUpperCase()}</h3>
                    <p class="slot-url">${slotUrl}</p>
                </div>
                <span class="status ${slot.status}">${slot.status.toUpperCase()}</span>
            </div>

            <form class="slot-form" data-slot="${slotId}">
                <div class="form-group">
                    <label for="repo-${slotId}">Repository URL:</label>
                    <input 
                        type="url" 
                        id="repo-${slotId}" 
                        name="repository" 
                        value="${slot.repository || ''}"
                        placeholder="https://github.com/user/repo"
                    >
                </div>

                <div class="form-group">
                    <label for="branch-${slotId}">Branch:</label>
                    <input 
                        type="text" 
                        id="branch-${slotId}" 
                        name="branch" 
                        value="${slot.branch || 'main'}"
                        placeholder="main"
                    >
                </div>

                <div class="form-group">
                    <label>Environment Variables:</label>
                    <div class="env-vars" id="env-${slotId}">
                        ${this.renderEnvironmentVars(slot.environment || {})}
                        <button type="button" class="btn btn-primary btn-sm w-100 mt-1" onclick="adminPanel.addEnvVar('${slotId}')">
                            + Add Environment Variable
                        </button>
                    </div>
                </div>

                <div class="button-group">
                    <button type="button" class="btn btn-primary" onclick="adminPanel.saveSlot('${slotId}')">
                        Save
                    </button>
                    <button type="button" class="btn btn-success" onclick="adminPanel.deploySlot('${slotId}')">
                        Deploy
                    </button>
                    <button type="button" class="btn btn-warning" onclick="adminPanel.restartSlot('${slotId}')">
                        Restart
                    </button>
                </div>

                <div class="button-group-vertical mt-2">
                    <button type="button" class="btn btn-info" onclick="adminPanel.viewLogs('${slotId}')">
                        View Logs
                    </button>
                    <a href="${slotUrl}" target="_blank" class="btn btn-outline">
                        Open App
                    </a>
                </div>
            </form>
        `;

        return card;
    }

    renderEnvironmentVars(envVars) {
        return Object.entries(envVars).map(([key, value]) => `
            <div class="env-var-row">
                <input type="text" placeholder="KEY" value="${key}" class="env-key">
                <input type="text" placeholder="VALUE" value="${value}" class="env-value">
                <button type="button" class="btn btn-danger btn-remove" onclick="adminPanel.removeEnvVar(this)">×</button>
            </div>
        `).join('');
    }

    // Environment Variable Management
    addEnvVar(slotId) {
        const container = document.getElementById(`env-${slotId}`);
        const button = container.querySelector('.btn-primary');

        const envRow = document.createElement('div');
        envRow.className = 'env-var-row';
        envRow.innerHTML = `
            <input type="text" placeholder="KEY" class="env-key">
            <input type="text" placeholder="VALUE" class="env-value">
            <button type="button" class="btn btn-danger btn-remove" onclick="adminPanel.removeEnvVar(this)">×</button>
        `;

        container.insertBefore(envRow, button);
    }

    removeEnvVar(button) {
        button.closest('.env-var-row').remove();
    }

    collectEnvironmentVars(slotId) {
        const container = document.getElementById(`env-${slotId}`);
        const envVars = {};

        container.querySelectorAll('.env-var-row').forEach(row => {
            const key = row.querySelector('.env-key').value.trim();
            const value = row.querySelector('.env-value').value.trim();

            if (key && value) {
                envVars[key] = value;
            }
        });

        return envVars;
    }

    // Slot Operations
    async saveSlot(slotId) {
        const form = document.querySelector(`.slot-form[data-slot="${slotId}"]`);
        const formData = new FormData(form);

        const payload = {
            repository: formData.get('repository'),
            branch: formData.get('branch'),
            environment: this.collectEnvironmentVars(slotId)
        };

        try {
            this.setLoading(slotId, true);
            const response = await fetch(`/api/slots/${slotId}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                this.showAlert(`Configuration saved for slot ${slotId.toUpperCase()}`, 'success');
                this.loadSlotConfigurations(); // Refresh display
            } else {
                const error = await response.json();
                throw new Error(error.message || 'Failed to save configuration');
            }
        } catch (error) {
            this.showAlert('Error saving configuration: ' + error.message, 'danger');
        } finally {
            this.setLoading(slotId, false);
        }
    }

    async deploySlot(slotId) {
        try {
            this.setLoading(slotId, true);
            this.updateSlotStatus(slotId, 'deploying');

            const response = await fetch(`/api/deploy/${slotId}`, {
                method: 'POST'
            });

            const result = await response.json();

            if (response.ok) {
                this.showAlert(`Deployment successful for slot ${slotId.toUpperCase()}`, 'success');
                this.updateSlotStatus(slotId, 'deployed');
            } else {
                this.showAlert('Deployment failed: ' + result.error, 'danger');
                this.updateSlotStatus(slotId, 'error');
            }
        } catch (error) {
            this.showAlert('Error deploying slot: ' + error.message, 'danger');
            this.updateSlotStatus(slotId, 'error');
        } finally {
            this.setLoading(slotId, false);
        }
    }

    async restartSlot(slotId) {
        try {
            this.setLoading(slotId, true);

            const response = await fetch(`/api/restart/${slotId}`, {
                method: 'POST'
            });

            const result = await response.json();

            if (response.ok) {
                this.showAlert(`Slot ${slotId.toUpperCase()} restarted successfully`, 'success');
            } else {
                this.showAlert('Restart failed: ' + result.error, 'danger');
            }
        } catch (error) {
            this.showAlert('Error restarting slot: ' + error.message, 'danger');
        } finally {
            this.setLoading(slotId, false);
        }
    }

    // Global Operations
    async deployAll() {
        try {
            this.showAlert('Deploying all configured slots...', 'info');

            const response = await fetch('/api/deploy-all', {
                method: 'POST'
            });

            const result = await response.json();

            if (response.ok) {
                this.showAlert('Batch deployment completed', 'success');
                this.loadSlotConfigurations(); // Refresh display
            } else {
                this.showAlert('Batch deployment failed: ' + result.error, 'danger');
            }
        } catch (error) {
            this.showAlert('Error deploying all slots: ' + error.message, 'danger');
        }
    }

    async saveAllSlots() {
        const slots = ['a', 'b', 'c', 'd', 'e'];
        const promises = slots.map(slotId => this.saveSlot(slotId));

        try {
            await Promise.all(promises);
            this.showAlert('All configurations saved', 'success');
        } catch (error) {
            this.showAlert('Error saving configurations: ' + error.message, 'danger');
        }
    }

    // Logs Management
    async viewLogs(slotId) {
        this.switchTab('logs');
        await this.loadSlotLogs(slotId);
    }

    async loadLogsView() {
        const logsContainer = document.getElementById('logs-container');
        if (!logsContainer) return;

        logsContainer.innerHTML = `
            <div class="logs-header">
                <h3>Application Logs</h3>
                <div class="logs-controls">
                    <select id="logs-slot-selector" class="form-control">
                        <option value="">Select a slot...</option>
                        <option value="a">Slot A</option>
                        <option value="b">Slot B</option>
                        <option value="c">Slot C</option>
                        <option value="d">Slot D</option>
                        <option value="e">Slot E</option>
                    </select>
                    <button class="btn btn-primary" onclick="adminPanel.refreshLogs()">Refresh</button>
                    <button class="btn btn-secondary" onclick="adminPanel.clearLogs()">Clear</button>
                </div>
            </div>
            <div class="logs-container" id="logs-output">
                Select a slot to view logs
            </div>
        `;

        // Setup logs selector
        document.getElementById('logs-slot-selector').addEventListener('change', (e) => {
            if (e.target.value) {
                this.loadSlotLogs(e.target.value);
            }
        });
    }

    async loadSlotLogs(slotId) {
        try {
            const response = await fetch(`/api/logs/${slotId}`);
            const result = await response.json();

            const logsOutput = document.getElementById('logs-output');
            if (logsOutput) {
                logsOutput.textContent = result.logs.join('\n') || 'No logs available';
                logsOutput.scrollTop = logsOutput.scrollHeight;
            }

            // Update selector
            const selector = document.getElementById('logs-slot-selector');
            if (selector && selector.value !== slotId) {
                selector.value = slotId;
            }
        } catch (error) {
            this.showAlert('Error loading logs: ' + error.message, 'danger');
        }
    }

    refreshLogs() {
        const selector = document.getElementById('logs-slot-selector');
        if (selector && selector.value) {
            this.loadSlotLogs(selector.value);
        }
    }

    clearLogs() {
        const logsOutput = document.getElementById('logs-output');
        if (logsOutput) {
            logsOutput.textContent = 'Logs cleared';
        }
    }

    // UI Helpers
    updateSlotStatus(slotId, status) {
        const statusElement = document.querySelector(`[data-slot="${slotId}"] .status`);
        if (statusElement) {
            statusElement.className = `status ${status}`;
            statusElement.textContent = status.toUpperCase();
        }
    }

    setLoading(slotId, loading) {
        const card = document.querySelector(`[data-slot="${slotId}"]`);
        if (!card) return;

        const buttons = card.querySelectorAll('.btn');
        buttons.forEach(btn => {
            btn.disabled = loading;
        });

        if (loading) {
            this.loadingStates.add(slotId);
        } else {
            this.loadingStates.delete(slotId);
        }
    }

    showAlert(message, type = 'info') {
        // Remove existing alerts
        document.querySelectorAll('.alert').forEach(alert => alert.remove());

        const alert = document.createElement('div');
        alert.className = `alert alert-${type}`;
        alert.textContent = message;

        const container = document.querySelector('.container');
        container.insertBefore(alert, container.firstChild);

        // Auto-remove after 5 seconds
        setTimeout(() => {
            alert.remove();
        }, 5000);
    }

    // Auto-save functionality
    autoSaveSlot(slotId) {
        // Only auto-save if slot has repository configured
        const repoInput = document.getElementById(`repo-${slotId}`);
        if (repoInput && repoInput.value.trim()) {
            this.saveSlot(slotId);
        }
    }

    // Utility functions
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    // Settings Management
    loadSettings() {
        const settingsContainer = document.getElementById('settings-container');
        if (!settingsContainer) return;

        settingsContainer.innerHTML = `
            <div class="settings-section">
                <h3>Global Settings</h3>
                <div class="form-group">
                    <label>Default Branch:</label>
                    <input type="text" id="default-branch" value="main" class="form-control">
                </div>
                <div class="form-group">
                    <label>Auto-deploy on webhook:</label>
                    <input type="checkbox" id="auto-deploy" checked>
                </div>
                <div class="form-group">
                    <label>Log retention (days):</label>
                    <input type="number" id="log-retention" value="7" class="form-control">
                </div>
                <button class="btn btn-primary" onclick="adminPanel.saveSettings()">Save Settings</button>
            </div>

            <div class="settings-section mt-3">
                <h3>Webhook URL</h3>
                <p>Use this URL in your GitHub repository webhook settings:</p>
                <code>https://admin--${window.location.hostname.split('--').slice(1).join('--')}/webhook</code>
            </div>

            <div class="settings-section mt-3">
                <h3>Database</h3>
                <p>PostgreSQL database is available at:</p>
                <code>postgresql://coder:password@localhost:5432/workspace_db</code>
                <div class="mt-2">
                    <a href="https://pgadmin--${window.location.hostname.split('--').slice(1).join('--')}" target="_blank" class="btn btn-info">
                        Open PGAdmin
                    </a>
                </div>
            </div>
        `;
    }

    saveSettings() {
        this.showAlert('Settings saved successfully', 'success');
    }
}

// Initialize admin panel when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.adminPanel = new AdminPanel();
});

// Export for module use if needed
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AdminPanel;
}
