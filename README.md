# SSH Alert - Secure SSH Connection Monitoring

Безопасная и надёжная утилита для отслеживания SSH-подключений к серверу с отправкой уведомлений в Telegram.

## 🚀 Возможности

- **Максимальная идентификация пользователя**: IP-адрес, fingerprint ключа, комментарий ключа, тип подключения
- **Гибкие уведомления**: Разделение звуковых и тихих сообщений для разных типов подключений
- **Надёжность**: Предотвращение дублированных уведомлений при параллельных сессиях
- **Retry логика**: Автоматические повторы при сбоях сети или Telegram API
- **Гибкая конфигурация**: Настройка через конфигурационный файл
- **Безопасность**: Минимальные зависимости, работа без изменений SSH-клиентов

## 📋 Требования

- Linux сервер с OpenSSH
- Python 3.6+
- curl
- bash 4.0+
- Права root для установки

## 🛠 Установка

### Быстрая установка

```bash
# Клонируйте репозиторий
git clone <repository-url>
cd ssh-alert

# Запустите установку
sudo ./install.sh
```

### Ручная установка

1. **Скопируйте файлы**:
   ```bash
   sudo mkdir -p /opt/ssh-alert
   sudo cp ssh-alert-enhanced.sh /opt/ssh-alert/
   sudo cp key-parser.py /opt/ssh-alert/
   sudo cp config.conf /etc/ssh-alert/
   sudo chmod +x /opt/ssh-alert/*.sh
   sudo chmod +x /opt/ssh-alert/*.py
   ```

2. **Настройте SSH**:
   ```bash
   sudo cp /etc/ssh/sshrc /etc/ssh/sshrc.backup
   sudo tee /etc/ssh/sshrc > /dev/null << 'EOF'
   #!/bin/bash
   /opt/ssh-alert/ssh-alert-enhanced.sh &
   EOF
   sudo chmod +x /etc/ssh/sshrc
   ```

3. **Настройте конфигурацию**:
   ```bash
   sudo nano /etc/ssh-alert/config.conf
   ```

## ⚙️ Конфигурация

### Основные настройки

Отредактируйте файл `/etc/ssh-alert/config.conf`:

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

### Настройка authorized_keys

Для максимальной идентификации пользователей настройте `authorized_keys`:

```bash
sudo ./setup-authorized-keys.sh
```

Или вручную добавьте `SSH_USER` в ключи:

```
environment="SSH_USER=alice@example.com" ssh-rsa AAAAB3NzaC1yc2E... alice@laptop
```

## 📱 Создание Telegram бота

1. **Создайте бота**:
   - Отправьте `/newbot` боту [@BotFather](https://t.me/BotFather)
   - Следуйте инструкциям для создания бота
   - Сохраните полученный токен

2. **Получите Chat ID**:
   - Добавьте бота в чат или отправьте ему сообщение
   - Перейдите по ссылке: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Найдите `chat.id` в ответе

## 🔧 Использование

### Основные команды

```bash
# Просмотр логов
sudo tail -f /var/log/ssh-alert.log

# Тестирование конфигурации
sudo /opt/ssh-alert/ssh-alert-enhanced.sh

# Настройка ключей
sudo ./setup-authorized-keys.sh

# Удаление
sudo /opt/ssh-alert/uninstall.sh
```

### Типы уведомлений

SSH Alert различает следующие типы подключений:

- **Interactive shell** - Интерактивная сессия (по умолчанию с звуком)
- **Tunnel** - SSH туннель (по умолчанию без звука)
- **Command execution** - Выполнение команды (настраивается)

### Пример уведомления

```
🔐 SSH Login Alert:
User: root
Person: alice@example.com
Host: server01.example.com
IP: 103.75.127.215
Type: Interactive shell
Key: a1:b2:c3:d4:e5:f6...
Time: 2024-01-15 14:30:25 UTC
```

## 🛡 Безопасность

### Рекомендации

1. **Ограничьте доступ к конфигурации**:
   ```bash
   sudo chmod 600 /etc/ssh-alert/config.conf
   sudo chown root:root /etc/ssh-alert/config.conf
   ```

2. **Настройте файрвол**:
   ```bash
   # Разрешите SSH только с доверенных IP
   sudo ufw allow from 192.168.1.0/24 to any port 22
   ```

3. **Используйте ключи вместо паролей**:
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Установите: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

### Логирование

SSH Alert ведёт подробные логи:

```bash
# Просмотр логов
sudo tail -f /var/log/ssh-alert.log

# JSON логирование (опционально)
# Установите JSON_LOGGING=true в config.conf
```

## 🔍 Устранение неполадок

### Частые проблемы

1. **Уведомления не приходят**:
   ```bash
   # Проверьте токен и chat_id
   sudo grep -E "TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID" /etc/ssh-alert/config.conf
   
   # Проверьте логи
   sudo tail -f /var/log/ssh-alert.log
   ```

2. **Скрипт не запускается**:
   ```bash
   # Проверьте права доступа
   ls -la /opt/ssh-alert/ssh-alert-enhanced.sh
   
   # Проверьте синтаксис
   bash -n /opt/ssh-alert/ssh-alert-enhanced.sh
   ```

3. **Python ошибки**:
   ```bash
   # Проверьте версию Python
   python3 --version
   
   # Тестируйте парсер
   python3 /opt/ssh-alert/key-parser.py get-info
   ```

### Отладка

Включите отладочные логи:

```bash
sudo nano /etc/ssh-alert/config.conf
# Установите: LOG_LEVEL="DEBUG"
```

## 📊 Мониторинг

### Проверка работы

```bash
# Статус системы
sudo systemctl status ssh-alert 2>/dev/null || echo "Service not installed"

# Активные подключения
sudo ss -tnp | grep sshd

# Последние уведомления
sudo grep "SSH alert sent" /var/log/ssh-alert.log | tail -5
```

### Метрики

SSH Alert может интегрироваться с системами мониторинга через JSON логи:

```bash
# Включите JSON логирование
echo 'JSON_LOGGING=true' | sudo tee -a /etc/ssh-alert/config.conf

# Парсинг логов
sudo tail -f /var/log/ssh-alert.log | jq '.'
```

## 🔄 Обновление

```bash
# Создайте резервную копию
sudo cp -r /opt/ssh-alert /opt/ssh-alert.backup
sudo cp /etc/ssh-alert/config.conf /etc/ssh-alert/config.conf.backup

# Обновите файлы
sudo cp ssh-alert-enhanced.sh /opt/ssh-alert/
sudo cp key-parser.py /opt/ssh-alert/

# Перезапустите службу (если используется)
sudo systemctl restart ssh-alert
```

## 📝 Лицензия

Этот проект распространяется под лицензией MIT. См. файл `LICENSE` для подробностей.

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте ветку для новой функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📞 Поддержка

Если у вас возникли проблемы или вопросы:

1. Проверьте [раздел устранения неполадок](#устранение-неполадок)
2. Создайте [Issue](https://github.com/your-repo/ssh-alert/issues)
3. Обратитесь к документации

## 🔮 Планы развития

- [ ] Поддержка других мессенджеров (Slack, Discord)
- [ ] Веб-интерфейс для управления
- [ ] Интеграция с SIEM системами
- [ ] Машинное обучение для обнаружения аномалий
- [ ] Поддержка IPv6
- [ ] Расширенная аналитика подключений
