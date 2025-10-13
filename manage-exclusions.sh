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

# Add IP exclusion
add_ip_exclusion() {
    local new_exclusion="$1"
    local current_exclusions="${EXCLUDED_IPS:-}"
    
    # Check if already exists
    if [[ -n "$current_exclusions" ]]; then
        IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
        for excluded in "${EXCLUDED[@]}"; do
            excluded=$(echo "$excluded" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$excluded" == "$new_exclusion" ]]; then
                log_warning "IP exclusion '$new_exclusion' already exists"
                return 0
            fi
        done
        
        new_exclusions="$current_exclusions,$new_exclusion"
    else
        new_exclusions="$new_exclusion"
    fi
    
    # Update configuration
    backup_config
    sed -i "s/^EXCLUDED_IPS=.*/EXCLUDED_IPS=\"$new_exclusions\"/" "$CONFIG_FILE"
    log_success "Added IP exclusion: $new_exclusion"
}

# Remove IP exclusion
remove_ip_exclusion() {
    local exclusion_to_remove="$1"
    local current_exclusions="${EXCLUDED_IPS:-}"
    
    if [[ -z "$current_exclusions" ]]; then
        log_warning "No IP exclusions configured"
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
    sed -i "s/^EXCLUDED_IPS=.*/EXCLUDED_IPS=\"$new_exclusions\"/" "$CONFIG_FILE"
    log_success "Removed IP exclusion: $exclusion_to_remove"
}

# Add username exclusion
add_username_exclusion() {
    local new_exclusion="$1"
    local current_exclusions="${EXCLUDED_USERNAMES:-}"
    
    # Check if already exists
    if [[ -n "$current_exclusions" ]]; then
        IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
        for excluded in "${EXCLUDED[@]}"; do
            excluded=$(echo "$excluded" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$excluded" == "$new_exclusion" ]]; then
                log_warning "Username exclusion '$new_exclusion' already exists"
                return 0
            fi
        done
        
        new_exclusions="$current_exclusions,$new_exclusion"
    else
        new_exclusions="$new_exclusion"
    fi
    
    # Update configuration
    backup_config
    sed -i "s/^EXCLUDED_USERNAMES=.*/EXCLUDED_USERNAMES=\"$new_exclusions\"/" "$CONFIG_FILE"
    log_success "Added username exclusion: $new_exclusion"
}

# Remove username exclusion
remove_username_exclusion() {
    local exclusion_to_remove="$1"
    local current_exclusions="${EXCLUDED_USERNAMES:-}"
    
    if [[ -z "$current_exclusions" ]]; then
        log_warning "No username exclusions configured"
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
    sed -i "s/^EXCLUDED_USERNAMES=.*/EXCLUDED_USERNAMES=\"$new_exclusions\"/" "$CONFIG_FILE"
    log_success "Removed username exclusion: $exclusion_to_remove"
}

# List IP exclusions
list_ip_exclusions() {
    local current_exclusions="${EXCLUDED_IPS:-}"
    
    if [[ -z "$current_exclusions" ]]; then
        log "No IP exclusions configured"
        return 0
    fi
    
    log "Current IP exclusions:"
    IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
    for i in "${!EXCLUDED[@]}"; do
        local excluded=$(echo "${EXCLUDED[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "  $((i+1)). $excluded"
    done
}

# List username exclusions
list_username_exclusions() {
    local current_exclusions="${EXCLUDED_USERNAMES:-}"
    
    if [[ -z "$current_exclusions" ]]; then
        log "No username exclusions configured"
        return 0
    fi
    
    log "Current username exclusions:"
    IFS=',' read -ra EXCLUDED <<< "$current_exclusions"
    for i in "${!EXCLUDED[@]}"; do
        local excluded=$(echo "${EXCLUDED[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "  $((i+1)). $excluded"
    done
}

# Clear IP exclusions
clear_ip_exclusions() {
    backup_config
    sed -i "s/^EXCLUDED_IPS=.*/EXCLUDED_IPS=\"\"/" "$CONFIG_FILE"
    log_success "Cleared all IP exclusions"
}

# Clear username exclusions
clear_username_exclusions() {
    backup_config
    sed -i "s/^EXCLUDED_USERNAMES=.*/EXCLUDED_USERNAMES=\"\"/" "$CONFIG_FILE"
    log_success "Cleared all username exclusions"
}

# Show help
show_help() {
    cat << EOF
SSH Alert - Exclusions Manager
==============================

Usage: $0 [COMMAND] [TYPE] [VALUE]

Commands:
  add <type> <value>      Add an exclusion
  remove <type> <value>   Remove an exclusion
  list [type]             List current exclusions
  clear <type>            Clear all exclusions of a type
  help                    Show this help message

Types:
  key                     Key comment exclusions
  ip                      IP address exclusions
  user                    Username exclusions

Examples:
  # Key comment exclusions
  $0 add key "pipeline@ci"
  $0 add key "deploy@automation"
  $0 remove key "pipeline@ci"
  
  # IP address exclusions
  $0 add ip "192.168.1.100"
  $0 add ip "10.0.0.50"
  $0 remove ip "192.168.1.100"
  
  # Username exclusions
  $0 add user "gitlab-runner"
  $0 add user "jenkins"
  $0 remove user "gitlab-runner"
  
  # List exclusions
  $0 list                 # List all exclusions
  $0 list key             # List only key exclusions
  $0 list ip              # List only IP exclusions
  $0 list user            # List only username exclusions
  
  # Clear exclusions
  $0 clear key            # Clear all key exclusions
  $0 clear ip             # Clear all IP exclusions
  $0 clear user           # Clear all username exclusions

Notes:
  - Key comments are matched exactly or as substrings
  - IP addresses and usernames are matched exactly
  - Multiple exclusions are comma-separated
  - Configuration is automatically backed up before changes
  - Changes take effect immediately for new connections

EOF
}

# Main function
main() {
    check_root
    load_config
    
    local command="${1:-help}"
    local type="${2:-}"
    local value="${3:-}"
    
    case "$command" in
        "add")
            if [[ -z "$type" ]]; then
                log_error "Please specify exclusion type (key, ip, or user)"
                echo "Usage: $0 add <type> <value>"
                exit 1
            fi
            
            if [[ -z "$value" ]]; then
                log_error "Please provide a value to exclude"
                echo "Usage: $0 add <type> <value>"
                exit 1
            fi
            
            case "$type" in
                "key")
                    add_exclusion "$value"
                    ;;
                "ip")
                    add_ip_exclusion "$value"
                    ;;
                "user")
                    add_username_exclusion "$value"
                    ;;
                *)
                    log_error "Unknown exclusion type: $type"
                    echo "Valid types: key, ip, user"
                    exit 1
                    ;;
            esac
            ;;
            
        "remove")
            if [[ -z "$type" ]]; then
                log_error "Please specify exclusion type (key, ip, or user)"
                echo "Usage: $0 remove <type> <value>"
                exit 1
            fi
            
            if [[ -z "$value" ]]; then
                log_error "Please provide a value to remove"
                echo "Usage: $0 remove <type> <value>"
                exit 1
            fi
            
            case "$type" in
                "key")
                    remove_exclusion "$value"
                    ;;
                "ip")
                    remove_ip_exclusion "$value"
                    ;;
                "user")
                    remove_username_exclusion "$value"
                    ;;
                *)
                    log_error "Unknown exclusion type: $type"
                    echo "Valid types: key, ip, user"
                    exit 1
                    ;;
            esac
            ;;
            
        "list")
            if [[ -z "$type" ]]; then
                # List all exclusions
                echo ""
                list_exclusions
                echo ""
                list_ip_exclusions
                echo ""
                list_username_exclusions
                echo ""
            else
                case "$type" in
                    "key")
                        list_exclusions
                        ;;
                    "ip")
                        list_ip_exclusions
                        ;;
                    "user")
                        list_username_exclusions
                        ;;
                    *)
                        log_error "Unknown exclusion type: $type"
                        echo "Valid types: key, ip, user"
                        exit 1
                        ;;
                esac
            fi
            ;;
            
        "clear")
            if [[ -z "$type" ]]; then
                log_error "Please specify exclusion type to clear (key, ip, or user)"
                echo "Usage: $0 clear <type>"
                exit 1
            fi
            
            case "$type" in
                "key")
                    echo -n "Are you sure you want to clear all key exclusions? (y/N): "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        clear_exclusions
                    else
                        log "Operation cancelled"
                    fi
                    ;;
                "ip")
                    echo -n "Are you sure you want to clear all IP exclusions? (y/N): "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        clear_ip_exclusions
                    else
                        log "Operation cancelled"
                    fi
                    ;;
                "user")
                    echo -n "Are you sure you want to clear all username exclusions? (y/N): "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        clear_username_exclusions
                    else
                        log "Operation cancelled"
                    fi
                    ;;
                *)
                    log_error "Unknown exclusion type: $type"
                    echo "Valid types: key, ip, user"
                    exit 1
                    ;;
            esac
            ;;
            
        "help"|"--help"|"-h")
            show_help
            ;;
            
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
