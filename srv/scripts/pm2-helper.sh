#!/bin/bash
# PM2 management helper functions for individual placeholder architecture

# Enhanced error handling and validation
set -euo pipefail

# Source shared logging utilities
source "$(dirname "${BASH_SOURCE[0]}")/logging-utils.sh"

# Enhanced start_pm2_app function with multi-port placeholder integration
start_pm2_app() {
    local slot=$1
    local app_dir=$2
    local start_cmd=${3:-"npm start"}
    local port=$((3000 + $(echo "$slot" | tr 'abcde' '12345')))
    local config_file="/home/coder/srv/admin/config/slots.json"
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi
    
    if [[ ! -d "$app_dir" ]]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    # Check if PM2 daemon is running
    if ! pm2 list >/dev/null 2>&1; then
        log_error "PM2 daemon is not responding"
        return 1
    fi
    
    log_with_timestamp "Deploying slot $slot with PM2..."
    
    # Step 1: Stop placeholder server (will restart with updated config after deployment)
    log_with_timestamp "Stopping multi-port placeholder server..."
    if [ -d "/home/coder/srv" ]; then
        # Running in Coder workspace - use PM2 directly
        pm2 stop placeholder-server >/dev/null 2>&1 || log_warning "Placeholder server was not running"
    else
        # Running locally - use PM2 directly
        pm2 stop placeholder-server >/dev/null 2>&1 || log_warning "Placeholder server was not running"
    fi
    
    # Use static Node.js script to add slot to ecosystem configuration
    local script_path="$(dirname "${BASH_SOURCE[0]}")/add-slot.js"
    if [[ ! -f "$script_path" ]]; then
        log_error "Add slot script not found: $script_path"
        return 1
    fi
    
    # Run the Node.js script with proper arguments
    if ! node "$script_path" "$slot" "$app_dir" "$start_cmd" "$port" "$config_file" >> "/home/coder/data/logs/ecosystem-updates.log" 2>&1; then
        log_error "Failed to add slot to ecosystem configuration"
        return 1
    fi
    
    # Debug: Show the updated ecosystem configuration
    log_with_timestamp "Added slot to ecosystem configuration:"
    if [ -f "/home/coder/ecosystem.config.js" ]; then
        grep -A 20 "slot-$slot" /home/coder/ecosystem.config.js | head -15 || true
    fi
   
    # Restart the slot with new configuration
    # Use delete/start to ensure we pick up ecosystem config changes
    if pm2 delete "slot-$slot" >/dev/null 2>&1; then
        log_with_timestamp "Deleted existing slot-$slot process"
    fi
    
    # Start with updated ecosystem configuration
    if pm2 start /home/coder/ecosystem.config.js --only "slot-$slot"; then
        # Save PM2 configuration for persistence
        if pm2 save; then
            # Step 2: Restart placeholder server (will automatically detect the deployed slot and not create placeholder for it)
            log_with_timestamp "Restarting multi-port placeholder server..."
            if [ -d "/home/coder/srv" ]; then
                # Running in Coder workspace - use PM2 directly
                pm2 restart placeholder-server >/dev/null 2>&1 || pm2 start ecosystem.config.js --only placeholder-server
            else
                # Running locally - use PM2 directly
                pm2 restart placeholder-server >/dev/null 2>&1 || pm2 start ecosystem.config.js --only placeholder-server
            fi
            
            log_success "Slot $slot deployed successfully with PM2"
            return 0
        else
            log_error "Failed to save PM2 configuration"
            return 1
        fi
    else
        log_error "Failed to start slot $slot with updated configuration"
        return 1 
    fi 
} 

# Stop slot process without restoring placeholder (for deployment)
stop_slot_process() {
    local slot=$1
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi

    log_with_timestamp "Stopping slot $slot process..."
    
    # Check if PM2 daemon is healthy before proceeding
    if ! pm2 list >/dev/null 2>&1; then
        log_error "PM2 daemon is not responding, cannot stop slot"
        return 1
    fi
    
    # Just stop the PM2 process, don't restore placeholder yet
    if pm2 stop "slot-$slot" >/dev/null 2>&1; then
        log_success "Slot $slot process stopped"
        return 0
    else
        log_warning "Slot $slot process was not running or already stopped"
        return 0
    fi
}

# Stop slot and restore placeholder (updated for multi-port architecture)
stop_slot() {
    local slot=$1
    local port=$((3000 + $(echo "$slot" | tr 'abcde' '12345')))
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi

    log_with_timestamp "Stopping slot $slot and updating placeholders..."
    
    # Check if PM2 daemon is healthy before proceeding
    if ! pm2 list >/dev/null 2>&1; then
        log_error "PM2 daemon is not responding, cannot stop slot"
        return 1
    fi
    
    # Step 1: Stop the PM2 process for this slot
    if pm2 stop "slot-$slot" >/dev/null 2>&1; then
        log_with_timestamp "Stopped slot $slot PM2 process"
    else
        log_warning "Slot $slot process was not running or already stopped"
    fi

    # Step 2: Remove slot from PM2 ecosystem config
    local script_path="$(dirname "${BASH_SOURCE[0]}")/remove-slot.js"
    if [[ -f "$script_path" ]]; then
        if node "$script_path" "$slot" "$port"; then
            log_with_timestamp "Removed slot $slot from PM2 ecosystem"
        else
            log_warning "Failed to remove slot from PM2 ecosystem"
        fi
    fi

    # Step 3: Delete the PM2 process entirely
    if pm2 delete "slot-$slot" >/dev/null 2>&1; then
        log_with_timestamp "Deleted slot $slot from PM2"
    else
        log_warning "Slot $slot was not in PM2 or already deleted"
    fi

    # Step 4: Update slot status to empty in config
    local config_file="/home/coder/srv/admin/config/slots.json"
    if [ -f "$config_file" ]; then
        local temp_file=$(mktemp)
        if jq ".slots.$slot.status = \"empty\"" "$config_file" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$config_file"
            log_with_timestamp "Updated slot $slot status to empty"
        else
            log_warning "Failed to update slot status in config file"
            rm -f "$temp_file"
        fi
    fi
    
    # Step 5: Save PM2 configuration
    pm2 save || log_warning "Failed to save PM2 configuration"
    
    # Step 6: The multi-port placeholder server will automatically detect the empty slot
    # and start serving a placeholder on that port via file watching
    log_success "Slot $slot restored to placeholder via multi-port server"
    return 0
}

# Health check function with enhanced endpoint checking
health_check() {
    local slot=$1
    local port=$((3000 + $(echo "$slot" | tr 'abcde' '12345')))
    local max_attempts=30
    local attempt=1
    
    log_with_timestamp "Performing health check for slot $slot on port $port..."
    
    while [ $attempt -le $max_attempts ]; do
        # Try health endpoint first
        if curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then
            log_success "Health check passed for slot $slot"
            return 0
        fi
        
        # Fallback to root endpoint
        if curl -sf "http://localhost:$port/" >/dev/null 2>&1; then
            log_success "Health check passed for slot $slot (via root endpoint)"
            return 0
        fi
        
        if [ $attempt -eq 1 ]; then
            log_with_timestamp "Waiting for slot $slot to be ready..."
        fi
        
        sleep 2
        ((attempt++))
    done
    
    log_error "Health check failed for slot $slot after $max_attempts attempts"
    return 1
}

# Enhanced deployment function with backup and rollback
deploy_slot() {
    local slot=$1
    local app_dir="/home/coder/srv/apps/$slot"
    local backup_dir="/home/coder/data/backups/slot-$slot-$(date +%Y%m%d-%H%M%S)"
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi
    
    if [[ ! -d "$app_dir" ]]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    log_with_timestamp "Deploying slot $slot from $app_dir..."
    
    # Create backup if deployment directory exists
    if [[ -d "$app_dir" ]] && [[ "$(ls -A "$app_dir" 2>/dev/null)" ]]; then
        log_with_timestamp "Creating backup at $backup_dir..."
        mkdir -p "$backup_dir"
        cp -r "$app_dir"/* "$backup_dir"/ 2>/dev/null || true
    fi
    
    # Use shared PM2 deployment function
    if start_pm2_app "$slot" "$app_dir" "npm start"; then
        # Perform health check
        if health_check "$slot"; then
            log_success "Deployment of slot $slot completed successfully"
            return 0
        else
            log_error "Health check failed after deployment"
            # Attempt to restore placeholder
            if stop_slot "$slot"; then
                log_warning "Restored placeholder after failed deployment"
            fi
            return 1
        fi
    else
        log_error "Failed to deploy slot $slot"
        return 1
    fi
}

# Function to get detailed slot status
get_slot_status() {
    local slot=$1
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi
    
    # Check if PM2 daemon is running
    if ! pm2 list >/dev/null 2>&1; then
        echo "PM2 daemon not available"
        return 1
    fi
    
    pm2 describe "slot-$slot" 2>/dev/null || echo "Process not found"
}

# Function to view slot logs
view_slot_logs() {
    local slot=$1
    local lines=${2:-50}
    
    # Validation
    if [[ ! "$slot" =~ ^[a-e]$ ]]; then
        log_error "Invalid slot name: $slot. Must be one of: a, b, c, d, e"
        return 1
    fi
    
    # Check if PM2 daemon is running
    if ! pm2 list >/dev/null 2>&1; then
        return 1
    fi
    
    pm2 logs "slot-$slot" --lines "$lines"
}

# Graceful shutdown handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Export functions for use in other scripts
export -f start_pm2_app stop_slot_process stop_slot deploy_slot health_check get_slot_status view_slot_logs

# If script is run directly, show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "PM2 Helper Functions"
    echo "Usage: source this file and call:"
    echo "  start_pm2_app <slot> <app_dir> [start_cmd]"
    echo "  stop_slot_process <slot>       # Stop process without restoring placeholder"
    echo "  stop_slot <slot>               # Stop process and restore placeholder"
    echo "  deploy_slot <slot>"
    echo "  health_check <slot>"
    echo "  get_slot_status <slot>"
    echo "  view_slot_logs <slot> [lines]"
    echo ""
    echo "Example: source /home/coder/srv/scripts/pm2-helper.sh"
    echo "         deploy_slot a"
fi
