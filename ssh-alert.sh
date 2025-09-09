#!/bin/bash

# SSH Alert - Secure SSH Connection Monitoring Tool
# =================================================
# Monitors SSH connections and sends notifications to Telegram
# Author: SSH Alert System
# Version: 1.0.0

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/ssh-alert/config.conf"
LOCK_FILE="/tmp/ssh-alert.lock"
RATE_LIMIT_DIR="/tmp/ssh-alert-rate-limit"

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Source configuration file
    source "$CONFIG_FILE"
    
    # Validate required settings
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        log_error "TELEGRAM_BOT_TOKEN is not set in configuration"
        exit 1
    fi
    
    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "TELEGRAM_CHAT_ID is not set in configuration"
        exit 1
    fi
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] || [[ "$level" != "DEBUG" ]]; then
        echo "[$timestamp] [$level] $message" >> "${LOG_FILE:-/var/log/ssh-alert.log}"
    fi
    
    if [[ "$level" == "ERROR" ]]; then
        echo "ERROR: $message" >&2
    elif [[ "$level" == "DEBUG" ]] && [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
        echo "DEBUG: $message" >&2
    fi
}

log_info() { log "INFO" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Rate limiting functions
check_rate_limit() {
    local key="$1"
    local limit_seconds="${2:-300}"
    local rate_file="${RATE_LIMIT_DIR}/${key}"
    
    mkdir -p "$RATE_LIMIT_DIR"
    
    if [[ -f "$rate_file" ]]; then
        local last_notification=$(cat "$rate_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_notification))
        
        if [[ $time_diff -lt $limit_seconds ]]; then
            log_debug "Rate limit active for key: $key (${time_diff}s ago, limit: ${limit_seconds}s)"
            return 1
        fi
    fi
    
    # Update rate limit file
    date +%s > "$rate_file"
    return 0
}

# IP address utilities
is_local_ip() {
    local ip="$1"
    
    if [[ "${IGNORE_LOCAL_IPS:-true}" != "true" ]]; then
        return 1
    fi
    
    # Check against common local IP ranges
    local local_ranges="${LOCAL_IP_RANGES:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.0/8}"
    
    IFS=',' read -ra RANGES <<< "$local_ranges"
    for range in "${RANGES[@]}"; do
        if ip_in_range "$ip" "$range"; then
            return 0
        fi
    done
    
    return 1
}

ip_in_range() {
    local ip="$1"
    local range="$2"
    
    # Simple CIDR check for common ranges
    case "$range" in
        "192.168.0.0/16")
            [[ "$ip" =~ ^192\.168\. ]]
            ;;
        "10.0.0.0/8")
            [[ "$ip" =~ ^10\. ]]
            ;;
        "172.16.0.0/12")
            [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
            ;;
        "127.0.0.0/8")
            [[ "$ip" =~ ^127\. ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# SSH key utilities
get_key_fingerprint() {
    local key_file="$1"
    local key_line="$2"
    
    # Extract the key part (remove options and comment)
    local key_part=$(echo "$key_line" | awk '{print $NF}')
    
    # Generate fingerprint
    echo "$key_part" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || echo "unknown"
}

get_key_comment() {
    local key_line="$1"
    
    # Extract comment from the end of the line
    echo "$key_line" | awk '{print $NF}' | sed 's/.* //'
}

find_key_in_authorized_keys() {
    local fingerprint="$1"
    local authorized_keys_file="${SSH_AUTHORIZED_KEYS_PATH:-/root/.ssh/authorized_keys}"
    
    if [[ ! -f "$authorized_keys_file" ]]; then
        log_warning "Authorized keys file not found: $authorized_keys_file"
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # Check if this line contains the fingerprint
        local line_fingerprint=$(get_key_fingerprint "" "$line")
        if [[ "$line_fingerprint" == "$fingerprint" ]]; then
            echo "$line"
            return 0
        fi
    done < "$authorized_keys_file"
    
    return 1
}

# Parse SSH environment variables
parse_ssh_environment() {
    local ssh_user=""
    local ssh_connection=""
    local ssh_client=""
    
    # Try to get SSH_USER from environment
    if [[ -n "${SSH_USER:-}" ]]; then
        ssh_user="$SSH_USER"
    fi
    
    # Parse SSH_CONNECTION for IP and port
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_connection="$SSH_CONNECTION"
    fi
    
    # Parse SSH_CLIENT for additional info
    if [[ -n "${SSH_CLIENT:-}" ]]; then
        ssh_client="$SSH_CLIENT"
    fi
    
    echo "$ssh_user|$ssh_connection|$ssh_client"
}

# Determine connection type
get_connection_type() {
    # Check if this is an interactive session
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        echo "Interactive shell"
    elif [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
        echo "Command execution"
    elif [[ -n "${SSH_TUNNEL:-}" ]]; then
        echo "Tunnel"
    else
        # Try to detect based on process tree
        local parent_pid=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
        if [[ -n "$parent_pid" ]]; then
            local parent_cmd=$(ps -o cmd= -p "$parent_pid" 2>/dev/null || echo "")
            if [[ "$parent_cmd" =~ sshd.*tunnel ]]; then
                echo "Tunnel"
            else
                echo "Interactive shell"
            fi
        else
            echo "Unknown"
        fi
    fi
}

# Telegram notification functions
send_telegram_message() {
    local message="$1"
    local disable_notification="${2:-false}"
    
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local data="chat_id=${TELEGRAM_CHAT_ID}&text=$(printf '%s\n' "$message" | sed 's/&/%26/g')&parse_mode=Markdown"
    
    if [[ "$disable_notification" == "true" ]]; then
        data="${data}&disable_notification=true"
    fi
    
    local attempt=1
    local max_attempts="${TELEGRAM_RETRY_ATTEMPTS:-3}"
    local retry_delay="${TELEGRAM_RETRY_DELAY:-5}"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Sending Telegram message (attempt $attempt/$max_attempts)"
        
        local response=$(curl -s -w "\n%{http_code}" -X POST "$url" -d "$data" --connect-timeout 10 --max-time 30)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n -1)
        
        if [[ "$http_code" == "200" ]]; then
            log_info "Telegram notification sent successfully"
            return 0
        else
            log_warning "Telegram API error (HTTP $http_code): $body"
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${retry_delay} seconds..."
                sleep "$retry_delay"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to send Telegram notification after $max_attempts attempts"
    return 1
}

# Main notification function
send_ssh_alert() {
    local ip_address="$1"
    local username="$2"
    local key_fingerprint="$3"
    local key_comment="$4"
    local connection_type="$5"
    
    # Skip local IPs if configured
    if is_local_ip "$ip_address"; then
        log_debug "Skipping notification for local IP: $ip_address"
        return 0
    fi
    
    # Check notification settings based on connection type
    case "$connection_type" in
        "Interactive shell")
            if [[ "${NOTIFY_INTERACTIVE_SESSIONS:-true}" != "true" ]]; then
                log_debug "Interactive sessions notifications disabled"
                return 0
            fi
            ;;
        "Tunnel")
            if [[ "${NOTIFY_TUNNELS:-false}" != "true" ]]; then
                log_debug "Tunnel notifications disabled"
                return 0
            fi
            ;;
        "Command execution")
            if [[ "${NOTIFY_COMMANDS:-false}" != "true" ]]; then
                log_debug "Command execution notifications disabled"
                return 0
            fi
            ;;
    esac
    
    # Rate limiting
    local rate_key="${ip_address}_${key_fingerprint}"
    local rate_limit_seconds="${RATE_LIMIT_PER_IP:-300}"
    
    if [[ "$connection_type" == "Tunnel" ]]; then
        rate_limit_seconds="${RATE_LIMIT_PER_KEY:-60}"
    fi
    
    if ! check_rate_limit "$rate_key" "$rate_limit_seconds"; then
        log_debug "Rate limit active for $rate_key"
        return 0
    fi
    
    # Prepare notification message
    local server_name="${SERVER_NAME:-$(hostname)}"
    local server_domain="${SERVER_DOMAIN:-}"
    local full_server_name="$server_name"
    
    if [[ -n "$server_domain" ]]; then
        full_server_name="${server_name}.${server_domain}"
    fi
    
    local person_info=""
    if [[ -n "$key_comment" && "$key_comment" != "unknown" ]]; then
        person_info="$key_comment"
    else
        person_info="Unknown"
    fi
    
    local message="🔐 *SSH Login Alert:*
*User:* \`$username\`
*Person:* \`$person_info\`
*Host:* \`$full_server_name\`
*IP:* \`$ip_address\`
*Type:* \`$connection_type\`
*Key:* \`${key_fingerprint:0:16}...\`
*Time:* \`$(date '+%Y-%m-%d %H:%M:%S UTC')\`"
    
    # Determine if notification should be silent
    local disable_sound="false"
    if [[ "$connection_type" == "Tunnel" ]] && [[ "${DISABLE_NOTIFICATION_SOUND_FOR_TUNNELS:-true}" == "true" ]]; then
        disable_sound="true"
    fi
    
    # Send notification
    send_telegram_message "$message" "$disable_sound"
    
    # Log the event
    log_info "SSH alert sent: $username@$full_server_name from $ip_address ($connection_type)"
}

# Main function
main() {
    # Acquire lock to prevent concurrent executions
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_debug "Another instance is running, exiting"
        exit 0
    fi
    
    # Load configuration
    load_config
    
    log_debug "SSH Alert script started"
    
    # Parse SSH environment
    local ssh_env=$(parse_ssh_environment)
    local ssh_user=$(echo "$ssh_env" | cut -d'|' -f1)
    local ssh_connection=$(echo "$ssh_env" | cut -d'|' -f2)
    local ssh_client=$(echo "$ssh_env" | cut -d'|' -f3)
    
    # Extract IP address
    local ip_address=""
    if [[ -n "$ssh_connection" ]]; then
        ip_address=$(echo "$ssh_connection" | awk '{print $1}')
    elif [[ -n "$ssh_client" ]]; then
        ip_address=$(echo "$ssh_client" | awk '{print $1}')
    else
        log_warning "Could not determine source IP address"
        ip_address="unknown"
    fi
    
    # Get current user
    local username="${SSH_USER:-$(whoami)}"
    
    # Determine connection type
    local connection_type=$(get_connection_type)
    
    # Try to get key fingerprint from environment or auth log
    local key_fingerprint="unknown"
    local key_comment="unknown"
    
    # Check if we have SSH key info in environment
    if [[ -n "${SSH_KEY_FINGERPRINT:-}" ]]; then
        key_fingerprint="$SSH_KEY_FINGERPRINT"
    elif [[ -n "${SSH_KEY_COMMENT:-}" ]]; then
        key_comment="$SSH_KEY_COMMENT"
    fi
    
    # If we don't have key info, try to find it in authorized_keys
    if [[ "$key_fingerprint" == "unknown" ]] && [[ "${PARSE_AUTH_LOG_FOR_FINGERPRINTS:-true}" == "true" ]]; then
        # This is a simplified approach - in a real implementation,
        # you might need to parse the auth log more carefully
        log_debug "Attempting to determine key fingerprint from auth log"
        # For now, we'll use a placeholder
        key_fingerprint="auth-log-parsing-needed"
    fi
    
    # Send alert
    send_ssh_alert "$ip_address" "$username" "$key_fingerprint" "$key_comment" "$connection_type"
    
    log_debug "SSH Alert script completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
