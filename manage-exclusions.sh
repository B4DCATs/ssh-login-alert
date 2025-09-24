#!/bin/bash

# SSH Alert - Key Exclusions Manager
# ==================================
# Script to manage key exclusions from SSH alerts
# Author: SSH Alert System
# Version: 1.0.0

set -euo pipefail

# Configuration
CONFIG_FILE="/etc/ssh-alert/config.conf"
BACKUP_DIR="/etc/ssh-alert/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Load current configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    source "$CONFIG_FILE"
}

# Backup configuration
backup_config() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/config.conf.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    log "Configuration backed up to: $backup_file"
}

# Get current exclusions
get_current_exclusions() {
    if [[ -n "${EXCLUDED_KEY_COMMENTS:-}" ]]; then
        echo "$EXCLUDED_KEY_COMMENTS"
    else
        echo ""
    fi
}

# Add exclusion
add_exclusion() {
    local new_exclusion="$1"
    local current_exclusions=$(get_current_exclusions)
    
    # Check if already exists
    if [[ -n "$current_exclusions" ]]; then
        IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
        for excluded in "${EXCLUDED[@]}"; do
            excluded=$(echo "$excluded" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$excluded" == "$new_exclusion" ]]; then
                log_warning "Exclusion '$new_exclusion' already exists"
                return 0
            fi
        done
        
        # Add to existing list
        new_exclusions="$current_exclusions,$new_exclusion"
    else
        new_exclusions="$new_exclusion"
    fi
    
    # Update configuration
    backup_config
    sed -i "s/^EXCLUDED_KEY_COMMENTS=.*/EXCLUDED_KEY_COMMENTS=\"$new_exclusions\"/" "$CONFIG_FILE"
    log_success "Added exclusion: $new_exclusion"
}

# Remove exclusion
remove_exclusion() {
    local exclusion_to_remove="$1"
    local current_exclusions=$(get_current_exclusions)
    
    if [[ -z "$current_exclusions" ]]; then
        log_warning "No exclusions configured"
        return 0
    fi
    
    # Parse and filter exclusions
    local new_exclusions=""
    IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
    for excluded in "${EXCLUDED[@]}"; do
        excluded=$(echo "$excluded" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$excluded" != "$exclusion_to_remove" ]]; then
            if [[ -n "$new_exclusions" ]]; then
                new_exclusions="$new_exclusions,$excluded"
            else
                new_exclusions="$excluded"
            fi
        fi
    done
    
    # Update configuration
    backup_config
    if [[ -n "$new_exclusions" ]]; then
        sed -i "s/^EXCLUDED_KEY_COMMENTS=.*/EXCLUDED_KEY_COMMENTS=\"$new_exclusions\"/" "$CONFIG_FILE"
    else
        sed -i "s/^EXCLUDED_KEY_COMMENTS=.*/EXCLUDED_KEY_COMMENTS=\"\"/" "$CONFIG_FILE"
    fi
    
    log_success "Removed exclusion: $exclusion_to_remove"
}

# List exclusions
list_exclusions() {
    local current_exclusions=$(get_current_exclusions)
    
    if [[ -z "$current_exclusions" ]]; then
        log "No exclusions configured"
        return 0
    fi
    
    log "Current exclusions:"
    IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
    for i in "${!EXCLUDED[@]}"; do
        local excluded=$(echo "${EXCLUDED[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "  $((i+1)). $excluded"
    done
}

# Clear all exclusions
clear_exclusions() {
    backup_config
    sed -i "s/^EXCLUDED_KEY_COMMENTS=.*/EXCLUDED_KEY_COMMENTS=\"\"/" "$CONFIG_FILE"
    log_success "Cleared all exclusions"
}

# Show help
show_help() {
    cat << EOF
SSH Alert - Key Exclusions Manager
==================================

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  add <comment>      Add a key comment to exclusions
  remove <comment>   Remove a key comment from exclusions
  list              List current exclusions
  clear             Clear all exclusions
  help              Show this help message

Examples:
  $0 add "pipeline@ci"
  $0 add "deploy@automation"
  $0 remove "pipeline@ci"
  $0 list
  $0 clear

Notes:
  - Key comments are matched exactly or as substrings
  - Multiple exclusions are comma-separated
  - Configuration is automatically backed up before changes
  - Changes take effect immediately for new connections

EOF
}

# Main function
main() {
    check_root
    load_config
    
    case "${1:-help}" in
        "add")
            if [[ -z "${2:-}" ]]; then
                log_error "Please provide a key comment to exclude"
                echo "Usage: $0 add <comment>"
                exit 1
            fi
            add_exclusion "$2"
            ;;
        "remove")
            if [[ -z "${2:-}" ]]; then
                log_error "Please provide a key comment to remove from exclusions"
                echo "Usage: $0 remove <comment>"
                exit 1
            fi
            remove_exclusion "$2"
            ;;
        "list")
            list_exclusions
            ;;
        "clear")
            echo -n "Are you sure you want to clear all exclusions? (y/N): "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                clear_exclusions
            else
                log "Operation cancelled"
            fi
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
