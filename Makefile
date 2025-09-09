# SSH Alert Makefile
# ==================

.PHONY: install uninstall test clean setup-keys show-config

# Default target
all: install

# Installation
install:
	@echo "Installing SSH Alert..."
	sudo ./install.sh

# Uninstallation
uninstall:
	@echo "Uninstalling SSH Alert..."
	sudo /opt/ssh-alert/uninstall.sh

# Test configuration
test:
	@echo "Testing SSH Alert configuration..."
	sudo bash -n ssh-alert-enhanced.sh
	sudo python3 -m py_compile key-parser.py
	@echo "Configuration test passed"

# Setup authorized keys
setup-keys:
	@echo "Setting up authorized keys..."
	sudo ./setup-authorized-keys.sh

# Show current configuration
show-config:
	@echo "Current SSH Alert configuration:"
	@if [ -f /etc/ssh-alert/config.conf ]; then \
		sudo cat /etc/ssh-alert/config.conf; \
	else \
		echo "Configuration file not found"; \
	fi

# View logs
logs:
	@echo "Viewing SSH Alert logs..."
	sudo tail -f /var/log/ssh-alert.log

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	sudo rm -f /tmp/ssh-alert.lock
	sudo rm -rf /tmp/ssh-alert-rate-limit

# Check system requirements
check-requirements:
	@echo "Checking system requirements..."
	@command -v curl >/dev/null 2>&1 || { echo "curl is required but not installed"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "python3 is required but not installed"; exit 1; }
	@command -v flock >/dev/null 2>&1 || { echo "flock is required but not installed"; exit 1; }
	@python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)" || { echo "Python 3.6+ is required"; exit 1; }
	@echo "All requirements satisfied"

# Backup configuration
backup:
	@echo "Creating backup..."
	@if [ -f /etc/ssh-alert/config.conf ]; then \
		sudo cp /etc/ssh-alert/config.conf /etc/ssh-alert/config.conf.backup.$(shell date +%Y%m%d_%H%M%S); \
		echo "Configuration backed up"; \
	else \
		echo "No configuration file to backup"; \
	fi

# Restore configuration
restore:
	@echo "Available backups:"
	@ls -la /etc/ssh-alert/config.conf.backup.* 2>/dev/null || echo "No backups found"
	@echo "To restore, manually copy a backup file to /etc/ssh-alert/config.conf"

# Help
help:
	@echo "SSH Alert Makefile"
	@echo "=================="
	@echo ""
	@echo "Available targets:"
	@echo "  install         - Install SSH Alert system"
	@echo "  uninstall       - Uninstall SSH Alert system"
	@echo "  test            - Test configuration and scripts"
	@echo "  setup-keys      - Setup authorized keys with SSH_USER"
	@echo "  show-config     - Show current configuration"
	@echo "  logs            - View SSH Alert logs in real-time"
	@echo "  clean           - Clean temporary files"
	@echo "  check-requirements - Check system requirements"
	@echo "  backup          - Backup current configuration"
	@echo "  restore         - Show available backups"
	@echo "  help            - Show this help message"
