#!/bin/bash

# ==========================================
# Simple Linux Docker Manager v1.0.7
# (Russian Edition + Wide View)
# ==========================================

# Настройки оболочки
set -o pipefail

# Глобальные константы
readonly PAGE_SIZE=50
readonly CACHE_TTL=5

# Глобальные переменные состояния
declare -g IMAGES_CURRENT_PAGE=1
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g SEARCH_FILTER=""

# Переменные кэша
declare -g CACHED_IMAGES_RAW=""
declare -g CACHED_IMAGES_TIME=0
declare -g CACHED_CONTAINERS_RAW=""
declare -g CACHED_CONTAINERS_TIME=0

# ГЛОБАЛЬНЫЕ МАССИВЫ ДАННЫХ
declare -ga image_ids=()
declare -ga image_names=()
declare -ga image_tags=()
declare -ga container_ids=()
declare -ga container_names=()
declare -ga container_status=()

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
GREY='\033[0;37m'
NC='\033[0m'

# --- БЛОК БЕЗОПАСНОСТИ ---

cleanup_exit() {
    stty echo 2>/dev/null
    unset docker_password
    echo -e "\n${CYAN}👋 Работа завершена.${NC}"
}
trap cleanup_exit EXIT SIGINT SIGTERM

check_dependencies() {
    local missing=0
    if ! command -v docker &> /dev/null; then echo -e "${RED}❌ Docker не найден.${NC}"; missing=1; fi
    if [ $missing -eq 0 ] && ! docker ps &> /dev/null; then echo -e "${RED}❌ Нет прав на Docker.${NC}"; missing=1; fi
    if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then echo -e "${RED}❌ Требуется Bash 4.0+.${NC}"; missing=1; fi
    if [ $missing -eq 1 ]; then exit 1; fi
}

# --- КЭШИРОВАНИЕ И ДАННЫЕ ---

invalidate_cache() {
    CACHED_IMAGES_RAW=""
    CACHED_CONTAINERS_RAW=""
}

get_images_list() {
    local current_time=$(date +%s)
    if [ -z "$CACHED_IMAGES_RAW" ] || [ $((current_time - CACHED_IMAGES_TIME)) -ge $CACHE_TTL ]; then
        CACHED_IMAGES_RAW=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
        CACHED_IMAGES_TIME=$current_time
    fi

    if [ -n "$SEARCH_FILTER" ]; then
        echo "$CACHED_IMAGES_RAW" | grep -i "$SEARCH_FILTER"
    else
        echo "$CACHED_IMAGES_RAW"
    fi
}

get_containers_list() {
    local current_time=$(date +%s)
    if [ -z "$CACHED_CONTAINERS_RAW" ] || [ $((current_time - CACHED_CONTAINERS_TIME)) -ge $CACHE_TTL ]; then
        CACHED_CONTAINERS_RAW=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}|{{.Label \"com.docker.compose.project\"}}" | tail -n +2)
        CACHED_CONTAINERS_TIME=$current_time
    fi

    if [ -n "$SEARCH_FILTER" ]; then
        echo "$CACHED_CONTAINERS_RAW" | grep -i "$SEARCH_FILTER"
    else
        echo "$CACHED_CONTAINERS_RAW"
    fi
}

# --- УТИЛИТЫ ---

safe_read() {
    local secret=0 prompt="$1" var_name="$2" max_chars="${3:-100}"
    shift 2
    if [ "$prompt" == "-s" ]; then secret=1; prompt="$2"; var_name="$3"; shift 3; fi
    [ -z "$var_name" ] && local dummy && var_name="dummy"

    echo -ne "$prompt"
    if [ $secret -eq 1 ]; then
        stty -echo; IFS= read -r -n "$max_chars" "$var_name"; stty echo; echo ""
    else
        IFS= read -r -n "$max_chars" "$var_name"
    fi
    if [ -n "${!var_name}" ]; then local extra; IFS= read -r -t 0.1 -n 1000 extra || true; fi
    return 0
}

size_to_bytes() {
    local size=$(echo "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local mult=1 num=0
    case "$size" in
        *gib) num=${size%gib}; mult=1073741824 ;;
        *gb)  num=${size%gb};  mult=1000000000 ;;
        *mib) num=${size%mib}; mult=1048576 ;;
        *mb)  num=${size%mb};  mult=1000000 ;;
        *kib) num=${size%kib}; mult=1024 ;;
        *kb)  num=${size%kb};  mult=1000 ;;
        *b)   num=${size%b};   mult=1 ;;
        *)    echo "0"; return ;;
    esac
    awk -v n="$num" -v m="$mult" 'BEGIN {printf "%.0f", n * m}' 2>/dev/null || echo "0"
}

format_bytes() {
    local b=$1
    [ -z "$b" ] || [ "$b" -eq 0 ] && echo "0B" && return
    if command -v bc >/dev/null 2>&1; then
        if [ "$b" -ge 1073741824 ]; then echo "$(echo "scale=2; $b/1073741824" | bc)GiB"
        elif [ "$b" -ge 1048576 ]; then echo "$(echo "scale=2; $b/1048576" | bc)MiB"
        else echo "$((b/1024))KiB"; fi
    else
        if [ "$b" -ge 1073741824 ]; then echo "$((b/1073741824))GiB"
        elif [ "$b" -ge 1048576 ]; then echo "$((b/1048576))MiB"
        else echo "$((b/1024))KiB"; fi
    fi
}

check_cancel() { [[ "$1" =~ ^[cCсС]$ ]]; }

# --- СТАТИСТИКА ---

show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    local disk_info=$(df "$docker_root" | tail -1 2>/dev/null)
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    
    local images_size_raw=$(docker system df --format "{{.Type}} {{.Size}}" 2>/dev/null | awk '/Images/{print $2 $3}')
    local total_images_count=$(docker images -q 2>/dev/null | wc -l)

    echo -e "${CYAN}║ 📦 ${GREEN}Образы:${NC} ${images_size_raw:-0B} (${total_images_count}) ${CYAN} │ Диск:${NC} $(format_bytes $((disk_used*1024)))/$(format_bytes $((disk_total*1024)))                          ${CYAN}║${NC}"
    
    if [ -n "$SEARCH_FILTER" ]; then
         echo -e "${CYAN}║ 🔍 ${YELLOW}ПОИСК:${NC} '$SEARCH_FILTER'${CYAN} (Сброс: '/')${NC}                                           ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    local running=$(docker ps -q 2>/dev/null | wc -l)
    local total=$(docker ps -aq 2>/dev/null | wc -l)
    
    local mem_display="Calc..."
    if [ "$total" -lt 100 ]; then
        local mem_bytes=0
        while IFS= read -r mem; do
            mem_bytes=$((mem_bytes + $(size_to_bytes "$mem")))
        done < <(docker stats --no-stream --format "{{.MemUsage}}" $(docker ps -q) 2>/dev/null | cut -d'/' -f1)
        mem_display=$(format_bytes $mem_bytes)
    fi

    echo -e "${CYAN}║ 🐳 ${GREEN}Контейнеры:${NC} ${total} (Работает: ${running}) ${CYAN} │ Память:${NC} ${mem_display}                        ${CYAN}║${NC}"
     if [ -n "$SEARCH_FILTER" ]; then
         echo -e "${CYAN}║ 🔍 ${YELLOW}ПОИСК:${NC} '$SEARCH_FILTER'${CYAN} (Сброс: '/')${NC}                                           ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Simple Linux Docker Manager ${YELLOW}v1.0.7${CYAN}           ║${NC}"
    echo -e "${CYAN}║     ${GREEN}Russian Wide Edition${CYAN}                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}\n"
}

press_enter() { echo ""; safe_read "${CYAN}Нажмите Enter...${NC}" dummy; }

# --- СПИСКИ (CORE) ---

show_images() {
    local page=${1:-1}
    local start=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end=$(( page * PAGE_SIZE ))
    
    image_ids=(); image_names=(); image_tags=()
    local display_count=1
    
    local data=$(get_images_list)
    local total_items=$(echo "$data" | grep -v "^$" | wc -l)
    local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    echo -e "${YELLOW}📦 Список образов${NC} (Стр. $page/$total_pages | Всего: $total_items)"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────${NC}"
    
    local i=1
    while IFS='|' read -r id repo tag size created; do
        [ -z "$id" ] && continue
        if [ $i -ge $start ] && [ $i -le $end ]; then
            image_ids[$display_count]=$id
            image_names[$display_count]="$repo"
            image_tags[$display_count]="$tag"
            
            printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-20s${NC} ${RED}%-8s${NC} ${GREY}%s${NC}\n" \
                "$display_count" "${repo:0:30}" "${tag:0:20}" "$size" "${created%% *}"
            ((display_count++))
        fi
        ((i++))
    done <<< "$data"
    
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────${NC}"
    [ $total_items -eq 0 ] && echo -e "${RED}📭 Ничего не найдено${NC}"
    
    IMAGES_TOTAL_PAGES=$total_pages
    return 0
}

show_containers() {
    local page=${1:-1}
    local start=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end=$(( page * PAGE_SIZE ))
    
    container_ids=(); container_names=(); container_status=()
    local display_count=1

    local data=$(get_containers_list)
    local total_items=$(echo "$data" | grep -v "^$" | wc -l)
    
    if [ $total_items -gt 0 ] && [ -z "$SEARCH_FILTER" ]; then
         if [ -n "$(docker ps -aq)" ]; then
             declare -A ip_map
             while IFS='|' read -r fid ip; do ip_map["${fid:0:12}"]="$ip"; done < <(docker inspect --format '{{.ID}}|{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) 2>/dev/null)
         fi
    fi

    local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    echo -e "${YELLOW}🐳 Список контейнеров${NC} (Стр. $page/$total_pages | Всего: $total_items)"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    # УВЕЛИЧЕНА ШИРИНА ДЛЯ NAMES (50 символов)
    printf "${GREEN}%-3s${NC} ${PURPLE}%-12s${NC} ${CYAN}%-50s${NC} ${BLUE}%-15s${NC} ${YELLOW}%-15s${NC}\n" "No" "ID" "ИМЯ КОНТЕЙНЕРА" "СТАТУС" "IP"
    
    local i=1
    while IFS='|' read -r id image status names compose_proj; do
        [ -z "$id" ] && continue
        if [ $i -ge $start ] && [ $i -le $end ]; then
            container_ids[$display_count]=$id
            container_names[$display_count]="$names"
            
            # Увеличенная длина обрезки имени (50 символов)
            local name_display="${names:0:50}"
            if [ -n "$compose_proj" ]; then
                name_display="${name_display} ${ORANGE}[C]${NC}"
            fi

            local ip="${ip_map[$id]:--}"
            local color=$GREEN
            [[ "$status" == *"Exited"* ]] && color=$RED
            [[ "$status" == *"Dead"* ]] && color=$RED
            
            # Обновленный формат вывода (50 символов для имени)
            printf "${GREEN}%-3d${NC} ${PURPLE}%-12s${NC} ${CYAN}%-50b${NC} ${color}%-15s${NC} ${YELLOW}%-15s${NC}\n" \
                "$display_count" "$id" "$name_display" "${status:0:15}" "$ip"
            ((display_count++))
        fi
        ((i++))
    done <<< "$data"
    
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    CONTAINERS_TOTAL_PAGES=$total_pages
    return 0
}

# --- ДЕЙСТВИЯ ---

set_filter() {
    echo -e "${YELLOW}🔍 Поиск / Фильтр${NC}"
    echo -e "Введите текст (пусто для сброса):"
    safe_read "> " input 20
    SEARCH_FILTER="$input"
    IMAGES_CURRENT_PAGE=1
    CONTAINERS_CURRENT_PAGE=1
}

update_image() {
    safe_read "${CYAN}Номер: ${NC}" num 5
    [ -z "${image_ids[$num]}" ] && return
    local full="${image_names[$num]}:${image_tags[$num]}"
    [[ "$full" == *"<none>"* ]] && echo "${RED}Ошибка: <none>${NC}" && return
    echo "Скачивание $full..."
    docker pull "$full" && invalidate_cache && echo "${GREEN}Готово${NC}" || echo "${RED}Ошибка${NC}"
}

docker_push() {
    safe_read "${CYAN}Номер: ${NC}" num 5
    [ -z "${image_ids[$num]}" ] && return
    local full="${image_names[$num]}:${image_tags[$num]}"
    
    safe_read "${CYAN}Логин: ${NC}" user 50
    safe_read -s "${CYAN}Пароль: ${NC}" pass 200
    
    echo "$pass" | docker login --username "$user" --password-stdin
    local ret=$?
    unset pass
    
    if [ $ret -eq 0 ]; then
        docker push "$full" && echo "${GREEN}Успешно${NC}"
        docker logout
    else
        echo "${RED}Ошибка входа${NC}"
    fi
    invalidate_cache
}

batch_action() {
    local type=$1 action=$2
    echo -e "${YELLOW}Введите номера (через пробел):${NC}"
    safe_read "> " input 50
    check_cancel "$input" && return
    read -a nums <<< "$input"
    
    echo "Выполняем..."
    for n in "${nums[@]}"; do
        local id=""
        [ "$type" == "img" ] && id="${image_ids[$n]}"
        [ "$type" == "cnt" ] && id="${container_ids[$n]}"
        
        if [ -n "$id" ]; then
            if [ "$action" == "rmi" ]; then docker rmi -f "$id" 2>/dev/null; fi
            if [ "$action" == "stop" ]; then docker stop "$id" 2>/dev/null; fi
            if [ "$action" == "start" ]; then docker start "$id" 2>/dev/null; fi
            if [ "$action" == "rm" ]; then docker rm "$id" 2>/dev/null; fi
            if [ "$action" == "kill" ]; then docker stop "$id" 2>/dev/null; docker rm "$id" 2>/dev/null; fi
            echo -e "ID ${id:0:12} -> ${GREEN}OK${NC}"
        fi
    done
    invalidate_cache
    press_enter
}

# --- МЕНЮ ---

menu_images() {
    while true; do
        print_header; show_disk_stats; show_images "$IMAGES_CURRENT_PAGE"
        echo -e "${CYAN}1-3${NC} Удалить/Очистить/Все | ${CYAN}4-5${NC} None/Кеш | ${CYAN}6${NC} Обновить (Pull) | ${CYAN}7${NC} Push | ${CYAN}8${NC} Поиск"
        [ $IMAGES_TOTAL_PAGES -gt 1 ] && echo -e "${CYAN}n/p${NC} След/Пред страница"
        echo -e "${GREEN}9${NC} Переход к контейнерам  ${GREEN}0${NC} Назад"
        
        safe_read "🎯 Выбор: " c 1
        case $c in
            1) batch_action "img" "rmi" ;;
            2) docker image prune -a -f; invalidate_cache; press_enter ;;
            3) safe_read "Введите DELETE для подтверждения: " conf; [ "$conf" == "DELETE" ] && (docker images -q | xargs -r docker rmi -f); invalidate_cache; press_enter ;;
            4) docker image prune -f; invalidate_cache; press_enter ;;
            5) docker buildx prune -f; press_enter ;;
            6) update_image; press_enter ;;
            7) docker_push; press_enter ;;
            8|/) set_filter ;;
            9) return 2 ;; # Код переключения
            n) [ $IMAGES_CURRENT_PAGE -lt $IMAGES_TOTAL_PAGES ] && ((IMAGES_CURRENT_PAGE++)) ;;
            p) [ $IMAGES_CURRENT_PAGE -gt 1 ] && ((IMAGES_CURRENT_PAGE--)) ;;
            0) return 0 ;;
        esac
    done
}

menu_containers() {
    while true; do
        print_header; show_containers_stats; show_containers "$CONTAINERS_CURRENT_PAGE"
        echo -e "${CYAN}1${NC} Стоп | ${CYAN}2${NC} Старт | ${CYAN}3${NC} Удалить | ${CYAN}4${NC} Kill+Del | ${CYAN}5${NC} Поиск"
        [ $CONTAINERS_TOTAL_PAGES -gt 1 ] && echo -e "${CYAN}n/p${NC} След/Пред страница"
        echo -e "${GREEN}9${NC} Переход к образам  ${GREEN}0${NC} Назад"
        
        safe_read "🎯 Выбор: " c 1
        case $c in
            1) batch_action "cnt" "stop" ;;
            2) batch_action "cnt" "start" ;;
            3) batch_action "cnt" "rm" ;;
            4) batch_action "cnt" "kill" ;;
            5|/) set_filter ;;
            9) return 2 ;; # Код переключения
            n) [ $CONTAINERS_CURRENT_PAGE -lt $CONTAINERS_TOTAL_PAGES ] && ((CONTAINERS_CURRENT_PAGE++)) ;;
            p) [ $CONTAINERS_CURRENT_PAGE -gt 1 ] && ((CONTAINERS_CURRENT_PAGE--)) ;;
            0) return 0 ;;
        esac
    done
}

# --- MAIN LOOP ---

check_dependencies

# State Machine для переходов
NEXT_MENU="main"

while true; do
    if [ "$NEXT_MENU" == "main" ]; then
        print_header
        echo -e "${CYAN}1.${NC} 📦 Образы"
        echo -e "${CYAN}2.${NC} 🐳 Контейнеры"
        echo -e "${CYAN}3.${NC} 🧹 Полная очистка"
        echo -e "${RED}0. 🚪 Выход${NC}"
        safe_read "Выбор: " c 1
        case $c in
            1) NEXT_MENU="images" ;;
            2) NEXT_MENU="containers" ;;
            3) docker system prune -a -f; invalidate_cache; press_enter ;;
            0) cleanup_exit; exit 0 ;;
        esac
    
    elif [ "$NEXT_MENU" == "images" ]; then
        menu_images
        ret=$?
        if [ $ret -eq 2 ]; then NEXT_MENU="containers"; else NEXT_MENU="main"; fi
        
    elif [ "$NEXT_MENU" == "containers" ]; then
        menu_containers
        ret=$?
        if [ $ret -eq 2 ]; then NEXT_MENU="images"; else NEXT_MENU="main"; fi
    fi
done
