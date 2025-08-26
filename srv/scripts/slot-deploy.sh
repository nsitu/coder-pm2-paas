#!/usr/bin/env bash
# Enhanced slot deployment script - Phase 2 PM2 implementation
set -euo pipefail

# Validate inputs
SLOT="${1:?slot name required (a-e)}"
REPO_URL="${2:?git url required}"
BRANCH="${3:-main}"

# Validate slot name
if [[ ! "$SLOT" =~ ^[a-e]$ ]]; then
    echo "Invalid slot name. Must be one of: a, b, c, d, e"
    exit 1
fi

# Configuration 
BASE="/home/coder/srv"
DATA_DIR="/home/coder/data"

# Set up log file before sourcing utilities
LOG_FILE="$DATA_DIR/logs/deploy-$SLOT.log"

# Source shared logging utilities
source "/home/coder/srv/scripts/logging-utils.sh"

# Source PM2 helper functions
source "/home/coder/srv/scripts/pm2-helper.sh"

APP_DIR="$BASE/apps/$SLOT"
CONFIG_FILE="$BASE/admin/config/slots.json"
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
    
    # Only handle failures here - successful deployments are handled in main flow
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed for slot $SLOT, restoring placeholder..."
        update_slot_status "error"
        
        # Restore placeholder on failure
        if command -v stop_slot >/dev/null 2>&1; then
            stop_slot "$SLOT" || log_error "Failed to restore placeholder for slot $SLOT"
        fi
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# Function to update slot status in config
update_slot_status() {
    local status="$1"
    local message="${2:-}"
    
    if [ -f "$CONFIG_FILE" ]; then
        if node /home/coder/srv/scripts/update-slot.js --slot "$SLOT" --status "$status" --last-deploy now --config "$CONFIG_FILE" >/dev/null 2>&1; then
            log "Updated slot $SLOT status to: $status"
        else
            log_warning "Failed to update slot status in config file"
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

# Replace the detect_start_command function with this corrected version

detect_start_command() {
    local start_cmd=""
    local main_file=""
    
    if [ -f package.json ]; then
        # Check for start script
        if jq -e '.scripts.start' package.json >/dev/null 2>&1; then
            start_cmd="npm start" 
        else
            # Try to find main file
            main_file=$(jq -r '.main // "index.js"' package.json 2>/dev/null || echo "index.js")
            
            # Check common entry points
            for candidate in "$main_file" "index.js" "app.js" "server.js" "src/index.js" "src/app.js"; do
                if [ -f "$candidate" ]; then
                    start_cmd="node $candidate" 
                    break
                fi
            done
        fi
    else
        # No package.json, check for common files
        for candidate in "index.js" "app.js" "server.js" "main.js"; do
            if [ -f "$candidate" ]; then
                start_cmd="node $candidate" 
                break
            fi
        done
    fi
    
    if [ -z "$start_cmd" ]; then
        log_error "Could not detect how to start the application"
        return 1
    fi
    
    # Return just the command, no logging mixed in
    echo "$start_cmd"
}

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
# Main deployment flow
main() {
    log "Starting deployment for slot $SLOT"
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
    
    # Step 3: Stop existing application process (but don't restore placeholder yet)
    log "Stopping existing application on slot $SLOT..."
    
    # Just stop the PM2 process, don't restore placeholder
    if pm2 describe "slot-$SLOT" >/dev/null 2>&1; then
        if stop_slot_process "$SLOT"; then
            log_success "Stopped slot $SLOT process"
        else
            log_error "Failed to stop slot $SLOT process"
            exit 1
        fi
    else
        log "No PM2 process found for slot $SLOT"
    fi
    
    # Step 4: Backup current deployment
    backup_current_deployment
    
    # Step 5: Clone or update repository
    log "Fetching code from repository..."
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
    
    # Step 6: Detect site type and branch
    local DETECT_OUTPUT
    DETECT_OUTPUT=$(node /home/coder/srv/scripts/site-detect-cli.js "$APP_DIR" 2>/dev/null || echo '{}')
    local SITE_TYPE
    local OUT_DIR
    local SPA
    SITE_TYPE=$(echo "$DETECT_OUTPUT" | jq -r '.type // "nodejs"')
    OUT_DIR=$(echo "$DETECT_OUTPUT" | jq -r '.outputDir // ""')
    SPA=$(echo "$DETECT_OUTPUT" | jq -r '.spa // true')

    log "Detected site type: $SITE_TYPE"

    # Fallback: if no package.json but root index.html exists, deploy as static without build
    if [ "$SITE_TYPE" != "static" ] && [ ! -f package.json ] && [ -f index.html ]; then
        log "No package.json found but index.html present; treating as static site without build"
        SITE_TYPE="static"
        OUT_DIR="$APP_DIR"
        # best-effort SPA detection: consider SPA unless 404.html exists
        if [ -f "$APP_DIR/404.html" ]; then
            SPA=false
        else
            SPA=true
        fi
    fi

    if [ "$SITE_TYPE" = "static" ]; then
        # Static flow: install with dev deps, build if present
        if [ -f package.json ]; then
            log "Installing dependencies for static build..."
            if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
                npm ci --silent || npm install --silent
            else
                npm install --silent
            fi
            if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
                log "Building static site..."
                npm run build --silent || { log_error "Build failed"; exit 1; }
            fi
        fi

        # Determine output directory (post-build or fallback to repo root with index.html)
        DETECT_OUTPUT=$(node /home/coder/srv/scripts/site-detect-cli.js "$APP_DIR" 2>/dev/null || echo '{}')
        # Preserve OUT_DIR if already set to repo root by fallback; otherwise update from detection
        if [ "$OUT_DIR" != "$APP_DIR" ]; then
            OUT_DIR=$(echo "$DETECT_OUTPUT" | jq -r '.outputDir // ""')
        fi
        SPA=$(echo "$DETECT_OUTPUT" | jq -r '.spa // true')
        if [ -z "$OUT_DIR" ] || [ ! -d "$OUT_DIR" ]; then
            # If detection failed, but repo root has index.html, use repo root
            if [ -f "$APP_DIR/index.html" ]; then
                OUT_DIR="$APP_DIR"
                SPA=$([ -f "$APP_DIR/404.html" ] && echo false || echo true)
                log "Using repository root as static output directory"
            else
                log_error "Static output directory not found"
                exit 1
            fi
        fi
        if [ ! -f "$OUT_DIR/index.html" ]; then
            log_error "index.html not found in static output directory"
            exit 1
        fi

        # Sync to static_root atomically
        local STATIC_ROOT="/home/coder/srv/static/$SLOT/current"
        local STATIC_TMP="/home/coder/srv/static/$SLOT/.next-${RANDOM}"
        mkdir -p "$STATIC_TMP" "$STATIC_ROOT"
        rsync -a --delete "$OUT_DIR"/ "$STATIC_TMP"/
        rm -rf "$STATIC_ROOT" && mv "$STATIC_TMP" "$STATIC_ROOT"

        # Ensure PM2 app not holding port
        if pm2 describe "slot-$SLOT" >/dev/null 2>&1; then
            stop_slot_process "$SLOT" || true
        fi

        # Update slots.json via Node helper
        if [ -f "$CONFIG_FILE" ]; then
            if node /home/coder/srv/scripts/update-slot.js \
                --slot "$SLOT" \
                --status deployed \
                --type static \
                --static-root "$STATIC_ROOT" \
                --spa-mode "$SPA" \
                --last-deploy now \
                --inc-deploy-count \
                --config "$CONFIG_FILE" >/dev/null 2>&1; then
                log "slots.json updated for static deployment"
            else
                log_warning "Failed to update slots.json"
            fi
        fi

        # Health check via Slot Web Server
        if health_check "$SLOT"; then
            update_slot_status "deployed"
            log_success "Static site deployed to $STATIC_ROOT and served on port $PORT"
            return 0
        else
            update_slot_status "error"
            log_error "Static site not healthy on port $PORT"
            exit 1
        fi
    else
        # Node.js flow: production deps and PM2 start
        if [ -f package.json ]; then
            log "Installing production dependencies..."
            if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
                npm ci --omit=dev --silent || npm install --omit=dev --silent
            else
                npm install --omit=dev --silent
            fi
        fi

        # Detect start command
        start_cmd=$(detect_start_command)
        # Start and health check
        if start_application "$start_cmd"; then
            log_success "Application started"
        else
            exit 1
        fi
        if health_check "$SLOT"; then
            update_slot_status "deployed"
            log_success "Deployment completed successfully!"
            log_success "Application is running on port $PORT"
            log_success "Logs: $DATA_DIR/logs/slot-$SLOT.log"
        else
            update_slot_status "error"
            log_error "Deployment failed health check"
            exit 1
        fi
    fi
}

# Run main deployment
main "$@"
