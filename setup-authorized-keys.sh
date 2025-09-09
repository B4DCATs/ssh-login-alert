#!/bin/bash

# SSH Alert Authorized Keys Setup
# ===============================
# Helps configure authorized_keys with SSH_USER environment variables
# for better user identification in SSH Alert notifications

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AUTHORIZED_KEYS_FILE="/root/.ssh/authorized_keys"
BACKUP_DIR="/root/.ssh/backup"

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

# Create backup
create_backup() {
    if [[ -f "$AUTHORIZED_KEYS_FILE" ]]; then
        print_info "Creating backup of authorized_keys..."
        mkdir -p "$BACKUP_DIR"
        cp "$AUTHORIZED_KEYS_FILE" "$BACKUP_DIR/authorized_keys.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"
    fi
}

# Parse existing authorized_keys
parse_existing_keys() {
    local keys=()
    
    if [[ -f "$AUTHORIZED_KEYS_FILE" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" && ! "$line" =~ ^# ]]; then
                keys+=("$line")
            fi
        done < "$AUTHORIZED_KEYS_FILE"
    fi
    
    printf '%s\n' "${keys[@]}"
}

# Generate key fingerprint
get_key_fingerprint() {
    local key_line="$1"
    local key_data=$(echo "$key_line" | awk '{print $2}')
    
    if [[ -n "$key_data" ]]; then
        echo "$key_data" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || echo "unknown"
    else
        echo "unknown"
    fi
}

# Get key comment
get_key_comment() {
    local key_line="$1"
    echo "$key_line" | awk '{print $NF}'
}

# Add SSH_USER to key line
add_ssh_user_to_key() {
    local key_line="$1"
    local ssh_user="$2"
    
    # Check if SSH_USER is already present
    if echo "$key_line" | grep -q "environment=\"SSH_USER="; then
        echo "$key_line"
        return
    fi
    
    # Add SSH_USER environment variable
    local key_type=$(echo "$key_line" | awk '{print $1}')
    local key_data=$(echo "$key_line" | awk '{print $2}')
    local comment=$(echo "$key_line" | awk '{print $NF}')
    
    echo "environment=\"SSH_USER=$ssh_user\" $key_type $key_data $comment"
}

# Interactive key setup
interactive_setup() {
    print_info "Starting interactive authorized_keys setup..."
    echo
    
    local existing_keys=()
    while IFS= read -r line; do
        existing_keys+=("$line")
    done < <(parse_existing_keys)
    
    if [[ ${#existing_keys[@]} -eq 0 ]]; then
        print_warning "No existing keys found in $AUTHORIZED_KEYS_FILE"
        echo
        print_info "You can add keys manually or use this script to add new ones."
        read -p "Do you want to add a new key? (y/n): " add_new
        if [[ "$add_new" =~ ^[Yy]$ ]]; then
            add_new_key
        fi
        return
    fi
    
    print_info "Found ${#existing_keys[@]} existing key(s):"
    echo
    
    local i=1
    for key in "${existing_keys[@]}"; do
        local fingerprint=$(get_key_fingerprint "$key")
        local comment=$(get_key_comment "$key")
        
        echo "$i) Fingerprint: $fingerprint"
        echo "   Comment: $comment"
        echo "   Key: ${key:0:50}..."
        echo
        ((i++))
    done
    
    echo "Options:"
    echo "  [1-${#existing_keys[@]}] - Configure SSH_USER for existing key"
    echo "  [n] - Add new key"
    echo "  [q] - Quit"
    echo
    
    read -p "Select option: " choice
    
    case "$choice" in
        [1-9]*)
            if [[ "$choice" -ge 1 && "$choice" -le ${#existing_keys[@]} ]]; then
                local selected_key="${existing_keys[$((choice-1))]}"
                configure_existing_key "$selected_key"
            else
                print_error "Invalid selection"
            fi
            ;;
        [Nn])
            add_new_key
            ;;
        [Qq])
            print_info "Exiting..."
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Configure existing key
configure_existing_key() {
    local key_line="$1"
    local fingerprint=$(get_key_fingerprint "$key_line")
    local comment=$(get_key_comment "$key_line")
    
    echo
    print_info "Configuring key: $fingerprint"
    print_info "Current comment: $comment"
    echo
    
    # Check if SSH_USER is already set
    if echo "$key_line" | grep -q "environment=\"SSH_USER="; then
        local current_user=$(echo "$key_line" | sed -n 's/.*environment="SSH_USER=\([^"]*\)".*/\1/p')
        print_info "SSH_USER is already set to: $current_user"
        read -p "Do you want to change it? (y/n): " change_user
        if [[ ! "$change_user" =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    read -p "Enter SSH_USER for this key (e.g., alice@example.com): " ssh_user
    
    if [[ -n "$ssh_user" ]]; then
        local new_key_line=$(add_ssh_user_to_key "$key_line" "$ssh_user")
        update_authorized_keys "$key_line" "$new_key_line"
        print_success "SSH_USER configured for key: $ssh_user"
    else
        print_warning "SSH_USER not set"
    fi
}

# Add new key
add_new_key() {
    echo
    print_info "Adding new SSH key..."
    echo
    
    read -p "Enter the public key: " public_key
    
    if [[ -z "$public_key" ]]; then
        print_error "Public key cannot be empty"
        return
    fi
    
    # Validate key format
    if ! echo "$public_key" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)"; then
        print_error "Invalid key format"
        return
    fi
    
    read -p "Enter SSH_USER for this key (e.g., alice@example.com): " ssh_user
    read -p "Enter comment for this key (optional): " comment
    
    # Build the key line
    local key_line="$public_key"
    if [[ -n "$comment" ]]; then
        key_line="$key_line $comment"
    fi
    
    # Add SSH_USER if provided
    if [[ -n "$ssh_user" ]]; then
        key_line=$(add_ssh_user_to_key "$key_line" "$ssh_user")
    fi
    
    # Add to authorized_keys
    echo "$key_line" >> "$AUTHORIZED_KEYS_FILE"
    chmod 600 "$AUTHORIZED_KEYS_FILE"
    chown root:root "$AUTHORIZED_KEYS_FILE"
    
    print_success "Key added successfully"
    
    local fingerprint=$(get_key_fingerprint "$key_line")
    print_info "Key fingerprint: $fingerprint"
}

# Update authorized_keys file
update_authorized_keys() {
    local old_line="$1"
    local new_line="$2"
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Replace the line
    while IFS= read -r line; do
        if [[ "$line" == "$old_line" ]]; then
            echo "$new_line" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$AUTHORIZED_KEYS_FILE"
    
    # Replace original file
    mv "$temp_file" "$AUTHORIZED_KEYS_FILE"
    chmod 600 "$AUTHORIZED_KEYS_FILE"
    chown root:root "$AUTHORIZED_KEYS_FILE"
}

# Show current configuration
show_configuration() {
    print_info "Current authorized_keys configuration:"
    echo
    
    if [[ ! -f "$AUTHORIZED_KEYS_FILE" ]]; then
        print_warning "Authorized keys file not found: $AUTHORIZED_KEYS_FILE"
        return
    fi
    
    local line_num=1
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            local fingerprint=$(get_key_fingerprint "$line")
            local comment=$(get_key_comment "$line")
            
            echo "Key #$line_num:"
            echo "  Fingerprint: $fingerprint"
            echo "  Comment: $comment"
            
            # Check for SSH_USER
            if echo "$line" | grep -q "environment=\"SSH_USER="; then
                local ssh_user=$(echo "$line" | sed -n 's/.*environment="SSH_USER=\([^"]*\)".*/\1/p')
                echo "  SSH_USER: $ssh_user"
            else
                echo "  SSH_USER: Not set"
            fi
            echo
            ((line_num++))
        fi
    done < "$AUTHORIZED_KEYS_FILE"
}

# Test SSH Alert integration
test_ssh_alert() {
    print_info "Testing SSH Alert integration..."
    
    if [[ ! -f "/opt/ssh-alert/ssh-alert-enhanced.sh" ]]; then
        print_warning "SSH Alert not installed. Please run install.sh first."
        return
    fi
    
    # Test key parser
    if python3 /opt/ssh-alert/key-parser.py get-info > /dev/null 2>&1; then
        print_success "SSH Alert key parser test passed"
    else
        print_error "SSH Alert key parser test failed"
    fi
    
    # Test configuration
    if [[ -f "/etc/ssh-alert/config.conf" ]]; then
        print_success "SSH Alert configuration found"
    else
        print_warning "SSH Alert configuration not found"
    fi
}

# Main function
main() {
    echo "SSH Alert Authorized Keys Setup"
    echo "==============================="
    echo
    
    check_root
    create_backup
    
    while true; do
        echo "Options:"
        echo "  [1] - Interactive setup"
        echo "  [2] - Show current configuration"
        echo "  [3] - Test SSH Alert integration"
        echo "  [4] - Add new key"
        echo "  [q] - Quit"
        echo
        
        read -p "Select option: " choice
        
        case "$choice" in
            1)
                interactive_setup
                ;;
            2)
                show_configuration
                ;;
            3)
                test_ssh_alert
                ;;
            4)
                add_new_key
                ;;
            [Qq])
                print_info "Exiting..."
                break
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        echo
    done
    
    print_success "Setup completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
