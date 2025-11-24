#!/bin/bash

# ==========================================
# Simple Linux Docker Manager (SLDM) v1.2.2
# English Edition (Async, Auto-Refresh, UI Polish)
# https://github.com/rjohny55/Simple-Linux-Docker-Manager
# ==========================================

# Shell settings
set -o pipefail

# Global Constants
readonly PAGE_SIZE=50
readonly CACHE_TTL=5
readonly RAM_CACHE_FILE="/tmp/sldm_ram_$(id -u).cache"
readonly RAM_LOCK_FILE="/tmp/sldm_ram_$(id -u).lock"

# Global State Variables
declare -g IMAGES_CURRENT_PAGE=1
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g SEARCH_FILTER=""

# Cache Variables
declare -g CACHED_IMAGES_RAW=""
declare -g CACHED_IMAGES_TIME=0
declare -g CACHED_CONTAINERS_RAW=""
declare -g CACHED_CONTAINERS_TIME=0

# GLOBAL DATA ARRAYS
declare -ga image_ids=()
declare -ga image_names=()
declare -ga image_tags=()
declare -ga container_ids=()
declare -ga container_names=()
declare -ga container_status=()

# Colors
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[0;34m'
PURPLE=$'\e[0;35m'
CYAN=$'\e[0;36m'
ORANGE=$'\e[0;33m'
GREY=$'\e[0;37m'
NC=$'\e[0m'

# --- SECURITY & CLEANUP ---

cleanup_exit() {
    stty echo 2>/dev/null
    unset docker_password
    rm -f "$RAM_CACHE_FILE" "$RAM_LOCK_FILE"
    echo -e "\n${CYAN}👋 See you!${NC}"
}
trap cleanup_exit EXIT SIGINT SIGTERM

check_dependencies() {
    local missing=0
    if ! command -v docker &> /dev/null; then echo -e "${RED}❌ Docker not found.${NC}"; missing=1; fi
    if [ $missing -eq 0 ] && ! docker ps &> /dev/null; then echo -e "${RED}❌ No permissions for Docker.${NC}"; missing=1; fi
    if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then echo -e "${RED}❌ Bash 4.0+ required.${NC}"; missing=1; fi
    if [ $missing -eq 1 ]; then exit 1; fi
}

# --- CACHING & ASYNC ---

invalidate_cache() {
    CACHED_IMAGES_RAW=""
    CACHED_CONTAINERS_RAW=""
}

trigger_async_ram_calc() {
    if [ -f "$RAM_LOCK_FILE" ]; then
        local pid=$(cat "$RAM_LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return; fi
    fi
    (
        echo $$ > "$RAM_LOCK_FILE"
        local sum=0
        if [ -n "$(docker ps -q)" ]; then
            while IFS= read -r mem; do
                local bytes=$(size_to_bytes "$mem")
                sum=$((sum + bytes))
            done < <(docker stats --no-stream --format "{{.MemUsage}}" $(docker ps -q) 2>/dev/null | cut -d'/' -f1)
        fi
        echo "$sum" > "$RAM_CACHE_FILE"
        rm -f "$RAM_LOCK_FILE"
    ) & >/dev/null 2>&1
}

force_refresh() {
    invalidate_cache
    rm -f "$RAM_CACHE_FILE"
    trigger_async_ram_calc
}

get_images_list() {
    local current_time=$(date +%s)
    if [ -z "$CACHED_IMAGES_RAW" ] || [ $((current_time - CACHED_IMAGES_TIME)) -ge $CACHE_TTL ]; then
        CACHED_IMAGES_RAW=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
        CACHED_IMAGES_TIME=$current_time
    fi
    if [ -n "$SEARCH_FILTER" ]; then echo "$CACHED_IMAGES_RAW" | grep -i "$SEARCH_FILTER"; else echo "$CACHED_IMAGES_RAW"; fi
}

get_containers_list() {
    local current_time=$(date +%s)
    if [ -z "$CACHED_CONTAINERS_RAW" ] || [ $((current_time - CACHED_CONTAINERS_TIME)) -ge $CACHE_TTL ]; then
        CACHED_CONTAINERS_RAW=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}|{{.Label \"com.docker.compose.project\"}}" | tail -n +2)
        CACHED_CONTAINERS_TIME=$current_time
    fi
    if [ -n "$SEARCH_FILTER" ]; then echo "$CACHED_CONTAINERS_RAW" | grep -i "$SEARCH_FILTER"; else echo "$CACHED_CONTAINERS_RAW"; fi
}

# --- UTILITIES ---

safe_read() {
    local secret=0 timeout=0 timeout_val=0 prompt="$1" var_name="$2" max_chars="${3:-100}"
    shift 2
    while [[ "$prompt" == -* ]]; do
        case "$prompt" in
            -s|--secret) secret=1; prompt="$1"; var_name="$2"; shift 2 ;;
            -t|--timeout) timeout=1; timeout_val="$1"; prompt="$2"; var_name="$3"; shift 3 ;;
            *) break ;;
        esac
    done
    [ -z "$var_name" ] && local dummy && var_name="dummy"
    echo -ne "$prompt"
    if [ $secret -eq 1 ]; then stty -echo; IFS= read -r -n "$max_chars" "$var_name"; stty echo; echo ""
    elif [ $timeout -eq 1 ]; then if ! IFS= read -r -t "$timeout_val" -n "$max_chars" "$var_name"; then return 1; fi
    else IFS= read -r -n "$max_chars" "$var_name"; fi
    if [ -n "${!var_name}" ]; then local extra; IFS= read -r -t 0.1 -n 1000 extra || true; fi
    return 0
}

size_to_bytes() {
    local size=$(echo "$1" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local mult=1 num=0
    case "$size" in
        *tib) num=${size%tib}; mult=1099511627776 ;;
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
        if [ "$b" -ge 1099511627776 ]; then echo "$(echo "scale=2; $b/1099511627776" | bc)TiB"
        elif [ "$b" -ge 1073741824 ]; then echo "$(echo "scale=2; $b/1073741824" | bc)GiB"
        elif [ "$b" -ge 1048576 ]; then echo "$(echo "scale=2; $b/1048576" | bc)MiB"
        else echo "$((b/1024))KiB"; fi
    else
        if [ "$b" -ge 1099511627776 ]; then echo "$((b/1099511627776))TiB"
        elif [ "$b" -ge 1073741824 ]; then echo "$((b/1073741824))GiB"
        elif [ "$b" -ge 1048576 ]; then echo "$((b/1048576))MiB"
        else echo "$((b/1024))KiB"; fi
    fi
}

get_cpu_usage() {
    if [ -f /proc/stat ]; then
        read cpu a b c idle rest < /proc/stat
        local total1=$((a+b+c+idle))
        local idle1=$idle
        sleep 0.1
        read cpu a b c idle rest < /proc/stat
        local total2=$((a+b+c+idle))
        local idle2=$idle
        local diff_idle=$((idle2 - idle1))
        local diff_total=$((total2 - total1))
        if [ $diff_total -eq 0 ]; then echo "0"; return; fi
        echo $(( (1000 * (diff_total - diff_idle) / diff_total + 5) / 10 ))
    else
        echo "0"
    fi
}

check_cancel() { [[ "$1" =~ ^[cCсС]$ ]]; }

# --- UI DISPLAY ---

show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    local disk_info=$(df "$docker_root" | tail -1 2>/dev/null)
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local images_size_raw=$(docker system df --format "{{.Type}}\t{{.Size}}" 2>/dev/null | grep "Images" | awk '{print $2 $3}')
    local total_images_count=$(docker images -q 2>/dev/null | wc -l)

    echo -e "${CYAN}║ 📦 ${GREEN}Images:${NC} ${images_size_raw:-0B} (${total_images_count}) ${CYAN} │ Disk:${NC} $(format_bytes $((disk_used*1024)))/$(format_bytes $((disk_total*1024)))                             ${CYAN}║${NC}"
    if [ -n "$SEARCH_FILTER" ]; then
         echo -e "${CYAN}║ 🔍 ${YELLOW}SEARCH:${NC} '$SEARCH_FILTER'${CYAN} (Reset: '/')${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    
    local running=$(docker ps -q 2>/dev/null | wc -l)
    local total=$(docker ps -aq 2>/dev/null | wc -l)
    
    local docker_ram_display="Loading..."
    if [ -f "$RAM_CACHE_FILE" ]; then
        local cached_bytes=$(cat "$RAM_CACHE_FILE")
        docker_ram_display=$(format_bytes "$cached_bytes")
    else
        trigger_async_ram_calc
    fi

    local sys_ram_total=0
    if [ -f /proc/meminfo ]; then
        local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        sys_ram_total=$((mem_total_kb * 1024))
    elif command -v sysctl >/dev/null; then
        sys_ram_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    fi
    
    local host_cpu=$(get_cpu_usage)
    local c_info="Containers: ${total} (Run: ${running})"
    local r_info="RAM: ${docker_ram_display} / $(format_bytes $sys_ram_total)"
    local cpu_info="CPU: ${host_cpu}%"
    
    local BOX_WIDTH=84
    local SPACES="                                                                                                    "
    
    printf "${CYAN}║ 🐳 ${GREEN}%s${CYAN} │ ${YELLOW}%s${CYAN} │ ${RED}%s${NC}" "$c_info" "$r_info" "$cpu_info"
    
    local stripped_len=$((${#c_info} + ${#r_info} + ${#cpu_info} + 7))
    local pad=$((BOX_WIDTH - stripped_len))
    [ $pad -lt 0 ] && pad=0
    
    printf "%s\n" "${SPACES:0:$pad}"

    if [ -n "$SEARCH_FILTER" ]; then
         echo -e "${CYAN}║ 🔍 ${YELLOW}SEARCH:${NC} '$SEARCH_FILTER'${CYAN} (Reset: '/')${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help_modal() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    HELP MENU                     ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}Navigation:${NC}                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  n / p     - Next / Previous Page                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  9         - Switch Images <-> Containers        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  0         - Back / Exit                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} ${YELLOW}Actions:${NC}                                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  r         - Refresh + Recalc RAM                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  / or 8    - Search / Filter                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  1-7       - Select Menu Item                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  h or ?    - Show Help                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    press_enter
}

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Simple Linux Docker Manager             ║${NC}"
    echo -e "${CYAN}║          ${GREEN}v1.2.2 English Edition${NC}                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}\n"
}

press_enter() { echo ""; safe_read "${CYAN}Press Enter...${NC}" dummy; }

# --- LIST VIEWS ---

show_images() {
    local page=${1:-1}
    local start=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end=$(( page * PAGE_SIZE ))
    
    image_ids=(); image_names=(); image_tags=()
    local display_count=1
    
    local data=$(get_images_list)
    local total_items=$(echo "$data" | grep -c . || echo 0)
    local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    echo -e "${YELLOW}📦 Image List${NC} (Page $page/$total_pages | Total: $total_items)"
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────────────────────${NC}"
    
    local i=1
    while IFS='|' read -r id repo tag size created; do
        [ -z "$id" ] && continue
        if (( i >= start && i <= end )); then
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
    [ $total_items -eq 0 ] && echo -e "${RED}📭 No images found${NC}"
    IMAGES_TOTAL_PAGES=$total_pages
    return 0
}

show_containers() {
    local page=${1:-1}
    local start=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end=$(( page * PAGE_SIZE ))
    
    container_ids=(); container_names=(); container_status=()
    local display_count=1

    declare -A ip_map
    if command -v docker >/dev/null && [ -n "$(docker ps -aq)" ]; then
         while IFS='|' read -r fid ip; do [ -n "$ip" ] && ip_map["${fid:0:12}"]="$ip"; done < <(docker inspect --format '{{.ID}}|{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) 2>/dev/null)
    fi

    local data=$(get_containers_list)
    local total_items=$(echo "$data" | grep -c . || echo 0)
    local total_pages=$(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    echo -e "${YELLOW}🐳 Container List${NC} (Page $page/$total_pages | Total: $total_items)"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    local SPACES="                                                                                                    "
    local W_NAME=50
    local W_STATUS=20

    local h_name="CONTAINER NAME"
    local h_status="STATUS"
    
    local pad_h_name="${SPACES:0:$((W_NAME - ${#h_name}))}"
    local pad_h_status="${SPACES:0:$((W_STATUS - ${#h_status}))}"

    printf "${GREEN}%-4s${NC} ${PURPLE}%-12s${NC} ${CYAN}%s%s${NC} ${BLUE}%s%s${NC} ${YELLOW}%s${NC}\n" \
           "No" "ID" "$h_name" "$pad_h_name" "$h_status" "$pad_h_status" "IP"
           
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    local i=1
    while IFS='|' read -r id image status names compose_proj; do
        [ -z "$id" ] && continue
        if (( i >= start && i <= end )); then
            container_ids[$display_count]=$id
            container_names[$display_count]="$names"
            container_status[$display_count]="$status"
            
            local label=""
            [ -n "$compose_proj" ] && label=" [C]"
            local label_len=${#label}
            
            local avail_len=$((W_NAME - label_len))
            local name_display="${names}"
            if [ ${#names} -gt $avail_len ]; then name_display="${names:0:$avail_len}"; fi
            
            local full_len=$((${#name_display} + label_len))
            local pad_len=$((W_NAME - full_len))
            [ $pad_len -lt 0 ] && pad_len=0
            local padding="${SPACES:0:$pad_len}"
            
            local status_display="${status:0:$W_STATUS}"
            local pad_status_len=$((W_STATUS - ${#status_display}))
            [ $pad_status_len -lt 0 ] && pad_status_len=0
            local padding_status="${SPACES:0:$pad_status_len}"

            local ip="${ip_map[${id:0:12}]:--}"
            local color=$GREEN
            [[ "$status" == *"Exit"* || "$status" == *"Dead"* ]] && color=$RED
            
            printf "${GREEN}%-4d${NC} ${PURPLE}%-12s${NC} " "$display_count" "${id:0:12}"
            printf "${CYAN}%s${NC}${ORANGE}%s${NC}%s " "$name_display" "$label" "$padding"
            printf "${color}%s${NC}%s ${YELLOW}%s${NC}\n" "$status_display" "$padding_status" "$ip"

            ((display_count++))
        fi
        ((i++))
    done <<< "$data"
    
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    CONTAINERS_TOTAL_PAGES=$total_pages
    return 0
}

# --- ACTIONS & MENUS ---

set_filter() {
    echo -e "${YELLOW}🔍 Search / Filter${NC}"
    echo -e "Enter text (empty to reset):"
    safe_read "> " input 20
    SEARCH_FILTER="$input"
    IMAGES_CURRENT_PAGE=1
    CONTAINERS_CURRENT_PAGE=1
    force_refresh
}

update_image() {
    safe_read "${CYAN}Number: ${NC}" num 5
    [ -z "${image_ids[$num]}" ] && return
    local full="${image_names[$num]}:${image_tags[$num]}"
    [[ "$full" == *"<none>"* ]] && echo "${RED}Error: <none>${NC}" && return
    echo "Pulling $full..."
    docker pull "$full" && force_refresh && echo "${GREEN}Done${NC}" || echo "${RED}Error${NC}"
}

docker_push() {
    safe_read "${CYAN}Number: ${NC}" num 5
    [ -z "${image_ids[$num]}" ] && return
    local full="${image_names[$num]}:${image_tags[$num]}"
    safe_read "${CYAN}Username: ${NC}" user 50
    safe_read -s "${CYAN}Password: ${NC}" pass 200
    echo "$pass" | docker login --username "$user" --password-stdin
    local ret=$?
    unset pass
    if [ $ret -eq 0 ]; then docker push "$full" && echo "${GREEN}Success${NC}"; docker logout; else echo "${RED}Login Failed${NC}"; fi
    force_refresh
}

batch_action() {
    local type=$1 action=$2
    echo -e "${YELLOW}Enter numbers (space separated):${NC}"
    safe_read "> " input 50
    check_cancel "$input" && return
    read -a nums <<< "$input"
    echo "Processing..."
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
    rm -f "$RAM_CACHE_FILE"
    invalidate_cache
    trigger_async_ram_calc
    press_enter
}

menu_images() {
    rm -f "$RAM_CACHE_FILE"
    while true; do
        print_header; show_disk_stats; show_images "$IMAGES_CURRENT_PAGE"
        echo -e "${CYAN}1-3${NC} Del/Prune/All | ${CYAN}4-5${NC} None/Cache | ${CYAN}6${NC} Pull | ${CYAN}7${NC} Push | ${CYAN}8${NC} Search"
        [ $IMAGES_TOTAL_PAGES -gt 1 ] && echo -e "${CYAN}n/p${NC} Next/Prev Page"
        echo -e "${GREEN}9${NC} To Containers | ${GREEN}0${NC} Back | ${GREEN}h${NC} Help"
        
        safe_read "🎯 Select: " c 1
        case $c in
            1) batch_action "img" "rmi" ;;
            2) docker image prune -a -f; force_refresh; press_enter ;;
            3) safe_read "Type DELETE to confirm: " conf; [ "$conf" == "DELETE" ] && (docker images -q | xargs -r docker rmi -f); force_refresh; press_enter ;;
            4) docker image prune -f; force_refresh; press_enter ;;
            5) docker buildx prune -f; press_enter ;;
            6) update_image; press_enter ;;
            7) docker_push; press_enter ;;
            8|/) set_filter ;;
            9) return 2 ;; 
            h|?) show_help_modal ;;
            n) [ $IMAGES_CURRENT_PAGE -lt $IMAGES_TOTAL_PAGES ] && ((IMAGES_CURRENT_PAGE++)) ;;
            p) [ $IMAGES_CURRENT_PAGE -gt 1 ] && ((IMAGES_CURRENT_PAGE--)) ;;
            0) return 0 ;;
        esac
    done
}

menu_containers() {
    local ram_state=0
    while true; do
        print_header; show_containers_stats; show_containers "$CONTAINERS_CURRENT_PAGE"
        if [ -f "$RAM_CACHE_FILE" ]; then ram_state=1; else ram_state=0; fi
        
        echo -e "${CYAN}1${NC} Stop | ${CYAN}2${NC} Start | ${CYAN}3${NC} Remove | ${CYAN}4${NC} Kill | ${CYAN}5${NC} Search | ${GREEN}r${NC} Refresh"
        [ $CONTAINERS_TOTAL_PAGES -gt 1 ] && echo -e "${CYAN}n/p${NC} Next/Prev Page"
        echo -e "${GREEN}9${NC} To Images | ${GREEN}0${NC} Back | ${GREEN}h${NC} Help"
        
        local c=""
        while true; do
            if [ $ram_state -eq 0 ] && [ -f "$RAM_CACHE_FILE" ]; then break; fi
            if read -t 1 -n 1 c; then break; fi
        done
        
        case $c in
            1) batch_action "cnt" "stop" ;;
            2) batch_action "cnt" "start" ;;
            3) batch_action "cnt" "rm" ;;
            4) batch_action "cnt" "kill" ;;
            5|/) set_filter ;;
            r) force_refresh ;;
            9) rm -f "$RAM_CACHE_FILE"; return 2 ;;
            h|?) show_help_modal ;;
            n) [ $CONTAINERS_CURRENT_PAGE -lt $CONTAINERS_TOTAL_PAGES ] && ((CONTAINERS_CURRENT_PAGE++)) ;;
            p) [ $CONTAINERS_CURRENT_PAGE -gt 1 ] && ((CONTAINERS_CURRENT_PAGE--)) ;;
            0) rm -f "$RAM_CACHE_FILE"; return 0 ;;
        esac
    done
}

cleanup_menu() {
    while true; do
        print_header
        echo -e "${YELLOW}🧹 Docker Cleanup Menu${NC}"
        echo -e "${CYAN}1.${NC} Remove unused images (prune -a)"
        echo -e "${CYAN}2.${NC} Remove dangling images (prune)"
        echo -e "${CYAN}3.${NC} Clear build cache (buildx prune)"
        echo -e "${CYAN}4.${NC} Remove unused volumes (Volume prune)"
        echo -e "${CYAN}5.${NC} Remove unused networks (Network prune)"
        echo -e "${RED}6. Full system cleanup (System prune -a)${NC}"
        echo -e "${GREEN}0. Back${NC}"
        safe_read "🎯 Select: " c 1
        case $c in
            1) docker image prune -a -f; force_refresh; press_enter ;;
            2) docker image prune -f; force_refresh; press_enter ;;
            3) docker buildx prune -f; press_enter ;;
            4) docker volume prune -f; press_enter ;;
            5) docker network prune -f; press_enter ;;
            6) docker system prune -a -f; force_refresh; press_enter ;;
            0) return ;;
        esac
    done
}

# --- MAIN LOOP ---
check_dependencies
NEXT_MENU="main"
while true; do
    if [ "$NEXT_MENU" == "main" ]; then
        print_header
        echo -e "${CYAN}1.${NC} 📦 Images"
        echo -e "${CYAN}2.${NC} 🐳 Containers"
        echo -e "${CYAN}3.${NC} 🧹 Extended Cleanup"
        echo -e "${GREEN}h.${NC} ℹ️ Help"
        echo -e "${RED}0. 🚪 Exit${NC}"
        safe_read "Select: " c 1
        case $c in
            1) NEXT_MENU="images" ;;
            2) NEXT_MENU="containers" ;;
            3) cleanup_menu ;;
            h|?) show_help_modal ;;
            0) cleanup_exit; exit 0 ;;
        esac
    elif [ "$NEXT_MENU" == "images" ]; then
        menu_images; ret=$?; if [ $ret -eq 2 ]; then NEXT_MENU="containers"; else NEXT_MENU="main"; fi
    elif [ "$NEXT_MENU" == "containers" ]; then
        menu_containers; ret=$?; if [ $ret -eq 2 ]; then NEXT_MENU="images"; else NEXT_MENU="main"; fi
    fi
done
