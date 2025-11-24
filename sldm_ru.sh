#!/bin/bash

# ==========================================
# Simple Linux Docker Manager v1.0.5
# (High Performance & Security Edition)
# ==========================================

# Настройки оболочки
set -o pipefail
# Мы не используем set -e, так как это интерактивное меню, 
# и ошибка (например, grep ничего не нашел) не должна выкидывать из скрипта.

# Глобальные константы
readonly PAGE_SIZE=50

# Глобальные переменные для пагинации
declare -g IMAGES_CURRENT_PAGE=1
declare -g IMAGES_TOTAL_PAGES=1
declare -g IMAGES_TOTAL_ITEMS=0
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g CONTAINERS_TOTAL_PAGES=1
declare -g CONTAINERS_TOTAL_ITEMS=0

# ГЛОБАЛЬНЫЕ МАССИВЫ ДАННЫХ (Исправление CRITICAL BUG)
declare -ga image_ids=()
declare -ga image_names=()
declare -ga image_tags=()
declare -ga container_ids=()
declare -ga container_names=()
declare -ga container_status=()

# Цвета для меню
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# --- БЛОК БЕЗОПАСНОСТИ И ПРОВЕРОК ---

# Функция очистки при выходе
cleanup_exit() {
    stty echo 2>/dev/null
    # Очистка чувствительных переменных на всякий случай
    unset docker_password
    echo -e "\n${CYAN}👋 Работа скрипта завершена.${NC}"
}

trap cleanup_exit EXIT SIGINT SIGTERM

check_dependencies() {
    local missing=0
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Ошибка: Docker не найден.${NC}"
        missing=1
    fi

    if [ $missing -eq 0 ] && ! docker ps &> /dev/null; then
        echo -e "${RED}❌ Ошибка: Нет прав на выполнение команд Docker.${NC}"
        echo -e "${YELLOW}💡 Совет: Запустите через sudo или добавьте юзера в группу docker.${NC}"
        missing=1
    fi
    
    if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
        echo -e "${RED}❌ Ошибка: Требуется Bash 4.0+.${NC}"
        missing=1
    fi

    if [ $missing -eq 1 ]; then exit 1; fi
}

# --- УТИЛИТЫ ---

safe_read() {
    local secret=0
    local timeout=0
    local timeout_value=0
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--secret) secret=1; shift ;;
            -t|--timeout) timeout=1; timeout_value=$2; shift 2 ;;
            *) break ;;
        esac
    done
    
    local prompt="$1"
    local var_name="$2"
    local max_chars="${3:-100}"
    
    # Если переменная не передана, используем dummy
    if [ -z "$var_name" ]; then local dummy; var_name="dummy"; fi
    
    while true; do
        echo -ne "$prompt"
        if [ $secret -eq 1 ]; then
            stty -echo
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
            stty echo
            echo ""
        elif [ $timeout -eq 1 ]; then
            if IFS= read -r -t $timeout_value -n "$max_chars" "$var_name"; then local ret=0; else local ret=1; fi
        else
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
        fi
        
        if [ $ret -ne 0 ]; then return 1; fi
        
        # Очистка буфера ввода
        if [ -n "${!var_name}" ]; then
            local extra_chars
            IFS= read -r -t 0.1 -n 1000 extra_chars || true
        fi
        
        if [[ "${!var_name}" =~ ^[[:cntrl:]] ]]; then
            echo -e "${RED}❌ Недопустимый ввод.${NC}"
            continue
        fi
        break
    done
    return 0
}

size_to_bytes() {
    local size=$1
    if [ -z "$size" ]; then echo "0"; return; fi
    # Оптимизированный парсинг без лишних subshells
    local clean_size=$(echo "$size" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local multiplier=1
    local number=0

    if [[ $clean_size == *"gib" ]]; then number=$(echo "$clean_size" | sed 's/gib//'); multiplier=1073741824
    elif [[ $clean_size == *"gb" ]]; then number=$(echo "$clean_size" | sed 's/gb//'); multiplier=1000000000
    elif [[ $clean_size == *"mib" ]]; then number=$(echo "$clean_size" | sed 's/mib//'); multiplier=1048576
    elif [[ $clean_size == *"mb" ]]; then number=$(echo "$clean_size" | sed 's/mb//'); multiplier=1000000
    elif [[ $clean_size == *"kib" ]]; then number=$(echo "$clean_size" | sed 's/kib//'); multiplier=1024
    elif [[ $clean_size == *"kb" ]]; then number=$(echo "$clean_size" | sed 's/kb//'); multiplier=1000
    elif [[ $clean_size == *"b" ]]; then number=$(echo "$clean_size" | sed 's/b//'); multiplier=1
    fi
    
    # Используем awk для арифметики с плавающей точкой, если число дробное
    awk -v n="$number" -v m="$multiplier" 'BEGIN {printf "%.0f", n * m}' 2>/dev/null || echo "0"
}

format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then echo "0B"; return; fi
    if command -v bc >/dev/null 2>&1; then
        if [ "$bytes" -ge 1099511627776 ]; then echo "$(echo "scale=2; $bytes/1099511627776" | bc)TiB"
        elif [ "$bytes" -ge 1073741824 ]; then echo "$(echo "scale=2; $bytes/1073741824" | bc)GiB"
        elif [ "$bytes" -ge 1048576 ]; then echo "$(echo "scale=2; $bytes/1048576" | bc)MiB"
        elif [ "$bytes" -ge 1024 ]; then echo "$(echo "scale=2; $bytes/1024" | bc)KiB"
        else echo "${bytes}B"; fi
    else
        # Fallback на bash arithmetic (целочисленное)
        if [ "$bytes" -ge 1099511627776 ]; then echo "$((bytes / 1099511627776))TiB"
        elif [ "$bytes" -ge 1073741824 ]; then echo "$((bytes / 1073741824))GiB"
        elif [ "$bytes" -ge 1048576 ]; then echo "$((bytes / 1048576))MiB"
        elif [ "$bytes" -ge 1024 ]; then echo "$((bytes / 1024))KiB"
        else echo "${bytes}B"; fi
    fi
}

get_memory_stats() {
    local total_ram=0 available_ram=0 used_ram=0
    if [ -f /proc/meminfo ]; then
        total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        available_ram=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        total_ram=$((total_ram * 1024))
        available_ram=$((available_ram * 1024))
        used_ram=$((total_ram - available_ram))
    else
        local memory_info=$(free -b 2>/dev/null | grep Mem:)
        if [ -n "$memory_info" ]; then
            total_ram=$(echo "$memory_info" | awk '{print $2}')
            used_ram=$(echo "$memory_info" | awk '{print $3}')
            available_ram=$(echo "$memory_info" | awk '{print $7}')
        fi
    fi
    echo "$total_ram $available_ram $used_ram"
}

safe_calc() {
    local expression=$1
    if command -v bc >/dev/null 2>&1; then echo "$expression" | bc 2>/dev/null || echo "0"
    else
        local result=$(echo "$expression" | sed 's/\.//g' | awk '{print int($1)}')
        echo "${result:-0}"
    fi
}

check_confirmation() {
    local confirm="$1"
    if [[ "$confirm" =~ ^[yYдД]$ ]]; then return 0; else return 1; fi
}

check_cancel() {
    local input="$1"
    if [[ "$input" =~ ^[cCсС]$ ]]; then return 0; else return 1; fi
}

# --- ФУНКЦИИ СТАТИСТИКИ ---

get_total_containers_memory() {
    local total_memory_bytes=0
    if command -v docker >/dev/null 2>&1; then
        # Используем пакетную обработку
        while IFS= read -r mem_usage; do
            if [ -n "$mem_usage" ] && [ "$mem_usage" != "MEM USAGE" ]; then
                local mem_value=$(echo "$mem_usage" | cut -d'/' -f1 | tr -d ' ')
                local mem_bytes=$(size_to_bytes "$mem_value")
                total_memory_bytes=$((total_memory_bytes + mem_bytes))
            fi
        done < <(docker stats --no-stream --format "table {{.MemUsage}}" $(docker ps -q) 2>/dev/null | tail -n +2)
    fi
    echo "$total_memory_bytes"
}

show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📦 ОБРАЗЫ DOCKER                        📊 СТАТИСТИКА СИСТЕМЫ                    ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    local disk_info=$(df "$docker_root" | tail -1 2>/dev/null)
    
    if [ -n "$disk_info" ]; then
        local disk_total=$(echo "$disk_info" | awk '{print $2}')
        local disk_used=$(echo "$disk_info" | awk '{print $3}')
        local disk_available=$(echo "$disk_info" | awk '{print $4}')
        local disk_total_bytes=$((disk_total * 1024))
        local disk_used_bytes=$((disk_used * 1024))
        local disk_available_bytes=$((disk_available * 1024))
        
        # Получаем размер образов более надежным способом
        local total_images_bytes=0
        while IFS=' ' read -r size unit; do
             # Простой хак для суммирования, более точно через docker system df
             :
        done < <(docker images --format "{{.Size}}" 2>/dev/null)
        
        # Лучший способ для общего размера
        local sys_df=$(docker system df --format "{{.Size}}" | sed -n '1p') # Images line
        local total_images_size=${sys_df:-"0B"}
        local total_images_bytes_val=$(size_to_bytes "$total_images_size")

        local total_images_count=$(docker images -q 2>/dev/null | wc -l)
        
        local images_percent=0
        if [ "$disk_total_bytes" -gt 0 ] && [ "$total_images_bytes_val" -gt 0 ]; then
            images_percent=$(safe_calc "scale=1; $total_images_bytes_val * 100 / $disk_total_bytes")
        fi
        
        echo -e "${CYAN}║ ${GREEN}• Образы:${NC} $total_images_size ${CYAN}• Диск:${NC} $(format_bytes $disk_used_bytes)/$(format_bytes $disk_total_bytes) ${CYAN}• Свободно:${NC} $(format_bytes $disk_available_bytes) "
        echo -e "${CYAN}║ ${GREEN}• Занято образами:${NC} ${images_percent}% ${CYAN}• Всего образов:${NC} $total_images_count "
    else
        echo -e "${CYAN}║ ${RED}Не удалось получить информацию о диске ($docker_root)${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🐳 КОНТЕЙНЕРЫ DOCKER                     📊 СТАТИСТИКА СИСТЕМЫ                   ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    local running_containers=$(docker ps -q 2>/dev/null | wc -l)
    local stopped_containers=$((total_containers - running_containers))
    local total_memory_bytes=$(get_total_containers_memory)
    
    read -r total_ram available_ram used_ram <<< "$(get_memory_stats)"
    
    local containers_ram_percent=0
    if [ "$total_ram" -gt 0 ] && [ "$total_memory_bytes" -gt 0 ]; then
        containers_ram_percent=$(safe_calc "scale=1; $total_memory_bytes * 100 / $total_ram")
    fi
    
    echo -e "${CYAN}║ ${GREEN}• Контейнеры:${NC} $(format_bytes $total_memory_bytes) ${CYAN}• RAM:${NC} ${containers_ram_percent}% ${CYAN} • Свободно:${NC} $(format_bytes $available_ram) ${CYAN}• Всего RAM:${NC} $(format_bytes $total_ram)"
    echo -e "${CYAN}║ ${GREEN}• Запущено:${NC} $running_containers ${CYAN}• Остановлено:${NC} $stopped_containers ${CYAN} • Всего:${NC} $total_containers"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           Simple Linux Docker Manager v1.0.5     ║"
    echo "║          HIGH PERFORMANCE & SECURE EDITION       ║"
    echo "║          https://github.com/rjohny55/            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    local dummy
    safe_read "" dummy
}

# --- СПИСКИ (CORE) ---

show_images() {
    local page=${1:-1}
    local start_index=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end_index=$(( page * PAGE_SIZE ))
    
    echo -e "${YELLOW}📦 Список Docker образов (Страница $page):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Очищаем глобальные массивы перед заполнением
    image_ids=()
    image_names=()
    image_tags=()
    
    local counter=1
    local display_counter=1 # Начинаем с 1 для удобства пользователя
    # Индекс массива для хранения данных (0-based)
    local array_index=1 
    
    local all_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    local total_images=$(echo "$all_images" | wc -l)
    local total_pages=$(( (total_images + PAGE_SIZE - 1) / PAGE_SIZE ))

    if [ -z "$all_images" ]; then
        echo -e "${RED}📭 Нет Docker образов.${NC}"
        IMAGES_TOTAL_PAGES=1
        return 1
    fi

    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                # Сохраняем в глобальный массив по индексу display_counter
                image_ids[$display_counter]=$id
                image_names[$display_counter]="$repository"
                image_tags[$display_counter]="$tag"
                
                short_created=$(echo "$created" | cut -d' ' -f1)
                printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-25s${NC} ${RED}%-10s${NC} ${ORANGE}%s${NC}\n" \
                    "$display_counter" "${repository:0:30}" "${tag:0:25}" "$size" "$short_created"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_images"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Страница ${YELLOW}$page${CYAN} из ${YELLOW}$total_pages${CYAN}. Всего образов: ${YELLOW}$total_images${NC}"
    fi
    
    IMAGES_CURRENT_PAGE=$page
    IMAGES_TOTAL_PAGES=$total_pages
    IMAGES_TOTAL_ITEMS=$total_images
    
    return 0
}

show_containers() {
    local page=${1:-1}
    local start_index=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end_index=$(( page * PAGE_SIZE ))
    
    echo -e "${YELLOW}🐳 Список Docker контейнеров (Страница $page):${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Очищаем массивы
    container_ids=()
    container_names=()
    container_status=()
    
    # 1. Batch IP Loading
    declare -A ip_map
    if [ -n "$(docker ps -aq)" ]; then
        while IFS='|' read -r full_id ip; do
            local short_id="${full_id:0:12}"
            ip_map[$short_id]="$ip"
        done < <(docker inspect --format '{{.ID}}|{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) 2>/dev/null)
    fi

    # 2. Batch Memory Loading
    declare -A mem_map
    if [ -n "$(docker ps -q)" ]; then
        while IFS=':' read -r id mem; do
            local mem_clean=$(echo "$mem" | cut -d'/' -f1 | tr -d ' ')
            mem_map[$id]="$mem_clean"
        done < <(docker stats --no-stream --format "{{.ID}}:{{.MemUsage}}" $(docker ps -q) 2>/dev/null)
    fi
    
    local counter=1
    local display_counter=1 # Начинаем с 1
    
    local all_containers=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}" | tail -n +2)
    local total_containers=$(echo "$all_containers" | wc -l)
    local total_pages=$(( (total_containers + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    if [ -z "$all_containers" ]; then
        echo -e "${RED}📭 Нет Docker контейнеров.${NC}"
        CONTAINERS_TOTAL_PAGES=1
        return 1
    fi
    
    printf "${GREEN}%-3s${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${BLUE}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
        "No" "CONTAINER ID" "NAMES" "STATUS" "IP" "MEMORY"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    while IFS='|' read -r id image status names; do
        if [ -n "$id" ] && [ "$id" != "CONTAINER ID" ]; then
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                container_ids[$display_counter]=$id
                container_names[$display_counter]="$names"
                container_status[$display_counter]="$status"
                
                local ip="${ip_map[$id]}"
                [ -z "$ip" ] && ip="-"
                
                local memory="${mem_map[$id]}"
                [ -z "$memory" ] && memory="-"
                
                local status_color=$GREEN
                if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"Dead"* ]]; then
                    status_color=$RED
                elif [[ "$status" == *"Up"* ]]; then
                    status_color=$GREEN
                else
                    status_color=$YELLOW
                fi
                
                printf "${GREEN}%-3d${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${status_color}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
                    "$display_counter" "${id}" "${names:0:20}" "${status:0:19}" "$ip" "$memory"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_containers"
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Страница ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Всего контейнеров: ${YELLOW}$total_containers${NC}"
    fi
    
    CONTAINERS_CURRENT_PAGE=$page
    CONTAINERS_TOTAL_PAGES=$total_pages
    CONTAINERS_TOTAL_ITEMS=$total_containers
    
    return 0
}

# --- ОПЕРАЦИИ ---

update_selected_image() {
    echo -e "${YELLOW}🔄 Обновление образа${NC}"
    echo -e "${CYAN}Введите номер:${NC}"
    
    if ! safe_read "> " input 10; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then echo -e "${RED}❌ Неверный ввод.${NC}"; return 1; fi
    if [ -z "${image_ids[$input]}" ]; then echo -e "${RED}❌ Неверный номер ($input).${NC}"; return 1; fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    if [[ "$image_name" == *"<none>"* ]] || [[ "$image_tag" == *"<none>"* ]]; then
        echo -e "${RED}❌ Нельзя обновить образ без репозитория.${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}🔄 Pulling: ${CYAN}$full_image_name${NC}"
    if docker pull "$full_image_name"; then
        echo -e "${GREEN}✅ Успешно${NC}"
    else
        echo -e "${RED}❌ Ошибка${NC}"
    fi
}

push_selected_image() {
    echo -e "${YELLOW}📤 Пуш образа${NC}"
    echo -e "${CYAN}Введите номер:${NC}"
    
    if ! safe_read "> " input 10; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    if [ -z "${image_ids[$input]}" ]; then echo -e "${RED}❌ Неверный номер.${NC}"; return 1; fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    echo -e "\n${YELLOW}📤 Пуш: ${CYAN}$full_image_name${NC}"
    echo -e "${YELLOW}🔐 Docker Login:${NC}"
    echo -e "${CYAN}Логин:${NC}"
    local docker_username
    if ! safe_read "> " docker_username 50; then return 1; fi
    
    echo -e "${CYAN}Пароль:${NC}"
    local docker_password
    if ! safe_read -s "> " docker_password 200; then return 1; fi
    
    echo -e "\n${YELLOW}🔐 Авторизация...${NC}"
    # Используем переменную и сразу её сбрасываем
    echo "$docker_password" | docker login --username "$docker_username" --password-stdin
    local login_status=$?
    unset docker_password # ВАЖНО: Сброс пароля
    
    if [ $login_status -eq 0 ]; then
        echo -e "${GREEN}✅ OK${NC}"
        docker push "$full_image_name" && echo -e "${GREEN}✅ Запушено${NC}" || echo -e "${RED}❌ Ошибка пуша${NC}"
        docker logout
    else
        echo -e "${RED}❌ Ошибка авторизации${NC}"
    fi
}

# --- МЕНЮ ---

show_images_menu() {
    echo -e "${CYAN}🛠️  Операции с образами:${NC}"
    echo -e "${GREEN}1. 🗑️  Удалить выбранные${NC}    ${PURPLE}5. 🛠️  Очистить кеш сборок${NC}"
    echo -e "${YELLOW}2. 🧹  Удалить неиспользуемые${NC} ${BLUE}6. 🔄  Обновить список${NC}"
    echo -e "${RED}3. 💥  Удалить ВСЕ образы${NC}     ${CYAN}7. 🔄  Pull образа${NC}"
    echo -e "${ORANGE}4. 🔍  Удалить <none>${NC}         ${GREEN}8. 📤  Push образа${NC}"
    
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        echo -e "${CYAN}───────────────────────────────────────${NC}"
        [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ] && echo -e "${CYAN}9. 📄  Следующая страница${NC}"
        [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ] && echo -e "${CYAN}10. 📄 Предыдущая страница${NC}"
    fi
    echo -e "${CYAN}───────────────────────────────────────${NC}"
    echo -e "${GREEN}11. 🐳 К контейнерам${NC}"
    echo -e "${GREEN}0. 🏠  В меню${NC}"
    safe_read "${CYAN}🎯 Ваш выбор: ${NC}" choice 2
}

show_containers_menu() {
    echo -e "${CYAN}🛠️  Операции с контейнерами:${NC}"
    echo -e "${GREEN}1. ⏹️   Стоп выбранных${NC}       ${BLUE}5. 🔄   Обновить список${NC}"
    echo -e "${YELLOW}2. 🗑️   Удалить выбранные${NC}"
    echo -e "${RED}3. 💀   Стоп + Удалить${NC}"
    echo -e "${GREEN}4. ▶️   Старт выбранных${NC}"
    
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        echo -e "${CYAN}───────────────────────────────────────${NC}"
        [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ] && echo -e "${CYAN}6. 📄  Следующая страница${NC}"
        [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ] && echo -e "${CYAN}7. 📄  Предыдущая страница${NC}"
    fi
    echo -e "${CYAN}───────────────────────────────────────${NC}"
    echo -e "${GREEN}8. 📦   К образам${NC}"
    echo -e "${GREEN}0. 🏠   В меню${NC}"
    safe_read "${CYAN}🎯 Ваш выбор: ${NC}" choice 1
}

# --- МАССОВЫЕ ДЕЙСТВИЯ ---

delete_selected_images() {
    echo -e "${YELLOW}🗑️ Номера (через пробел):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    [ -z "$input" ] && return 1
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}Удаляем:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${image_names[$num]}" ] && echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
    done
    
    safe_read "Уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        for num in "${selected_numbers[@]}"; do
            [ -n "${image_ids[$num]}" ] && docker rmi -f "${image_ids[$num]}" 2>/dev/null
        done
        echo -e "${GREEN}✅ Готово${NC}"
        return 0
    fi
    return 1
}

stop_selected_containers() {
    echo -e "${YELLOW}⏹️ Номера (через пробел):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}Стоп:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${container_names[$num]}" ] && echo -e "  ${RED}■${NC} ${container_names[$num]}"
    done
    
    safe_read "Уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        for num in "${selected_numbers[@]}"; do
            [ -n "${container_ids[$num]}" ] && docker stop "${container_ids[$num]}" 2>/dev/null
        done
        echo -e "${GREEN}✅ Готово${NC}"
        return 0
    fi
    return 1
}

delete_selected_containers() {
    echo -e "${YELLOW}🗑️ Номера (через пробел):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    
    read -a selected_numbers <<< "$input"
    safe_read "Уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        for num in "${selected_numbers[@]}"; do
            [ -n "${container_ids[$num]}" ] && docker rm "${container_ids[$num]}" 2>/dev/null
        done
        echo -e "${GREEN}✅ Готово${NC}"
        return 0
    fi
    return 1
}

stop_and_delete_containers() {
    echo -e "${YELLOW}💀 Номера (через пробел):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then return 1; fi
    
    read -a selected_numbers <<< "$input"
    safe_read "Уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                docker stop "${container_ids[$num]}" 2>/dev/null
                docker rm "${container_ids[$num]}" 2>/dev/null
            fi
        done
        echo -e "${GREEN}✅ Готово${NC}"
        return 0
    fi
    return 1
}

start_selected_containers() {
    echo -e "${YELLOW}▶️ Номера (через пробел):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    
    read -a selected_numbers <<< "$input"
    safe_read "Уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        for num in "${selected_numbers[@]}"; do
            [ -n "${container_ids[$num]}" ] && docker start "${container_ids[$num]}" 2>/dev/null
        done
        echo -e "${GREEN}✅ Готово${NC}"
        return 0
    fi
    return 1
}

# --- ОЧИСТКА ---

delete_unused_images() {
    echo -e "${YELLOW}🧹 Удаление dangling образов...${NC}"
    safe_read "Вы уверены? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        docker image prune -a -f
        echo -e "${GREEN}✅ Готово${NC}"
    fi
}

delete_all_images() {
    echo -e "${RED}🚨 ОПАСНО: Удаление ВСЕХ образов!${NC}"
    safe_read "Введите 'DELETE': " confirm 10
    if [ "$confirm" = "DELETE" ]; then
        # Исправлено: если список пуст, xargs не запустится
        docker images -q | xargs -r docker rmi -f 2>/dev/null
        echo -e "${GREEN}✅ Готово${NC}"
    fi
}

delete_none_images() {
    echo -e "${YELLOW}🔍 Поиск <none>...${NC}"
    docker image prune -f
}

delete_build_cache() {
    docker buildx prune -f
}

cleanup_docker_system() {
    print_header
    echo -e "${YELLOW}🧹 Очистка:${NC}"
    echo -e "${GREEN}1. 🗑️   Неиспользуемые (prune -a)${NC}"
    echo -e "${ORANGE}2. 🔍   Dangling (prune)${NC}"
    echo -e "${PURPLE}3. 🛠️   Build Cache${NC}"
    echo -e "${RED}4. 💥   System Prune -a (ALL)${NC}"
    echo -e "${GREEN}0. 🏠   Назад${NC}"
    safe_read "${CYAN}🎯: ${NC}" choice 1
    
    case $choice in
        1) delete_unused_images; press_enter_to_continue ;;
        2) delete_none_images; press_enter_to_continue ;;
        3) delete_build_cache; press_enter_to_continue ;;
        4) docker system prune -a -f; press_enter_to_continue ;;
        0) return ;;
    esac
}

images_submenu() {
    local current_page=${1:-1}
    while true; do
        print_header; show_disk_stats; show_images "$current_page"; show_images_menu
        case $choice in
            1) delete_selected_images; press_enter_to_continue ;;
            2) delete_unused_images; press_enter_to_continue ;;
            3) delete_all_images; press_enter_to_continue ;;
            4) delete_none_images; press_enter_to_continue ;;
            5) delete_build_cache; press_enter_to_continue ;;
            6) current_page=1 ;;
            7) update_selected_image; press_enter_to_continue ;;
            8) push_selected_image; press_enter_to_continue ;;
            9) [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ] && current_page=$((IMAGES_CURRENT_PAGE + 1)) ;;
            10) [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ] && current_page=$((IMAGES_CURRENT_PAGE - 1)) ;;
            11) return 1 ;;
            0) return 0 ;;
        esac
    done
}

containers_submenu() {
    local current_page=${1:-1}
    while true; do
        print_header; show_containers_stats; show_containers "$current_page"; show_containers_menu
        case $choice in
            1) stop_selected_containers; press_enter_to_continue ;;
            2) delete_selected_containers; press_enter_to_continue ;;
            3) stop_and_delete_containers; press_enter_to_continue ;;
            4) start_selected_containers; press_enter_to_continue ;;
            5) current_page=1 ;;
            6) [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ] && current_page=$((CONTAINERS_CURRENT_PAGE + 1)) ;;
            7) [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ] && current_page=$((CONTAINERS_CURRENT_PAGE - 1)) ;;
            8) return 1 ;;
            0) return 0 ;;
        esac
    done
}

show_main_menu() {
    print_header
    echo -e "${CYAN}🏠 Главное меню:${NC}"
    echo -e "${GREEN}1. 📦  Образы${NC}"
    echo -e "${GREEN}2. 🐳  Контейнеры${NC}"
    echo -e "${YELLOW}3. 🧹  Очистка${NC}"
    echo -e "${RED}0. 🚪  Выход${NC}"
    safe_read "${CYAN}🎯: ${NC}" choice 1
}

# ==========================================
# ЗАПУСК
# ==========================================
check_dependencies
while true; do
    show_main_menu
    case $choice in
        1) images_submenu && continue || containers_submenu ;;
        2) containers_submenu && continue || images_submenu ;;
        3) cleanup_docker_system ;;
        0) cleanup_exit; exit 0 ;;
    esac
done
