# Simple Linux Docker Manager (SLDM) 🐳

![Version](https://img.shields.io/badge/version-1.2.3-blue) [![Bash](https://img.shields.io/badge/Bash-4.4%2B-green)](https://www.gnu.org/software/bash/) [![Docker](https://img.shields.io/badge/Docker-20.10%2B-blue)](https://docker.com) ![License](https://img.shields.io/badge/license-Apache-orange) [![Stars](https://img.shields.io/github/stars/rjohny55/Simple-Linux-Docker-Manager?style=social)](https://github.com/rjohny55/Simple-Linux-Docker-Manager)



A powerful, lightweight, **asynchronous** command-line tool for managing Docker images, containers, volumes, and networks. Features a beautiful TUI (Text User Interface), real-time system monitoring, and instant responsiveness.

> **Optimized for:** Raspberry Pi, Orange Pi, VPS, and High-Load Servers.  
> **Compatible with:** Linux (Debian, Ubuntu, Alpine, Arch, etc.) & macOS.

---

## 🇬🇧 English Version

### 📖 Overview
SLDM v1.2.3 Final Release — best bash-docker manager 2025 year 
Optimization & Hardware (System & Hardware)

    Moved Cache to RAM (/dev/shm):
        Cache and lock files (.cache, .lock) are now created in /dev/shm (Shared Memory).
        Why: This eliminates constant writing to the SSD/SD card during every statistic update (once per second), which is critical for the longevity of flash storage on Raspberry Pi and other single-board computers.
        Speed: Read/write operations in RAM are instantaneous.

    Universal Compatibility:
        Added a check for the existence of /dev/shm.
        If the script is running on a system without Shared Memory (e.g., macOS or specific container environments), it automatically falls back to using /tmp.

🐛 Bug Fixes

    Disk Statistics:
        Improved parsing of the docker system df command.
        Added handling for empty values: if Docker has not yet calculated the image sizes, the script now correctly displays 0B instead of an empty string or an error.

**SLDM v1.2.2 (Async Edition)** is a massive leap forward. It transforms a simple bash script into a professional monitoring dashboard.
It uses a **Smart Event Loop** and **Background Processing** to calculate heavy statistics (like RAM usage) without freezing the interface.

### 🌟 Key Features

#### 🚀 Performance & Architecture (New in v1.2)
- **Async Core:** Memory calculations run in the background. The UI never freezes.
- **Smart Event Loop:** Auto-refreshes data when calculations are done.
- **Zero-Lag Navigation:** Switch pages and menus instantly, even with 100+ containers.

#### 📊 Real-Time Monitoring
- **Host CPU Usage:** Real-time processor load percentage.
- **RAM Usage:** Shows `Docker Memory / Total Host Memory`.
- **Disk Stats:** Accurate image size calculation using `docker system df`.

#### 🖼️ & 🐳 Advanced Management
- **Live Search/Filter:** Press `/` to filter images or containers by name instantly.
- **Docker Compose Support:** Containers from Compose are marked with `[C]`.
- **Wide View:** Optimized table layout for long container names.
- **Actions:** Stop, Start, Kill, Remove, Pull, Push (with secure login).
- **Quick Navigation:** Jump between Images/Containers with `9`.

#### 🧹 Extended Cleanup
- **Images:** Remove unused, dangling, or ALL images.
- **Containers:** Stop & Delete in one go.
- **New:** Prune **Volumes** and **Networks**.
- **New:** Clear Build Cache.
🚀 Advantages & Performance

✨ Minimal Resource Usage

    Pure Bash implementation - no additional dependencies
    Low memory footprint (<10MB during operation)
    Efficient process management without background services
    Fast execution with optimized Docker API calls
    No GUI overhead - pure terminal interface

📱 Mobile & Mini-Computer Optimized

    ✅ Raspberry Pi (all models)
    ✅ Orange Pi (all variants)
    ✅ Rock64 and other SBCs
    ✅ Atomic Pi and mini x86 systems
    ✅ Low-power ARM devices
    ✅ Embedded Linux systems

### 🛠️ Installation
```bash
curl -sSL https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm.sh -o ~/bin/sldm && chmod +x ~/bin/sldm
```
#### Method 1: Direct Download
```bash
# Download
wget https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm

# Make executable
chmod +x sldm

# Run
./sldm
```

#### Method 2: Git Clone
```bash
git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
cd Simple-Linux-Docker-Manager
chmod +x sldm
./sldm
```

### 🎮 Hotkeys

| Key | Action |
|:---:|---|
| `1-7` | Select menu item |
| `/` | **Search / Filter** list |
| `r` | **Force Refresh** & Recalculate RAM |
| `n/p` | Next / Previous Page |
| `9` | Switch context (Images ↔ Containers) |
| `h` | Show Help Modal |
| `0` | Back / Exit |

---

## 🇷🇺 Русская Версия / Russian Version
SLDM v1.2.3 Final Release — лучший bash-докер-менеджер 2025 года
### 📖 Обзор
# Simple Linux Docker Manager (SLDM) 🐳

**Самый быстрый, красивый и удобный Docker-менеджер на чистом Bash в 2025 году**

Русская TUI-утилита для управления Docker без lazydocker, ctops и прочего тяжёлого мусора.

https://github.com/rjohny55/Simple-Linux-Docker-Manager/assets/23423432/демо-гифка.gif

### Особенности
- Асинхронный подсчёт RAM (список появляется мгновенно, цифры — через 1–2 сек)
- Кэш в `/dev/shm` — не убивает SSD
- Поиск, пагинация `n/p`, переключение `9`, справка `h`
- Поддержка docker-compose (`[C]` метка)
- CPU/RAM хоста в реальном времени
- Полная очистка: тома, сети, buildx, system prune
- Работает без sudo, без зависимостей
- Одна команда установки

### Установка (1 строка)
```bash
curl -sSL https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm.sh -o ~/bin/sldm && chmod +x ~/bin/sldm
```
**SLDM v1.2.3** — это полноценный TUI-инструмент для управления Docker. Главное отличие от обычных скриптов — **асинхронное ядро**. Скрипт не "виснет" при подсчете памяти контейнеров, а выполняет это в фоне, обновляя интерфейс на лету.

Идеальная замена `lazydocker` для слабых машин или серверов, где важна каждая мегабайт памяти.

### 🌟 Основные возможности
(Новое в v1.2.3)
Оптимизация и Железо (System & Hardware)

    Перенос кэша в RAM (/dev/shm):
        Файлы кэша и блокировок (.cache, .lock) теперь создаются в /dev/shm (Shared Memory).
        Зачем: Это исключает постоянную запись на SSD/SD-карту при каждом обновлении статистики (раз в секунду), что критически важно для долговечности флеш-памяти на Raspberry Pi и других микрокомпьютерах.
        Скорость: Чтение/запись в оперативную память происходит мгновенно.

    Универсальная совместимость:
        Добавлена проверка наличия /dev/shm.
        Если скрипт запущен на системе без Shared Memory (например, macOS или специфичные контейнеры), он автоматически откатывается на использование /tmp.

🐛 Исправления ошибок (Bug Fixes)

    Статистика диска:
        Улучшен парсинг команды docker system df.
        Добавлена защита от пустых значений: если Docker еще не подсчитал размер образов, скрипт корректно выведет 0B вместо пустоты или ошибки.

#### 🚀 Производительность (Новое в v1.2)
- **Асинхронное ядро:** Подсчет `docker stats` вынесен в фон. Интерфейс летает.
- **Умное автообновление:** Экран обновляется сам, как только готовы данные о памяти.
- **Отзывчивость:** Мгновенное переключение страниц даже при 500+ контейнерах.

#### 📊 Мониторинг в реальном времени
- **CPU Хоста:** Показывает общую загрузку процессора (%).
- **RAM Хоста:** Показывает `Память Контейнеров / Всю память сервера`.
- **Диск:** Точный подсчет места, занятого образами (без дублей слоев).

#### 🖼️ и 🐳 Управление ресурсами
- **Живой Поиск:** Нажмите `/` чтобы мгновенно отфильтровать список.
- **Docker Compose:** Контейнеры из Compose помечены меткой `[C]`.
- **Широкий вид:** Таблица адаптируется под длинные имена.
- **Действия:** Стоп, Старт, Kill, Удаление, Pull, Push (безопасный ввод пароля).
- **Быстрый переход:** Кнопка `9` переключает между Образами и Контейнерами.

#### 🧹 Расширенная очистка
- **Образы:** Удаление неиспользуемых, dangling или ВСЕХ сразу.
- **Контейнеры:** Остановка и удаление одной командой.
- **Новое:** Очистка **Томов (Volumes)** и **Сетей (Networks)**.
- **Новое:** Очистка кэша сборки (Buildx).

### 🛠️ Установка
```bash
curl -sSL https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm.sh -o ~/bin/sldm && chmod +x ~/bin/sldm
```
#### Способ 1: Прямая загрузка
```bash
# Скачать
wget https://raw.githubusercontent.com/rjohny55/Simple-Linux-Docker-Manager/main/sldm

# Сделать исполняемым
chmod +x sldm

# Запустить
./sldm
```

#### Способ 2: Git Clone
```bash
git clone https://github.com/rjohny55/Simple-Linux-Docker-Manager.git
cd Simple-Linux-Docker-Manager
chmod +x sldm
./sldm
```

### 🎮 Горячие клавиши

| Клавиша | Действие |
|:---:|---|
| `1-7` | Выбор пункта меню |
| `/` | **Поиск / Фильтр** списка |
| `r` | **Обновить** и пересчитать память |
| `n/p` | След. / Пред. страница |
| `9` | Переключение (Образы ↔ Контейнеры) |
| `h` | Справка |
| `0` | Назад / Выход |

### 🔧 Требования / Requirements

- **OS:** Linux (Ubuntu, Debian, CentOS, Alpine, Arch, etc.) OR macOS.
- **Shell:** Bash 4.0+.
- **Docker:** Installed and running.
- **Root/Sudo:** Optional (required only if your user is not in `docker` group).
- 
#### System Compatibility

| Device Type | RAM Usage | Storage | Performance |
|-------------|-----------|---------|-------------|
| Raspberry Pi 4 | <15MB | MicroSD | Excellent |
| Orange Pi Zero | <10MB | MicroSD | Great |
| Rock64 4GB | <12MB | eMMC | Excellent |
| Atomic Pi | <20MB | eMMC | Excellent |
---

## 📄 License

Apache 2.0

## ⚠️ Disclaimer

This tool performs destructive actions (removing containers, images, volumes). Always check what you are deleting.
Этот инструмент выполняет деструктивные действия. Всегда проверяйте, что именно вы удаляете.
```
