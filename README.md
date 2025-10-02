# SSH Alert - Secure SSH Connection Monitoring

[![Bash](https://img.shields.io/badge/bash-4.0+-blue.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/python-3.6+-blue.svg?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Discord](https://img.shields.io/discord/1411852800241176616?style=for-the-badge&logo=discord&logoColor=white&label=Discord)](https://discord.gg/VMKdhujjCW)

A secure and reliable utility for monitoring SSH connections to a server with Telegram notifications.

## 🚀 Features

- **Maximum user identification**: IP address, key fingerprint, key comment, connection type
- **Flexible notifications**: Separate sound and silent messages for different connection types
- **Reliability**: Prevention of duplicate notifications during parallel sessions
- **Retry logic**: Automatic retries on network or Telegram API failures
- **Flexible configuration**: Configuration through config file
- **Security**: Minimal dependencies, works without SSH client modifications

## 📋 Requirements

- Linux server with OpenSSH
- Python 3.6+
- curl
- bash 4.0+
- Root privileges for installation

## 🛠 Installation

### Quick Installation

```bash
# Clone the repository
git clone https://github.com/B4DCATs/ssh-login-alert
cd ssh-login-alert

# Run the installation
sudo ./install.sh
```

**After installation, the repository can be removed:**
```bash
# After successful installation
cd ..
rm -rf ssh-login-alert
```

### What happens during installation

1. **Files are copied** to `/opt/ssh-alert/` and `/etc/ssh-alert/`
2. **SSH integration** is configured through `/etc/ssh/sshrc`
3. **Log rotation configuration** is created
4. **Interactive Telegram setup** is launched
5. **Configuration is tested**

### Manual Installation (if needed)

1. **Copy files**:
   ```bash
   sudo mkdir -p /opt/ssh-alert /etc/ssh-alert
   sudo cp ssh-alert-enhanced.sh /opt/ssh-alert/
   sudo cp key-parser.py /opt/ssh-alert/
   sudo cp config.conf /etc/ssh-alert/
   sudo cp logrotate.conf /etc/logrotate.d/ssh-alert
   sudo chmod +x /opt/ssh-alert/*.sh
   sudo chmod +x /opt/ssh-alert/*.py
   ```

2. **Configure SSH**:
   ```bash
   sudo tee /etc/ssh/sshrc > /dev/null << 'EOF'
   #!/bin/bash
   # SSH Alert Integration
   if [ -n "${SSH_ALERT_DISABLED:-}" ]; then
       exit 0
   fi
   /opt/ssh-alert/ssh-alert-enhanced.sh &
   EOF
   sudo chmod +x /etc/ssh/sshrc
   ```

3. **Configure settings**:
   ```bash
   sudo nano /etc/ssh-alert/config.conf
   ```

## ⚙️ Configuration

### Basic Settings

Edit the file `/etc/ssh-alert/config.conf`:

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"

# Server Information
SERVER_NAME="server01"
SERVER_DOMAIN="example.com"

# Notification Settings
NOTIFY_INTERACTIVE_SESSIONS=true
NOTIFY_TUNNELS=false
NOTIFY_COMMANDS=false
DISABLE_NOTIFICATION_SOUND_FOR_TUNNELS=true

# Rate Limiting (seconds)
RATE_LIMIT_PER_IP=300
RATE_LIMIT_PER_KEY=60
```

### authorized_keys Configuration

For maximum user identification, configure `authorized_keys`:

```bash
sudo ./setup-authorized-keys.sh
```

Or manually add `SSH_USER` to keys:

```
environment="SSH_USER=alice@example.com" ssh-rsa AAAAB3NzaC1yc2E... alice@laptop
```

### Key Exclusions from Notifications

For automated connections (pipelines, monitoring), you can exclude certain keys from notifications:

```bash
# Add exclusion
sudo ./manage-exclusions.sh add "pipeline@ci"
sudo ./manage-exclusions.sh add "deploy@automation"

# View current exclusions
sudo ./manage-exclusions.sh list

# Remove exclusion
sudo ./manage-exclusions.sh remove "pipeline@ci"

# Clear all exclusions
sudo ./manage-exclusions.sh clear
```

**Usage examples:**
- `pipeline@ci` - for CI/CD pipelines
- `deploy@automation` - for automatic deployment
- `monitoring@system` - for monitoring systems
- `backup@cron` - for automatic backups

**Note:** Exclusions work by key comments in `authorized_keys`. Keys with specified comments will not trigger notifications.

## 📱 Creating a Telegram Bot

1. **Create a bot**:
   - Send `/newbot` to [@BotFather](https://t.me/BotFather)
   - Follow the instructions to create a bot
   - Save the received token

2. **Get Chat ID**:
   - Add the bot to a chat or send it a message
   - Go to the link: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find `chat.id` in the response

## 🔧 Usage

### Basic Commands

```bash
# View logs
sudo tail -f /var/log/ssh-alert.log

# Test configuration
sudo /opt/ssh-alert/ssh-alert-enhanced.sh

# Log management
sudo /opt/ssh-alert/check-log-rotation.sh status    # Check rotation status
sudo /opt/ssh-alert/check-log-rotation.sh test      # Test configuration
sudo /opt/ssh-alert/check-log-rotation.sh rotate    # Force rotation

# Exclusion management
sudo ./manage-exclusions.sh list                    # Show current exclusions
sudo ./manage-exclusions.sh add "pipeline@ci"       # Add exclusion
sudo ./manage-exclusions.sh remove "pipeline@ci"    # Remove exclusion
sudo ./manage-exclusions.sh clear                   # Clear all exclusions

# Uninstall
sudo /opt/ssh-alert/uninstall.sh
```

### Notification Types

SSH Alert distinguishes the following connection types:

- **Interactive shell** - Interactive session (default with sound)
- **Tunnel** - SSH tunnel (default without sound)
- **Command execution** - Command execution (configurable)

### Notification Example

```
🔐 SSH Login Alert:
Host IP: 203.0.113.1 / 192.168.1.100
Host: server01.example.com
Person: alice@example.com
IP: 198.51.100.50
Type: Interactive shell
Key: SHA256:abcd1234...
Time: 2024-01-15 14:30:25 UTC
```

## 🛡 Security

### Recommendations

1. **Restrict access to configuration**:
   ```bash
   sudo chmod 600 /etc/ssh-alert/config.conf
   sudo chown root:root /etc/ssh-alert/config.conf
   ```

2. **Configure firewall**:
   ```bash
   # Allow SSH only from trusted IPs
   sudo ufw allow from 192.168.1.0/24 to any port 22
   ```

3. **Use keys instead of passwords**:
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

### Logging

SSH Alert maintains detailed logs:

```bash
# View logs
sudo tail -f /var/log/ssh-alert.log

# JSON logging (optional)
# Set JSON_LOGGING=true in config.conf
```

### Log Rotation

SSH Alert automatically configures log rotation through `logrotate`:

```bash
# Check rotation status
make check-logs

# Test rotation configuration
make test-logs

# Force rotation
make rotate-logs

# Manual check
sudo ./check-log-rotation.sh status
```

**Rotation settings:**
- 📅 **Daily rotation** of logs
- 📦 **30 days** of compressed log storage
- 🗜️ **Compression** of old logs
- 📏 **Minimum size** 100KB for rotation
- 📏 **Maximum size** 10MB for forced rotation
- 🧹 **Cleanup** of rate limiting temporary files

## 🔍 Troubleshooting

### Common Issues

1. **Post-installation errors**:
   ```bash
   # If you see errors like "[[ not found" or "config.conf not found"
   sudo ./fix-installation.sh
   ```

2. **Notifications not arriving**:
   ```bash
   # Check token and chat_id
   sudo grep -E "TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID" /etc/ssh-alert/config.conf
   
   # Check logs
   sudo tail -f /var/log/ssh-alert.log
   ```

3. **Script not starting**:
   ```bash
   # Check permissions
   ls -la /opt/ssh-alert/ssh-alert-enhanced.sh
   
   # Check syntax
   bash -n /opt/ssh-alert/ssh-alert-enhanced.sh
   ```

4. **Python errors**:
   ```bash
   # Check Python version
   python3 --version
   
   # Test parser
   python3 /opt/ssh-alert/key-parser.py get-info
   ```

### Debugging

Enable debug logs:

```bash
sudo nano /etc/ssh-alert/config.conf
# Set: LOG_LEVEL="DEBUG"
```

## 📊 Monitoring

### System Check

```bash
# System status
sudo systemctl status ssh-alert 2>/dev/null || echo "Service not installed"

# Active connections
sudo ss -tnp | grep sshd

# Recent notifications
sudo grep "SSH alert sent" /var/log/ssh-alert.log | tail -5
```

### Metrics

SSH Alert can integrate with monitoring systems through JSON logs:

```bash
# Enable JSON logging
echo 'JSON_LOGGING=true' | sudo tee -a /etc/ssh-alert/config.conf

# Parse logs
sudo tail -f /var/log/ssh-alert.log | jq '.'
```

## 🔄 Updates

### Automatic Update

```bash
# Update from repository
git pull origin main
sudo ./install.sh
```

### Manual Update

```bash
# Create backup
sudo cp -r /opt/ssh-alert /opt/ssh-alert.backup
sudo cp /etc/ssh-alert/config.conf /etc/ssh-alert/config.conf.backup

# Update files
sudo cp ssh-alert-enhanced.sh /opt/ssh-alert/
sudo cp key-parser.py /opt/ssh-alert/
sudo cp uninstall.sh /opt/ssh-alert/
sudo cp check-log-rotation.sh /opt/ssh-alert/
sudo cp logrotate.conf /etc/logrotate.d/ssh-alert
```

## 🗑️ Uninstallation

### Complete Removal

```bash
# Run the uninstall script
sudo /opt/ssh-alert/uninstall.sh
```

### What gets removed

- ✅ All SSH Alert files
- ✅ SSH integration from `/etc/ssh/sshrc`
- ✅ Systemd service
- ✅ Log rotation configuration
- ✅ Temporary files and cache
- ✅ Backup copies are created

### Manual Removal

```bash
# Stop processes
sudo pkill -f ssh-alert

# Remove files
sudo rm -rf /opt/ssh-alert
sudo rm -rf /etc/ssh-alert

# Clear SSH integration
sudo rm -f /etc/ssh/sshrc

# Remove temporary files
sudo rm -f /tmp/ssh-alert.lock
sudo rm -rf /tmp/ssh-alert-rate-limit
```

## 📝 License

This project is distributed under the MIT license. See the `LICENSE` file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a branch for a new feature (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

If you encounter problems or have questions:

1. Check the [troubleshooting section](#troubleshooting)
2. Create an [Issue](https://github.com/your-repo/ssh-alert/issues)
3. Refer to the documentation

## 🔮 Development Roadmap

- [ ] Support for other messengers (Slack, Discord)
- [ ] Web interface for management
- [ ] Integration with SIEM systems
- [ ] Machine learning for anomaly detection
- [ ] IPv6 support
- [ ] Advanced connection analytics
