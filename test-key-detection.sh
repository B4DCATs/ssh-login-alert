#!/bin/bash

# Test Key Detection
# ==================

set -euo pipefail

echo "SSH Key Detection Test"
echo "======================"
echo

echo "1. Testing all keys in authorized_keys:"
echo

if [[ -f "/root/.ssh/authorized_keys" ]]; then
    local i=1
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            local key_type=$(echo "$line" | awk '{print $1}')
            local key_data=$(echo "$line" | awk '{print $2}')
            local comment=$(echo "$line" | awk '{print $NF}')
            local fingerprint=$(echo "$key_data" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' || echo "unknown")
            
            echo "Key #$i:"
            echo "  Type: $key_type"
            echo "  Comment: $comment"
            echo "  Fingerprint: $fingerprint"
            echo "  Testing find-key:"
            python3 /opt/ssh-alert/key-parser.py find-key "$fingerprint" 2>/dev/null || echo "    Key not found in cache"
            echo
            ((i++))
        fi
    done < "/root/.ssh/authorized_keys"
else
    echo "No authorized_keys file found"
fi

echo "2. Testing current connection:"
echo "IP: 2.58.65.38"
echo "User: root"
echo

echo "Testing find-key-by-connection:"
python3 /opt/ssh-alert/key-parser.py find-key-by-connection "2.58.65.38" "root"
echo

echo "3. Manual key test:"
echo "You can test specific fingerprints:"
echo "python3 /opt/ssh-alert/key-parser.py find-key FINGERPRINT"
echo

echo "Test completed!"
