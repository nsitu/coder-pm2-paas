#!/usr/bin/env bash
# Process Management System - Replaces PM2 functionality
# This script manages application processes for each slot

set -euo pipefail

# Configuration
BASE="/home/harold/coder-pm2-paas/srv"
DATA_DIR="/home/harold/coder-pm2-paas/data"
CONFIG_FILE="$BASE/admin/config/slots.json"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to get slot port
get_slot_port() {
    local slot="$1"
    echo $((3000 + $(echo "$slot" | tr 'abcde' '12345')))
}

# Function to get process info for a slot
get_process_info() {
    local slot="$1"
    local port=$(get_slot_port "$slot")
    local pid_file="$DATA_DIR/locks/slot-$slot.pid"
    
    local info="{}"
    
    # Check if PID file exists and process is running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # Process is running
            local memory=$(ps -o rss= -p "$pid" 2>/dev/null | xargs || echo "0")
            local cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | xargs || echo "0.0")
            local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | xargs || echo "Unknown")
            
            info=$(jq -n \
                --arg slot "$slot" \
                --arg port "$port" \
                --arg pid "$pid" \
                --arg status "running" \
                --arg memory "${memory}KB" \
                --arg cpu "${cpu}%" \
                --arg start_time "$start_time" \
                '{slot: $slot, port: $port, pid: $pid, status: $status, memory: $memory, cpu: $cpu, start_time: $start_time}'
            )
        else
            # PID file exists but process is dead
            rm -f "$pid_file"
            info=$(jq -n \
                --arg slot "$slot" \
                --arg port "$port" \
                --arg status "stopped" \
                '{slot: $slot, port: $port, status: $status, message: "Process died"}'
            )
        fi
    else
        # No PID file, check if something else is using the port
        local port_pid=$(lsof -ti :$port 2>/dev/null || echo "")
        if [ -n "$port_pid" ]; then
            info=$(jq -n \
                --arg slot "$slot" \
                --arg port "$port" \
                --arg pid "$port_pid" \
                --arg status "unknown" \
                '{slot: $slot, port: $port, pid: $pid, status: $status, message: "Process not managed by system"}'
            )
        else
            info=$(jq -n \
                --arg slot "$slot" \
                --arg port "$port" \
                --arg status "stopped" \
                '{slot: $slot, port: $port, status: $status}'
            )
        fi
    fi
    
    echo "$info"
}

# Function to list all slots
list_processes() {
    echo "{"
    echo "  \"processes\": ["
    
    local first=true
    for slot in a b c d e; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        
        local info=$(get_process_info "$slot")
        echo "    $info"
    done
    
    echo "  ],"
    echo "  \"timestamp\": \"$(date -Iseconds)\""
    echo "}"
}

# Function to stop a slot
stop_slot() {
    local slot="$1"
    local port=$(get_slot_port "$slot")
    local pid_file="$DATA_DIR/locks/slot-$slot.pid"
    
    log "Stopping slot $slot (port $port)..."
    
    # Stop via PID file first
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "Sending TERM signal to PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            
            # Wait for graceful shutdown
            local attempts=0
            while [ $attempts -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                ((attempts++))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log "Force killing PID $pid..."
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$pid_file"
    fi
    
    # Also kill any processes using the port
    local port_pids=$(lsof -ti :$port 2>/dev/null || echo "")
    if [ -n "$port_pids" ]; then
        log "Killing processes on port $port: $port_pids"
        echo "$port_pids" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        
        # Force kill if still there
        port_pids=$(lsof -ti :$port 2>/dev/null || echo "")
        if [ -n "$port_pids" ]; then
            echo "$port_pids" | xargs kill -KILL 2>/dev/null || true
        fi
    fi
    
    log_success "Slot $slot stopped"
}

# Function to restart a slot
restart_slot() {
    local slot="$1"
    
    log "Restarting slot $slot..."
    
    # Stop the slot
    stop_slot "$slot"
    
    # Get slot configuration
    if [ -f "$CONFIG_FILE" ]; then
        local slot_config=$(jq -r ".slots.$slot" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [ "$slot_config" != "null" ]; then
            local repository=$(echo "$slot_config" | jq -r '.repository // ""')
            local branch=$(echo "$slot_config" | jq -r '.branch // "main"')
            
            if [ -n "$repository" ]; then
                log "Redeploying slot $slot from $repository ($branch)..."
                "$BASE/scripts/slot-deploy.sh" "$slot" "$repository" "$branch"
            else
                log_error "No repository configured for slot $slot"
                return 1
            fi
        else
            log_error "No configuration found for slot $slot"
            return 1
        fi
    else
        log_error "Configuration file not found"
        return 1
    fi
}

# Function to get logs for a slot
get_logs() {
    local slot="$1"
    local lines="${2:-50}"
    local log_file="$DATA_DIR/logs/slot-$slot.log"
    
    if [ -f "$log_file" ]; then
        tail -n "$lines" "$log_file"
    else
        echo "No logs found for slot $slot"
    fi
}

# Function to monitor processes and restart if needed
monitor_processes() {
    log "Starting process monitor..."
    
    while true; do
        for slot in a b c d e; do
            local info=$(get_process_info "$slot")
            local status=$(echo "$info" | jq -r '.status')
            
            # Check if slot should be running but isn't
            if [ -f "$CONFIG_FILE" ]; then
                local slot_config=$(jq -r ".slots.$slot" "$CONFIG_FILE" 2>/dev/null || echo "null")
                if [ "$slot_config" != "null" ]; then
                    local expected_status=$(echo "$slot_config" | jq -r '.status // "empty"')
                    local repository=$(echo "$slot_config" | jq -r '.repository // ""')
                    
                    if [ "$expected_status" = "deployed" ] && [ "$status" = "stopped" ] && [ -n "$repository" ]; then
                        log "Slot $slot should be running but is stopped. Attempting restart..."
                        restart_slot "$slot" || log_error "Failed to restart slot $slot"
                    fi
                fi
            fi
        done
        
        sleep 30  # Check every 30 seconds
    done
}

# Function to show process status in a table format
status_table() {
    printf "%-5s %-6s %-8s %-10s %-10s %-8s %s\n" "SLOT" "PORT" "STATUS" "PID" "MEMORY" "CPU" "START TIME"
    printf "%-5s %-6s %-8s %-10s %-10s %-8s %s\n" "----" "----" "------" "---" "------" "---" "----------"
    
    for slot in a b c d e; do
        local info=$(get_process_info "$slot")
        local port=$(echo "$info" | jq -r '.port')
        local status=$(echo "$info" | jq -r '.status')
        local pid=$(echo "$info" | jq -r '.pid // "-"')
        local memory=$(echo "$info" | jq -r '.memory // "-"')
        local cpu=$(echo "$info" | jq -r '.cpu // "-"')
        local start_time=$(echo "$info" | jq -r '.start_time // "-"')
        
        printf "%-5s %-6s %-8s %-10s %-10s %-8s %s\n" "$slot" "$port" "$status" "$pid" "$memory" "$cpu" "$start_time"
    done
}

# Main command handler
case "${1:-help}" in
    "list"|"ls")
        list_processes
        ;;
    "status"|"st")
        status_table
        ;;
    "stop")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 stop <slot>"
            exit 1
        fi
        stop_slot "$2"
        ;;
    "restart")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 restart <slot>"
            exit 1
        fi
        restart_slot "$2"
        ;;
    "logs")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 logs <slot> [lines]"
            exit 1
        fi
        get_logs "$2" "${3:-50}"
        ;;
    "monitor")
        monitor_processes
        ;;
    "info")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 info <slot>"
            exit 1
        fi
        get_process_info "$2" | jq .
        ;;
    "stop-all")
        for slot in a b c d e; do
            stop_slot "$slot"
        done
        ;;
    "restart-all")
        for slot in a b c d e; do
            restart_slot "$slot"
        done
        ;;
    "help"|*)
        echo "Process Management System - Commands:"
        echo "  list, ls           - List all processes (JSON)"
        echo "  status, st         - Show status table"
        echo "  stop <slot>        - Stop a slot"
        echo "  restart <slot>     - Restart a slot"
        echo "  logs <slot> [lines]- Show logs for a slot"
        echo "  monitor            - Start process monitor"
        echo "  info <slot>        - Get detailed info for a slot"
        echo "  stop-all           - Stop all slots"
        echo "  restart-all        - Restart all slots"
        echo "  help               - Show this help"
        echo ""
        echo "Slots: a, b, c, d, e"
        echo "Ports: 3001-3005"
        ;;
esac
