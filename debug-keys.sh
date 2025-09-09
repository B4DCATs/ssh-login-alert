#!/bin/bash

# SSH Alert Key Debug Script
# ==========================
# Helps debug key detection issues

set -euo pipefail

echo "SSH Alert Key Debug"
echo "==================="
echo

echo "1. Authorized Keys File:"
if [[ -f "/root/.ssh/authorized_keys" ]]; then
    echo "Found authorized_keys file:"
    cat -n /root/.ssh/authorized_keys
else
    echo "No authorized_keys file found"
fi
echo

echo "2. Recent Auth Log Entries:"
if [[ -f "/var/log/auth.log" ]]; then
    echo "Last 10 SSH connections:"
    grep "sshd.*Accepted" /var/log/auth.log | tail -10
else
    echo "No auth.log found"
fi
echo

echo "3. Test Python Parser:"
echo "Testing get-info:"
python3 /opt/ssh-alert/key-parser.py get-info
echo

echo "Testing parse-auth-log:"
python3 /opt/ssh-alert/key-parser.py parse-auth-log "103.75.127.215" "root"
echo

echo "Testing find-key-by-connection:"
python3 /opt/ssh-alert/key-parser.py find-key-by-connection "103.75.127.215" "root"
echo

echo "4. Manual Key Analysis:"
echo "If you know your key fingerprint, test it:"
echo "python3 /opt/ssh-alert/key-parser.py find-key YOUR_FINGERPRINT"
echo

echo "Debug completed!"
