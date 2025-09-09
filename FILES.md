# SSH Alert - Список файлов проекта

## 📁 Структура проекта

```
ssh-alert/
├── README.md                    # Основная документация
├── LICENSE                      # MIT лицензия
├── Makefile                     # Управление проектом
├── config.conf                  # Конфигурационный файл
├── examples.md                  # Примеры конфигурации
├── FILES.md                     # Этот файл
│
├── install.sh                   # Скрипт установки
├── uninstall.sh                 # Скрипт удаления
├── fix-installation.sh          # Исправление проблем установки
│
├── ssh-alert.sh                 # Основной скрипт (базовая версия)
├── ssh-alert-enhanced.sh        # Улучшенный скрипт
├── key-parser.py                # Python парсер ключей
│
├── setup-authorized-keys.sh     # Настройка authorized_keys
├── setup-ssh-key-detection.sh   # Настройка определения ключей
├── debug-keys.sh                # Диагностика ключей
├── test-connection.sh           # Тестирование подключений
└── debug-ssh-info.sh            # Диагностика SSH информации
```

## 🔧 Основные файлы

### Установка и управление
- **`install.sh`** - Автоматическая установка с интерактивной настройкой
- **`uninstall.sh`** - Полное удаление с созданием резервных копий
- **`fix-installation.sh`** - Исправление проблем после установки
- **`Makefile`** - Удобные команды для управления

### Основные скрипты
- **`ssh-alert-enhanced.sh`** - Главный скрипт мониторинга SSH
- **`key-parser.py`** - Python модуль для работы с ключами и journald
- **`ssh-alert.sh`** - Базовая версия (для совместимости)

### Утилиты настройки
- **`setup-authorized-keys.sh`** - Настройка authorized_keys с SSH_USER
- **`setup-ssh-key-detection.sh`** - Настройка определения ключей
- **`debug-keys.sh`** - Диагностика проблем с ключами
- **`test-connection.sh`** - Тестирование подключений

### Конфигурация
- **`config.conf`** - Основной конфигурационный файл
- **`examples.md`** - Примеры конфигурации и использования

### Документация
- **`README.md`** - Полная документация проекта
- **`LICENSE`** - MIT лицензия
- **`FILES.md`** - Описание файлов проекта

## 🚀 Быстрый старт

```bash
# Установка
sudo ./install.sh

# Управление
make help

# Удаление
sudo ./uninstall.sh
```

## 📋 Требования

- Linux с OpenSSH
- Python 3.6+
- curl, bash 4.0+
- Права root для установки

## 🔗 Интеграция

- **SSH**: Автоматическая интеграция через `/etc/ssh/sshrc`
- **Systemd**: Опциональная служба
- **Logrotate**: Автоматическая ротация логов
- **Telegram**: Уведомления через Bot API
