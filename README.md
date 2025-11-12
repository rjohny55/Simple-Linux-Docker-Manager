#Simple Linux Docker Manager 🐳

A powerful, user-friendly command-line tool for managing Docker images and containers with a beautiful colorized interface.

---

## English Version

### 📖 Overview

Docker Manager is an interactive bash script that provides a comprehensive interface for managing Docker resources. It features a colorized menu system that makes Docker management intuitive and safe, especially for users who prefer GUI-like interactions in the terminal.

### ✨ Features

#### 🖼️ Image Management
- **View all images** with creation dates and sizes
- **Delete selected images** by number with preview
- **Delete unused images** (dangling and unused)
- **Delete ALL images** (with safety confirmation)
- **Delete `<none>` tagged images** (intermediate layers)
- **Delete Docker build cache**

#### 🐳 Container Management
- **View all containers** with status and names
- **Stop selected containers** by number
- **Delete selected containers** by number
- **Stop and delete containers** in one operation

#### 🎨 Interface Features
- **Color-coded output** for better readability
- **Interactive number selection** for operations
- **Safety confirmations** for destructive operations
- **Cancel option** in every operation
- **Real-time preview** of what will be affected

### 🛠️ Requirements

- **Docker** installed and running
- **Bash** shell
- Linux, macOS, or WSL on Windows

### 📦 Installation

1. **Download the script:**
   ```bash
   git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
   cd Simple-Linux-Docker-Manager
   ```

2. **Make it executable:**
   ```bash
   chmod +x sldm.sh
   ```

3. **Run the script:**
   ```bash
   ./sldm.sh
   ```

### 🚀 Usage

#### Quick Start
```bash
./sldm.sh
```

#### Menu Options
1. **Show all images** - Display all Docker images with details
2. **Delete selected images** - Choose specific images to remove
3. **Delete unused images** - Clean up unused images
4. **Delete ALL images** - Remove all images (requires confirmation)
5. **Delete images with `<none>` tag** - Clean intermediate layers
6. **Delete Docker build cache** - Free up build cache space
7. **Show all containers** - Display all containers
8. **Stop selected containers** - Stop running containers
9. **Delete selected containers** - Remove containers
10. **Stop and delete containers** - Combined operation

### 🎯 Examples

#### Clean up unused resources:
1. Run the script
2. Choose option 3 (Delete unused images)
3. Choose option 6 (Delete build cache)

#### Remove specific containers:
1. Run the script
2. Choose option 7 (Show containers)
3. Choose option 9 (Delete containers)
4. Enter container numbers (e.g., `1 3 5`)
5. Confirm deletion

### ⚠️ Safety Features

- **Double confirmation** for dangerous operations
- **Preview before deletion** shows exactly what will be removed
- **Cancel option** available at every step
- **Color-coded warnings** for destructive operations

### 🔧 Advanced Usage

#### Add to PATH for global access:
```bash
sudo cp sldm.sh /usr/local/bin/docker-manager
sldm_ru
```

#### Create alias for quick access:
```bash
echo "alias dm='./sldm.sh'" >> ~/.bashrc
source ~/.bashrc
dm
```

---

## Русская Версия

### 📖 Обзор

Docker Manager - это интерактивный bash-скрипт, предоставляющий удобный интерфейс для управления ресурсами Docker. Он features цветное меню, которое делает управление Docker интуитивно понятным и безопасным, особенно для пользователей, предпочитающих GUI-подобные взаимодействия в терминале.

### ✨ Возможности

#### 🖼️ Управление образами
- **Просмотр всех образов** с датами создания и размерами
- **Удаление выбранных образов** по номерам с предпросмотром
- **Удаление неиспользуемых образов** (dangling и неиспользуемые)
- **Удаление ВСЕХ образов** (с подтверждением безопасности)
- **Удаление образов с тегом `<none>`** (промежуточные слои)
- **Удаление кеша сборок Docker**

#### 🐳 Управление контейнерами
- **Просмотр всех контейнеров** со статусами и именами
- **Остановка выбранных контейнеров** по номерам
- **Удаление выбранных контейнеров** по номерам
- **Остановка и удаление контейнеров** одной операцией

#### 🎨 Особенности интерфейса
- **Цветной вывод** для лучшей читаемости
- **Интерактивный выбор по номерам** для операций
- **Подтверждения безопасности** для деструктивных операций
- **Опция отмены** в каждой операции
- **Предварительный просмотр** того, что будет затронуто

### 🛠️ Требования

- **Docker** установлен и запущен
- **Bash** оболочка
- Linux, macOS или WSL на Windows

### 📦 Установка

1. **Скачайте скрипт:**
   ```bash
   git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
   cd Simple-Linux-Docker-Manager
   ```

2. **Сделайте его исполняемым:**
   ```bash
   chmod +x sldm_ru.sh
   ```

3. **Запустите скрипт:**
   ```bash
   ./sldm_ru.sh
   ```

### 🚀 Использование

#### Быстрый старт
```bash
./sldm_ru.sh
```

#### Опции меню
1. **Показать все образы** - Отображает все образы Docker с деталями
2. **Удалить выбранные образы** - Выбор конкретных образов для удаления
3. **Удалить неиспользуемые образы** - Очистка неиспользуемых образов
4. **Удалить ВСЕ образы** - Удаление всех образов (требует подтверждения)
5. **Удалить образы с тегом `<none>`** - Очистка промежуточных слоев
6. **Удалить кеш сборок Docker** - Освобождение места кеша сборок
7. **Показать все контейнеры** - Отображает все контейнеры
8. **Остановить выбранные контейнеры** - Остановка работающих контейнеров
9. **Удалить выбранные контейнеры** - Удаление контейнеров
10. **Остановить и удалить контейнеры** - Комбинированная операция

### 🎯 Примеры

#### Очистка неиспользуемых ресурсов:
1. Запустите скрипт
2. Выберите опцию 3 (Удалить неиспользуемые образы)
3. Выберите опцию 6 (Удалить кеш сборок)

#### Удаление конкретных контейнеров:
1. Запустите скрипт
2. Выберите опцию 7 (Показать контейнеры)
3. Выберите опцию 9 (Удалить контейнеры)
4. Введите номера контейнеров (например, `1 3 5`)
5. Подтвердите удаление

### ⚠️ Функции безопасности

- **Двойное подтверждение** для опасных операций
- **Предварительный просмотр** показывает что именно будет удалено
- **Опция отмены** доступна на каждом шаге
- **Цветные предупреждения** для деструктивных операций

### 🔧 Продвинутое использование

#### Добавление в PATH для глобального доступа:
```bash
sudo cp sldm_ru.sh /usr/local/bin/docker-manager
sldm_ru
```

#### Создание алиаса для быстрого доступа:
```bash
echo "alias dm='./sldm_ru'" >> ~/.bashrc
source ~/.bashrc
dm
```

---

## 📝 License

MIT License - feel free to use this script in your projects!

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This script performs destructive operations. Always ensure you have backups and understand what you're deleting. The authors are not responsible for any data loss.

---

**⭐ If you find this project useful, please give it a star!**
