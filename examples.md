# SSH Alert - Примеры конфигурации

## Примеры authorized_keys

### Базовый ключ с SSH_USER
```
environment="SSH_USER=alice@example.com" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... alice@laptop
```

### Ключ с ограничениями
```
environment="SSH_USER=bob@company.com" command="/bin/true",no-port-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... bob@workstation
```

### Ключ для туннелей
```
environment="SSH_USER=tunnel@service.com" no-pty,no-X11-forwarding,permitopen="localhost:8080" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD... tunnel@gateway
```

## Примеры конфигурации

### Минимальная конфигурация
```bash
TELEGRAM_BOT_TOKEN="1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="-1001234567890"
NOTIFY_INTERACTIVE_SESSIONS=true
NOTIFY_TUNNELS=false
```

### Полная конфигурация
```bash
# Telegram
TELEGRAM_BOT_TOKEN="1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
TELEGRAM_CHAT_ID="-1001234567890"

# Server
SERVER_NAME="web-server-01"
SERVER_DOMAIN="example.com"

# Notifications
NOTIFY_INTERACTIVE_SESSIONS=true
NOTIFY_TUNNELS=true
NOTIFY_COMMANDS=false
DISABLE_NOTIFICATION_SOUND_FOR_TUNNELS=true

# Rate limiting
RATE_LIMIT_PER_IP=600
RATE_LIMIT_PER_KEY=120

# Logging
LOG_LEVEL="INFO"
JSON_LOGGING=true
```

## Примеры использования

### Тестирование уведомлений
```bash
# Симуляция SSH подключения
export SSH_CONNECTION="192.168.1.100 12345 192.168.1.1 22"
export SSH_USER="testuser"
sudo /opt/ssh-alert/ssh-alert-enhanced.sh
```

### Мониторинг логов
```bash
# Просмотр в реальном времени
sudo tail -f /var/log/ssh-alert.log

# Поиск по IP
sudo grep "192.168.1.100" /var/log/ssh-alert.log

# JSON логи
sudo tail -f /var/log/ssh-alert.log | jq '.'
```
