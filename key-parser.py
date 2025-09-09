#!/usr/bin/env python3
"""
SSH Key Parser - Advanced key fingerprint and comment extraction
===============================================================
This module provides advanced functionality for parsing SSH keys,
extracting fingerprints, and matching them with authorized_keys entries.
"""

import os
import sys
import re
import subprocess
import hashlib
import base64
import struct
from typing import Optional, Tuple, Dict, List
import json
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class SSHKeyParser:
    """Advanced SSH key parser for fingerprint extraction and matching."""
    
    def __init__(self, authorized_keys_path: str = "/root/.ssh/authorized_keys"):
        self.authorized_keys_path = authorized_keys_path
        self.auth_log_path = "/var/log/auth.log"  # Add this line
        self.key_cache = {}
        self._load_authorized_keys()
    
    def _load_authorized_keys(self):
        """Load and parse authorized_keys file."""
        if not os.path.exists(self.authorized_keys_path):
            logger.warning(f"Authorized keys file not found: {self.authorized_keys_path}")
            return
        
        try:
            with open(self.authorized_keys_path, 'r') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    # Parse the line
                    key_info = self._parse_authorized_key_line(line)
                    if key_info:
                        key_info['line_number'] = line_num
                        self.key_cache[key_info['fingerprint']] = key_info
                        
        except Exception as e:
            logger.error(f"Error loading authorized keys: {e}")
    
    def _parse_authorized_key_line(self, line: str) -> Optional[Dict]:
        """Parse a single authorized_keys line."""
        try:
            # Split the line into parts
            parts = line.split()
            if len(parts) < 2:
                return None
            
            # Extract key type and data
            key_type = parts[0]
            key_data = parts[1]
            comment = parts[2] if len(parts) > 2 else ""
            
            # Generate fingerprint
            fingerprint = self._generate_fingerprint(key_type, key_data)
            
            # Extract options if present
            options = {}
            if len(parts) > 3:
                # Look for environment variables and other options
                for part in parts[2:-1]:  # Skip key data and comment
                    if '=' in part:
                        key, value = part.split('=', 1)
                        options[key] = value
            
            return {
                'type': key_type,
                'data': key_data,
                'fingerprint': fingerprint,
                'comment': comment,
                'options': options,
                'full_line': line
            }
            
        except Exception as e:
            logger.error(f"Error parsing key line: {e}")
            return None
    
    def _generate_fingerprint(self, key_type: str, key_data: str) -> str:
        """Generate SSH key fingerprint."""
        try:
            # Decode base64 key data
            key_bytes = base64.b64decode(key_data)
            
            # Generate MD5 fingerprint (OpenSSH style)
            md5_hash = hashlib.md5(key_bytes).hexdigest()
            fingerprint = ':'.join([md5_hash[i:i+2] for i in range(0, len(md5_hash), 2)])
            
            return fingerprint
            
        except Exception as e:
            logger.error(f"Error generating fingerprint: {e}")
            return "unknown"
    
    def find_key_by_fingerprint(self, fingerprint: str) -> Optional[Dict]:
        """Find key information by fingerprint."""
        return self.key_cache.get(fingerprint)
    
    def find_key_by_ip_and_user(self, ip_address: str, username: str) -> Optional[Dict]:
        """Find key information by IP and username from recent connections."""
        try:
            # Try to find recent connection in auth log
            auth_parser = AuthLogParser()
            connection_info = auth_parser.find_recent_ssh_connection(ip_address, username)
            
            if connection_info and connection_info.get('fingerprint') != 'unknown':
                found_key = self.find_key_by_fingerprint(connection_info['fingerprint'])
                if found_key:
                    return found_key
            
            # If no fingerprint found or key not found, try alternative methods
            # Method 1: Use key_data from connection_info if available
            if connection_info and connection_info.get('key_data') != 'unknown':
                found_key = self._find_key_by_data(connection_info['key_data'])
                if found_key:
                    return found_key
            
            # Method 2: Look for the most recent connection in auth log and try to match by key data
            if os.path.exists(self.auth_log_path):
                with open(self.auth_log_path, 'r') as f:
                    lines = f.readlines()
                    recent_lines = lines[-100:] if len(lines) > 100 else lines
                    
                    # Look for the most recent connection from this IP
                    for line in reversed(recent_lines):
                        if ip_address in line and "Accepted" in line and "sshd" in line:
                            # Parse the line to get key data
                            parsed_line = auth_parser._parse_ssh_connection_line(line)
                            if parsed_line.get('key_data') != 'unknown':
                                found_key = self._find_key_by_data(parsed_line['key_data'])
                                if found_key:
                                    return found_key
            
            # Method 3: If no auth.log, try to determine key from SSH environment
            # This is a fallback when auth.log is not available
            return self._find_key_from_ssh_environment()
            
        except Exception as e:
            logger.error(f"Error finding key by IP and user: {e}")
            return None
    
    def _find_key_from_ssh_environment(self) -> Optional[Dict]:
        """Try to find key information from SSH environment variables."""
        try:
            # Check if we have SSH key fingerprint in environment
            ssh_key_fingerprint = os.environ.get('SSH_KEY_FINGERPRINT')
            if ssh_key_fingerprint:
                return self.find_key_by_fingerprint(ssh_key_fingerprint)
            
            # Check if we have SSH key comment in environment
            ssh_key_comment = os.environ.get('SSH_KEY_COMMENT')
            if ssh_key_comment:
                # Try to find key by comment
                for key_info in self.key_cache.values():
                    if key_info.get('comment') == ssh_key_comment:
                        return key_info
            
            # If no environment info, return None to avoid showing wrong key
            return None
            
        except Exception as e:
            logger.error(f"Error finding key from SSH environment: {e}")
            return None
    
    def _find_key_by_data(self, key_data: str) -> Optional[Dict]:
        """Find key by its data (base64 part)."""
        try:
            if not os.path.exists(self.authorized_keys_path):
                return None
                
            with open(self.authorized_keys_path, 'r') as f:
                for line in f:
                    if line.strip() and not line.startswith('#'):
                        parts = line.strip().split()
                        if len(parts) >= 2 and parts[1] == key_data:
                            return self._parse_authorized_key_line(line.strip())
            return None
        except Exception as e:
            logger.error(f"Error finding key by data: {e}")
            return None
    
    def get_key_comment(self, fingerprint: str) -> str:
        """Get comment for a key by fingerprint."""
        key_info = self.find_key_by_fingerprint(fingerprint)
        if key_info:
            return key_info.get('comment', '')
        return 'unknown'
    
    def get_key_options(self, fingerprint: str) -> Dict:
        """Get options for a key by fingerprint."""
        key_info = self.find_key_by_fingerprint(fingerprint)
        if key_info:
            return key_info.get('options', {})
        return {}
    
    def get_ssh_user_from_options(self, fingerprint: str) -> Optional[str]:
        """Extract SSH_USER from key options."""
        options = self.get_key_options(fingerprint)
        return options.get('SSH_USER')

class AuthLogParser:
    """Parser for SSH authentication logs."""
    
    def __init__(self, auth_log_path: str = "/var/log/auth.log"):
        self.auth_log_path = auth_log_path
    
    def find_recent_ssh_connection(self, ip_address: str, username: str, 
                                 max_lines: int = 1000) -> Optional[Dict]:
        """Find recent SSH connection in auth log."""
        try:
            if not os.path.exists(self.auth_log_path):
                logger.warning(f"Auth log file not found: {self.auth_log_path}")
                return None
            
            # Read recent lines from the end of the file
            with open(self.auth_log_path, 'r') as f:
                lines = f.readlines()
                recent_lines = lines[-max_lines:] if len(lines) > max_lines else lines
            
            # Look for recent SSH connection
            for line in reversed(recent_lines):
                if self._is_ssh_connection_line(line, ip_address, username):
                    return self._parse_ssh_connection_line(line)
            
            # If no exact match, try to find any recent connection from this IP
            for line in reversed(recent_lines):
                if ip_address in line and "Accepted" in line and "sshd" in line:
                    return self._parse_ssh_connection_line(line)
            
            return None
            
        except Exception as e:
            logger.error(f"Error parsing auth log: {e}")
            return None
    
    def _is_ssh_connection_line(self, line: str, ip_address: str, username: str) -> bool:
        """Check if line represents SSH connection for given IP and user."""
        # Look for successful SSH connection patterns
        patterns = [
            rf"Accepted publickey for {re.escape(username)} from {re.escape(ip_address)}",
            rf"Accepted password for {re.escape(username)} from {re.escape(ip_address)}",
            rf"Accepted keyboard-interactive for {re.escape(username)} from {re.escape(ip_address)}"
        ]
        
        for pattern in patterns:
            if re.search(pattern, line):
                return True
        
        return False
    
    def _parse_ssh_connection_line(self, line: str) -> Dict:
        """Parse SSH connection line to extract key information."""
        result = {
            'fingerprint': 'unknown',
            'key_type': 'unknown',
            'auth_method': 'unknown',
            'key_data': 'unknown'
        }
        
        try:
            # Extract fingerprint if present (various formats)
            fingerprint_patterns = [
                r'RSA SHA256:([A-Za-z0-9+/=]+)',
                r'ED25519 SHA256:([A-Za-z0-9+/=]+)',
                r'ECDSA SHA256:([A-Za-z0-9+/=]+)',
                r'DSA SHA256:([A-Za-z0-9+/=]+)',
                r'key fingerprint ([a-f0-9:]+)',
                r'fingerprint ([a-f0-9:]+)'
            ]
            
            for pattern in fingerprint_patterns:
                fingerprint_match = re.search(pattern, line)
                if fingerprint_match:
                    result['fingerprint'] = fingerprint_match.group(1)
                    break
            
            # Extract key data (base64 part) - this is more reliable than fingerprint
            key_data_patterns = [
                r'key ([A-Za-z0-9+/=]{50,})',  # Look for long base64 strings
                r'RSA ([A-Za-z0-9+/=]{50,})',
                r'ED25519 ([A-Za-z0-9+/=]{50,})',
                r'ECDSA ([A-Za-z0-9+/=]{50,})',
                r'DSA ([A-Za-z0-9+/=]{50,})'
            ]
            
            for pattern in key_data_patterns:
                key_data_match = re.search(pattern, line)
                if key_data_match:
                    result['key_data'] = key_data_match.group(1)
                    break
            
            # Extract key type
            key_type_match = re.search(r'(RSA|ECDSA|ED25519|DSA)', line)
            if key_type_match:
                result['key_type'] = key_type_match.group(1)
            
            # Extract authentication method
            if 'publickey' in line:
                result['auth_method'] = 'publickey'
            elif 'password' in line:
                result['auth_method'] = 'password'
            elif 'keyboard-interactive' in line:
                result['auth_method'] = 'keyboard-interactive'
            
        except Exception as e:
            logger.error(f"Error parsing SSH connection line: {e}")
        
        return result

class SSHConnectionDetector:
    """Detects SSH connection information from environment and system."""
    
    @staticmethod
    def get_connection_info() -> Dict:
        """Get comprehensive SSH connection information."""
        info = {
            'ip_address': 'unknown',
            'username': 'unknown',
            'connection_type': 'unknown',
            'key_fingerprint': 'unknown',
            'key_comment': 'unknown',
            'ssh_user': None,
            'port': 'unknown',
            'client_version': 'unknown'
        }
        
        # Debug: log environment variables
        logger.debug(f"Environment USER: {os.environ.get('USER', 'NOT_SET')}")
        logger.debug(f"Environment LOGNAME: {os.environ.get('LOGNAME', 'NOT_SET')}")
        logger.debug(f"Environment SSH_USER: {os.environ.get('SSH_USER', 'NOT_SET')}")
        
        # Get IP address
        info['ip_address'] = SSHConnectionDetector._get_source_ip()
        
        # Get username
        info['username'] = SSHConnectionDetector._get_username()
        
        # Get connection type
        info['connection_type'] = SSHConnectionDetector._get_connection_type()
        
        # Get SSH user from environment
        info['ssh_user'] = os.environ.get('SSH_USER')
        
        # Get port
        info['port'] = SSHConnectionDetector._get_source_port()
        
        # Get client version
        info['client_version'] = os.environ.get('SSH_CLIENT_VERSION', 'unknown')
        
        return info
    
    @staticmethod
    def _get_source_ip() -> str:
        """Get source IP address."""
        # Try SSH_CONNECTION first
        ssh_connection = os.environ.get('SSH_CONNECTION')
        if ssh_connection:
            return ssh_connection.split()[0]
        
        # Try SSH_CLIENT
        ssh_client = os.environ.get('SSH_CLIENT')
        if ssh_client:
            return ssh_client.split()[0]
        
        # Try to get from network connections
        try:
            result = subprocess.run(['ss', '-tnp'], capture_output=True, text=True)
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                for line in lines:
                    if 'sshd' in line and 'ESTAB' in line:
                        parts = line.split()
                        if len(parts) >= 4:
                            remote_addr = parts[3]
                            if ':' in remote_addr:
                                return remote_addr.split(':')[0]
        except Exception:
            pass
        
        return 'unknown'
    
    @staticmethod
    def _get_username() -> str:
        """Get current username."""
        # Try SSH_USER first
        ssh_user = os.environ.get('SSH_USER')
        if ssh_user:
            return ssh_user
        
        # Try to get from environment
        username = os.environ.get('USER') or os.environ.get('LOGNAME')
        if username:
            return username
        
        # Fall back to whoami
        try:
            result = subprocess.run(['whoami'], capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass
        
        return 'unknown'
    
    @staticmethod
    def _get_connection_type() -> str:
        """Determine connection type."""
        # Check for original command
        if os.environ.get('SSH_ORIGINAL_COMMAND'):
            return 'Command execution'
        
        # Check for tunnel
        if os.environ.get('SSH_TUNNEL'):
            return 'Tunnel'
        
        # Check if interactive
        if sys.stdin.isatty() and sys.stdout.isatty():
            return 'Interactive shell'
        
        # Try to detect from process tree
        try:
            result = subprocess.run(['ps', '-o', 'cmd=', '-p', str(os.getppid())], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                parent_cmd = result.stdout.strip()
                if 'tunnel' in parent_cmd.lower():
                    return 'Tunnel'
                elif 'command' in parent_cmd.lower():
                    return 'Command execution'
        except Exception:
            pass
        
        return 'Interactive shell'
    
    @staticmethod
    def _get_source_port() -> str:
        """Get source port."""
        ssh_connection = os.environ.get('SSH_CONNECTION')
        if ssh_connection:
            parts = ssh_connection.split()
            if len(parts) >= 2:
                return parts[1]
        
        ssh_client = os.environ.get('SSH_CLIENT')
        if ssh_client:
            parts = ssh_client.split()
            if len(parts) >= 2:
                return parts[1]
        
        return 'unknown'

def main():
    """Main function for testing the key parser."""
    if len(sys.argv) < 2:
        print("Usage: python3 key-parser.py <command> [args]")
        print("Commands:")
        print("  get-info - Get current SSH connection info")
        print("  find-key <fingerprint> - Find key by fingerprint")
        print("  parse-auth-log <ip> <username> - Parse auth log for connection")
        print("  find-key-by-connection <ip> <username> - Find key by connection info")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "get-info":
        detector = SSHConnectionDetector()
        info = detector.get_connection_info()
        print(json.dumps(info, indent=2))
    
    elif command == "find-key":
        if len(sys.argv) < 3:
            print("Error: fingerprint required")
            sys.exit(1)
        
        fingerprint = sys.argv[2]
        parser = SSHKeyParser()
        key_info = parser.find_key_by_fingerprint(fingerprint)
        
        if key_info:
            print(json.dumps(key_info, indent=2))
        else:
            print("Key not found")
    
    elif command == "parse-auth-log":
        if len(sys.argv) < 4:
            print("Error: IP address and username required")
            sys.exit(1)
        
        ip_address = sys.argv[2]
        username = sys.argv[3]
        
        auth_parser = AuthLogParser()
        connection_info = auth_parser.find_recent_ssh_connection(ip_address, username)
        
        if connection_info:
            print(json.dumps(connection_info, indent=2))
        else:
            print("Connection not found in auth log")
    
    elif command == "find-key-by-connection":
        if len(sys.argv) < 4:
            print("Error: IP address and username required")
            sys.exit(1)
        
        ip_address = sys.argv[2]
        username = sys.argv[3]
        
        parser = SSHKeyParser()
        key_info = parser.find_key_by_ip_and_user(ip_address, username)
        
        if key_info:
            print(json.dumps(key_info, indent=2))
        else:
            print("Key not found")
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
