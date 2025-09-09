#!/bin/bash

# SSH Alert Debug Script
# ======================
# Helps diagnose SSH connection information issues

set -euo pipefail

echo "SSH Alert Debug Information"
echo "=========================="
echo

echo "1. Environment Variables:"
echo "SSH_CONNECTION: ${SSH_CONNECTION:-NOT_SET}"
echo "SSH_CLIENT: ${SSH_CLIENT:-NOT_SET}"
echo "SSH_USER: ${SSH_USER:-NOT_SET}"
echo "SSH_ORIGINAL_COMMAND: ${SSH_ORIGINAL_COMMAND:-NOT_SET}"
echo "SSH_TUNNEL: ${SSH_TUNNEL:-NOT_SET}"
echo

echo "2. Current User:"
echo "whoami: $(whoami)"
echo "id: $(id)"
echo

echo "3. Process Information:"
echo "PID: $$"
echo "PPID: $PPID"
echo "Parent process: $(ps -o cmd= -p $PPID 2>/dev/null || echo 'unknown')"
echo

echo "4. Network Connections:"
ss -tnp | grep sshd | head -5
echo

echo "5. Authorized Keys:"
if [[ -f "/root/.ssh/authorized_keys" ]]; then
    echo "Found authorized_keys file:"
    head -3 /root/.ssh/authorized_keys
    echo "..."
else
    echo "No authorized_keys file found"
fi
echo

echo "6. Auth Log (last 10 SSH entries):"
if [[ -f "/var/log/auth.log" ]]; then
    grep "sshd" /var/log/auth.log | tail -10
else
    echo "No auth.log found"
fi
echo

echo "7. Python Parser Test:"
if [[ -f "/opt/ssh-alert/key-parser.py" ]]; then
    python3 /opt/ssh-alert/key-parser.py get-info 2>/dev/null || echo "Python parser failed"
else
    echo "Python parser not found"
fi
echo

echo "8. Configuration:"
if [[ -f "/etc/ssh-alert/config.conf" ]]; then
    echo "Config file exists"
    grep -E "TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID" /etc/ssh-alert/config.conf | sed 's/=.*/=***HIDDEN***/'
else
    echo "Config file not found"
fi
