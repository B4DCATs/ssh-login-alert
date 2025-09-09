#!/bin/bash

# SSH Alert Installation Script
# =============================
# Installs and configures SSH Alert monitoring system
# Author: SSH Alert System
# Version: 1.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/ssh-alert"
CONFIG_DIR="/etc/ssh-alert"
LOG_DIR="/var/log"
SERVICE_USER="root"

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

# Check system requirements
check_requirements() {
    print_info "Checking system requirements..."
    
    # Check for required commands
    local required_commands=("curl" "python3" "flock" "ss")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "Required command not found: $cmd"
            print_info "Please install the missing package and try again"
            exit 1
        fi
    done
    
    # Check Python version
    local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ $(echo "$python_version < 3.6" | bc -l) -eq 1 ]]; then
        print_error "Python 3.6 or higher is required. Found: $python_version"
        exit 1
    fi
    
    print_success "System requirements check passed"
}

# Create directories
create_directories() {
    print_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    print_success "Directories created"
}

# Install files
install_files() {
    print_info "Installing SSH Alert files..."
    
    # Copy main scripts
    cp ssh-alert.sh "$INSTALL_DIR/"
    cp ssh-alert-enhanced.sh "$INSTALL_DIR/"
    cp key-parser.py "$INSTALL_DIR/"
    
    # Copy additional files if they exist
    [[ -f "logrotate.conf" ]] && cp logrotate.conf "$INSTALL_DIR/"
    
    # Copy configuration template
    cp config.conf "$CONFIG_DIR/config.conf.template"
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR/ssh-alert.sh"
    chmod +x "$INSTALL_DIR/ssh-alert-enhanced.sh"
    chmod +x "$INSTALL_DIR/key-parser.py"
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"
    
    print_success "Files installed successfully"
}

# Configure SSH
configure_ssh() {
    print_info "Configuring SSH integration..."
    
    # Check if sshrc already exists
    if [[ -f "/etc/ssh/sshrc" ]]; then
        print_warning "/etc/ssh/sshrc already exists. Creating backup..."
        cp "/etc/ssh/sshrc" "/etc/ssh/sshrc.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create sshrc
    cat > "/etc/ssh/sshrc" << 'EOF'
#!/bin/bash
# SSH Alert Integration
# This script runs on every SSH login

# Only run for interactive sessions or when explicitly requested
if [ -n "${SSH_ALERT_DISABLED:-}" ]; then
    exit 0
fi

# Run SSH Alert in background
/opt/ssh-alert/ssh-alert-enhanced.sh &
EOF
    
    chmod +x "/etc/ssh/sshrc"
    
    print_success "SSH configuration completed"
}

# Create systemd service (optional)
create_systemd_service() {
    print_info "Creating systemd service..."
    
    cat > "/etc/systemd/system/ssh-alert.service" << EOF
[Unit]
Description=SSH Alert Monitoring Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/ssh-alert/ssh-alert-enhanced.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    print_success "Systemd service created"
}

# Setup log rotation
setup_log_rotation() {
    print_info "Setting up log rotation..."
    
    # Copy logrotate configuration
    if [[ -f "logrotate.conf" ]]; then
        cp "logrotate.conf" "/etc/logrotate.d/ssh-alert"
        print_success "Log rotation configuration copied"
    else
        # Fallback configuration
        cat > "/etc/logrotate.d/ssh-alert" << 'EOF'
/var/log/ssh-alert.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    missingok
    copytruncate
    minsize 100k
    maxsize 10M
    postrotate
        # No need to reload anything for this log
    endscript
}

/tmp/ssh-alert-rate-limit/* {
    daily
    rotate 7
    nocompress
    notifempty
    nocreate
    missingok
    olddir /tmp/ssh-alert-rate-limit/old
    postrotate
        # Remove old directory if empty
        rmdir /tmp/ssh-alert-rate-limit/old 2>/dev/null || true
    endscript
}
EOF
        print_success "Log rotation configured (fallback)"
    fi
    
    # Test logrotate configuration
    if logrotate -d /etc/logrotate.d/ssh-alert >/dev/null 2>&1; then
        print_success "Log rotation configuration is valid"
    else
        print_warning "Log rotation configuration test failed, but continuing..."
    fi
}

# Interactive configuration
interactive_config() {
    print_info "Starting interactive configuration..."
    
    local config_file="$CONFIG_DIR/config.conf"
    
    # Copy template to actual config
    cp "$CONFIG_DIR/config.conf.template" "$config_file"
    
    echo
    print_info "Please provide the following information:"
    echo
    
    # Telegram Bot Token
    read -p "Telegram Bot Token: " telegram_token
    if [[ -n "$telegram_token" ]]; then
        sed -i "s/TELEGRAM_BOT_TOKEN=\"\"/TELEGRAM_BOT_TOKEN=\"$telegram_token\"/" "$config_file"
    fi
    
    # Telegram Chat ID
    read -p "Telegram Chat ID: " telegram_chat_id
    if [[ -n "$telegram_chat_id" ]]; then
        sed -i "s/TELEGRAM_CHAT_ID=\"\"/TELEGRAM_CHAT_ID=\"$telegram_chat_id\"/" "$config_file"
    fi
    
    # Server Name
    read -p "Server Name (default: $(hostname)): " server_name
    if [[ -n "$server_name" ]]; then
        sed -i "s/SERVER_NAME=\"\$(hostname)\"/SERVER_NAME=\"$server_name\"/" "$config_file"
    fi
    
    # Server Domain
    read -p "Server Domain (optional): " server_domain
    if [[ -n "$server_domain" ]]; then
        sed -i "s/SERVER_DOMAIN=\"\"/SERVER_DOMAIN=\"$server_domain\"/" "$config_file"
    fi
    
    # Notification preferences
    echo
    print_info "Notification preferences:"
    
    read -p "Notify for interactive sessions? (y/n, default: y): " notify_interactive
    if [[ "$notify_interactive" =~ ^[Nn]$ ]]; then
        sed -i "s/NOTIFY_INTERACTIVE_SESSIONS=true/NOTIFY_INTERACTIVE_SESSIONS=false/" "$config_file"
    fi
    
    read -p "Notify for tunnels? (y/n, default: n): " notify_tunnels
    if [[ "$notify_tunnels" =~ ^[Yy]$ ]]; then
        sed -i "s/NOTIFY_TUNNELS=false/NOTIFY_TUNNELS=true/" "$config_file"
    fi
    
    read -p "Notify for command executions? (y/n, default: n): " notify_commands
    if [[ "$notify_commands" =~ ^[Yy]$ ]]; then
        sed -i "s/NOTIFY_COMMANDS=false/NOTIFY_COMMANDS=true/" "$config_file"
    fi
    
    # Rate limiting
    echo
    print_info "Rate limiting settings:"
    
    read -p "Rate limit per IP (seconds, default: 300): " rate_limit_ip
    if [[ -n "$rate_limit_ip" && "$rate_limit_ip" =~ ^[0-9]+$ ]]; then
        sed -i "s/RATE_LIMIT_PER_IP=300/RATE_LIMIT_PER_IP=$rate_limit_ip/" "$config_file"
    fi
    
    read -p "Rate limit per key (seconds, default: 60): " rate_limit_key
    if [[ -n "$rate_limit_key" && "$rate_limit_key" =~ ^[0-9]+$ ]]; then
        sed -i "s/RATE_LIMIT_PER_KEY=60/RATE_LIMIT_PER_KEY=$rate_limit_key/" "$config_file"
    fi
    
    # Logging
    echo
    print_info "Logging settings:"
    
    read -p "Enable JSON logging? (y/n, default: n): " json_logging
    if [[ "$json_logging" =~ ^[Yy]$ ]]; then
        sed -i "s/JSON_LOGGING=false/JSON_LOGGING=true/" "$config_file"
    fi
    
    read -p "Log level (DEBUG/INFO/WARNING/ERROR, default: INFO): " log_level
    if [[ -n "$log_level" ]]; then
        sed -i "s/LOG_LEVEL=\"INFO\"/LOG_LEVEL=\"$log_level\"/" "$config_file"
    fi
    
    # Set proper permissions
    chmod 600 "$config_file"
    chown "$SERVICE_USER:$SERVICE_USER" "$config_file"
    
    print_success "Configuration completed"
}

# Test configuration
test_configuration() {
    print_info "Testing configuration..."
    
    local config_file="$CONFIG_DIR/config.conf"
    
    # Test if configuration is valid
    if ! bash -n "$INSTALL_DIR/ssh-alert-enhanced.sh"; then
        print_error "Syntax error in SSH Alert script"
        return 1
    fi
    
    # Test Python parser
    if ! python3 "$INSTALL_DIR/key-parser.py" get-info > /dev/null 2>&1; then
        print_error "Python key parser test failed"
        return 1
    fi
    
    # Test configuration loading
    if ! source "$config_file"; then
        print_error "Configuration file has syntax errors"
        return 1
    fi
    
    # Test Telegram configuration
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        print_warning "Telegram Bot Token not configured"
    fi
    
    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        print_warning "Telegram Chat ID not configured"
    fi
    
    print_success "Configuration test passed"
}

# Copy uninstall script
copy_uninstall_script() {
    print_info "Copying uninstall script..."
    
    if [[ -f "uninstall.sh" ]]; then
        cp "uninstall.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/uninstall.sh"
        print_success "Uninstall script copied"
    else
        print_warning "Uninstall script not found in current directory"
    fi
}

# Main installation function
main() {
    echo "SSH Alert Installation Script"
    echo "============================="
    echo
    
    check_root
    check_requirements
    create_directories
    install_files
    configure_ssh
    create_systemd_service
    setup_log_rotation
    interactive_config
    test_configuration
    copy_uninstall_script
    
    echo
    print_success "SSH Alert installation completed successfully!"
    echo
    print_info "Installation summary:"
    echo "  - Files installed to: $INSTALL_DIR"
    echo "  - Configuration: $CONFIG_DIR/config.conf"
    echo "  - Logs: $LOG_DIR/ssh-alert.log"
    echo "  - SSH integration: /etc/ssh/sshrc"
    echo "  - Uninstall script: $INSTALL_DIR/uninstall.sh"
    echo
    print_info "Next steps:"
    echo "  1. Test the installation by connecting via SSH"
    echo "  2. Check logs: tail -f $LOG_DIR/ssh-alert.log"
    echo "  3. Configure additional settings in $CONFIG_DIR/config.conf"
    echo
    print_warning "Note: SSH Alert will start monitoring on the next SSH connection"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
