#!/bin/bash
# Shared logging utilities for PM2 PaaS scripts

# Default log file (can be overridden by setting LOG_FILE before sourcing)
: ${LOG_FILE:="/dev/null"}

# Logging functions
log() {
    local message="$1"
    if [ "$LOG_FILE" != "/dev/null" ] && [ -n "$LOG_FILE" ]; then
        echo "$message" | tee -a "$LOG_FILE"
    else
        echo "$message"
    fi
}

log_with_timestamp() {
    local message="$1"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    if [ "$LOG_FILE" != "/dev/null" ] && [ -n "$LOG_FILE" ]; then
        echo "$timestamp $message" | tee -a "$LOG_FILE"
    else
        echo "$timestamp $message"
    fi
}

log_error() {
    local message="$1"
    local full_message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message"
    if [ "$LOG_FILE" != "/dev/null" ] && [ -n "$LOG_FILE" ]; then
        echo "$full_message" | tee -a "$LOG_FILE" >&2
    else
        echo "$full_message" >&2
    fi
}

log_success() {
    local message="$1"
    local full_message="[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $message"
    if [ "$LOG_FILE" != "/dev/null" ] && [ -n "$LOG_FILE" ]; then
        echo "$full_message" | tee -a "$LOG_FILE"
    else
        echo "$full_message"
    fi
}

log_warning() {
    local message="$1"
    local full_message="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $message"
    if [ "$LOG_FILE" != "/dev/null" ] && [ -n "$LOG_FILE" ]; then
        echo "$full_message" | tee -a "$LOG_FILE"
    else
        echo "$full_message"
    fi
}

# Export functions for use in other scripts
export -f log log_with_timestamp log_error log_success log_warning
