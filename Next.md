# Next Generation Architecture Plan

## Overview
Transform coder-pm2-paas from a webhook-driven deployment system to a structured slot-based Platform-as-a-Service with an integrated admin interface. Each workspace will provide 5 configurable deployment slots plus an admin control panel.

## Core Architecture Changes

### 1. Slot-Based Deployment System
- **5 Application Slots**: Each workspace provides exactly 5 deployment slots (a, b, c, d, e)
- **Configurable Subdomains**: Mutable Coder parameters allow users to customize subdomain slugs
- **Default Documentation**: Empty slots serve documentation pages until configured
- **Ports**: Each slot runs independently with its own port 
- **Environment**: Each app is started with relevant environment variables passed in from configuration.

### 2. Admin Web Application
- **Configuration Interface**: Web-based form for managing slot configurations
- **Deployment Management**: Deploy, restart, and monitor applications per slot
- **Log Viewer**: Real-time log tailing for each running application
- **Webhook Endpoint**: Intelligent webhook handling based on repository matching

### 3. Database Integration
- **PostgreSQL**: Pre-installed and configured in the workspace for application use
- **PGAdmin**: Web interface for database management available as coder web app
- **Persistent Storage**: Databases stored in persistent volume claim configured via Coder terraform
- **Local Access**: Apps can connect to databases via localhost/environment variables

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1-2)

#### 1.1 Coder Template Updates
**File: `coder/main.tf`**
- [ ] Add mutable parameters for 5 subdomain slots (default: a, b, c, d, e)
- [ ] Configure subdomain routing for each slot
- [ ] Add PostgreSQL and PGAdmin app definitions
- [ ] Update resource limits for additional services

```hcl
data "coder_parameter" "slot_a_subdomain" {
  name         = "SLOT_A_SUBDOMAIN"
  display_name = "Slot A Subdomain"
  type         = "string"
  mutable      = true
  default      = "a"
}
# Repeat for slots b, c, d, e
```

#### 1.2 Docker Image Enhancement
**File: `Dockerfile`**
- [ ] Install PostgreSQL server and client
- [ ] Install PGAdmin4
- [ ] Configure PostgreSQL for development use
- [ ] Set up database persistence in `/home/coder/data/postgres`

#### 1.3 Startup Script Revision
**File: `coder/startup.sh`**
- [ ] Initialize PostgreSQL data directory
- [ ] Start PostgreSQL service
- [ ] Start PGAdmin service
- [ ] Create default database and user
- [ ] Set up admin web app

### Phase 2: Admin Web Application (Week 3-4) ✅ COMPLETED

#### 2.1 Admin App Structure ✅
**Directory: `srv/admin/`**
```
srv/admin/
├── package.json
├── server.js           # Express app with full API
├── public/
│   ├── index.html      # Main admin interface (SPA)
│   ├── style.css       # Complete styling system
│   └── app.js          # Frontend JavaScript class
├── config/
│   └── slots.json      # Slot configurations (auto-generated)
└── views/
    ├── dashboard.ejs   # Main dashboard view
    ├── slot-config.ejs # Slot configuration form
    └── logs.ejs        # Log viewer
```

#### 2.2 Configuration Management ✅
**File: `srv/admin/config/slots.json`**
```json
{
  "slots": {
    "a": {
      "subdomain": "a",
      "repository": "",
      "branch": "main",
      "environment": {},
      "status": "empty",
      "port": 3001
    },
    // ... slots b, c, d, e
  }
}
```

#### 2.3 Admin API Endpoints ✅
- `GET /` - Admin dashboard (uses EJS template)
- `GET /config/:slot` - Slot configuration page
- `GET /logs/:slot` - Log viewer page
- `GET /api/slots` - Get all slot configurations
- `PUT /api/slots/:slot` - Update slot configuration
- `POST /api/deploy/:slot` - Deploy specific slot
- `POST /api/restart/:slot` - Restart specific application
- `POST /api/deploy-all` - Deploy all configured slots
- `GET /api/logs/:slot` - Get application logs
- `POST /webhook` - GitHub webhook endpoint with intelligent routing

**Features Implemented:**
- ✅ Tabbed interface (Dashboard, Logs, Settings)
- ✅ Real-time slot status management
- ✅ Environment variable editor with add/remove functionality
- ✅ Auto-save configuration on changes
- ✅ Batch deployment operations
- ✅ Responsive design for mobile/desktop
- ✅ Real-time log viewer with filtering
- ✅ Keyboard shortcuts (Ctrl+S for save, Ctrl+D for deploy)
- ✅ Link integration with slot URLs
- ✅ Configuration validation and error handling

### Phase 3: Deployment Engine (Week 5-6) ✅ COMPLETED

#### 3.1 Enhanced Deployment Script ✅
**File: `srv/scripts/slot-deploy.sh`** (renamed from deploy folder)
```bash
#!/usr/bin/env bash
# Enhanced slot deployment script with comprehensive features:
# - Color-coded logging and output
# - Deployment locks to prevent concurrent deployments
# - Repository validation and access checking
# - Backup system with automatic cleanup
# - Health checks with retry logic
# - Memory limits and restart policies
# - Environment variable injection from configuration
# - Process monitoring and management
# - Detailed error reporting and troubleshooting
```

**Features Implemented:**
- ✅ Comprehensive logging with timestamps and color coding
- ✅ Deployment locks to prevent race conditions
- ✅ Automatic backup system with rotation (keeps last 5)
- ✅ Repository validation and branch verification
- ✅ Graceful process shutdown (TERM → KILL)
- ✅ Health check with configurable retry logic
- ✅ Memory limits via systemd-run when available
- ✅ Environment variable injection from slot configuration
- ✅ Application type detection (npm start vs direct node)
- ✅ Build script execution (npm run build)
- ✅ Status tracking and configuration updates

#### 3.2 Process Management System ✅
**File: `srv/scripts/process-manager.sh`**
```bash
#!/usr/bin/env bash
# Complete process management system replacing PM2:
# - list, status, stop, restart, logs commands
# - Process monitoring with PID file management
# - Resource usage tracking (memory, CPU)
# - Automatic restart capabilities
# - Batch operations (stop-all, restart-all)
# - Integration with slot configuration system
```

**Features Implemented:**
- ✅ Process listing with detailed information (PID, memory, CPU, start time)
- ✅ Status table display with color-coded output
- ✅ Individual slot management (stop, restart, logs)
- ✅ Process monitoring and health checking
- ✅ PID file management for reliable process tracking
- ✅ Port-based process identification and cleanup
- ✅ Graceful shutdown with fallback force kill
- ✅ Integration with deployment configuration
- ✅ Batch operations for all slots
- ✅ JSON output for API integration

#### 3.3 Configuration Management System ✅
**File: `srv/scripts/config-manager.js`**
```javascript
// Dynamic configuration system with:
// - Slot configuration generation and migration
// - Environment variable management
// - Configuration validation and backup
// - Export capabilities for deployment
// - CLI interface for configuration operations
```

**Features Implemented:**
- ✅ Dynamic slot configuration with full metadata
- ✅ Configuration migration and validation system
- ✅ Environment variable generation and injection
- ✅ Configuration backup with automatic rotation
- ✅ Health check configuration per slot
- ✅ Build configuration and caching options
- ✅ Deployment strategy configuration
- ✅ Monitoring and alerting configuration
- ✅ CLI interface for configuration management
- ✅ Export functionality for deployment scripts

#### 3.4 Enhanced Admin API Endpoints ✅
**Updated Admin Server with:**
```javascript
// New endpoints for comprehensive process management:
// - GET /api/processes - List all process information
// - GET /api/processes/:slot - Get detailed slot information
// - POST /api/processes/:slot/stop - Stop specific slot
// - GET /api/deployments/history - Deployment history and statistics
// - Enhanced webhook handling with better error reporting
// - Bulk operations with progress tracking
```

**Features Implemented:**
- ✅ Process monitoring API with real-time status
- ✅ Deployment history tracking with statistics
- ✅ Enhanced webhook handling with repository matching
- ✅ Bulk deployment operations with progress tracking
- ✅ Individual slot process management
- ✅ Detailed deployment information and metadata
- ✅ Error handling with comprehensive logging
- ✅ Configuration integration with slot settings

**Technical Improvements:**
- ✅ Color-coded terminal output for better UX
- ✅ Comprehensive error handling and logging
- ✅ Process isolation and resource management
- ✅ Deployment locks preventing concurrent operations
- ✅ Health check system with configurable retries
- ✅ Backup and rollback capabilities
- ✅ Configuration validation and migration
- ✅ API integration for monitoring and control

### Phase 4: Database Integration (Week 7) ✅ COMPLETED

#### 4.1 PostgreSQL Setup ✅
- ✅ Configure PostgreSQL in persistent volume
- ✅ Create development database and user
- ✅ Set up connection environment variables
- ✅ Configure automatic startup

#### 4.2 PGAdmin Configuration ✅ SIMPLIFIED
- ✅ Simplified pip-based PGAdmin4 installation (replaced complex apt approach)
- ✅ Direct Python web application approach (no Apache/WSGI required)
- ✅ Environment-based configuration (no complex config files)
- ✅ Configure for local database access

#### 4.3 Database Persistence ✅
**Directory Structure:**
```
/home/coder/data/
├── postgres/           # PostgreSQL data directory
├── pgadmin/           # PGAdmin configuration
└── backups/           # Database backup storage
```

**Architecture Improvements:**
- ✅ Replaced complex apt-based pgladmin4-web (Apache/WSGI dependencies)
- ✅ Simplified to pip-based PGAdmin4 as direct Python application
- ✅ Consistent with architecture philosophy of direct process management
- ✅ Environment variable based configuration for simplicity
- ✅ No Apache/WSGI complexity required
- ✅ Startup script updated for pip-based PGAdmin4 initialization
- ✅ Reorganized deploy/ folder to scripts/ for better organization
- ✅ Consolidated all operational scripts (deployment, process management, health monitoring) in one location
- ✅ Improved script discoverability and maintenance

### Phase 5: Frontend Interface (Week 8)

#### 5.1 Admin Dashboard Features
- [ ] Slot status overview (deployed, empty, error)
- [ ] Quick deploy/restart buttons
- [ ] Repository configuration forms
- [ ] Environment variable management
- [ ] Real-time deployment status

#### 5.2 Log Viewer
- [ ] Real-time log streaming via WebSockets
- [ ] Log filtering and search
- [ ] Download log files
- [ ] Error highlighting

#### 5.3 Configuration Forms
- [ ] Repository URL validation
- [ ] Branch selection
- [ ] Environment variable key-value editor
- [ ] Deployment history

## Technical Specifications

### Port Allocation
- **Admin App**: 9000
- **PostgreSQL**: 5432
- **PGAdmin**: 5050
- **Slot A**: 3001
- **Slot B**: 3002
- **Slot C**: 3003
- **Slot D**: 3004
- **Slot E**: 3005

### URL Structure
- **Admin**: `https://admin--workspace--user.domain/`
- **PGAdmin**: `https://pgadmin--workspace--user.domain/`
- **Slot A**: `https://a--workspace--user.domain/` (default)
- **Slot B**: `https://custom--workspace--user.domain/` (if customized)

### Environment Variables (Auto-injected)
```bash
# Database connection
DATABASE_URL=postgresql://coder:password@localhost:5432/workspace_db
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=workspace_db
POSTGRES_USER=coder
POSTGRES_PASSWORD=generated_password

# Application specific
PORT=3001  # Varies by slot
SLOT_NAME=a
BASE_PATH=/
NODE_ENV=development
```

## Security Considerations

### 1. Access Control
- [ ] Admin interface authentication
- [ ] Database access restrictions
- [ ] Repository access validation

### 2. Webhook Security
- [ ] GitHub signature validation
- [ ] Rate limiting
- [ ] Request payload validation

### 3. Process Isolation
- [ ] PM2 process separation
- [ ] Resource limits per slot
- [ ] Environment variable isolation
 

### Data Preservation
- Application files remain in persistent volume
- Database data migrates to PostgreSQL
- Configuration converts to JSON format
- Logs archive to persistent storage
  

This architecture provides a much more structured and user-friendly approach to application deployment within Coder workspaces, while maintaining the simplicity and educational focus of the original system.