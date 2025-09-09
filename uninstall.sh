#!/bin/bash

# SSH Alert Uninstall Script
# ==========================
# Safely removes SSH Alert from the system

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

# Show warning and get confirmation
confirm_uninstall() {
    echo "SSH Alert Uninstall Script"
    echo "========================="
    echo
    print_warning "This will completely remove SSH Alert from your system."
    print_warning "The following will be removed:"
    echo "  - SSH Alert files from /opt/ssh-alert/"
    echo "  - Configuration files from /etc/ssh-alert/"
    echo "  - SSH integration from /etc/ssh/sshrc"
    echo "  - Systemd service (if installed)"
    echo "  - Log rotation configuration"
    echo "  - Temporary files and rate limiting data"
    echo
    print_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
}

# Stop SSH Alert processes
stop_processes() {
    print_info "Stopping SSH Alert processes..."
    
    # Kill any running SSH Alert processes
    pkill -f "ssh-alert" 2>/dev/null || true
    
    # Stop systemd service if it exists
    if systemctl is-active --quiet ssh-alert 2>/dev/null; then
        systemctl stop ssh-alert 2>/dev/null || true
    fi
    
    print_success "Processes stopped"
}

# Remove SSH integration
remove_ssh_integration() {
    print_info "Removing SSH integration..."
    
    # Backup current sshrc
    if [[ -f "/etc/ssh/sshrc" ]]; then
        cp "/etc/ssh/sshrc" "/etc/ssh/sshrc.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backed up /etc/ssh/sshrc"
    fi
    
    # Remove SSH Alert from sshrc
    if [[ -f "/etc/ssh/sshrc" ]]; then
        # Remove SSH Alert lines
        sed -i '/# SSH Alert Integration/,/^$/d' "/etc/ssh/sshrc"
        sed -i '/ssh-alert/d' "/etc/ssh/sshrc"
        
        # If sshrc is now empty or only contains comments, remove it
        if [[ ! -s "/etc/ssh/sshrc" ]] || [[ -z "$(grep -v '^#' /etc/ssh/sshrc)" ]]; then
            rm -f "/etc/ssh/sshrc"
            print_info "Removed empty /etc/ssh/sshrc"
        else
            print_info "Cleaned /etc/ssh/sshrc"
        fi
    fi
    
    # Remove AuthorizedKeysCommand if it was added
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        if grep -q "AuthorizedKeysCommand.*ssh-alert" "/etc/ssh/sshd_config"; then
            # Backup sshd_config
            cp "/etc/ssh/sshd_config" "/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Remove AuthorizedKeysCommand lines
            sed -i '/# SSH Alert AuthorizedKeysCommand/d' "/etc/ssh/sshd_config"
            sed -i '/AuthorizedKeysCommand.*ssh-alert/d' "/etc/ssh/sshd_config"
            sed -i '/AuthorizedKeysCommandUser root/d' "/etc/ssh/sshd_config"
            
            print_info "Removed AuthorizedKeysCommand from sshd_config"
            print_warning "You may need to restart SSH service: systemctl restart sshd"
        fi
    fi
    
    print_success "SSH integration removed"
}

# Remove systemd service
remove_systemd_service() {
    print_info "Removing systemd service..."
    
    if [[ -f "/etc/systemd/system/ssh-alert.service" ]]; then
        systemctl stop ssh-alert 2>/dev/null || true
        systemctl disable ssh-alert 2>/dev/null || true
        rm -f "/etc/systemd/system/ssh-alert.service"
        systemctl daemon-reload
        print_success "Systemd service removed"
    else
        print_info "No systemd service found"
    fi
}

# Remove log rotation
remove_log_rotation() {
    print_info "Removing log rotation configuration..."
    
    if [[ -f "/etc/logrotate.d/ssh-alert" ]]; then
        rm -f "/etc/logrotate.d/ssh-alert"
        print_success "Log rotation configuration removed"
    else
        print_info "No log rotation configuration found"
    fi
}

# Remove files and directories
remove_files() {
    print_info "Removing SSH Alert files..."
    
    # Remove main directories
    if [[ -d "/opt/ssh-alert" ]]; then
        rm -rf "/opt/ssh-alert"
        print_success "Removed /opt/ssh-alert"
    fi
    
    if [[ -d "/etc/ssh-alert" ]]; then
        rm -rf "/etc/ssh-alert"
        print_success "Removed /etc/ssh-alert"
    fi
    
    # Remove temporary files
    rm -f "/tmp/ssh-alert.lock"
    rm -rf "/tmp/ssh-alert-rate-limit"
    print_success "Removed temporary files"
}

# Clean up logs
cleanup_logs() {
    print_info "Cleaning up logs..."
    
    if [[ -f "/var/log/ssh-alert.log" ]]; then
        print_warning "Log file /var/log/ssh-alert.log still exists"
        print_info "You can remove it manually if not needed: rm /var/log/ssh-alert.log"
    fi
}

# Verify removal
verify_removal() {
    print_info "Verifying removal..."
    
    local errors=0
    
    # Check if files still exist
    if [[ -d "/opt/ssh-alert" ]]; then
        print_error "/opt/ssh-alert still exists"
        ((errors++))
    fi
    
    if [[ -d "/etc/ssh-alert" ]]; then
        print_error "/etc/ssh-alert still exists"
        ((errors++))
    fi
    
    if [[ -f "/etc/ssh/sshrc" ]] && grep -q "ssh-alert" "/etc/ssh/sshrc"; then
        print_error "SSH Alert references still found in /etc/ssh/sshrc"
        ((errors++))
    fi
    
    if [[ -f "/etc/systemd/system/ssh-alert.service" ]]; then
        print_error "Systemd service still exists"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_success "SSH Alert successfully removed"
        return 0
    else
        print_error "Some files could not be removed. Please check manually."
        return 1
    fi
}

# Show completion message
show_completion() {
    echo
    print_success "SSH Alert uninstall completed!"
    echo
    print_info "Summary of actions taken:"
    echo "  ✓ Stopped SSH Alert processes"
    echo "  ✓ Removed SSH integration"
    echo "  ✓ Removed systemd service"
    echo "  ✓ Removed log rotation configuration"
    echo "  ✓ Removed SSH Alert files"
    echo "  ✓ Cleaned up temporary files"
    echo
    print_warning "Important notes:"
    echo "  - SSH service may need to be restarted: systemctl restart sshd"
    echo "  - Log files may still exist in /var/log/ssh-alert.log"
    echo "  - Backup files were created with timestamps"
    echo
    print_info "SSH Alert has been completely removed from your system."
}

# Main function
main() {
    check_root
    confirm_uninstall
    
    stop_processes
    remove_ssh_integration
    remove_systemd_service
    remove_log_rotation
    remove_files
    cleanup_logs
    
    if verify_removal; then
        show_completion
        exit 0
    else
        print_error "Uninstall completed with errors"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
