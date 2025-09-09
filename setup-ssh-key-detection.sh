#!/bin/bash

# SSH Key Detection Setup
# =======================
# Helps setup SSH to pass key information to the alert system

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

# Show current authorized_keys
show_authorized_keys() {
    print_info "Current authorized_keys:"
    echo
    
    if [[ -f "/root/.ssh/authorized_keys" ]]; then
        local i=1
        while IFS= read -r line; do
            if [[ -n "$line" && ! "$line" =~ ^# ]]; then
                local key_type=$(echo "$line" | awk '{print $1}')
                local comment=$(echo "$line" | awk '{print $NF}')
                local fingerprint=$(echo "$line" | awk '{print $2}' | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || echo "unknown")
                
                echo "$i) Type: $key_type"
                echo "   Comment: $comment"
                echo "   Fingerprint: $fingerprint"
                echo
                ((i++))
            fi
        done < "/root/.ssh/authorized_keys"
    else
        print_warning "No authorized_keys file found"
    fi
}

# Setup SSH to pass key information
setup_ssh_key_detection() {
    print_info "Setting up SSH key detection..."
    
    # Create a wrapper script that will be called by sshrc
    cat > "/opt/ssh-alert/ssh-key-detector.sh" << 'EOF'
#!/bin/bash

# SSH Key Detector
# This script tries to determine which key was used for authentication

# Get the current SSH connection info
SSH_CONNECTION_INFO=$(python3 /opt/ssh-alert/key-parser.py get-info 2>/dev/null)

if [[ -n "$SSH_CONNECTION_INFO" ]]; then
    # Extract IP and username
    IP_ADDRESS=$(echo "$SSH_CONNECTION_INFO" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_address', 'unknown'))" 2>/dev/null)
    USERNAME=$(echo "$SSH_CONNECTION_INFO" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('username', 'unknown'))" 2>/dev/null)
    
    # Try to find the key used
    KEY_INFO=$(python3 /opt/ssh-alert/key-parser.py find-key-by-connection "$IP_ADDRESS" "$USERNAME" 2>/dev/null)
    
    if [[ -n "$KEY_INFO" && "$KEY_INFO" != "Key not found" ]]; then
        # Extract key information
        FINGERPRINT=$(echo "$KEY_INFO" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('fingerprint', 'unknown'))" 2>/dev/null)
        COMMENT=$(echo "$KEY_INFO" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('comment', 'unknown'))" 2>/dev/null)
        
        # Set environment variables for the alert script
        export SSH_KEY_FINGERPRINT="$FINGERPRINT"
        export SSH_KEY_COMMENT="$COMMENT"
    fi
fi

# Run the main SSH alert script
/opt/ssh-alert/ssh-alert-enhanced.sh
EOF
    
    chmod +x "/opt/ssh-alert/ssh-key-detector.sh"
    
    # Update sshrc to use the new detector
    cat > "/etc/ssh/sshrc" << 'EOF'
#!/bin/bash
# SSH Alert Integration
# This script runs on every SSH login

# Only run for interactive sessions or when explicitly requested
if [ -n "${SSH_ALERT_DISABLED:-}" ]; then
    exit 0
fi

# Run SSH Alert with key detection in background
/opt/ssh-alert/ssh-key-detector.sh &
EOF
    
    chmod +x "/etc/ssh/sshrc"
    
    print_success "SSH key detection setup completed"
}

# Alternative method: Use AuthorizedKeysCommand
setup_authorized_keys_command() {
    print_info "Setting up AuthorizedKeysCommand method..."
    
    # Create the command script
    cat > "/opt/ssh-alert/authorized-keys-command.sh" << 'EOF'
#!/bin/bash

# AuthorizedKeysCommand for SSH Alert
# This script is called by SSH to get authorized keys and can pass key info

# Get the key being used
KEY_LINE="$1"
USERNAME="$2"

# Extract key information
if [[ -n "$KEY_LINE" ]]; then
    KEY_TYPE=$(echo "$KEY_LINE" | awk '{print $1}')
    KEY_DATA=$(echo "$KEY_LINE" | awk '{print $2}')
    COMMENT=$(echo "$KEY_LINE" | awk '{print $NF}')
    
    # Generate fingerprint
    FINGERPRINT=$(echo "$KEY_DATA" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || echo "unknown")
    
    # Set environment variables for the session
    export SSH_KEY_FINGERPRINT="$FINGERPRINT"
    export SSH_KEY_COMMENT="$COMMENT"
    export SSH_KEY_TYPE="$KEY_TYPE"
fi

# Return the authorized keys (this is what SSH expects)
cat /root/.ssh/authorized_keys
EOF
    
    chmod +x "/opt/ssh-alert/authorized-keys-command.sh"
    
    print_info "AuthorizedKeysCommand script created"
    print_warning "To use this method, you need to add to /etc/ssh/sshd_config:"
    print_warning "AuthorizedKeysCommand /opt/ssh-alert/authorized-keys-command.sh"
    print_warning "Then restart SSH: systemctl restart sshd"
}

# Main function
main() {
    echo "SSH Key Detection Setup"
    echo "======================="
    echo
    
    check_root
    
    show_authorized_keys
    
    echo "Setup options:"
    echo "1) Use wrapper script method (recommended)"
    echo "2) Use AuthorizedKeysCommand method (advanced)"
    echo "3) Show current setup"
    echo "q) Quit"
    echo
    
    read -p "Select option: " choice
    
    case "$choice" in
        1)
            setup_ssh_key_detection
            ;;
        2)
            setup_authorized_keys_command
            ;;
        3)
            print_info "Current sshrc:"
            cat /etc/ssh/sshrc
            ;;
        [Qq])
            print_info "Exiting..."
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo
    print_success "Setup completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
