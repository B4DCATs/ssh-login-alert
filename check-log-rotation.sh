#!/bin/bash

# SSH Alert Log Rotation Checker
# ==============================
# Checks and manages log rotation for SSH Alert

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check logrotate configuration
check_logrotate_config() {
    print_info "Checking logrotate configuration..."
    
    local config_file="/etc/logrotate.d/ssh-alert"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Logrotate configuration not found: $config_file"
        return 1
    fi
    
    print_success "Logrotate configuration found"
    
    # Test configuration
    if logrotate -d "$config_file" >/dev/null 2>&1; then
        print_success "Logrotate configuration is valid"
    else
        print_error "Logrotate configuration has errors"
        logrotate -d "$config_file"
        return 1
    fi
}

# Check log file status
check_log_status() {
    print_info "Checking log file status..."
    
    local log_file="/var/log/ssh-alert.log"
    
    if [[ ! -f "$log_file" ]]; then
        print_warning "Log file not found: $log_file"
        return 0
    fi
    
    local size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
    local size_mb=$((size / 1024 / 1024))
    
    print_info "Log file size: ${size_mb}MB"
    
    if [[ $size_mb -gt 100 ]]; then
        print_warning "Log file is large (${size_mb}MB). Consider manual rotation."
    else
        print_success "Log file size is reasonable"
    fi
}

# Check rate limiting directory
check_rate_limit_dir() {
    print_info "Checking rate limiting directory..."
    
    local rate_dir="/tmp/ssh-alert-rate-limit"
    
    if [[ ! -d "$rate_dir" ]]; then
        print_info "Rate limiting directory not found (normal if no connections yet)"
        return 0
    fi
    
    local file_count=$(find "$rate_dir" -type f 2>/dev/null | wc -l)
    local old_count=$(find "$rate_dir/old" -type f 2>/dev/null | wc -l || echo "0")
    
    print_info "Active rate limit files: $file_count"
    print_info "Old rate limit files: $old_count"
    
    if [[ $file_count -gt 100 ]]; then
        print_warning "Many rate limit files found. Consider cleanup."
    else
        print_success "Rate limiting directory is clean"
    fi
}

# Test log rotation
test_log_rotation() {
    print_info "Testing log rotation..."
    
    local config_file="/etc/logrotate.d/ssh-alert"
    local log_file="/var/log/ssh-alert.log"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Logrotate configuration not found"
        return 1
    fi
    
    # Create test log file if it doesn't exist
    if [[ ! -f "$log_file" ]]; then
        print_info "Creating test log file..."
        echo "$(date): Test log entry" > "$log_file"
        chmod 644 "$log_file"
    fi
    
    # Test rotation in dry-run mode
    if logrotate -d "$config_file" >/dev/null 2>&1; then
        print_success "Log rotation test passed"
    else
        print_error "Log rotation test failed"
        return 1
    fi
}

# Force log rotation
force_rotation() {
    print_info "Forcing log rotation..."
    
    local config_file="/etc/logrotate.d/ssh-alert"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Logrotate configuration not found"
        return 1
    fi
    
    if logrotate -f "$config_file"; then
        print_success "Log rotation completed"
    else
        print_error "Log rotation failed"
        return 1
    fi
}

# Clean old logs
clean_old_logs() {
    print_info "Cleaning old logs..."
    
    local log_file="/var/log/ssh-alert.log"
    local rotated_logs=0
    
    # Count rotated logs
    for i in {1..30}; do
        if [[ -f "${log_file}.${i}.gz" ]]; then
            ((rotated_logs++))
        fi
    done
    
    print_info "Found $rotated_logs rotated log files"
    
    if [[ $rotated_logs -gt 0 ]]; then
        print_info "Rotated logs:"
        ls -lh "${log_file}".*.gz 2>/dev/null | head -10
    fi
}

# Show log rotation status
show_status() {
    print_info "Log Rotation Status"
    print_info "==================="
    echo
    
    # Check configuration
    check_logrotate_config
    echo
    
    # Check log status
    check_log_status
    echo
    
    # Check rate limiting
    check_rate_limit_dir
    echo
    
    # Show rotated logs
    clean_old_logs
}

# Main function
main() {
    local action="${1:-status}"
    
    check_root
    
    case "$action" in
        "status")
            show_status
            ;;
        "test")
            test_log_rotation
            ;;
        "rotate")
            force_rotation
            ;;
        "clean")
            clean_old_logs
            ;;
        "check")
            check_logrotate_config
            check_log_status
            check_rate_limit_dir
            ;;
        *)
            echo "Usage: $0 {status|test|rotate|clean|check}"
            echo
            echo "Commands:"
            echo "  status  - Show complete log rotation status"
            echo "  test    - Test log rotation configuration"
            echo "  rotate  - Force log rotation"
            echo "  clean   - Show old rotated logs"
            echo "  check   - Check configuration and files"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
