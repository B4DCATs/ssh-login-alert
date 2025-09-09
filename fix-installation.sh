#!/bin/bash

# SSH Alert Fix Installation Script
# =================================
# Fixes common installation issues

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

# Fix sshrc syntax
fix_sshrc() {
    print_info "Fixing /etc/ssh/sshrc syntax..."
    
    if [[ -f "/etc/ssh/sshrc" ]]; then
        # Create backup
        cp "/etc/ssh/sshrc" "/etc/ssh/sshrc.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Fix the syntax issue
        sed -i 's/if \[\[ -n/if [ -n/g' "/etc/ssh/sshrc"
        
        print_success "Fixed sshrc syntax"
    else
        print_warning "/etc/ssh/sshrc not found"
    fi
}

# Fix configuration file path
fix_config_path() {
    print_info "Fixing configuration file path..."
    
    # Check if config exists in wrong location
    if [[ -f "/opt/ssh-alert/config.conf" ]]; then
        print_info "Moving config from /opt/ssh-alert/ to /etc/ssh-alert/"
        mkdir -p "/etc/ssh-alert"
        mv "/opt/ssh-alert/config.conf" "/etc/ssh-alert/config.conf"
        chmod 600 "/etc/ssh-alert/config.conf"
        chown root:root "/etc/ssh-alert/config.conf"
        print_success "Configuration file moved"
    elif [[ -f "/etc/ssh-alert/config.conf" ]]; then
        print_success "Configuration file already in correct location"
    else
        print_warning "No configuration file found"
    fi
}

# Update scripts with correct config path
update_scripts() {
    print_info "Updating scripts with correct configuration path..."
    
    # Update ssh-alert-enhanced.sh
    if [[ -f "/opt/ssh-alert/ssh-alert-enhanced.sh" ]]; then
        sed -i 's|CONFIG_FILE="${SCRIPT_DIR}/config.conf"|CONFIG_FILE="/etc/ssh-alert/config.conf"|g' "/opt/ssh-alert/ssh-alert-enhanced.sh"
        print_success "Updated ssh-alert-enhanced.sh"
    fi
    
    # Update ssh-alert.sh
    if [[ -f "/opt/ssh-alert/ssh-alert.sh" ]]; then
        sed -i 's|CONFIG_FILE="${SCRIPT_DIR}/config.conf"|CONFIG_FILE="/etc/ssh-alert/config.conf"|g' "/opt/ssh-alert/ssh-alert.sh"
        print_success "Updated ssh-alert.sh"
    fi
}

# Test the fix
test_fix() {
    print_info "Testing the fix..."
    
    # Test sshrc syntax
    if bash -n "/etc/ssh/sshrc" 2>/dev/null; then
        print_success "sshrc syntax is correct"
    else
        print_error "sshrc still has syntax errors"
        return 1
    fi
    
    # Test if config is accessible
    if [[ -f "/etc/ssh-alert/config.conf" ]]; then
        print_success "Configuration file is accessible"
    else
        print_error "Configuration file not found"
        return 1
    fi
    
    # Test script syntax
    if bash -n "/opt/ssh-alert/ssh-alert-enhanced.sh" 2>/dev/null; then
        print_success "Script syntax is correct"
    else
        print_error "Script has syntax errors"
        return 1
    fi
}

# Main function
main() {
    echo "SSH Alert Fix Installation Script"
    echo "================================="
    echo
    
    check_root
    
    fix_sshrc
    fix_config_path
    update_scripts
    test_fix
    
    echo
    print_success "Installation fix completed!"
    echo
    print_info "You can now test SSH Alert by connecting via SSH"
    print_info "Check logs with: tail -f /var/log/ssh-alert.log"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
