# Migration Plan: Custom Process Management → PM2

This document outlines the plan to migrate from our custom process management system to using PM2 for more robust Node.js process management.

## Current State
- Custom bash-based process management with PID files
- Manual process starting, stopping, and monitoring
- Complex placeholder server restart logic
- Manual log file management

## Target State
- PM2-based process management for all Node.js applications
- **Individual placeholder apps per slot** (always 6 PM2 processes: admin + 5 slots)
- Robust process monitoring and automatic restarts
- Built-in logging and log rotation
- Simplified deployment and management scripts
- **No complex placeholder restart logic** - slots switch between placeholder and deployed app seamlessly

## Architectural Decision: Individual Placeholder Apps

**Benefits of Individual Placeholder Architecture:**
- ✅ **Perfect PM2 alignment**: Each slot is always a PM2 process (admin + slot-a + slot-b + slot-c + slot-d + slot-e)
- ✅ **Simplified state management**: No need to restart placeholder server when deploying/stopping apps
- ✅ **Better isolation**: One slot crashing doesn't affect others
- ✅ **Cleaner deployment logic**: Just `pm2 restart slot-a` with updated ecosystem config
- ✅ **Easier debugging**: Each slot has its own logs and process status
- ✅ **More resilient**: Individual slot failures don't cascade

**Resource Usage:**
- Previous: 1 placeholder (50MB) + N deployed apps = 50MB + N×50MB
- New: 5 placeholders (250MB) + N deployed apps = 250MB + N×50MB
- Overhead: Only 200MB additional (negligible in 62GB workspace)

---

## Phase 1: PM2 Configuration & Setup

### 1.1 Create PM2 Ecosystem File
**Generated at runtime:** `/home/coder/ecosystem.config.js`

The ecosystem configuration will be generated during startup in `startup.sh` to properly handle dynamic environment variables from Coder's Terraform configuration.

**Add to `startup.sh` during first boot:**

```bash
if [ "$BOOT_MODE" = "first" ]; then
  echo -e "${YELLOW}📋 Setting up PM2 ecosystem configuration...${NC}"
  
  # Create PM2 logs directory
  mkdir -p /home/coder/data/logs
  
  # Configure PM2 log rotation (if not already configured at image level)
  if ! pm2 list | grep -q "pm2-logrotate"; then
    echo -e "${YELLOW}  📝 Configuring PM2 log rotation...${NC}"
    pm2 install pm2-logrotate
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 5
    pm2 set pm2-logrotate:compress true
  fi
  
  cat > "/home/coder/ecosystem.config.js" << 'EOF'
module.exports = {
  apps: [
    {
      name: 'admin-server',
      script: '/home/coder/srv/admin/server.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '9000'
      },
      error_file: '/home/coder/data/logs/admin-error.log',
      out_file: '/home/coder/data/logs/admin-out.log',
      log_file: '/home/coder/data/logs/admin.log',
      time: true
    },
    {
      name: 'slot-a',
      script: '/home/coder/srv/placeholders/slot-placeholder.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '3001',
        SLOT_NAME: 'a'
      },
      error_file: '/home/coder/data/logs/slot-a-error.log',
      out_file: '/home/coder/data/logs/slot-a-out.log',
      log_file: '/home/coder/data/logs/slot-a.log',
      time: true
    },
    {
      name: 'slot-b',
      script: '/home/coder/srv/placeholders/slot-placeholder.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '3002',
        SLOT_NAME: 'b'
      },
      error_file: '/home/coder/data/logs/slot-b-error.log',
      out_file: '/home/coder/data/logs/slot-b-out.log',
      log_file: '/home/coder/data/logs/slot-b.log',
      time: true
    },
    {
      name: 'slot-c',
      script: '/home/coder/srv/placeholders/slot-placeholder.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '3003',
        SLOT_NAME: 'c'
      },
      error_file: '/home/coder/data/logs/slot-c-error.log',
      out_file: '/home/coder/data/logs/slot-c-out.log',
      log_file: '/home/coder/data/logs/slot-c.log',
      time: true
    },
    {
      name: 'slot-d',
      script: '/home/coder/srv/placeholders/slot-placeholder.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '3004',
        SLOT_NAME: 'd'
      },
      error_file: '/home/coder/data/logs/slot-d-error.log',
      out_file: '/home/coder/data/logs/slot-d-out.log',
      log_file: '/home/coder/data/logs/slot-d.log',
      time: true
    },
    {
      name: 'slot-e',
      script: '/home/coder/srv/placeholders/slot-placeholder.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_restarts: 10,
      env: {
        NODE_ENV: 'development',
        PORT: '3005',
        SLOT_NAME: 'e'
      },
      error_file: '/home/coder/data/logs/slot-e-error.log',
      out_file: '/home/coder/data/logs/slot-e-out.log',
      log_file: '/home/coder/data/logs/slot-e.log',
      time: true
    }
  ]
};
EOF

  echo -e "${GREEN}  ✅ PM2 ecosystem configuration generated${NC}"
fi
```

**Why runtime generation is essential for Coder workspaces:**
- Environment variables (`ADMIN_URL`, `SLOT_*_SUBDOMAIN`, `SLOT_*_URL`, etc.) are injected by Terraform at container start
- Each workspace instance has unique URLs based on workspace name, user, and workspace agent
- Slot URLs are pre-built by Terraform, eliminating need for runtime URL construction
- Follows existing pattern of runtime configuration in `startup.sh`
- Ensures configuration matches actual runtime environment
- Container images are shared across users but configuration is per-workspace

**Environment Variable Strategy:**
- PM2 processes inherit all workspace environment variables by default
- The `env` object in ecosystem config only specifies **overrides or additions**
- This keeps configuration minimal and leverages PM2's natural inheritance
- Only specify variables that need different values or are process-specific (like PORT)

### 1.2 Individual Placeholder Script
**File:** `/home/coder/srv/placeholders/slot-placeholder.js`

```javascript
const express = require('express');
const path = require('path');

const app = express();
const port = process.env.PORT;
const slot = process.env.SLOT_NAME;

// Middleware
app.use(express.static('public'));

// Main placeholder page
app.get('/', (req, res) => {
    const slotUrl = process.env[`SLOT_${slot?.toUpperCase()}_URL`] || `http://localhost:${port}`;
    const adminUrl = process.env.ADMIN_URL || `https://admin--${process.env.CODER_WORKSPACE_NAME}--${process.env.CODER_USERNAME}.${process.env.CODER_ACCESS_URL?.replace('https://', '') || 'localhost:9000'}`;
    
    res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Slot ${slot?.toUpperCase() || 'Unknown'} - Ready for Deployment</title>
        <style>
            body { font-family: system-ui, -apple-system, sans-serif; 
                   max-width: 800px; margin: 0 auto; padding: 2rem; 
                   text-align: center; background: #f8f9fa; }
            .container { background: white; padding: 3rem; border-radius: 8px; 
                        box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .slot-name { color: #0066cc; font-size: 2.5rem; margin-bottom: 1rem; }
            .status { color: #666; font-size: 1.2rem; margin-bottom: 2rem; }
            .deploy-btn { display: inline-block; background: #0066cc; color: white; 
                         padding: 1rem 2rem; text-decoration: none; border-radius: 5px;
                         font-weight: 500; transition: background 0.2s; }
            .deploy-btn:hover { background: #0052a3; }
            .info { margin-top: 2rem; color: #666; font-size: 0.9rem; }
            .url-info { background: #f8f9fa; padding: 1rem; border-radius: 5px; margin: 1rem 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1 class="slot-name">Slot ${slot?.toUpperCase() || 'Unknown'}</h1>
            <p class="status">This slot is ready for deployment</p>
            <p>Deploy your Node.js application to this slot to make it accessible.</p>
            
            <div class="url-info">
                <p><strong>This slot will be available at:</strong></p>
                <p><a href="${slotUrl}" target="_blank">${slotUrl}</a></p>
            </div>
            
            <a href="${adminUrl}" class="deploy-btn">Configure & Deploy Application</a>
            <div class="info">
                <p>Running on port ${port || 'unknown'} • Managed by PM2</p>
            </div>
        </div>
    </body>
    </html>
    `);
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy', 
        slot: slot, 
        port: port,
        timestamp: new Date().toISOString(),
        type: 'placeholder'
    });
});

// Catch-all route
app.get('*', (req, res) => {
    res.redirect('/');
});

app.listen(port, () => {
    console.log(`📍 Placeholder for slot ${slot} listening on port ${port}`);
});
```

### 1.3 PM2 Helper Functions
**File:** `/home/coder/srv/scripts/pm2-helper.sh`

```bash
#!/bin/bash
# PM2 management helper functions for individual placeholder architecture

# Start PM2 application for a slot (replaces placeholder with deployed app)
start_pm2_app() {
    local slot=$1
    local app_dir=$2
    local start_cmd=${3:-"npm start"}
    local port=$((3000 + $(echo "$slot" | tr 'abcde' '12345')))
    local config_file="/home/coder/srv/admin/config/slots.json"
    
    echo "Deploying slot $slot with PM2..."
    
    # Update ecosystem config to replace placeholder with deployed app
    node -e "
    const fs = require('fs');
    const ecosystemPath = '/home/coder/ecosystem.config.js';
    const configPath = '$config_file';
    
    try {
        // Read current ecosystem config
        delete require.cache[ecosystemPath];
        const config = require(ecosystemPath);
        
        // Read slot configuration for user-defined environment variables
        let userEnvVars = {};
        if (fs.existsSync(configPath)) {
            try {
                const slotsConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
                userEnvVars = slotsConfig.slots?.$slot?.environment || {};
            } catch (err) {
                console.warn('Failed to read slot configuration:', err.message);
            }
        }
        
        // Find the slot app configuration
        const slotApp = config.apps.find(app => app.name === 'slot-$slot');
        if (!slotApp) {
            console.error('Slot $slot not found in ecosystem config');
            process.exit(1);
        }
        
        // Build environment variables - merge system defaults with user-defined
        const envVars = {
            // System environment variables (always present)
            PORT: '$port',
            SLOT_NAME: '$slot',
            NODE_ENV: 'development',
            // Database connection (inherited from workspace)
            DATABASE_URL: 'postgresql://coder:coder_dev_password@localhost:5432/workspace_db',
            POSTGRES_HOST: 'localhost',
            POSTGRES_PORT: '5432',
            POSTGRES_DB: 'workspace_db',
            POSTGRES_USER: 'coder',
            POSTGRES_PASSWORD: 'coder_dev_password',
            // User-defined environment variables (override system defaults if conflicts)
            ...userEnvVars
        };
        
        // Update slot configuration to use deployed app
        slotApp.script = '$start_cmd';
        slotApp.cwd = '$app_dir';
        slotApp.env = envVars;
        slotApp.max_restarts = 3; // Lower restart limit for deployed apps
        
        // Write updated config
        const output = 'module.exports = ' + JSON.stringify(config, null, 2) + ';';
        fs.writeFileSync(ecosystemPath, output);
        
        console.log('Updated ecosystem config for slot $slot with deployed app');
        console.log('Environment variables:', Object.keys(envVars).join(', '));
    } catch (error) {
        console.error('Failed to update ecosystem config:', error.message);
        process.exit(1);
    }
    "
    
    # Restart the slot with new configuration
    if pm2 restart "slot-$slot" --update-env; then
        # Save PM2 configuration for persistence
        pm2 save
        echo "Slot $slot deployed successfully with PM2"
        return 0
    else
        echo "Error: Failed to deploy slot $slot with PM2"
        return 1
    fi
}

# Stop slot and restore placeholder
stop_slot() {
    local slot=$1
    echo "Stopping slot $slot and restoring placeholder..."
    
    # Update ecosystem config to restore placeholder
    node -e "
    const fs = require('fs');
    const ecosystemPath = '/home/coder/ecosystem.config.js';
    
    try {
        delete require.cache[ecosystemPath];
        const config = require(ecosystemPath);
        
        // Find the slot app configuration
        const slotApp = config.apps.find(app => app.name === 'slot-$slot');
        if (!slotApp) {
            console.error('Slot $slot not found in ecosystem config');
            process.exit(1);
        }
        
        // Restore placeholder configuration
        slotApp.script = '/home/coder/srv/placeholders/slot-placeholder.js';
        slotApp.cwd = '/home/coder/srv/placeholders';
        slotApp.env = {
            NODE_ENV: 'development',
            PORT: slotApp.env.PORT, // Keep the same port
            SLOT_NAME: '$slot'
        };
        slotApp.max_restarts = 10; // Higher restart limit for placeholders
        
        const output = 'module.exports = ' + JSON.stringify(config, null, 2) + ';';
        fs.writeFileSync(ecosystemPath, output);
        
        console.log('Restored placeholder configuration for slot $slot');
    } catch (error) {
        console.error('Failed to restore placeholder config:', error.message);
        process.exit(1);
    }
    "
    
    # Restart the slot with placeholder configuration
    if pm2 restart "slot-$slot" --update-env; then
        # Save updated PM2 state
        pm2 save
        echo "Slot $slot restored to placeholder"
    else
        echo "Error: Failed to restore placeholder for slot $slot"
        return 1
    fi
}

# Deploy app to slot (uses shared PM2 function)
deploy_slot() {
    local slot=$1
    local app_dir="/home/coder/srv/apps/$slot"
    
    echo "Deploying slot $slot..."
    
    if [ -d "$app_dir" ]; then
        # Use shared PM2 deployment function
        start_pm2_app "$slot" "$app_dir" "npm start"
    else
        echo "Error: App directory $app_dir not found"
        return 1
    fi
}

# Deploy app to slot (uses shared PM2 function)
deploy_slot() {
    local slot=$1
    local app_dir="/home/coder/srv/apps/$slot"
    
    echo "Deploying slot $slot..."
    
    if [ -d "$app_dir" ]; then
        # Use shared PM2 startup function
        start_pm2_app "$slot" "$app_dir" "npm start"
    else
        echo "Error: App directory $app_dir not found"
        return 1
    fi
}

# Stop slot and restart placeholder
stop_slot() {
    local slot=$1
    echo "Stopping slot $slot..."
    
    # Stop and delete PM2 process
    pm2 stop "slot-$slot" 2>/dev/null || true
    pm2 delete "slot-$slot" 2>/dev/null || true
    
    # Remove from ecosystem config
    node -e "
    const fs = require('fs');
    const ecosystemPath = '/home/coder/ecosystem.config.js';
    
    delete require.cache[ecosystemPath];
    const config = require(ecosystemPath);
    
    // Remove slot config
    config.apps = config.apps.filter(app => app.name !== 'slot-$slot');
    
    const output = 'module.exports = ' + JSON.stringify(config, null, 2) + ';';
    fs.writeFileSync(ecosystemPath, output);
    "
    
    # Save updated PM2 state
    pm2 save
    
    echo "Slot $slot stopped, restarting placeholder server..."
    start_placeholder
}

# Get PM2 process status
get_process_status() {
    pm2 jlist | jq '.'
}

# Check if a slot is running
is_slot_running() {
    local slot=$1
    pm2 describe "slot-$slot" 2>/dev/null | grep -q "online"
}
```

---

## Phase 2: Update Deployment Script

### 2.1 Replace Process Management in `slot-deploy.sh`

**Note:** Source the PM2 helper functions at the top of the script:
```bash
# Source PM2 helper functions
source "/home/coder/srv/scripts/pm2-helper.sh"
```

**Key functions to replace:**

#### `start_application()` function:
```bash
start_application() {
    local start_cmd="$1"
    
    log "Starting application with PM2..."
    
    # Use the shared PM2 startup function
    if start_pm2_app "$SLOT" "$APP_DIR" "$start_cmd"; then
        log_success "Application started with PM2"
        return 0
    else
        log_error "Failed to start application with PM2"
        return 1
    fi
}
```
```

#### `health_check()` function:
```bash
health_check() {
    local max_attempts=15
    local attempt=1
    
    log "Running health check on slot $SLOT..."
    
    while [ $attempt -le $max_attempts ]; do
        # Check if PM2 process is running and online
        if pm2 describe "slot-$SLOT" 2>/dev/null | grep -q "online"; then
            # Check application health endpoint if available, fallback to root
            if curl -f -s "http://localhost:$PORT/health" >/dev/null 2>&1; then
                log_success "Application is healthy on port $PORT (health endpoint)"
                return 0
            elif curl -f -s "http://localhost:$PORT/" >/dev/null 2>&1; then
                log_success "Application is responding on port $PORT (root endpoint)"
                return 0
            fi
        fi
        
        log "Health check attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Health check failed after $max_attempts attempts"
    
    # Log PM2 status for debugging
    log "PM2 process status:"
    pm2 describe "slot-$SLOT" 2>/dev/null || log "PM2 process not found"
    
    return 1
}
```

#### `stop_existing_app()` function:
```bash
stop_existing_app() {
    log "Stopping existing application on slot $SLOT..."
    
    # Stop PM2 process (this will restore placeholder automatically via ecosystem config update)
    if pm2 describe "slot-$SLOT" >/dev/null 2>&1; then
        # Use the stop_slot helper function to restore placeholder
        if stop_slot "$SLOT"; then
            log_success "Stopped slot $SLOT and restored placeholder"
        else
            log_error "Failed to stop slot $SLOT properly"
        fi
    else
        log "No PM2 process found for slot $SLOT"
    fi
    
    # Fallback: kill any remaining processes on the port
    local pids=$(lsof -ti :$PORT 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        log_success "Cleaned up port $PORT"
    fi
}
```

#### `restart_placeholder_server()` function:
```bash
# This function is no longer needed with individual placeholder architecture
# Each slot automatically runs its placeholder when not deployed
restart_placeholder_server() {
    log "Individual placeholders are managed per slot - no global restart needed"
    return 0
}
```

---

## Phase 3: Update Admin Server ✅ **COMPLETED**

### 3.1 Replace Process Management in `server.js` ✅

**Completed Updates:**
- ✅ **Updated `/api/restart/:slot` endpoint** - Now uses `pm2 restart slot-${slotId}` instead of legacy process-manager.sh
- ✅ **Enhanced `/api/processes` endpoint** - Returns PM2 process information with CPU, memory, uptime, restarts
- ✅ **Updated `/api/processes/:slot` endpoint** - Provides detailed slot info including PM2 status and deployment type detection
- ✅ **Enhanced `/api/processes/:slot/stop` endpoint** - Uses pm2-helper.sh stop_slot() function to restore placeholder 
- ✅ **Added `/api/processes/:slot/status` endpoint** - Comprehensive slot status with PM2 and deployment information
- ✅ **Docker image rebuilt** as `nsitu/coder-paas:phase3` and `nsitu/coder-paas:latest`

#### Update restart endpoint: ✅ **IMPLEMENTED**
```javascript
app.post('/api/restart/:slot', (req, res) => {
    const slotId = req.params.slot;
    
    exec(`pm2 restart slot-${slotId}`, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: `Failed to restart slot ${slotId}`,
                details: error.message,
                stderr: stderr
            });
        } else {
            res.json({
                success: true,
                message: `Slot ${slotId} restarted successfully`,
                output: stdout
            });
        }
    });
});
```

#### Update stop endpoint: ✅ **IMPLEMENTED**
```javascript
app.post('/api/processes/:slot/stop', (req, res) => {
    const slotId = req.params.slot;
    
    // Use the stop_slot helper function to restore placeholder
    exec(`source /home/coder/srv/scripts/pm2-helper.sh && stop_slot ${slotId}`, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: `Failed to stop slot ${slotId}`,
                details: error.message,
                stderr: stderr
            });
        } else {
            // Update slot status
            const config = loadConfig();
            if (config.slots[slotId]) {
                config.slots[slotId].status = 'empty';
                saveConfig(config);
            }
            
            res.json({
                success: true,
                message: `Slot ${slotId} stopped and restored to placeholder`,
                output: stdout
            });
        }
    });
});
```

#### Add enhanced process info endpoint: ✅ **IMPLEMENTED**
```javascript
app.get('/api/processes', (req, res) => {
    exec('pm2 jlist', (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({
                error: 'Failed to get PM2 processes',
                details: error.message 
            });
        } else {
            try {
                const processes = JSON.parse(stdout);
                
                // Enhance with additional info
                const enhancedProcesses = processes.map(proc => ({
                    name: proc.name,
                    status: proc.pm2_env?.status,
                    cpu: proc.monit?.cpu || 0,
                    memory: proc.monit?.memory || 0,
                    uptime: proc.pm2_env?.pm_uptime,
                    restarts: proc.pm2_env?.restart_time || 0,
                    pid: proc.pid,
                    type: proc.name.startsWith('slot-') ? 'slot' : 'system'
                }));
                
                res.json({
                    processes: enhancedProcesses,
                    total: processes.length,
                    online: processes.filter(p => p.pm2_env?.status === 'online').length
                });
            } catch (parseError) {
                res.status(500).json({ 
                    error: 'Failed to parse PM2 output',
                    details: parseError.message 
                });
            }
        }
    });
});

app.get('/api/processes/:slot/status', (req, res) => {
    const slotId = req.params.slot;
    
    exec(`pm2 describe slot-${slotId} --format json`, (error, stdout, stderr) => {
        if (error) {
            return res.status(404).json({ error: 'Slot not found or not running' });
        }
        
        try {
            const processInfo = JSON.parse(stdout)[0];
            const config = loadConfig();
            const slotConfig = config.slots?.[slotId] || {};
            
            // Determine if this is a deployed app or placeholder
            const isPlaceholder = processInfo.pm2_env?.cwd?.includes('/placeholders');
            
            res.json({
                pm2: {
                    name: processInfo.name,
                    status: processInfo.pm2_env?.status,
                    cpu: processInfo.monit?.cpu || 0,
                    memory: processInfo.monit?.memory || 0,
                    uptime: processInfo.pm2_env?.pm_uptime,
                    restarts: processInfo.pm2_env?.restart_time || 0,
                    pid: processInfo.pid
                },
                slot: {
                    repository: slotConfig.repository || null,
                    branch: slotConfig.branch || null,
                    status: slotConfig.status || 'empty',
                    lastDeployment: slotConfig.last_deploy || null,
                    port: processInfo.pm2_env?.env?.PORT
                },
                type: isPlaceholder ? 'placeholder' : 'deployed',
                url: process.env[`SLOT_${slotId.toUpperCase()}_URL`] || `http://localhost:${processInfo.pm2_env?.env?.PORT}`
            });
        } catch (parseError) {
            res.status(500).json({ error: 'Failed to parse PM2 output' });
        }
    });
});
```
                const enhancedProcesses = processes.map(proc => ({
                    name: proc.name,
                    pid: proc.pid,
                    status: proc.pm2_env?.status || 'unknown',
                    cpu: proc.monit?.cpu || 0,
                    memory: proc.monit?.memory || 0,
                    uptime: proc.pm2_env?.pm_uptime ? Date.now() - proc.pm2_env.pm_uptime : 0,
                    restarts: proc.pm2_env?.restart_time || 0,
                    port: proc.pm2_env?.env?.PORT || null
                }));
                
                res.json({
                    processes: enhancedProcesses,
                    total: enhancedProcesses.length,
                    online: enhancedProcesses.filter(p => p.status === 'online').length
                });
            } catch (parseError) {
                res.status(500).json({ 
                    error: 'Failed to parse PM2 output',
                    details: parseError.message 
                });
            }
        }
    });
});

app.get('/api/processes/:slot', (req, res) => {
    const slotId = req.params.slot;
    
    exec(`pm2 describe slot-${slotId}`, (error, stdout, stderr) => {
        if (error) {
            res.status(404).json({ 
                error: `Slot ${slotId} not found or not running`,
                details: error.message 
            });
        } else {
            try {
                // PM2 describe returns an array
                const processInfo = JSON.parse(stdout);
                res.json(processInfo[0] || {});
            } catch (parseError) {
                res.status(500).json({ 
                    error: 'Failed to parse PM2 output',
                    details: parseError.message 
                });
            }
        }
    });
});
```

---

## Phase 4: Update Startup Scripts

### 4.1 Update `placeholders.sh` (No longer needed)

**Note:** With the individual placeholder architecture, the `placeholders.sh` script is no longer needed. Each slot placeholder is managed directly by PM2 through the ecosystem configuration.

The startup process now simply ensures PM2 is running with the ecosystem configuration, which automatically includes all placeholder slots.

### 4.2 Update startup process

Instead of `placeholders.sh`, the startup process should ensure all PM2 processes are running:

```bash
# In startup.sh or admin.sh, ensure PM2 processes are running
echo "$(date): Starting PM2 ecosystem..." >> "$LOG_DIR/startup.log"

# Start all processes from ecosystem config
if pm2 status >/dev/null 2>&1; then
    echo "$(date): PM2 already running, restarting with updated config..." >> "$LOG_DIR/startup.log"
    pm2 reload ecosystem.config.js
else
    echo "$(date): Starting PM2 ecosystem for the first time..." >> "$LOG_DIR/startup.log"
    pm2 start ecosystem.config.js
fi

# Save PM2 configuration
pm2 save

echo "$(date): PM2 ecosystem startup completed" >> "$LOG_DIR/startup.log"
```

### 4.3 Update `admin.sh` for PM2
```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# Detach this script from Coder pipes so spawned daemons cannot inherit them
exec </dev/null >/dev/null 2>&1

mkdir -p /home/coder/logs /home/coder/data/pids

# Graceful shutdown handling
cleanup() {
    echo "$(date): Gracefully stopping PM2 processes..." >> /home/coder/logs/shutdown.log
    pm2 stop all --silent
    pm2 save --silent
    echo "$(date): PM2 shutdown completed" >> /home/coder/logs/shutdown.log
}

trap cleanup SIGTERM SIGINT

# Ensure PM2 daemon is healthy
ensure_pm2_daemon() {
    if ! pm2 ping >/dev/null 2>&1; then
        echo "$(date): PM2 daemon not responding, restarting..." >> /home/coder/logs/startup.log
        pm2 kill
        pm2 resurrect 2>/dev/null || echo "$(date): No previous PM2 state to resurrect" >> /home/coder/logs/startup.log
    fi
}

# Gate on PostgreSQL readiness (best-effort, 30s)
PGPORT="${PGPORT:-5432}"
for i in $(seq 1 30); do
  /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 -p "$PGPORT" >/dev/null 2>&1 && break
  sleep 1
done

echo "$(date): Starting PM2 ecosystem..." >> /home/coder/logs/startup.log

# Ensure PM2 daemon is healthy before proceeding
ensure_pm2_daemon

# Change to home directory where ecosystem.config.js is located
cd /home/coder

# Start PM2 ecosystem (includes admin server and all slot placeholders)
if pm2 status >/dev/null 2>&1 && [ "$(pm2 list | grep -c online)" -gt 0 ]; then
    echo "$(date): PM2 processes running, reloading ecosystem..." >> /home/coder/logs/startup.log
    pm2 reload ecosystem.config.js
else
    echo "$(date): Starting PM2 ecosystem..." >> /home/coder/logs/startup.log
    pm2 start ecosystem.config.js
fi

# Save PM2 configuration for container restart persistence
pm2 save

echo "$(date): Admin server and placeholders started via PM2" >> /home/coder/logs/startup.log
exit 0
```

# Start Admin panel with PM2 using ecosystem config
if ! pm2 describe admin-server >/dev/null 2>&1; then
  if [ -f "/home/coder/srv/admin/server.js" ]; then
    pm2 start ecosystem.config.js --only admin-server --update-env
  fi
fi

exit 0
```

### 4.3 Container Persistence Strategy
**Important for Coder workspaces:** PM2 daemon state needs to be preserved across container restarts. Add to `startup.sh`:

```bash
# PM2 daemon resurrection on container restart
if [ "$BOOT_MODE" = "rehydrate" ] && [ -f "/home/coder/.pm2/dump.pm2" ]; then
  echo -e "${YELLOW}🔄 Restoring PM2 processes from previous session...${NC}"
  pm2 resurrect
  echo -e "${GREEN}  ✅ PM2 processes restored${NC}"
fi

# Always save PM2 state on successful startup (both modes)
pm2 save > /dev/null 2>&1 || true
```

---

## File Management & Cleanup Strategy

### Files to Remove After Migration
**Obsolete Custom Process Management:**
- ❌ `/srv/scripts/process-manager.sh` - Replaced by PM2 native commands
- ❌ `/srv/scripts/slot-deploy.sh` - Replaced by simplified PM2-based deployment
- ❌ `/srv/apps/deploy.sh` - Replaced by PM2 deployment logic
- ❌ `/coder/monitor.sh` - PM2 provides built-in monitoring
- ❌ `/coder/placeholders.sh` - Single placeholder server no longer needed

**Legacy Configuration:**
- ❌ `/home/coder/data/pids/` directory - PM2 manages PIDs internally
- ❌ `/home/coder/data/locks/` directory - PM2 handles process locking
- ❌ `/coder/monitor.sh` - PM2 provides built-in process monitoring and restart
- ❌ `/coder/placeholders.sh` - Individual placeholders managed by PM2

### Files to Modify (Not Remove)
**Startup & Service Scripts:**
- ✅ `/coder/startup.sh` - Enhanced with PM2 ecosystem generation and startup
- ✅ `/coder/admin.sh` - Modified to use PM2 for admin process management
- ✅ `/srv/admin/server.js` - Enhanced with PM2 process status APIs
- ✅ `/srv/scripts/health-check.sh` - Updated to check PM2 processes instead of PIDs

**Placeholder Architecture:**
- ✅ `/srv/placeholders/server.js` - Simplified to individual slot placeholder script
- ✅ `/srv/placeholders/package.json` - Retained for placeholder dependencies

**Configuration & UI:**
- ✅ `/srv/admin/config/slots.json` - Retained with enhanced PM2-specific settings
- ✅ `/srv/admin/views/*.ejs` - Enhanced with PM2 process status displays
- ✅ `/srv/admin/public/app.js` - Updated for PM2 API integration

**Infrastructure:**
- ✅ `/coder/main.tf` - Retained with enhanced environment variable configuration
- ✅ `/Dockerfile` - Enhanced with PM2 installation and optimization

### New Files Created During Migration
**PM2 Configuration:**
- ➕ `/home/coder/ecosystem.config.js` - Runtime-generated PM2 ecosystem configuration
- ➕ `/home/coder/slot-placeholder.js` - Individual placeholder script template

**Enhanced Scripts:**
- ➕ `/srv/scripts/validate-pm2-migration.sh` - Migration validation and testing
- ➕ `/home/coder/data/logs/pm2/` - PM2 log directory structure

### Migration Strategy Notes
**Directory Structure Changes:**
```bash
# Before (Custom Management)
/home/coder/data/
├── pids/           # ❌ Remove - PM2 manages PIDs
├── locks/          # ❌ Remove - PM2 handles locking
├── logs/           # ✅ Keep - Enhanced for PM2 logs
└── backups/        # ✅ Keep - Deployment backups still needed

# After (PM2 Management)  
/home/coder/data/
├── logs/
│   └── pm2/        # ➕ New - PM2 managed logs
└── backups/        # ✅ Retained - Still needed for deployments
```

**Process Lifecycle Changes:**
- **Before**: Manual PID files, bash process management, complex restart logic
- **After**: PM2 process registry, ecosystem configuration, simple `pm2 restart` commands

**Benefits of File Cleanup:**
- 🧹 **Reduced complexity**: ~500 lines of custom process management code removed  
- 🔒 **Better security**: No manual PID/lock file management vulnerabilities
- 📊 **Improved observability**: PM2's built-in monitoring replaces custom solutions
- 🚀 **Faster deployments**: Simplified scripts reduce deployment time
- 🐛 **Easier debugging**: PM2 logs and status commands replace custom diagnostics

---

## Phase 5: Benefits of PM2 Migration

### 5.1 Immediate Benefits:
- ✅ **Robust process management** - PM2 handles crashes, restarts, and monitoring
- ✅ **Built-in logging** - Automatic log rotation and management
- ✅ **Process monitoring** - Real-time status and resource usage
- ✅ **Graceful shutdowns** - Proper SIGTERM/SIGKILL handling  
- ✅ **Memory management** - Automatic restart on memory leaks
- ✅ **Startup management** - Processes auto-start on system boot
- ✅ **Better error handling** - Detailed process status and error reporting

### 5.2 Enhanced Features:
- ✅ **Web dashboard** - `pm2 monit` for real-time monitoring
- ✅ **Load balancing** - Easy horizontal scaling if needed
- ✅ **Zero-downtime deployments** - `pm2 reload` for seamless updates
- ✅ **Health checks** - Built-in process health monitoring
- ✅ **Resource limits** - Memory and CPU usage controls
- ✅ **Process clustering** - Multi-core utilization capabilities

### 5.3 Operational Benefits:
- ✅ **Simplified debugging** - Better process introspection
- ✅ **Automatic recovery** - Self-healing applications
- ✅ **Performance monitoring** - Built-in metrics collection
- ✅ **Log management** - Centralized logging with rotation

---

## Phase 6: Migration Validation

### 6.1 Validation Script
**File:** `/home/coder/srv/scripts/validate-pm2-migration.sh`

```bash
#!/bin/bash
# PM2 Migration Validation Script


validate_migration() {
    echo -e "${YELLOW}🔍 Validating PM2 migration...${NC}"
    
    local errors=0
    
    # Check PM2 daemon is running
    if ! pm2 ping >/dev/null 2>&1; then
        echo -e "${RED}❌ PM2 daemon not running${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✅ PM2 daemon is running${NC}"
    fi
    
    # Check all expected processes are running
    local expected_processes=("admin-server" "slot-a" "slot-b" "slot-c" "slot-d" "slot-e")
    for process in "${expected_processes[@]}"; do
        if pm2 describe "$process" >/dev/null 2>&1; then
            local status=$(pm2 describe "$process" | grep -o "status.*online" | head -1)
            if [[ "$status" == *"online"* ]]; then
                echo -e "${GREEN}✅ $process is running and online${NC}"
            else
                echo -e "${RED}❌ $process exists but not online${NC}"
                ((errors++))
            fi
        else
            echo -e "${RED}❌ $process not found in PM2${NC}"
            ((errors++))
        fi
    done
    
    # Check all slot ports are responding
    local ports=(3001 3002 3003 3004 3005 9000)
    local port_names=("slot-a" "slot-b" "slot-c" "slot-d" "slot-e" "admin")
    for i in "${!ports[@]}"; do
        local port=${ports[$i]}
        local name=${port_names[$i]}
        if curl -f -s "http://localhost:$port" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $name responding on port $port${NC}"
        else
            echo -e "${RED}❌ $name not responding on port $port${NC}"
            ((errors++))
        fi
    done
    
    # Check ecosystem configuration exists and is valid
    if [[ -f "/home/coder/ecosystem.config.js" ]]; then
        if node -c /home/coder/ecosystem.config.js >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Ecosystem configuration is valid${NC}"
        else
            echo -e "${RED}❌ Ecosystem configuration has syntax errors${NC}"
            ((errors++))
        fi
    else
        echo -e "${RED}❌ Ecosystem configuration file not found${NC}"
        ((errors++))
    fi
    
    # Check PM2 log rotation is configured
    if pm2 describe pm2-logrotate >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PM2 log rotation is configured${NC}"
    else
        echo -e "${YELLOW}⚠️  PM2 log rotation not found (optional)${NC}"
    fi
    
    # Check slot configuration file exists
    if [[ -f "/home/coder/srv/admin/config/slots.json" ]]; then
        if jq empty /home/coder/srv/admin/config/slots.json >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Slot configuration file is valid JSON${NC}"
        else
            echo -e "${RED}❌ Slot configuration file has invalid JSON${NC}"
            ((errors++))
        fi
    else
        echo -e "${YELLOW}⚠️  Slot configuration file not found (will be created)${NC}"
    fi
    
    # Summary
    echo ""
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✅ PM2 migration validation successful! All systems operational.${NC}"
        return 0
    else
        echo -e "${RED}❌ PM2 migration validation failed with $errors error(s).${NC}"
        echo -e "${YELLOW}💡 Check the above output and resolve issues before proceeding.${NC}"
        return 1
    fi
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_migration
fi
```

### 6.2 Integration Testing
After migration, test key workflows:

```bash
# Test deployment workflow
echo "Testing slot deployment..."
cd /home/coder/srv/scripts
./slot-deploy.sh a https://github.com/example/test-app.git main

# Test restart functionality
echo "Testing slot restart..."
pm2 restart slot-a

# Test stop/restore functionality
echo "Testing slot stop and placeholder restore..."
source pm2-helper.sh && stop_slot a

# Test admin panel API endpoints
echo "Testing admin panel APIs..."
curl -s http://localhost:9000/api/slots | jq
curl -s http://localhost:9000/api/processes | jq
```

---

## Phase 7: Migration Steps

### Step 1: Create PM2 Configuration (Low Risk)
- [ ] Add ecosystem config generation to `startup.sh`
- [ ] Create `pm2-helper.sh` in Docker image or bootstrap
- [ ] Test PM2 commands manually in workspace
- [ ] Verify PM2 daemon persistence across container restarts

### Step 2: Update Core Services (Medium Risk)
- [ ] Update `admin.sh` to use PM2 for admin server
- [ ] Update `placeholders.sh` to use PM2
- [ ] Add PM2 resurrection logic to `startup.sh`
- [ ] Test all core services with PM2

### Step 3: Update Deployment Script (High Risk)
- [ ] Replace `start_application()` function
- [ ] Replace `health_check()` function  
- [ ] Replace `stop_existing_app()` function
- [ ] Replace `restart_placeholder_server()` function
- [ ] Test deployment with PM2
- [ ] Verify proper cleanup on deployment failures

### Step 4: Update Admin Server Endpoints
- [ ] Update `/api/restart/:slot` endpoint
- [ ] Update `/api/processes/:slot/stop` endpoint
- [ ] Add enhanced `/api/processes` endpoint
- [ ] Add `/api/processes/:slot` endpoint
- [ ] Update admin UI to show PM2 process info
- [ ] Test all API endpoints

### Step 5: Container Integration Testing
- [ ] Test workspace creation from Docker image
- [ ] Test container restart scenarios (rehydrate mode)
- [ ] Validate PM2 process restoration
- [ ] Test workspace destruction cleanup
- [ ] Verify no PM2 daemon conflicts between workspaces

### Step 6: Production Readiness & Cleanup
- [ ] **Remove all legacy process management code permanently**
- [ ] **Delete old PID file management functions**
- [ ] **Remove custom process monitoring scripts entirely**
- [ ] Update Docker image build to include PM2 optimizations
- [ ] Add PM2 monitoring endpoint for Coder health checks
- [ ] Update documentation for PM2-only workflows
- [ ] **Verify no legacy process management references remain**

---

## Docker Image Considerations

### Build-time Optimizations
Add to `Dockerfile`:
```dockerfile
# PM2 configuration for container environment
RUN pm2 install pm2-logrotate && \
    pm2 set pm2-logrotate:max_size 10M && \
    pm2 set pm2-logrotate:retain 7 && \
    pm2 set pm2-logrotate:compress true

# Pre-create PM2 directories to avoid permission issues
RUN mkdir -p /home/coder/.pm2/logs /home/coder/.pm2/pids && \
    chown -R coder:coder /home/coder/.pm2
```

### Environment Variables for PM2
The following environment variables should be available in the container:
- `PM2_HOME=/home/coder/.pm2` (for daemon persistence)
- `PM2_PUBLIC_KEY` and `PM2_SECRET_KEY` (if using PM2 Plus)
- Standard Coder environment variables are already handled

---

## Coder Workspace Integration

### Health Check Integration
Update Terraform configuration to use PM2 for health checks:
```terraform
# In main.tf - update app health checks to use PM2 status
healthcheck {
  url       = "http://localhost:3001/healthz"
  interval  = 15
  threshold = 3
}
```

### Log Aggregation Strategy
- PM2 logs are already centralized in `/home/coder/data/logs/`
- This aligns with existing persistent volume mounts
- PM2 log rotation prevents disk space issues
- Logs are accessible through admin panel and PM2 CLI

### Multi-User Isolation
- Each Coder workspace gets its own container instance
- PM2 daemon runs per-container, providing natural isolation
- No shared PM2 state between different users' workspaces
- PM2 process names include slot identifiers to avoid conflicts

---

## Rollback Plan

**Commitment to PM2 Migration**: This migration is a complete transition to PM2-based process management. No legacy process management code will be preserved.

If issues arise during migration:

1. **Debug PM2 configuration issues** in place
2. **Fix PM2 process management problems** directly
3. **Container restart**: Clean slate via workspace restart if needed
4. **PM2 daemon reset**: `pm2 kill && pm2 resurrect` to reset daemon state
5. **Configuration regeneration**: Re-run startup script to recreate ecosystem config

**Debugging strategies:**
- Use `pm2 logs` and `pm2 monit` for real-time troubleshooting
- Check PM2 daemon status with `pm2 status` and `pm2 info <app>`
- Verify ecosystem configuration with detailed PM2 describe commands
- Container logs provide additional context for startup issues

**Clean slate recovery:**
- If PM2 state becomes problematic: `rm -rf /home/coder/.pm2/` and restart workspace
- Workspace destruction and recreation provides ultimate clean state
- All configuration is regenerated on workspace boot, ensuring consistency

---

## Success Criteria

Migration is complete when:

- ✅ All slots can be deployed successfully using PM2
- ✅ Placeholder server restarts properly using PM2  
- ✅ Admin panel shows accurate process status from PM2
- ✅ Process restarts and stops work reliably through PM2
- ✅ Logging is centralized through PM2 and accessible
- ✅ No orphaned processes or ports after operations
- ✅ Container restarts preserve and restore PM2 processes correctly
- ✅ System is more stable than before migration
- ✅ Multiple workspace instances can coexist without PM2 conflicts
- ✅ PM2 monitoring integrates with Coder's health check system
- ✅ **Script consolidation complete**: Eliminated redundant scripts, reduced from 1,449 to 933 total lines

**Container-specific success criteria:**
- ✅ PM2 daemon starts automatically on container boot
- ✅ PM2 processes restore correctly on workspace restart (rehydrate mode)
- ✅ PM2 logs rotate properly to prevent disk space issues
- ✅ PM2 process isolation works between different workspace instances
- ✅ Docker image builds successfully with PM2 optimizations

---

## Script Consolidation Results (Phase 2 Cleanup)

**Disabled Legacy/Redundant Scripts:**
- `process-manager.sh.disabled` (334 lines) - Legacy PID-based process management
- `pm2-deploy.sh.disabled` (163 lines) - Redundant simplified deployment script

**Active Scripts Maintained:**
- `slot-deploy.sh` (401 lines) - Comprehensive PM2-based deployment with all features
- `pm2-helper.sh` (382 lines) - Core PM2 management functions and utilities  
- `health-check.sh` (150 lines) - PM2-focused health monitoring (legacy fallbacks removed)

**Total line reduction:** 1,449 → 933 lines (35% reduction, eliminated 516 lines of redundant code)

**Key improvements:**
- Eliminated duplicate deployment logic between `slot-deploy.sh` and `pm2-deploy.sh`
- Removed legacy PID-based process management from `process-manager.sh`
- Streamlined health-check.sh to focus on PM2-only monitoring
- Maintained comprehensive functionality in consolidated scripts