#!/bin/bash

# ==========================================
# Simple Linux Docker Manager v1.0.3
# (High Performance & Security Edition)
# ==========================================

# Global Constants
readonly PAGE_SIZE=50

# Global variables for pagination
declare -g IMAGES_CURRENT_PAGE=1
declare -g IMAGES_TOTAL_PAGES=1
declare -g IMAGES_TOTAL_ITEMS=0
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g CONTAINERS_TOTAL_PAGES=1
declare -g CONTAINERS_TOTAL_ITEMS=0

# Menu Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# --- SECURITY AND CHECK BLOCK ---

# Cleanup function on exit (restores terminal settings)
cleanup_exit() {
    stty echo 2>/dev/null
    echo -e "\n${CYAN}👋 Script execution finished.${NC}"
}

# Trap signals (EXIT, Ctrl+C, Termination)
trap cleanup_exit EXIT SIGINT SIGTERM

# Check dependencies before running
check_dependencies() {
    local missing=0
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Error: Docker not found. Install Docker to run the script.${NC}"
        missing=1
    fi

    if [ $missing -eq 0 ] && ! docker ps &> /dev/null; then
        echo -e "${RED}❌ Error: Docker command execution rights missing.${NC}"
        echo -e "${YELLOW}💡 Tip: Run the script using sudo or add your user to the docker group.${NC}"
        missing=1
    fi
    
    # Check Bash version for associative arrays (requires bash 4.0+)
    if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
        echo -e "${RED}❌ Error: Bash version 4.0 or higher is required (for performance optimization).${NC}"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# --- UTILITIES ---

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
        
        if [ -n "${!var_name}" ]; then
            local extra_chars
            IFS= read -r -t 0.1 -n 1000 extra_chars || true
        fi
        
        if [[ "${!var_name}" =~ ^[[:cntrl:]] ]]; then
            echo -e "${RED}❌ Invalid input. Use only numbers and letters.${NC}"
            continue
        fi
        break
    done
    return 0
}

size_to_bytes() {
    local size=$1
    if [ -z "$size" ]; then echo "0"; return; fi
    size=$(echo "$size" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    if [[ $size == *"gib" ]]; then local num=$(echo "$size" | sed 's/gib//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}')"
    elif [[ $size == *"gb" ]]; then local num=$(echo "$size" | sed 's/gb//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000 * 1000 * 1000}')"
    elif [[ $size == *"mib" ]]; then local num=$(echo "$size" | sed 's/mib//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024 * 1024}')"
    elif [[ $size == *"mb" ]]; then local num=$(echo "$size" | sed 's/mb//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000 * 1000}')"
    elif [[ $size == *"kib" ]]; then local num=$(echo "$size" | sed 's/kib//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1024}')"
    elif [[ $size == *"kb" ]]; then local num=$(echo "$size" | sed 's/kb//'); echo "$(echo "$num" | awk '{printf "%.0f", $1 * 1000}')"
    elif [[ $size == *"b" ]]; then local num=$(echo "$size" | sed 's/b//'); echo "$(echo "$num" | awk '{printf "%.0f", $1}')"
    else echo "0"; fi
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
    # Added English 'y' check
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || [ "$confirm" = "д" ] || [ "$confirm" = "Д" ]; then return 0; else return 1; fi
}

check_cancel() {
    local input="$1"
    if [[ "$input" == "c" || "$input" == "C" || "$input" == "с" || "$input" == "С" ]]; then return 0; else return 1; fi
}

# --- STATS FUNCTIONS (OPTIMIZED) ---

get_total_containers_memory() {
    local total_memory_bytes=0
    if command -v docker >/dev/null 2>&1; then
        while IFS= read -r mem_usage; do
            if [ -n "$mem_usage" ] && [ "$mem_usage" != "MEM USAGE" ]; then
                local mem_value=$(echo "$mem_usage" | cut -d'/' -f1 | tr -d ' ')
                local mem_bytes=$(size_to_bytes "$mem_value")
                total_memory_bytes=$((total_memory_bytes + mem_bytes))
            fi
        done < <(docker stats --no-stream --format "table {{.MemUsage}}" 2>/dev/null | tail -n +2)
    fi
    echo "$total_memory_bytes"
}

show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📦 DOCKER IMAGES                        📊 SYSTEM STATISTICS                    ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local disk_info=$(df / | tail -1 2>/dev/null)
    if [ -n "$disk_info" ]; then
        local disk_total=$(echo "$disk_info" | awk '{print $2}')
        local disk_used=$(echo "$disk_info" | awk '{print $3}')
        local disk_available=$(echo "$disk_info" | awk '{print $4}')
        local disk_total_bytes=$((disk_total * 1024))
        local disk_used_bytes=$((disk_used * 1024))
        local disk_available_bytes=$((disk_available * 1024))
        
        local images_info=$(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null | grep -w "Images")
        local total_images_size="0B"
        
        if [ -n "$images_info" ]; then
            total_images_size=$(echo "$images_info" | awk '{print $2}')
        else
            # Fallback
            local total_images_bytes=0
            while IFS='|' read -r id repository tag size created; do
                if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
                    local img_bytes=$(size_to_bytes "$size")
                    total_images_bytes=$((total_images_bytes + img_bytes))
                fi
            done < <(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2 2>/dev/null)
            total_images_size=$(format_bytes $total_images_bytes)
        fi
        
        local total_images_count=$(docker images -q 2>/dev/null | wc -l)
        local total_images_bytes=$(size_to_bytes "$total_images_size")
        local images_percent=0
        if [ "$disk_total_bytes" -gt 0 ] && [ "$total_images_bytes" -gt 0 ]; then
            images_percent=$(safe_calc "scale=1; $total_images_bytes * 100 / $disk_total_bytes")
        fi
        
        echo -e "${CYAN}║ ${GREEN}• Images:${NC} $total_images_size ${CYAN}• Disk Used:${NC} $(format_bytes $disk_used_bytes)/$(format_bytes $disk_total_bytes) ${CYAN}• Free:${NC} $(format_bytes $disk_available_bytes) "
        echo -e "${CYAN}║ ${GREEN}• Disk used by images:${NC} ${images_percent}% ${CYAN}• Total Images:${NC} $total_images_count "
    else
        echo -e "${CYAN}║ ${RED}Failed to get disk information${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🐳 DOCKER CONTAINERS                     📊 SYSTEM STATISTICS                   ║${NC}"
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
    
    local total_ram_display=$(format_bytes $total_ram)
    local available_ram_display=$(format_bytes $available_ram)
    local containers_memory_display=$(format_bytes $total_memory_bytes)
    
    echo -e "${CYAN}║ ${GREEN}• Containers Memory:${NC} $containers_memory_display ${CYAN}• RAM Used:${NC} ${containers_ram_percent}% ${CYAN} • Available RAM:${NC} $available_ram_display ${CYAN}• Total RAM:${NC} $total_ram_display"
    echo -e "${CYAN}║ ${GREEN}• Running:${NC} $running_containers ${CYAN}• Stopped:${NC} $stopped_containers ${CYAN} • Total:${NC} $total_containers"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           Simple Linux Docker Manager v1.0.3     ║"
    echo "║          HIGH PERFORMANCE EDITION                ║"
    echo "║          https://github.com/rjohny55/            ║"
    echo "║           Simple-Linux-Docker-Manager            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    safe_read "" dummy_input
}

# --- MAIN LIST FUNCTIONS ---

show_images() {
    local page=${1:-1}
    local start_index=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end_index=$(( page * PAGE_SIZE ))
    
    echo -e "${YELLOW}📦 List of Docker Images (Page $page):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    local display_counter=0
    declare -g image_ids=()
    declare -g image_names=()
    declare -g image_tags=()
    
    local all_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    local total_images=$(echo "$all_images" | wc -l)
    local total_pages=$(( (total_images + PAGE_SIZE - 1) / PAGE_SIZE ))

    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
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
        echo -e "${CYAN}📄 Page ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Total Images: ${YELLOW}$total_images${NC}"
        echo -e "${CYAN}🔍 Use navigation in the menu to switch pages${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 No Docker Images found.${NC}"
        return 1
    fi
    
    IMAGES_CURRENT_PAGE=$page
    IMAGES_TOTAL_PAGES=$total_pages
    IMAGES_TOTAL_ITEMS=$total_images
    
    return 0
}

# OPTIMIZED FUNCTION (BATCH PROCESSING)
show_containers() {
    local page=${1:-1}
    local start_index=$(( (page - 1) * PAGE_SIZE + 1 ))
    local end_index=$(( page * PAGE_SIZE ))
    
    echo -e "${YELLOW}🐳 List of Docker Containers (Page $page):${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # 1. Batch IP loading (Solves N+1 for Inspect)
    declare -A ip_map
    if [ -n "$(docker ps -aq)" ]; then
        # Get Full ID and IP in one command for all containers. Map key is the Short ID (12 chars).
        while IFS='|' read -r full_id ip; do
            short_id="${full_id:0:12}"
            ip_map[$short_id]="$ip"
        done < <(docker inspect --format '{{.ID}}|{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) 2>/dev/null)
    fi

    # 2. Batch Memory loading (Solves N+1 for Stats)
    declare -A mem_map
    if [ -n "$(docker ps -q)" ]; then
        # Stats only works for running containers. ID is usually Short ID.
        while IFS=':' read -r id mem; do
            # Clean up output from extra characters
            mem_clean=$(echo "$mem" | cut -d'/' -f1 | tr -d ' ')
            mem_map[$id]="$mem_clean"
        done < <(docker stats --no-stream --format "{{.ID}}:{{.MemUsage}}" $(docker ps -q) 2>/dev/null)
    fi
    
    local counter=1
    local display_counter=0
    declare -g container_ids=()
    declare -g container_names=()
    declare -g container_status=()
    
    # Getting the list. {{.ID}} in docker ps format gives Short ID (12 chars) by default.
    local all_containers=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}" | tail -n +2)
    local total_containers=$(echo "$all_containers" | wc -l)
    local total_pages=$(( (total_containers + PAGE_SIZE - 1) / PAGE_SIZE ))
    
    printf "${GREEN}%-3s${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${BLUE}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
        "No" "CONTAINER ID" "NAMES" "STATUS" "IP" "MEMORY"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    while IFS='|' read -r id image status names; do
        if [ -n "$id" ] && [ "$id" != "CONTAINER ID" ]; then
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                container_ids[$display_counter]=$id
                container_names[$display_counter]="$names"
                container_status[$display_counter]="$status"
                
                # Using cached data (Instant access)
                local ip="${ip_map[$id]}"
                [ -z "$ip" ] && ip="-"
                
                local memory="${mem_map[$id]}"
                [ -z "$memory" ] && memory="-"
                
                # Determine status color
                status_color=$GREEN
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
        echo -e "${CYAN}📄 Page ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Total containers: ${YELLOW}$total_containers${NC}"
        echo -e "${CYAN}🔍 Use navigation in the menu to switch pages${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 No Docker Containers found.${NC}"
        return 1
    fi
    
    CONTAINERS_CURRENT_PAGE=$page
    CONTAINERS_TOTAL_PAGES=$total_pages
    CONTAINERS_TOTAL_ITEMS=$total_containers
    
    return 0
}

# --- IMAGE OPERATIONS ---

update_selected_image() {
    echo -e "${YELLOW}🔄 Updating image from repository${NC}"
    echo -e "${CYAN}Enter the image number to update:${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 10; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Operation cancelled.${NC}"; return 1; fi
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then echo -e "${RED}❌ Invalid number.${NC}"; return 1; fi
    if [ -z "${image_ids[$input]}" ]; then echo -e "${RED}❌ Invalid image number.${NC}"; return 1; fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Cannot update an image without a repository name.${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}🔄 Pulling image: ${CYAN}$full_image_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    if docker pull "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Image updated successfully${NC}\n"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$image_name" | head -1
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Error updating image${NC}"
    fi
}

push_selected_image() {
    echo -e "${YELLOW}📤 Pushing image to repository${NC}"
    echo -e "${CYAN}Enter the image number to push:${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 10; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Operation cancelled.${NC}"; return 1; fi
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then echo -e "${RED}❌ Invalid number.${NC}"; return 1; fi
    if [ -z "${image_ids[$input]}" ]; then echo -e "${RED}❌ Invalid image number.${NC}"; return 1; fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Cannot push an image without a repository name.${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}📤 Preparing to push: ${CYAN}$full_image_name${NC}\n"
    echo -e "${YELLOW}🔐 Enter credentials:${NC}"
    echo -e "${CYAN}Username:${NC}"
    if ! safe_read "> " docker_username 50; then return 1; fi
    echo -e "${CYAN}Password (or token):${NC}"
    if ! safe_read -s "> " docker_password 200; then return 1; fi
    
    echo -e "\n${YELLOW}🔐 Authenticating...${NC}"
    if docker login --username "$docker_username" --password-stdin <<< "$docker_password"; then
        echo -e "${GREEN}✅ Authentication successful${NC}"
    else
        echo -e "${RED}❌ Authentication error${NC}"; return 1
    fi
    
    echo -e "\n${YELLOW}📤 Pushing image...${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    if docker push "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Image pushed successfully${NC}"
        docker logout; echo -e "${YELLOW}🔒 Logged out${NC}"
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Error pushing image${NC}"
        docker logout; echo -e "${YELLOW}🔒 Logged out${NC}"
    fi
}

show_images_menu() {
    echo -e "${CYAN}🛠️  Image Operations:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 🗑️  Delete selected images${NC}"
    echo -e "${YELLOW}2. 🧹  Delete unused images${NC}"
    echo -e "${RED}3. 💥  Delete ALL images${NC}"
    echo -e "${ORANGE}4. 🔍  Delete images with <none> tag${NC}"
    echo -e "${PURPLE}5. 🛠️  Delete Docker build cache${NC}"
    echo -e "${BLUE}6. 🔄  Refresh image list${NC}"
    echo -e "${CYAN}7. 🔄  Update selected image (pull)${NC}"
    echo -e "${GREEN}8. 📤  Push selected image (push)${NC}"
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ] && echo -e "${CYAN}9. 📄  Next page${NC}"
        [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ] && echo -e "${CYAN}10. 📄  Previous page${NC}"
    fi
    echo -e "${GREEN}11. 🐳  Go to Container management${NC}"
    echo -e "${GREEN}0. 🏠  Exit to Main Menu${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Select operation: ${NC}" choice 2
}

show_containers_menu() {
    echo -e "${CYAN}🛠️  Container Operations:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. ⏹️   Stop selected containers${NC}"
    echo -e "${YELLOW}2. 🗑️   Delete selected containers${NC}"
    echo -e "${RED}3. 💀   Stop and Delete selected containers${NC}"
    echo -e "${GREEN}4. ▶️   Start selected containers${NC}"
    echo -e "${BLUE}5. 🔄   Refresh container list${NC}"
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ] && echo -e "${CYAN}6. 📄  Next page${NC}"
        [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ] && echo -e "${CYAN}7. 📄  Previous page${NC}"
    fi
    echo -e "${GREEN}8. 📦   Go to Image management${NC}"
    echo -e "${GREEN}0. 🏠   Exit to Main Menu${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Select operation: ${NC}" choice 1
}

# --- ARRAY ACTIONS ---

delete_selected_images() {
    echo -e "${YELLOW}🗑️ Enter image numbers (space separated):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Cancelled${NC}"; return 1; fi
    [ -z "$input" ] && return 1
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}🗑️ Deleting:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${image_ids[$num]}" ] && echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
    done
    
    safe_read "Are you sure? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${image_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Deleting ${image_names[$num]}...${NC}"
                docker rmi -f "${image_ids[$num]}" 2>/dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Error${NC}"
            fi
        done
        return 0
    fi
    echo -e "${GREEN}✅ Cancelled${NC}"; return 1
}

stop_selected_containers() {
    echo -e "${YELLOW}⏹️ Enter container numbers (space separated):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Cancelled${NC}"; return 1; fi
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}⏹️ Stopping:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${container_ids[$num]}" ] && echo -e "  ${RED}■${NC} ${container_names[$num]}"
    done
    
    safe_read "Are you sure? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}⏹️ Stopping ${container_names[$num]}...${NC}"
                docker stop "${container_ids[$num]}" 2>/dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Error${NC}"
            fi
        done
        return 0
    fi
    echo -e "${GREEN}✅ Cancelled${NC}"; return 1
}

start_selected_containers() {
    echo -e "${YELLOW}▶️ Enter container numbers (space separated):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Cancelled${NC}"; return 1; fi
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}▶️ Starting:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${container_ids[$num]}" ] && echo -e "  ${GREEN}▶${NC} ${container_names[$num]}"
    done
    
    safe_read "Are you sure? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}▶️ Starting ${container_names[$num]}...${NC}"
                docker start "${container_ids[$num]}" 2>/dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Error${NC}"
            fi
        done
        return 0
    fi
    echo -e "${GREEN}✅ Cancelled${NC}"; return 1
}

delete_selected_containers() {
    echo -e "${YELLOW}🗑️ Enter container numbers (space separated):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Cancelled${NC}"; return 1; fi
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${YELLOW}🗑️ Deleting:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${container_ids[$num]}" ] && echo -e "  ${RED}×${NC} ${container_names[$num]}"
    done
    
    safe_read "Are you sure? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Deleting ${container_names[$num]}...${NC}"
                docker rm "${container_ids[$num]}" 2>/dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Error${NC}"
            fi
        done
        return 0
    fi
    echo -e "${GREEN}✅ Cancelled${NC}"; return 1
}

stop_and_delete_containers() {
    echo -e "${YELLOW}💀 Enter numbers for stop+delete (space separated):${NC}"
    if ! safe_read "> " input 50; then return 1; fi
    if check_cancel "$input"; then echo -e "${GREEN}✅ Cancelled${NC}"; return 1; fi
    
    read -a selected_numbers <<< "$input"
    echo -e "\n${RED}💀 Destroying:${NC}"
    for num in "${selected_numbers[@]}"; do
        [ -n "${container_ids[$num]}" ] && echo -e "  ${RED}☠${NC} ${container_names[$num]}"
    done
    
    safe_read "Are you sure? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}💀 Stop+Delete ${container_names[$num]}...${NC}"
                docker stop "${container_ids[$num]}" 2>/dev/null
                docker rm "${container_ids[$num]}" 2>/dev/null && echo -e "${GREEN}✅ OK${NC}" || echo -e "${RED}❌ Error${NC}"
            fi
        done
        return 0
    fi
    echo -e "${GREEN}✅ Cancelled${NC}"; return 1
}

# --- CLEANUP ---

delete_unused_images() {
    echo -e "${YELLOW}🧹 Deleting unused images...${NC}"
    echo -e "${RED}⚠️  Warning: All images currently not used by running containers will be deleted!${NC}"
    echo -e "${CYAN}(This frees space, but new container runs might require re-downloading images)${NC}"
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        echo -e "${YELLOW}🚀 Performing cleanup...${NC}"
        if docker image prune -a -f; then
            echo -e "${GREEN}✅ Unused images deleted.${NC}"
        else
            echo -e "${RED}❌ Error during deletion.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
    fi
}

delete_all_images() {
    echo -e "${RED}🚨 DANGER: Deleting ALL images!${NC}"
    safe_read "Enter 'DELETE' to confirm: " confirm 10
    if [ "$confirm" = "DELETE" ]; then
        docker rmi -f $(docker images -q) 2>/dev/null && echo -e "${GREEN}✅ Deleted${NC}" || echo -e "${RED}❌ Error${NC}"
    else
        echo -e "${GREEN}✅ Cancelled${NC}"
    fi
}

delete_none_images() {
    echo -e "${YELLOW}🔍 Searching for <none> images...${NC}"
    if [ -z "$(docker images -f "dangling=true" -q)" ]; then echo -e "${GREEN}✅ Clean${NC}"; return; fi
    
    docker images -f "dangling=true" --format "table {{.ID}}\t{{.Size}}\t{{.CreatedAt}}"
    safe_read "Delete all <none> images? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        docker image prune -f && echo -e "${GREEN}✅ Deleted${NC}" || echo -e "${RED}❌ Error${NC}"
    else
        echo -e "${GREEN}✅ Cancelled${NC}"
    fi
}

delete_build_cache() {
    echo -e "${CYAN}🔍 Scanning cache...${NC}"
    docker buildx prune --dry-run
    safe_read "Delete cache? (y/N): " confirm 1
    if check_confirmation "$confirm"; then
        docker buildx prune -f && echo -e "${GREEN}✅ Cache cleared${NC}"
    else
        echo -e "${GREEN}✅ Cancelled${NC}"
    fi
}

cleanup_docker_system() {
    print_header
    echo -e "${YELLOW}🧹 Docker System Cleanup:${NC}"
    echo -e "${GREEN}1. 🗑️   Delete unused images${NC}"
    echo -e "${ORANGE}2. 🔍   Delete images with <none> tag${NC}"
    echo -e "${PURPLE}3. 🛠️   Delete Docker build cache${NC}"
    echo -e "${RED}4. 💥   Full System Prune${NC}"
    echo -e "${GREEN}0. 🏠   Back${NC}"
    safe_read "${CYAN}🎯 Choice: ${NC}" choice 1
    
    case $choice in
        1) delete_unused_images; press_enter_to_continue ;;
        2) delete_none_images; press_enter_to_continue ;;
        3) delete_build_cache; press_enter_to_continue ;;
        4)
            echo -e "${RED}🚨 Full System Prune (prune -a)!${NC}"
            safe_read "Enter 'CLEAN' to confirm: " confirm 10
            if [ "$confirm" = "CLEAN" ]; then
                docker system prune -a -f && echo -e "${GREEN}✅ Done${NC}"
            else
                echo -e "${GREEN}✅ Cancelled${NC}"
            fi
            press_enter_to_continue
            ;;
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
            *) echo -e "${RED}❌ Invalid choice${NC}"; sleep 0.5 ;;
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
            *) echo -e "${RED}❌ Invalid choice${NC}"; sleep 0.5 ;;
        esac
    done
}

show_main_menu() {
    print_header
    echo -e "${CYAN}🏠 Main Menu:${NC}"
    echo -e "${GREEN}1. 📦  Show All Images${NC}"
    echo -e "${GREEN}2. 🐳  Show All Containers${NC}"
    echo -e "${YELLOW}3. 🧹  Docker System Cleanup${NC}"
    echo -e "${GREEN}0. 🚪  Exit${NC}"
    safe_read "${CYAN}🎯 Choice: ${NC}" choice 1
}

# ==========================================
# EXECUTION
# ==========================================
check_dependencies
while true; do
    show_main_menu
    case $choice in
        1) images_submenu && continue || containers_submenu ;;
        2) containers_submenu && continue || images_submenu ;;
        3) cleanup_docker_system ;;
        0) exit 0 ;;
        *) echo -e "${RED}❌ Error${NC}"; sleep 0.5 ;;
    esac
done
