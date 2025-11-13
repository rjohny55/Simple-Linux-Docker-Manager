#!/bin/bash

# Глобальные переменные для пагинации
declare -g IMAGES_CURRENT_PAGE=1
declare -g IMAGES_TOTAL_PAGES=1
declare -g IMAGES_TOTAL_ITEMS=0
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g CONTAINERS_TOTAL_PAGES=1
declare -g CONTAINERS_TOTAL_ITEMS=0

# Цвета для меню
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Функция для безопасного чтения ввода с поддержкой скрытого ввода
safe_read() {
    local secret=0
    local timeout=0
    local timeout_value=0
    
    # Проверяем флаги
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--secret)
                secret=1
                shift
                ;;
            -t|--timeout)
                timeout=1
                timeout_value=$2
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    local prompt="$1"
    local var_name="$2"
    local max_chars="${3:-100}"
    
    while true; do
        echo -ne "$prompt"
        if [ $secret -eq 1 ]; then
            # Скрытый ввод для паролей
            stty -echo
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
            stty echo
            echo ""  # Добавляем новую строку после скрытого ввода
        elif [ $timeout -eq 1 ]; then
            # Ввод с таймаутом
            if IFS= read -r -t $timeout_value -n "$max_chars" "$var_name"; then
                local ret=0
            else
                local ret=1
            fi
        else
            # Обычный ввод
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
        fi
        
        # Обработка Ctrl+C
        if [ $ret -ne 0 ]; then
            echo ""
            echo -e "${YELLOW}⚠️  Прервано пользователем${NC}"
            return 1
        fi
        
        # Очистка буфера ввода если есть лишние символы
        if [ -n "${!var_name}" ]; then
            local extra_chars
            IFS= read -r -t 0.1 -n 1000 extra_chars || true
        fi
        
        # Игнорирование escape-последовательностей от мыши
        if [[ "${!var_name}" =~ ^[[:cntrl:]] ]]; then
            echo -e "${RED}❌ Недопустимый ввод. Используйте только цифры и буквы.${NC}"
            continue
        fi
        
        break
    done
    return 0
}

# Функция для преобразования размера в байты
size_to_bytes() {
    local size=$1
    if [ -z "$size" ]; then
        echo "0"
        return
    fi
    
    # Удаляем пробелы и преобразуем в нижний регистр
    size=$(echo "$size" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    
    if [[ $size == *"gib" ]]; then
        local num=$(echo "$size" | sed 's/gib//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}')"
    elif [[ $size == *"gb" ]]; then
        local num=$(echo "$size" | sed 's/gb//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000 * 1000 * 1000}')"
    elif [[ $size == *"mib" ]]; then
        local num=$(echo "$size" | sed 's/mib//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024}')"
    elif [[ $size == *"mb" ]]; then
        local num=$(echo "$size" | sed 's/mb//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000 * 1000}')"
    elif [[ $size == *"kib" ]]; then
        local num=$(echo "$size" | sed 's/kib//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024}')"
    elif [[ $size == *"kb" ]]; then
        local num=$(echo "$size" | sed 's/kb//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000}')"
    elif [[ $size == *"b" ]]; then
        local num=$(echo "$size" | sed 's/b//')
        echo "$(echo "$num" | awk '{printf "%.0f", $1}')"
    else
        echo "0"
    fi
}

# Функция для форматирования байт в человеко-читаемый вид
format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then
        echo "0B"
        return
    fi
    
    if command -v bc >/dev/null 2>&1; then
        if [ "$bytes" -ge 1099511627776 ]; then
            echo "$(echo "scale=2; $bytes/1099511627776" | bc)TiB"
        elif [ "$bytes" -ge 1073741824 ]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc)GiB"
        elif [ "$bytes" -ge 1048576 ]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc)MiB"
        elif [ "$bytes" -ge 1024 ]; then
            echo "$(echo "scale=2; $bytes/1024" | bc)KiB"
        else
            echo "${bytes}B"
        fi
    else
        # Простой расчет если bc не установлен
        if [ "$bytes" -ge 1099511627776 ]; then
            echo "$((bytes / 1099511627776))TiB"
        elif [ "$bytes" -ge 1073741824 ]; then
            echo "$((bytes / 1073741824))GiB"
        elif [ "$bytes" -ge 1048576 ]; then
            echo "$((bytes / 1048576))MiB"
        elif [ "$bytes" -ge 1024 ]; then
            echo "$((bytes / 1024))KiB"
        else
            echo "${bytes}B"
        fi
    fi
}

# Функция для получения IP контейнера
get_container_ip() {
    local container_id=$1
    local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id" 2>/dev/null)
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        echo "-"
    else
        echo "$ip"
    fi
}

# Функция для получения использования памяти контейнера - УПРОЩЕННАЯ
get_container_memory() {
    local container_id=$1
    local status=$2
    
    # Для остановленных контейнеров не показываем использование памяти
    if [[ "$status" != *"Up"* ]]; then
        echo "-"
        return
    fi
    
    # Получаем использование памяти через docker stats
    local memory=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" 2>/dev/null | cut -d'/' -f1 | tr -d ' ')
    
    if [ -z "$memory" ] || [ "$memory" = "0B" ]; then
        echo "-"
    else
        echo "$memory"
    fi
}

# Функция для получения общей статистики памяти - УПРОЩЕННАЯ
get_memory_stats() {
    local total_ram=0
    local available_ram=0
    local used_ram=0
    
    # Получаем информацию о системе через /proc/meminfo
    if [ -f /proc/meminfo ]; then
        total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        available_ram=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        total_ram=$((total_ram * 1024))  # Convert kB to bytes
        available_ram=$((available_ram * 1024))  # Convert kB to bytes
        used_ram=$((total_ram - available_ram))
    else
        # Альтернативный метод через free
        local memory_info=$(free -b 2>/dev/null | grep Mem:)
        if [ -n "$memory_info" ]; then
            total_ram=$(echo "$memory_info" | awk '{print $2}')
            used_ram=$(echo "$memory_info" | awk '{print $3}')
            available_ram=$(echo "$memory_info" | awk '{print $7}')
        fi
    fi
    
    echo "$total_ram $available_ram $used_ram"
}

# Функция для получения общего использования памяти контейнерами - ИСПРАВЛЕННАЯ
get_total_containers_memory() {
    local total_memory_bytes=0
    
    # Получаем использование памяти для каждого запущенного контейнера
    if command -v docker >/dev/null 2>&1; then
        # Используем docker stats для получения использования памяти всех запущенных контейнеров
        while IFS= read -r mem_usage; do
            if [ -n "$mem_usage" ] && [ "$mem_usage" != "MEM USAGE" ]; then
                # Извлекаем только значение использования памяти (до '/')
                local mem_value=$(echo "$mem_usage" | cut -d'/' -f1 | tr -d ' ')
                local mem_bytes=$(size_to_bytes "$mem_value")
                total_memory_bytes=$((total_memory_bytes + mem_bytes))
            fi
        done < <(docker stats --no-stream --format "table {{.MemUsage}}" 2>/dev/null | tail -n +2)
    fi
    
    echo "$total_memory_bytes"
}

# Функция для безопасного вычисления с bc
safe_calc() {
    local expression=$1
    if command -v bc >/dev/null 2>&1; then
        echo "$expression" | bc 2>/dev/null || echo "0"
    else
        # Простая замена если bc не установлен
        local result=$(echo "$expression" | sed 's/\.//g' | awk '{print int($1)}')
        echo "${result:-0}"
    fi
}

# Функция для проверки подтверждения с поддержкой русской раскладки
check_confirmation() {
    local confirm="$1"
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || [ "$confirm" = "д" ] || [ "$confirm" = "Д" ]; then
        return 0
    else
        return 1
    fi
}

# Функция для проверки отмены с поддержкой русской раскладки
check_cancel() {
    local input="$1"
    if [[ "$input" == "c" || "$input" == "C" || "$input" == "с" || "$input" == "С" ]]; then
        return 0
    else
        return 1
    fi
}

# Функция для отображения статистики диска (для образов)
show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📦 ОБРАЗЫ DOCKER                        📊 СТАТИСТИКА СИСТЕМЫ                    ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Получаем статистику диска
    local disk_info=$(df / | tail -1 2>/dev/null)
    if [ -n "$disk_info" ]; then
        local disk_total=$(echo "$disk_info" | awk '{print $2}')
        local disk_used=$(echo "$disk_info" | awk '{print $3}')
        local disk_available=$(echo "$disk_info" | awk '{print $4}')
        local disk_total_bytes=$((disk_total * 1024))
        local disk_used_bytes=$((disk_used * 1024))
        local disk_available_bytes=$((disk_available * 1024))
        
        # Получаем общий размер образов
        local total_images_bytes=0
        while IFS='|' read -r id repository tag size created; do
            if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
                local img_bytes=$(size_to_bytes "$size")
                total_images_bytes=$((total_images_bytes + img_bytes))
            fi
        done < <(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
        
        local images_percent=0
        if [ "$disk_total_bytes" -gt 0 ]; then
            images_percent=$(safe_calc "scale=1; $total_images_bytes * 100 / $disk_total_bytes")
        fi
        
        echo -e "${CYAN}║ ${GREEN}• Образы:${NC} $(format_bytes $total_images_bytes) ${CYAN}• Диск:${NC} $(format_bytes $disk_used_bytes)/$(format_bytes $disk_total_bytes) ${CYAN}• Свободно:${NC} $(format_bytes $disk_available_bytes) "
        echo -e "${CYAN}║ ${GREEN}• Занято образами:${NC} ${images_percent}% ${CYAN}• Всего образов:${NC} $(docker images -q | wc -l) "
    else
        echo -e "${CYAN}║ ${RED}Не удалось получить информацию о диске${NC}"
    fi
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для отображения статистики контейнеров - ИСПРАВЛЕННЫЕ ГРАНИЦЫ
show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🐳 КОНТЕЙНЕРЫ DOCKER                     📊 СТАТИСТИКА СИСТЕМЫ                   ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Получаем общую информацию о контейнерах
    local total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    local running_containers=$(docker ps -q 2>/dev/null | wc -l)
    local stopped_containers=$((total_containers - running_containers))
    
    # Получаем общее использование памяти контейнерами
    local total_memory_bytes=$(get_total_containers_memory)
    
    # Получаем общую статистику памяти системы
    read -r total_ram available_ram used_ram <<< "$(get_memory_stats)"
    
    local containers_ram_percent=0
    if [ "$total_ram" -gt 0 ] && [ "$total_memory_bytes" -gt 0 ]; then
        containers_ram_percent=$(safe_calc "scale=1; $total_memory_bytes * 100 / $total_ram")
    fi
    
    # Форматируем размеры для отображения
    local total_ram_display=$(format_bytes $total_ram)
    local available_ram_display=$(format_bytes $available_ram)
    local containers_memory_display=$(format_bytes $total_memory_bytes)
    
    # Простой двухстрочный layout без закрывающих границ
    echo -e "${CYAN}║ ${GREEN}• Контейнеры:${NC} $containers_memory_display ${CYAN}• RAM:${NC} ${containers_ram_percent}% ${CYAN} • Свободно:${NC} $available_ram_display" • Всего RAM:${NC} $total_ram_display
    echo -e "${CYAN}║ ${GREEN}• Запущено:${NC} $running_containers" • Остановлено:${NC} $stopped_containers ${CYAN} • Всего:${NC} $total_containers  
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для отображения заголовка
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           Simple Linux Docker Manager            ║"
    echo "║         УПРАВЛЕНИЕ ОБРАЗАМИ И КОНТЕЙНЕРАМИ       ║"
    echo "║          https://github.com/rjohny55/            ║"
    echo "║           Simple-Linux-Docker-Manager            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Функция для ожидания нажатия Enter
press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Нажмите Enter для продолжения...${NC}"
    safe_read "" dummy_input
}

# Функция для показа всех образов с датой создания и пагинацией
show_images() {
    local page=${1:-1}
    local page_size=50
    local start_index=$(( (page - 1) * page_size + 1 ))
    local end_index=$(( page * page_size ))
    
    echo -e "${YELLOW}📦 Список Docker образов (Страница $page):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    local display_counter=0
    declare -g image_ids=()
    declare -g image_names=()
    declare -g image_tags=()
    
    # Получаем все образы
    local all_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    local total_images=$(echo "$all_images" | wc -l)
    local total_pages=$(( (total_images + page_size - 1) / page_size ))

    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            # Пагинация: показываем только элементы для текущей страницы
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                image_ids[$display_counter]=$id
                image_names[$display_counter]="$repository"
                image_tags[$display_counter]="$tag"
                
                # Форматируем дату (оставляем только дату, убираем время)
                short_created=$(echo "$created" | cut -d' ' -f1)
                printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-25s${NC} ${RED}%-10s${NC} ${ORANGE}%s${NC}\n" \
                    "$display_counter" "${repository:0:30}" "${tag:0:25}" "$size" "$short_created"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_images"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Отображаем навигацию по страницам если нужно
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Страница ${YELLOW}$page${CYAN} из ${YELLOW}$total_pages${CYAN}. Всего образов: ${YELLOW}$total_images${NC}"
        echo -e "${CYAN}🔍 Используйте навигацию в меню для перехода между страницами${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 Нет Docker образов.${NC}"
        return 1
    fi
    
    # Сохраняем информацию о пагинации для использования в меню
    IMAGES_CURRENT_PAGE=$page
    IMAGES_TOTAL_PAGES=$total_pages
    IMAGES_TOTAL_ITEMS=$total_images
    
    return 0
}

# Функция для показа всех контейнеров с пагинацией - УПРОЩЕННАЯ
show_containers() {
    local page=${1:-1}
    local page_size=50
    local start_index=$(( (page - 1) * page_size + 1 ))
    local end_index=$(( page * page_size ))
    
    echo -e "${YELLOW}🐳 Список Docker контейнеров (Страница $page):${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    local display_counter=0
    declare -g container_ids=()
    declare -g container_names=()
    declare -g container_status=()
    
    # Получаем общее количество контейнеров для пагинации
    local all_containers=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}" | tail -n +2)
    local total_containers=$(echo "$all_containers" | wc -l)
    local total_pages=$(( (total_containers + page_size - 1) / page_size ))
    
    # Заголовок таблицы - скорректированные ширины
    printf "${GREEN}%-3s${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${BLUE}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
        "No" "CONTAINER ID" "NAMES" "STATUS" "IP" "MEMORY"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    while IFS='|' read -r id image status names; do
        if [ -n "$id" ] && [ "$id" != "CONTAINER ID" ]; then
            # Пагинация: показываем только элементы для текущей страницы
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                container_ids[$display_counter]=$id
                container_names[$display_counter]="$names"
                container_status[$display_counter]="$status"
                
                # Получаем IP и память для контейнера
                local ip=$(get_container_ip "$id")
                local memory=$(get_container_memory "$id" "$status")
                
                 # Определяем цвет статуса
                status_color=$GREEN
                if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"Dead"* ]]; then
                    status_color=$RED
                elif [[ "$status" == *"Up"* ]]; then
                    status_color=$GREEN
                else
                    status_color=$YELLOW
                fi
                
                 #Скорректированное форматирование строк с большим местом для СТАТУСА
                printf "${GREEN}%-3d${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${status_color}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
                    "$display_counter" "${id:0:12}" "${names:0:20}" "${status:0:19}" "$ip" "$memory"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_containers"
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
   # Отображаем навигацию по страницам если нужно
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Страница ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Всего контейнеров: ${YELLOW}$total_containers${NC}"
        echo -e "${CYAN}🔍 Используйте навигацию в меню для перехода между страницами${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 Нет Docker контейнеров.${NC}"
        return 1
    fi
    
    # Сохраняем информацию о пагинации для использования в меню
    CONTAINERS_CURRENT_PAGE=$page
    CONTAINERS_TOTAL_PAGES=$total_pages
    CONTAINERS_TOTAL_ITEMS=$total_containers
    
    return 0
}

# Функция для обновления выбранного образа - НОВАЯ ФУНКЦИЯ
update_selected_image() {
    echo -e "${YELLOW}🔄 Обновление образа из репозитория${NC}"
    echo -e "${CYAN}Введите номер образа для обновления:${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 10; then
        return 1
    fi
    
    # Проверка на отмену
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Проверка на число
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Неверный номер. Введите число.${NC}"
        return 1
    fi
    
    if [ -z "${image_ids[$input]}" ]; then
        echo -e "${RED}❌ Неверный номер образа.${NC}"
        return 1
    fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    # Проверяем, что образ имеет репозиторий (не <none>)
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Нельзя обновить образ без репозитория.${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}🔄 Обновляем образ: ${CYAN}$full_image_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Выполняем обновление образа
    if docker pull "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Образ успешно обновлен${NC}"
        
        # Показываем информацию о новом образе
        echo ""
        echo -e "${CYAN}📊 Информация об обновленном образе:${NC}"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$image_name" | head -1
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Ошибка при обновлении образа${NC}"
    fi
}

# Функция для пуша выбранного образа - НОВАЯ ФУНКЦИЯ
push_selected_image() {
    echo -e "${YELLOW}📤 Пуш образа в репозиторий${NC}"
    echo -e "${CYAN}Введите номер образа для пуша:${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 10; then
        return 1
    fi
    
    # Проверка на отмену
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Проверка на число
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Неверный номер. Введите число.${NC}"
        return 1
    fi
    
    if [ -z "${image_ids[$input]}" ]; then
        echo -e "${RED}❌ Неверный номер образа.${NC}"
        return 1
    fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    # Проверяем, что образ имеет репозиторий (не <none>)
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Нельзя запушить образ без репозитория.${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}📤 Готовимся к пушу образа: ${CYAN}$full_image_name${NC}"
    echo ""
    
    # Запрос учетных данных
    echo -e "${YELLOW}🔐 Введите учетные данные для Docker registry:${NC}"
    echo -e "${CYAN}Логин:${NC}"
    if ! safe_read "> " docker_username 50; then
        return 1
    fi
    
    echo -e "${CYAN}Пароль:${NC}"
    if ! safe_read -s "> " docker_password 50; then
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}🔐 Авторизуемся в Docker registry...${NC}"
    
    # Авторизация в Docker registry
    if echo "$docker_password" | docker login --username "$docker_username" --password-stdin; then
        echo -e "${GREEN}✅ Успешная авторизация${NC}"
    else
        echo -e "${RED}❌ Ошибка авторизации${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}📤 Пушим образ: ${CYAN}$full_image_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Выполняем пуш образа
    if docker push "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Образ успешно запушен${NC}"
        
        # Выходим из учетной записи для безопасности
        docker logout
        echo -e "${YELLOW}🔒 Выполнен выход из учетной записи${NC}"
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Ошибка при пуше образа${NC}"
        
        # Все равно выходим из учетной записи
        docker logout
        echo -e "${YELLOW}🔒 Выполнен выход из учетной записи${NC}"
    fi
}

# Обновленное меню операций с образами с новыми функциями
show_images_menu() {
    echo -e "${CYAN}🛠️  Операции с образами:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 🗑️  Удалить выбранные образы${NC}"
    echo -e "${YELLOW}2. 🧹  Удалить неиспользуемые образы${NC}"
    echo -e "${RED}3. 💥  Удалить ВСЕ образы${NC}"
    echo -e "${ORANGE}4. 🔍  Удалить образы с тегом <none>${NC}"
    echo -e "${PURPLE}5. 🛠️  Удалить кеш сборок Docker${NC}"
    echo -e "${BLUE}6. 🔄  Обновить список образов${NC}"
    echo -e "${CYAN}7. 🔄  Обновить выбранный образ (pull)${NC}"
    echo -e "${GREEN}8. 📤  Запушить выбранный образ (push)${NC}"
    
    # Добавляем навигацию по страницам если есть несколько страниц
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
            echo -e "${CYAN}9. 📄  Следующая страница${NC}"
        fi
        if [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            echo -e "${CYAN}10. 📄  Предыдущая страница${NC}"
        fi
    fi
    
    echo -e "${GREEN}11. 🐳  Перейти к управлению контейнерами${NC}"
    echo -e "${GREEN}0. 🏠  Выход в главное меню${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Определяем максимальный допустимый выбор в зависимости от наличия страниц
    local max_choice=11
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ] && [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-11]: ${NC}" choice 2
        elif [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-10,11]: ${NC}" choice 2
        elif [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-8,10,11]: ${NC}" choice 2
        else
            safe_read "${CYAN}🎯 Выберите операцию [0-11]: ${NC}" choice 2
        fi
    else
        safe_read "${CYAN}🎯 Выберите операцию [0-11]: ${NC}" choice 2
    fi
}

# Функция для отображения меню операций с контейнерами с поддержкой пагинации
show_containers_menu() {
    echo -e "${CYAN}🛠️  Операции с контейнерами:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. ⏹️   Остановить выбранные контейнеры${NC}"
    echo -e "${YELLOW}2. 🗑️   Удалить выбранные контейнеры${NC}"
    echo -e "${RED}3. 💀   Остановить и удалить выбранные контейнеры${NC}"
    echo -e "${GREEN}4. ▶️   Запустить выбранные контейнеры${NC}"
    echo -e "${BLUE}5. 🔄   Обновить список контейнеров${NC}"
    
    # Добавляем навигацию по страницам если есть несколько страниц
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
            echo -e "${CYAN}6. 📄  Следующая страница${NC}"
        fi
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            echo -e "${CYAN}7. 📄  Предыдущая страница${NC}"
        fi
    fi
    
    echo -e "${GREEN}8. 📦   Перейти к управлению образами${NC}"
    echo -e "${GREEN}0. 🏠   Выход в главное меню${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    local max_choice=8
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ] && [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-8]: ${NC}" choice 1
        elif [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-6,8,0]: ${NC}" choice 1
        elif [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Выберите операцию [0-5,7,8,0]: ${NC}" choice 1
        else
            safe_read "${CYAN}🎯 Выберите операцию [0-8]: ${NC}" choice 1
        fi
    else
        safe_read "${CYAN}🎯 Выберите операцию [0-8]: ${NC}" choice 1
    fi
}

# Функция для удаления выбранных образов
delete_selected_images() {
    echo -e "${YELLOW}🗑️ Введите номера образов для удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Проверка на отмену с поддержкой русской раскладки
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Проверка на пустой ввод
    if [ -z "$input" ]; then
        echo -e "${RED}❌ Не выбрано ни одного образа.${NC}"
        return 1
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}🗑️ Будут удалены следующие образы:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${image_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
        fi
    done
    
    echo ""
    safe_read "Вы уверены? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${image_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Удаляем ${image_names[$num]}:${image_tags[$num]}...${NC}"
                if docker rmi -f "${image_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Успешно удален${NC}"
                else
                    echo -e "${RED}❌ Ошибка при удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Неверный номер: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Отмена удаления.${NC}"
        return 1
    fi
}

# Функция для остановки выбранных контейнеров
stop_selected_containers() {
    echo -e "${YELLOW}⏹️ Введите номера контейнеров для остановки (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Проверка на отмену с поддержкой русской раскладки
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}⏹️ Будут остановлены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}■${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Вы уверены? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}⏹️ Останавливаем ${container_names[$num]}...${NC}"
                if docker stop "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Успешно остановлен${NC}"
                else
                    echo -e "${RED}❌ Ошибка при остановке${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Неверный номер: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Отмена остановки.${NC}"
        return 1
    fi
}

# Функция для запуска выбранных контейнеров
start_selected_containers() {
    echo -e "${YELLOW}▶️  Введите номера контейнеров для запуска (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Проверка на отмену с поддержкой русской раскладки
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}▶️  Будут запущены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${GREEN}▶${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Вы уверены? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}▶️  Запускаем ${container_names[$num]}...${NC}"
                if docker start "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Успешно запущен${NC}"
                else
                    echo -e "${RED}❌ Ошибка при запуске${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Неверный номер: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Отмена запуска.${NC}"
        return 1
    fi
}

# Функция для удаления выбранных контейнеров
delete_selected_containers() {
    echo -e "${YELLOW}🗑️ Введите номера контейнеров для удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Проверка на отмену с поддержкой русской раскладки
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}🗑️ Будут удалены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Вы уверены? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Удаляем ${container_names[$num]}...${NC}"
                if docker rm "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Успешно удален${NC}"
                else
                    echo -e "${RED}❌ Ошибка при удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Неверный номер: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Отмена удаления.${NC}"
        return 1
    fi
}

# Функция для остановки и удаления выбранных контейнеров
stop_and_delete_containers() {
    echo -e "${YELLOW}💀 Введите номера контейнеров для остановки и удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Проверка на отмену с поддержкой русской раскладки
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${RED}💀 Будут остановлены и удалены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}☠${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Вы уверены? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}💀 Останавливаем и удаляем ${container_names[$num]}...${NC}"
                
                # Останавливаем контейнер (если он запущен)
                docker stop "${container_ids[$num]}" 2>/dev/null
                
                # Удаляем контейнер
                if docker rm "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Успешно остановлен и удален${NC}"
                else
                    echo -e "${RED}❌ Ошибка при остановке/удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Неверный номер: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Отмена операции.${NC}"
        return 1
    fi
}

# Функция для удаления неиспользуемых образов
delete_unused_images() {
    echo -e "${YELLOW}🧹 Удаляем неиспользуемые образы...${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    if docker image prune -a -f; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Готово!${NC}"
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Ошибка при удалении неиспользуемых образов${NC}"
    fi
}

# Функция для удаления всех образов
delete_all_images() {
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ⚠️ ОПАСНАЯ ОПЕРАЦИЯ ⚠️       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo -e "${RED}🚨 Будут удалены ВСЕ Docker образы!${NC}"
    echo ""
    
    safe_read "Вы уверены? (введите 'DELETE' для подтверждения): " confirm 10
    
    if [ "$confirm" = "DELETE" ]; then
        echo -e "${RED}🗑️ Удаляем все образы...${NC}"
        all_images=$(docker images -q)
        if [ -n "$all_images" ]; then
            if docker rmi -f $all_images 2>/dev/null; then
                echo -e "${GREEN}✅ Все образы удалены.${NC}"
            else
                echo -e "${RED}❌ Ошибка при удалении некоторых образов${NC}"
            fi
        else
            echo -e "${YELLOW}📭 Нет образов для удаления.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Отмена удаления.${NC}"
    fi
}

# Функция для удаления образов с тегом <none> - ИСПРАВЛЕННАЯ ВЕРСИЯ
delete_none_images() {
    echo -e "${YELLOW}🔍 Поиск образов с тегом <none>...${NC}"
    
    # Получаем ID всех dangling образов (образы с тегом <none>)
    dangling_images=$(docker images -f "dangling=true" -q)
    
    if [ -z "$dangling_images" ]; then
        echo -e "${GREEN}✅ Нет образов с тегом <none>.${NC}"
        # УБИРАЕМ вызов press_enter_to_continue здесь
        return
    fi
    
    echo ""
    echo -e "${RED}🗑️ Образы с тегом <none> (промежуточные образы):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Показываем информацию о dangling образах
    docker images -f "dangling=true" --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Считаем количество образов
    image_count=$(echo "$dangling_images" | wc -l)
    echo -e "${YELLOW}🗑️ Найдено ${image_count} образов с тегом <none>${NC}"
    
    echo ""
    safe_read "Удалить все образы с тегом <none>? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        echo -e "${YELLOW}🧹 Удаляем образы с тегом <none>...${NC}"
        
        # Удаляем все dangling images (образы с тегом <none>)
        if docker image prune -f; then
            echo -e "${GREEN}✅ Все образы с тегом <none> удалены${NC}"
        else
            echo -e "${RED}❌ Ошибка при удалении образов с тегом <none>${NC}"
        fi
    else
        echo -e "${GREEN}✅ Отмена удаления.${NC}"
    fi
}

# Функция для удаления кеша сборок Docker - ИСПРАВЛЕННАЯ ДЛЯ BUILDX
delete_build_cache() {
    echo -e "${YELLOW}🧹 Удаление кеша сборок Docker...${NC}"
    echo -e "${RED}⚠️ Внимание: Это освободит место, но может увеличить время следующих сборок.${NC}"
    echo ""

    # Используем buildx вместо builder
    echo -e "${CYAN}🔍 Сканируем кеш сборок...${NC}"
    local cache_output
    cache_output=$(docker buildx prune --dry-run 2>&1)
    
    # Проверяем, есть ли что удалять
    if echo "$cache_output" | grep -q "Total"; then
        # Извлекаем строку с Total размером
        local total_line=$(echo "$cache_output" | grep "Total")
        echo -e "${CYAN}📊 Будет освобождено: ${YELLOW}$total_line${NC}"
    else
        # Если не нашли Total, показываем весь вывод
        echo -e "${CYAN}📊 Информация о кеше:${NC}"
        echo "$cache_output"
    fi

    echo ""

    # Если в выводе есть ID кеша, показываем их
    if echo "$cache_output" | grep -q -E "^[a-zA-Z0-9]"; then
        echo -e "${YELLOW}Объекты кеша для удаления:${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo "$cache_output" | grep -E "^[a-zA-Z0-9]" | head -10
        local total_objects=$(echo "$cache_output" | grep -E "^[a-zA-Z0-9]" | wc -l)
        if [ "$total_objects" -gt 10 ]; then
            echo -e "${CYAN}... и еще $((total_objects - 10)) объектов${NC}"
        fi
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
    fi

    safe_read "Удалить весь кеш сборок? (y/N): " confirm 1

    if check_confirmation "$confirm"; then
        echo ""
        echo -e "${YELLOW}🧹 Удаляем кеш сборок...${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        
        # Используем buildx prune
        local delete_output
        delete_output=$(docker buildx prune -f 2>&1)
        
        # Показываем результат удаления
        echo "$delete_output"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        
        if echo "$delete_output" | grep -q "Total"; then
            echo -e "${GREEN}✅ Кеш сборок удален.${NC}"
        else
            echo -e "${GREEN}✅ Операция завершена.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Отмена удаления.${NC}"
    fi
}

# Главное меню для работы с образами с поддержкой пагинации и новыми функциями
images_submenu() {
    local current_page=${1:-1}
    
    while true; do
        print_header
        show_disk_stats
        if show_images "$current_page"; then
            echo -e "${YELLOW}Анализ использования диска...${NC}"
            echo ""
            
            # Получаем общий размер всех образов
            local total_images_bytes=0
            while IFS='|' read -r id repository tag size created; do
                if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
                    local img_bytes=$(size_to_bytes "$size")
                    total_images_bytes=$((total_images_bytes + img_bytes))
                fi
            done < <(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
            
            echo -e "${CYAN}Общий размер образов: ${YELLOW}$(format_bytes $total_images_bytes)${NC}"
            echo ""
        fi
        show_images_menu
        
        case $choice in
            1)
                if delete_selected_images; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            2)
                delete_unused_images
                press_enter_to_continue
                ;;
            3)
                delete_all_images
                press_enter_to_continue
                ;;
            4)
                delete_none_images
                press_enter_to_continue
                ;;
            5)
                delete_build_cache
                press_enter_to_continue
                ;;
            6)
                # Обновляем список на первой странице
                current_page=1
                ;;
            7)
                # Новая функция: обновить выбранный образ
                if update_selected_image; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            8)
                # Новая функция: запушить выбранный образ
                if push_selected_image; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            9)
                # Следующая страница
                if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
                    current_page=$((IMAGES_CURRENT_PAGE + 1))
                else
                    echo -e "${YELLOW}ℹ️  Это последняя страница${NC}"
                    press_enter_to_continue
                fi
                ;;
            10)
                # Предыдущая страница
                if [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
                    current_page=$((IMAGES_CURRENT_PAGE - 1))
                else
                    echo -e "${YELLOW}ℹ️  Это первая страница${NC}"
                    press_enter_to_continue
                fi
                ;;
            11)
                # Переход к управлению контейнерами
                return 1
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}❌ Неверный выбор. Попробуйте снова.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Главное меню для работы с контейнерами с поддержкой пагинации - УПРОЩЕННАЯ
containers_submenu() {
    local current_page=${1:-1}
    
    while true; do
        print_header
        show_containers_stats  # Только статистика сверху
        if show_containers "$current_page"; then
            # Убрана детальная статистика внизу
            echo ""
        fi
        show_containers_menu
        
        case $choice in
            1)
                if stop_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            2)
                if delete_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            3)
                if stop_and_delete_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            4)
                if start_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Операция завершена${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            5)
                # Обновляем список на первой странице
                current_page=1
                ;;
            6)
                # Следующая страница
                if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
                    current_page=$((CONTAINERS_CURRENT_PAGE + 1))
                else
                    echo -e "${YELLOW}ℹ️  Это последняя страница${NC}"
                    press_enter_to_continue
                fi
                ;;
            7)
                # Предыдущая страница
                if [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
                    current_page=$((CONTAINERS_CURRENT_PAGE - 1))
                else
                    echo -e "${YELLOW}ℹ️  Это первая страница${NC}"
                    press_enter_to_continue
                fi
                ;;
            8)
                # Переход к управлению образами
                return 1
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}❌ Неверный выбор. Попробуйте снова.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Функция для отображения главного меню
show_main_menu() {
    print_header
    echo -e "${CYAN}🏠 Главное меню:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 📦  Показать все образы${NC}"
    echo -e "${GREEN}2. 🐳  Показать все контейнеры${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}3. 🧹  Очистка системы Docker${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}0. 🚪  Выход${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Выберите пункт меню [0-3]: ${NC}" choice 1
}

# Функция для очистки системы Docker
cleanup_docker_system() {
    print_header
    echo -e "${YELLOW}🧹 Очистка системы Docker:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 🗑️   Удалить неиспользуемые образы${NC}"
    echo -e "${ORANGE}2. 🔍   Удалить образы с тегом <none>${NC}"
    echo -e "${PURPLE}3. 🛠️   Удалить кеш сборок Docker${NC}"
    echo -e "${RED}4. 💥   Полная очистка системы${NC}"
    echo -e "${GREEN}0. 🏠   Назад в главное меню${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Выберите операцию [0-4]: ${NC}" choice 1
    
    case $choice in
        1)
            delete_unused_images
            press_enter_to_continue
            ;;
        2)
            delete_none_images
            press_enter_to_continue
            ;;
        3)
            delete_build_cache
            press_enter_to_continue
            ;;
        4)
            echo -e "${RED}🚨 Полная очистка системы Docker...${NC}"
            echo -e "${YELLOW}Это удалит:${NC}"
            echo -e "  • Все остановленные контейнеры"
            echo -e "  • Все неиспользуемые сети"
            echo -e "  • Все неиспользуемые образы"
            echo -e "  • Все неиспользуемые сборки"
            echo -e "  • Все неиспользуемые кэши"
            echo ""
            safe_read "Вы уверены? (введите 'CLEAN' для подтверждения): " confirm 10
            if [ "$confirm" = "CLEAN" ]; then
                echo ""
                docker system prune -a -f
                echo -e "${GREEN}✅ Полная очистка завершена${NC}"
            else
                echo -e "${GREEN}✅ Отмена очистки${NC}"
            fi
            press_enter_to_continue
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор.${NC}"
            sleep 2
            ;;
    esac
}

# Основной цикл программы
while true; do
    show_main_menu
    
    case $choice in
        1)
            if images_submenu; then
                # Возврат в главное меню
                continue
            else
                # Переход к контейнерам
                containers_submenu
            fi
            ;;
        2)
            if containers_submenu; then
                # Возврат в главное меню
                continue
            else
                # Переход к образам
                images_submenu
            fi
            ;;
        3)
            cleanup_docker_system
            ;;
        0)
            echo -e "${GREEN}👋 Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор. Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
