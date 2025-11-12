# Simple Linux Docker Manager 🐳

A powerful, lightweight command-line tool for managing Docker images and containers with a beautiful colorized interface. Optimized for low-resource environments like Raspberry Pi, Orange Pi, and other mini-computers.

## English Version

### 📖 Overview

Docker Manager is an interactive bash script that provides a comprehensive interface for managing Docker resources. It features a colorized menu system that makes Docker management intuitive and safe, especially for users who prefer GUI-like interactions in the terminal.

**✨ Now with Enhanced Performance & Mobile Optimization**

### 🌟 Key Features

#### 🖼️ Enhanced Image Management
- **View all images** with creation dates, sizes, and pagination
- **Delete selected images** by number with preview
- **Delete unused images** (dangling and unused)
- **Delete ALL images** (with safety confirmation)
- **Delete `<none>` tagged images** (intermediate layers)
- **Delete Docker build cache**
- **🆕 Update selected images** from registry (pull)
- **🆕 Push images** to repositories
- **🆕 Smart pagination** for large image collections

#### 🐳 Advanced Container Management
- **View all containers** with status, names, IP addresses, and memory usage
- **Stop selected containers** by number
- **Delete selected containers** by number
- **Stop and delete containers** in one operation
- **Start selected containers** by number
- **🆕 Real-time container statistics** (IP, memory, status)
- **🆕 Paginated container lists**

#### 📊 System Monitoring
- **🆕 Disk usage statistics** for images
- **🆕 Memory usage statistics** for containers
- **🆕 Real-time system resource monitoring**
- **🆕 Storage optimization insights**

#### 🎨 Interface Features
- **Color-coded output** for better readability
- **Interactive number selection** for operations
- **Safety confirmations** for destructive operations
- **Cancel option** in every operation
- **Real-time preview** of what will be affected
- **🆕 Bilingual support** (English/Russian)

### 🚀 Advantages & Performance

**✨ Minimal Resource Usage**
- **Pure Bash implementation** - no additional dependencies
- **Low memory footprint** (<10MB during operation)
- **Efficient process management** without background services
- **Fast execution** with optimized Docker API calls
- **No GUI overhead** - pure terminal interface

**📱 Mobile & Mini-Computer Optimized**
- ✅ **Raspberry Pi** (all models)
- ✅ **Orange Pi** (all variants)  
- ✅ **Rock64** and other SBCs
- ✅ **Atomic Pi** and mini x86 systems
- ✅ **Low-power ARM devices**
- ✅ **Embedded Linux systems**

**⚡ Performance Benefits**
- Minimal CPU usage during idle
- Efficient memory management
- Fast startup and response times
- Optimized for slow storage (SD cards)
- Handles large numbers of images/containers efficiently

### 🛠️ Requirements

- **Bash** 4.0 or higher
- **Docker** installed and running
- **Linux** environment (including WSL on Windows)

### 📦 Installation

#### Method 1: Direct Download (English Version)
```bash
# Download the English version
wget https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm.sh

# Make executable
chmod +x sldm.sh

# Run the script
./sldm.sh
```

#### Method 2: Git Clone (Both Versions)
```bash
git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
cd Simple-Linux-Docker-Manager

# English version
chmod +x sldm.sh
./sldm.sh

# Russian version
chmod +x sldm_ru.sh
./sldm_ru.sh
```

### 🎮 Usage

#### Quick Start
```bash
./sldm.sh
```

#### Main Menu Options
1. **📦 Show all images** - Display all Docker images with pagination and details
2. **🐳 Show all containers** - Display all containers with status and resource usage
3. **🧹 Docker system cleanup** - Comprehensive cleanup options

#### Image Operations
- **Delete selected images** - Choose specific images to remove
- **Delete unused images** - Clean up unused images
- **Delete ALL images** - Remove all images (requires confirmation)
- **Delete images with `<none>` tag** - Clean intermediate layers
- **Delete Docker build cache** - Free up build cache space
- **🆕 Update selected image** - Pull latest version from registry
- **🆕 Push selected image** - Push to Docker repository

#### Container Operations
- **Stop selected containers** - Stop running containers
- **Delete selected containers** - Remove containers
- **Stop and delete containers** - Combined operation
- **Start selected containers** - Start stopped containers

### 🎯 Examples

#### Clean up unused resources:
1. Run the script: `./sldm.sh`
2. Choose option 3 (Docker system cleanup)
3. Select cleanup options as needed

#### Remove specific containers:
1. Run the script: `./sldm.sh`
2. Choose option 2 (Show all containers)
3. Choose delete operation
4. Enter container numbers (e.g., 1 3 5)
5. Confirm deletion

#### Update and manage images:
1. Run the script: `./sldm.sh`
2. Choose option 1 (Show all images)
3. Use new update/push features
4. Navigate pages if you have many images

### ⚠️ Safety Features

- **Double confirmation** for dangerous operations
- **Preview before deletion** shows exactly what will be removed
- **Cancel option** available at every step
- **Color-coded warnings** for destructive operations
- **🆕 Russian keyboard layout support** for confirmations

### 🔧 Advanced Usage

#### Add to PATH for global access:
```bash
sudo cp sldm.sh /usr/local/bin/docker-manager
docker-manager  # Now available anywhere
```

#### Create alias for quick access:
```bash
echo "alias dm='./sldm.sh'" >> ~/.bashrc
source ~/.bashrc
dm  # Quick access
```

#### System Compatibility

| Device Type | RAM Usage | Storage | Performance |
|-------------|-----------|---------|-------------|
| Raspberry Pi 4 | <15MB | MicroSD | Excellent |
| Orange Pi Zero | <10MB | MicroSD | Great |
| Rock64 4GB | <12MB | eMMC | Excellent |
| Atomic Pi | <20MB | eMMC | Excellent |

---

## Русская Версия / Russian Version

### 📖 Обзор

Docker Manager - это интерактивный bash-скрипт, предоставляющий удобный интерфейс для управления ресурсами Docker. Он features цветное меню, которое делает управление Docker интуитивно понятным и безопасным.

**✨ Теперь с улучшенной производительностью и оптимизацией для мобильных устройств**

### 🌟 Основные возможности

#### 🖼️ Расширенное управление образами
- **Просмотр всех образов** с датами создания, размерами и пагинацией
- **Удаление выбранных образов** по номерам с предпросмотром
- **Удаление неиспользуемых образов** (dangling и неиспользуемые)
- **Удаление ВСЕХ образов** (с подтверждением безопасности)
- **Удаление образов с тегом `<none>`** (промежуточные слои)
- **Удаление кеша сборок Docker**
- **🆕 Обновление выбранных образов** из реестра (pull)
- **🆕 Отправка образов** в репозитории
- **🆕 Умная пагинация** для больших коллекций образов

#### 🐳 Продвинутое управление контейнерами
- **Просмотр всех контейнеров** со статусами, именами, IP-адресами и использованием памяти
- **Остановка выбранных контейнеров** по номерам
- **Удаление выбранных контейнеров** по номерам
- **Остановка и удаление контейнеров** одной операцией
- **Запуск выбранных контейнеров** по номерам
- **🆕 Статистика контейнеров в реальном времени** (IP, память, статус)
- **🆕 Пагинация списков контейнеров**

#### 📊 Мониторинг системы
- **🆕 Статистика использования диска** для образов
- **🆕 Статистика использования памяти** для контейнеров
- **🆕 Мониторинг ресурсов системы** в реальном времени
- **🆕 Инсайты по оптимизации хранилища**

#### 🎨 Особенности интерфейса
- **Цветной вывод** для лучшей читаемости
- **Интерактивный выбор по номерам** для операций
- **Подтверждения безопасности** для деструктивных операций
- **Опция отмены** в каждой операции
- **Предварительный просмотр** того, что будет затронуто
- **🆕 Поддержка двух языков** (Английский/Русский)

### 🚀 Преимущества и производительность

**✨ Минимальное использование ресурсов**
- **Реализация на чистом Bash** - без дополнительных зависимостей
- **Низкое потребление памяти** (<10MB во время работы)
- **Эффективное управление процессами** без фоновых служб
- **Быстрое выполнение** с оптимизированными вызовами Docker API
- **Нет накладных расходов GUI** - чистый терминальный интерфейс

**📱 Оптимизация для мобильных и мини-компьютеров**
- ✅ **Raspberry Pi** (все модели)
- ✅ **Orange Pi** (все варианты)
- ✅ **Rock64** и другие одноплатные компьютеры
- ✅ **Atomic Pi** и мини x86 системы
- ✅ **Маломощные ARM устройства**
- ✅ **Встраиваемые Linux системы**

**⚡ Преимущества производительности**
- Минимальное использование CPU в простое
- Эффективное управление памятью
- Быстрый запуск и отклик
- Оптимизация для медленных носителей (SD карты)
- Эффективная работа с большим количеством образов/контейнеров

### 🛠️ Требования

- **Bash** 4.0 или выше
- **Docker** установлен и запущен
- **Linux** окружение (включая WSL на Windows)

### 📦 Установка

#### Способ 1: Прямая загрузка (Русская версия)
```bash
# Скачать русскую версию
wget https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm_ru.sh

# Сделать исполняемым
chmod +x sldm_ru.sh

# Запустить скрипт
./sldm_ru.sh
```

#### Способ 2: Git клонирование (Обе версии)
```bash
git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
cd Simple-Linux-Docker-Manager

# Русская версия
chmod +x sldm_ru.sh
./sldm_ru.sh

# Английская версия
chmod +x sldm.sh
./sldm.sh
```

### 🎮 Использование

#### Быстрый старт
```bash
./sldm_ru.sh
```

#### Основные опции меню
1. **📦 Показать все образы** - Отображает все образы Docker с пагинацией и деталями
2. **🐳 Показать все контейнеры** - Отображает все контейнеры со статусом и использованием ресурсов
3. **🧹 Очистка системы Docker** - Комплексные опции очистки

#### Операции с образами
- **Удалить выбранные образы** - Выбор конкретных образов для удаления
- **Удалить неиспользуемые образы** - Очистка неиспользуемых образов
- **Удалить ВСЕ образы** - Удаление всех образов (требует подтверждения)
- **Удалить образы с тегом `<none>`** - Очистка промежуточных слоев
- **Удалить кеш сборок Docker** - Освобождение места кеша сборок
- **🆕 Обновить выбранный образ** - Загрузка последней версии из реестра
- **🆕 Запушить выбранный образ** - Отправка в Docker репозиторий

#### Операции с контейнерами
- **Остановить выбранные контейнеры** - Остановка работающих контейнеров
- **Удалить выбранные контейнеры** - Удаление контейнеров
- **Остановить и удалить контейнеры** - Комбинированная операция
- **Запустить выбранные контейнеры** - Запуск остановленных контейнеров

### 🎯 Примеры

#### Очистка неиспользуемых ресурсов:
1. Запустите скрипт: `./sldm_ru.sh`
2. Выберите опцию 3 (Очистка системы Docker)
3. Выберите нужные опции очистки

#### Удаление конкретных контейнеров:
1. Запустите скрипт: `./sldm_ru.sh`
2. Выберите опцию 2 (Показать все контейнеры)
3. Выберите операцию удаления
4. Введите номера контейнеров (например, 1 3 5)
5. Подтвердите удаление

#### Обновление и управление образами:
1. Запустите скрипт: `./sldm_ru.sh`
2. Выберите опцию 1 (Показать все образы)
3. Используйте новые функции обновления/отправки
4. Переключайтесь между страницами при большом количестве образов

### ⚠️ Функции безопасности

- **Двойное подтверждение** для опасных операций
- **Предварительный просмотр** показывает что именно будет удалено
- **Опция отмены** доступна на каждом шаге
- **Цветные предупреждения** для деструктивных операций
- **🆕 Поддержка русской раскладки** для подтверждений

### 🔧 Продвинутое использование

#### Добавление в PATH для глобального доступа:
```bash
sudo cp sldm_ru.sh /usr/local/bin/docker-manager
docker-manager  # Теперь доступен везде
```

#### Создание алиаса для быстрого доступа:
```bash
echo "alias dm='./sldm_ru.sh'" >> ~/.bashrc
source ~/.bashrc
dm  # Быстрый доступ
```

#### Совместимость с системами

| Тип устройства | Использование RAM | Накопитель | Производительность |
|---------------|------------------|------------|-------------------|
| Raspberry Pi 4 | <15MB | MicroSD | Отличная |
| Orange Pi Zero | <10MB | MicroSD | Отличная |
| Rock64 4GB | <12MB | eMMC | Отличная |
| Atomic Pi | <20MB | eMMC | Отличная |

---

## 📄 License / Лицензия

MIT License - feel free to use this script in your projects!  
MIT License - свободно используйте этот скрипт в своих проектах!

## 🤝 Contributing / Участие в разработке

Contributions are welcome! Please feel free to submit a Pull Request.  
Вклад приветствуется! Вы можете создавать Pull Request.

## ⚠️ Disclaimer / Предупреждение

This script performs destructive operations. Always ensure you have backups and understand what you're deleting. The authors are not responsible for any data loss.  
Этот скрипт выполняет деструктивные операции. Всегда убеждайтесь, что у вас есть резервные копии и вы понимаете, что удаляете. Авторы не несут ответственности за потерю данных.

⭐ If you find this project useful, please give it a star!  
⭐ Если вы находите этот проект полезным, пожалуйста, поставьте звезду!
