#!/usr/bin/env bash
# Enhanced slot deployment script - Phase 3 implementation
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

# Validate inputs
SLOT="${1:?slot name required (a-e)}"
REPO_URL="${2:?git url required}"
BRANCH="${3:-main}"

# Validate slot name
if [[ ! "$SLOT" =~ ^[a-e]$ ]]; then
    echo "❌ Invalid slot name. Must be one of: a, b, c, d, e"
    exit 1
fi

# Configuration
# Determine base directory - works in both local dev and Coder workspace
if [ -d "/home/coder/srv" ]; then
  # Running in Coder workspace
  BASE="/home/coder/srv"
  DATA_DIR="/home/coder/data"
else
  # Running locally
  BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/data"
fi
APP_DIR="$BASE/apps/$SLOT"
CONFIG_FILE="$BASE/admin/config/slots.json"
LOG_FILE="$DATA_DIR/logs/deploy-$SLOT.log"
DEPLOYMENT_LOCK="$DATA_DIR/locks/slot-$SLOT.lock"

# Port mapping: a=3001, b=3002, c=3003, d=3004, e=3005
PORT=$((3000 + $(echo "$SLOT" | tr 'abcde' '12345')))

# Create necessary directories
mkdir -p "$DATA_DIR"/{logs,locks,backups} "$BASE/apps"

# Deployment lock to prevent concurrent deployments
if [ -f "$DEPLOYMENT_LOCK" ]; then
    LOCK_PID=$(cat "$DEPLOYMENT_LOCK" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
        log_error "Deployment already in progress for slot $SLOT (PID: $LOCK_PID)"
        exit 1
    else
        log_warning "Removing stale deployment lock for slot $SLOT"
        rm -f "$DEPLOYMENT_LOCK"
    fi
fi

# Create deployment lock
echo $$ > "$DEPLOYMENT_LOCK"

# Cleanup function
cleanup() {
    local exit_code=$?
    rm -f "$DEPLOYMENT_LOCK"
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed for slot $SLOT"
        update_slot_status "error"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Function to update slot status in config
update_slot_status() {
    local status="$1"
    local message="${2:-}"
    
    if [ -f "$CONFIG_FILE" ]; then
        local temp_file=$(mktemp)
        if jq ".slots.$SLOT.status = \"$status\" | .slots.$SLOT.last_deploy = \"$(date -Iseconds)\"" "$CONFIG_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$CONFIG_FILE"
            log "Updated slot $SLOT status to: $status"
        else
            log_warning "Failed to update slot status in config file"
            rm -f "$temp_file"
        fi
    fi
}

# Function to backup current deployment
backup_current_deployment() {
    if [ -d "$APP_DIR" ] && [ -d "$APP_DIR/.git" ]; then
        local backup_dir="$DATA_DIR/backups/slot-$SLOT-$(date +%Y%m%d-%H%M%S)"
        log "Creating backup of current deployment..."
        
        if cp -r "$APP_DIR" "$backup_dir" 2>/dev/null; then
            log_success "Backup created: $backup_dir"
            
            # Keep only last 5 backups
            find "$DATA_DIR/backups" -name "slot-$SLOT-*" -type d | sort -r | tail -n +6 | xargs rm -rf 2>/dev/null || true
        else
            log_warning "Failed to create backup"
        fi
    fi
}

# Function to load slot configuration
load_slot_config() {
    if [ -f "$CONFIG_FILE" ]; then
        SLOT_CONFIG=$(jq -r ".slots.$SLOT" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [ "$SLOT_CONFIG" != "null" ]; then
            # Extract environment variables
            ENV_JSON=$(echo "$SLOT_CONFIG" | jq -r '.environment // {}' 2>/dev/null || echo "{}")
            
            # Convert environment JSON to shell variables
            ENV_VARS=""
            if [ "$ENV_JSON" != "{}" ]; then
                ENV_VARS=$(echo "$ENV_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | tr '\n' ' ')
            fi
            
            # Get additional config
            MEMORY_LIMIT=$(echo "$SLOT_CONFIG" | jq -r '.memory_limit // "512M"' 2>/dev/null || echo "512M")
            RESTART_POLICY=$(echo "$SLOT_CONFIG" | jq -r '.restart_policy // "on-failure"' 2>/dev/null || echo "on-failure")
            
            log "Loaded configuration for slot $SLOT"
        else
            log_warning "No configuration found for slot $SLOT, using defaults"
            ENV_VARS=""
            MEMORY_LIMIT="512M"
            RESTART_POLICY="on-failure"
        fi
    else
        log_warning "Configuration file not found, using defaults"
        ENV_VARS=""
        MEMORY_LIMIT="512M"
        RESTART_POLICY="on-failure"
    fi
}

# Function to validate repository URL
validate_repository() {
    local repo_url="$1"
    
    # Basic URL validation
    if [[ ! "$repo_url" =~ ^https?://|^git@ ]]; then
        log_error "Invalid repository URL format: $repo_url"
        return 1
    fi
    
    # Test repository access
    log "Validating repository access..."
    if git ls-remote --heads "$repo_url" "$BRANCH" >/dev/null 2>&1; then
        log_success "Repository access validated"
        return 0
    else
        log_error "Cannot access repository or branch '$BRANCH' not found"
        return 1
    fi
}

# Function to stop existing application
stop_existing_app() {
    log "Stopping existing application on port $PORT..."
    
    # Find processes using the port
    local pids=$(lsof -ti :$PORT 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        log "Found processes on port $PORT: $pids"
        
        # Try graceful shutdown first
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 3
        
        # Force kill if still running
        local remaining_pids=$(lsof -ti :$PORT 2>/dev/null || true)
        if [ -n "$remaining_pids" ]; then
            log_warning "Force killing remaining processes: $remaining_pids"
            echo "$remaining_pids" | xargs kill -KILL 2>/dev/null || true
            sleep 1
        fi
        
        log_success "Stopped existing application"
    else
        log "No existing application found on port $PORT"
    fi
}

# Function to detect application type and start command
detect_start_command() {
    local start_cmd=""
    local main_file=""
    
    if [ -f package.json ]; then
        # Check for start script
        if jq -e '.scripts.start' package.json >/dev/null 2>&1; then
            start_cmd="npm start"
            log "Detected npm start script"
        else
            # Try to find main file
            main_file=$(jq -r '.main // "index.js"' package.json 2>/dev/null || echo "index.js")
            
            # Check common entry points
            for candidate in "$main_file" "index.js" "app.js" "server.js" "src/index.js" "src/app.js"; do
                if [ -f "$candidate" ]; then
                    start_cmd="node $candidate"
                    log "Detected Node.js entry point: $candidate"
                    break
                fi
            done
        fi
    else
        # No package.json, check for common files
        for candidate in "index.js" "app.js" "server.js" "main.js"; do
            if [ -f "$candidate" ]; then
                start_cmd="node $candidate"
                log "Detected Node.js file: $candidate"
                break
            fi
        done
    fi
    
    if [ -z "$start_cmd" ]; then
        log_error "Could not detect how to start the application"
        return 1
    fi
    
    echo "$start_cmd"
}

# Function to run health check
health_check() {
    local max_attempts=10
    local attempt=1
    
    log "Running health check for slot $SLOT on port $PORT..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 5 "http://localhost:$PORT/health" >/dev/null 2>&1; then
            log_success "Health check passed (attempt $attempt)"
            return 0
        elif curl -s --max-time 5 "http://localhost:$PORT/" >/dev/null 2>&1; then
            log_success "Application responding on root path (attempt $attempt)"
            return 0
        fi
        
        log "Health check attempt $attempt failed, retrying in 2 seconds..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Health check failed after $max_attempts attempts"
    return 1
}

# Function to start application with monitoring
start_application() {
    local start_cmd="$1"
    local app_log="$DATA_DIR/logs/slot-$SLOT.log"
    
    log "Starting application with command: $start_cmd"
    
    # Build environment variables
    local env_string="PORT=$PORT SLOT_NAME=$SLOT NODE_ENV=development"
    env_string="$env_string DATABASE_URL=postgresql://coder:coder_dev_password@localhost:5432/workspace_db"
    env_string="$env_string POSTGRES_HOST=localhost POSTGRES_PORT=5432"
    env_string="$env_string POSTGRES_DB=workspace_db POSTGRES_USER=coder"
    env_string="$env_string POSTGRES_PASSWORD=coder_dev_password"
    
    if [ -n "$ENV_VARS" ]; then
        env_string="$env_string $ENV_VARS"
    fi
    
    # Start application
    log "Environment: $env_string"
    
    # Use systemd-run for better process management if available
    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run --user --scope --property=MemoryMax="$MEMORY_LIMIT" \
            bash -c "cd '$APP_DIR' && exec env $env_string $start_cmd" \
            > "$app_log" 2>&1 &
    else
        # Fallback to nohup
        cd "$APP_DIR"
        nohup env $env_string $start_cmd > "$app_log" 2>&1 &
    fi
    
    local app_pid=$!
    echo "$app_pid" > "$DATA_DIR/locks/slot-$SLOT.pid"
    
    log "Application started with PID: $app_pid"
    sleep 3
    
    # Verify process is still running
    if ! kill -0 "$app_pid" 2>/dev/null; then
        log_error "Application process died immediately after start"
        log_error "Check logs: $app_log"
        return 1
    fi
    
    log_success "Application process is running"
}

# Main deployment flow
main() {
    log "🚀 Starting deployment for slot $SLOT"
    log "Repository: $REPO_URL"
    log "Branch: $BRANCH"
    log "Port: $PORT"
    
    update_slot_status "deploying"
    
    # Step 1: Load configuration
    load_slot_config
    
    # Step 2: Validate repository
    if ! validate_repository "$REPO_URL"; then
        exit 1
    fi
    
    # Step 3: Stop existing application
    stop_existing_app
    
    # Step 4: Backup current deployment
    backup_current_deployment
    
    # Step 5: Clone or update repository
    log "📥 Fetching code from repository..."
    if [ -d "$APP_DIR/.git" ]; then
        cd "$APP_DIR"
        log "Updating existing repository..."
        git fetch origin "$BRANCH" --depth=1
        git checkout "$BRANCH"
        git reset --hard "origin/$BRANCH"
        log_success "Repository updated"
    else
        log "Cloning fresh repository..."
        rm -rf "$APP_DIR"
        if git clone --branch "$BRANCH" --depth=1 "$REPO_URL" "$APP_DIR"; then
            log_success "Repository cloned"
        else
            log_error "Failed to clone repository"
            exit 1
        fi
    fi
    
    cd "$APP_DIR"
    
    # Step 6: Install dependencies
    if [ -f package.json ]; then
        log "📦 Installing dependencies..."
        
        # Clean install for better reliability
        if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
            if npm ci --omit=dev --silent; then
                log_success "Dependencies installed via npm ci"
            else
                log_warning "npm ci failed, falling back to npm install"
                npm install --omit=dev --silent
            fi
        else
            npm install --omit=dev --silent
            log_success "Dependencies installed via npm install"
        fi
        
        # Run build script if it exists
        if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
            log "🔨 Building application..."
            if npm run build --silent; then
                log_success "Application built successfully"
            else
                log_error "Build failed"
                exit 1
            fi
        fi
    else
        log_warning "No package.json found, skipping dependency installation"
    fi
    
    # Step 7: Detect start command
    start_cmd=$(detect_start_command)
    
    # Step 8: Start application
    if start_application "$start_cmd"; then
        log_success "Application started"
    else
        exit 1
    fi
    
    # Step 9: Health check
    if health_check; then
        update_slot_status "deployed"
        log_success "✅ Deployment completed successfully!"
        log_success "🌐 Application is running on port $PORT"
        log_success "📋 Logs: $DATA_DIR/logs/slot-$SLOT.log"
    else
        update_slot_status "error"
        log_error "❌ Deployment failed health check"
        exit 1
    fi
}

# Run main deployment
main "$@"
