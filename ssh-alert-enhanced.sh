#!/bin/bash

# SSH Alert Enhanced - Secure SSH Connection Monitoring Tool
# =========================================================
# Enhanced version with Python key parser integration
# Author: SSH Alert System
# Version: 1.1.0

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/ssh-alert/config.conf"
LOCK_FILE="/tmp/ssh-alert.lock"
RATE_LIMIT_DIR="/tmp/ssh-alert-rate-limit"
KEY_PARSER="${SCRIPT_DIR}/key-parser.py"

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

# Enhanced connection information gathering
get_connection_info() {
    if [[ ! -f "$KEY_PARSER" ]]; then
        log_warning "Python key parser not found, using fallback method"
        get_connection_info_fallback
        return
    fi
    
    # Use Python parser for enhanced information
    local connection_info
    if connection_info=$(python3 "$KEY_PARSER" get-info 2>/dev/null); then
        echo "$connection_info"
    else
        log_warning "Python parser failed, using fallback method"
        get_connection_info_fallback
    fi
}

get_connection_info_fallback() {
    # Fallback method using environment variables
    local ip_address=""
    local username=""
    local connection_type=""
    
    # Get IP address
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ip_address=$(echo "$SSH_CONNECTION" | awk '{print $1}')
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        ip_address=$(echo "$SSH_CLIENT" | awk '{print $1}')
    else
        ip_address="unknown"
    fi
    
    # Get username
    username="${SSH_USER:-$(whoami)}"
    
    # Get connection type
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        connection_type="Interactive shell"
    elif [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
        connection_type="Command execution"
    elif [[ -n "${SSH_TUNNEL:-}" ]]; then
        connection_type="Tunnel"
    else
        connection_type="Unknown"
    fi
    
    # Return as JSON-like structure
    cat << EOF
{
  "ip_address": "$ip_address",
  "username": "$username",
  "connection_type": "$connection_type",
  "key_fingerprint": "unknown",
  "key_comment": "unknown",
  "ssh_user": "${SSH_USER:-}",
  "port": "unknown",
  "client_version": "unknown"
}
EOF
}

# Enhanced key information gathering
get_key_info() {
    local ip_address="$1"
    local username="$2"
    
    if [[ ! -f "$KEY_PARSER" ]]; then
        echo '{"fingerprint": "unknown", "comment": "unknown"}'
        return
    fi
    
    # Try to get key info from auth log
    local auth_log_info
    if auth_log_info=$(python3 "$KEY_PARSER" parse-auth-log "$ip_address" "$username" 2>/dev/null); then
        local fingerprint=$(echo "$auth_log_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('fingerprint', 'unknown'))")
        
        if [[ "$fingerprint" != "unknown" ]]; then
            # Try to find key in authorized_keys
            local key_info
            if key_info=$(python3 "$KEY_PARSER" find-key "$fingerprint" 2>/dev/null); then
                echo "$key_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    result = {
        'fingerprint': data.get('fingerprint', 'unknown'),
        'comment': data.get('comment', 'unknown'),
        'ssh_user': data.get('options', {}).get('SSH_USER', '')
    }
    print(json.dumps(result))
except:
    print('{\"fingerprint\": \"unknown\", \"comment\": \"unknown\"}')
"
                return
            fi
        fi
    fi
    
    # Fallback
    echo '{"fingerprint": "unknown", "comment": "unknown"}'
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

# JSON logging function
log_json_event() {
    local event_data="$1"
    
    if [[ "${JSON_LOGGING:-false}" == "true" ]]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local json_log_entry=$(echo "$event_data" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    data['timestamp'] = '$timestamp'
    data['event_type'] = 'ssh_connection'
    print(json.dumps(data))
except:
    print('{\"timestamp\": \"$timestamp\", \"event_type\": \"ssh_connection\", \"error\": \"json_parse_failed\"}')
")
        echo "$json_log_entry" >> "${LOG_FILE:-/var/log/ssh-alert.log}"
    fi
}

# Main notification function
send_ssh_alert() {
    local connection_info="$1"
    local key_info="$2"
    
    # Parse connection info
    local ip_address=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_address', 'unknown'))")
    local username=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('username', 'unknown'))")
    local connection_type=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('connection_type', 'unknown'))")
    local ssh_user=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ssh_user', ''))")
    
    # Parse key info
    local key_fingerprint=$(echo "$key_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('fingerprint', 'unknown'))")
    local key_comment=$(echo "$key_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('comment', 'unknown'))")
    local key_ssh_user=$(echo "$key_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ssh_user', ''))")
    
    # Use SSH_USER from key if available
    if [[ -n "$key_ssh_user" ]]; then
        username="$key_ssh_user"
    elif [[ -n "$ssh_user" ]]; then
        username="$ssh_user"
    fi
    
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
    
    # JSON logging
    local event_data=$(echo "$connection_info" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    data.update($key_info)
    data['server_name'] = '$full_server_name'
    data['notification_sent'] = True
    data['sound_disabled'] = '$disable_sound'
    print(json.dumps(data))
except:
    print('{\"error\": \"json_merge_failed\"}')
")
    log_json_event "$event_data"
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
    
    log_debug "SSH Alert Enhanced script started"
    
    # Get connection information
    local connection_info
    connection_info=$(get_connection_info)
    
    # Parse basic info for key lookup
    local ip_address=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ip_address', 'unknown'))")
    local username=$(echo "$connection_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('username', 'unknown'))")
    
    # Get key information
    local key_info
    key_info=$(get_key_info "$ip_address" "$username")
    
    # Send alert
    send_ssh_alert "$connection_info" "$key_info"
    
    log_debug "SSH Alert Enhanced script completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
