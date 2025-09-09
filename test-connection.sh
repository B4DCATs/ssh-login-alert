#!/bin/bash

# Test SSH Alert Connection Detection
# ===================================

set -euo pipefail

echo "Testing SSH Alert Connection Detection"
echo "====================================="
echo

# Test Python parser
echo "1. Testing Python parser get-info:"
python3 /opt/ssh-alert/key-parser.py get-info
echo

# Test key detection
echo "2. Testing key detection by connection:"
python3 /opt/ssh-alert/key-parser.py find-key-by-connection "103.75.127.215" "root"
echo

# Test auth log parsing
echo "3. Testing auth log parsing:"
python3 /opt/ssh-alert/key-parser.py parse-auth-log "103.75.127.215" "root"
echo

# Test bash script
echo "4. Testing bash script key detection:"
/opt/ssh-alert/ssh-alert-enhanced.sh
echo

echo "Test completed!"
