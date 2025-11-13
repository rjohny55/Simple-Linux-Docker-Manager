#!/bin/bash

# Global variables for pagination
declare -g IMAGES_CURRENT_PAGE=1
declare -g IMAGES_TOTAL_PAGES=1
declare -g IMAGES_TOTAL_ITEMS=0
declare -g CONTAINERS_CURRENT_PAGE=1
declare -g CONTAINERS_TOTAL_PAGES=1
declare -g CONTAINERS_TOTAL_ITEMS=0

# Colors for menu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Function for safe input reading with hidden input support
safe_read() {
    local secret=0
    local timeout=0
    local timeout_value=0
    
    # Check flags
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
            # Hidden input for passwords
            stty -echo
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
            stty echo
            echo ""  # Add new line after hidden input
        elif [ $timeout -eq 1 ]; then
            # Input with timeout
            if IFS= read -r -t $timeout_value -n "$max_chars" "$var_name"; then
                local ret=0
            else
                local ret=1
            fi
        else
            # Regular input
            IFS= read -r -n "$max_chars" "$var_name"
            local ret=$?
        fi
        
        # Handle Ctrl+C
        if [ $ret -ne 0 ]; then
            echo ""
            echo -e "${YELLOW}⚠️  Operation cancelled by user${NC}"
            return 1
        fi
        
        # Clear input buffer if there are extra characters
        if [ -n "${!var_name}" ]; then
            local extra_chars
            IFS= read -r -t 0.1 -n 1000 extra_chars || true
        fi
        
        # Ignore mouse escape sequences
        if [[ "${!var_name}" =~ ^[[:cntrl:]] ]]; then
            echo -e "${RED}❌ Invalid input. Use only numbers and letters.${NC}"
            continue
        fi
        
        break
    done
    return 0
}

# Function to convert size to bytes
size_to_bytes() {
    local size=$1
    if [ -z "$size" ]; then
        echo "0"
        return
    fi
    
    # Remove spaces and convert to lowercase
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

# Function to format bytes to human-readable format
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
        # Simple calculation if bc is not installed
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

# Function to get container IP
get_container_ip() {
    local container_id=$1
    local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id" 2>/dev/null)
    if [ -z "$ip" ] || [ "$ip" = "<no value>" ]; then
        echo "-"
    else
        echo "$ip"
    fi
}

# Function to get container memory usage - SIMPLIFIED
get_container_memory() {
    local container_id=$1
    local status=$2
    
    # Don't show memory usage for stopped containers
    if [[ "$status" != *"Up"* ]]; then
        echo "-"
        return
    fi
    
    # Get memory usage via docker stats
    local memory=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" 2>/dev/null | cut -d'/' -f1 | tr -d ' ')
    
    if [ -z "$memory" ] || [ "$memory" = "0B" ]; then
        echo "-"
    else
        echo "$memory"
    fi
}

# Function to get general memory statistics - SIMPLIFIED
get_memory_stats() {
    local total_ram=0
    local available_ram=0
    local used_ram=0
    
    # Get system information via /proc/meminfo
    if [ -f /proc/meminfo ]; then
        total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        available_ram=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        total_ram=$((total_ram * 1024))  # Convert kB to bytes
        available_ram=$((available_ram * 1024))  # Convert kB to bytes
        used_ram=$((total_ram - available_ram))
    else
        # Alternative method via free
        local memory_info=$(free -b 2>/dev/null | grep Mem:)
        if [ -n "$memory_info" ]; then
            total_ram=$(echo "$memory_info" | awk '{print $2}')
            used_ram=$(echo "$memory_info" | awk '{print $3}')
            available_ram=$(echo "$memory_info" | awk '{print $7}')
        fi
    fi
    
    echo "$total_ram $available_ram $used_ram"
}

# Function to get total container memory usage - FIXED
get_total_containers_memory() {
    local total_memory_bytes=0
    
    # Get memory usage for each running container
    if command -v docker >/dev/null 2>&1; then
        # Use docker stats to get memory usage of all running containers
        while IFS= read -r mem_usage; do
            if [ -n "$mem_usage" ] && [ "$mem_usage" != "MEM USAGE" ]; then
                # Extract only memory usage value (before '/')
                local mem_value=$(echo "$mem_usage" | cut -d'/' -f1 | tr -d ' ')
                local mem_bytes=$(size_to_bytes "$mem_value")
                total_memory_bytes=$((total_memory_bytes + mem_bytes))
            fi
        done < <(docker stats --no-stream --format "table {{.MemUsage}}" 2>/dev/null | tail -n +2)
    fi
    
    echo "$total_memory_bytes"
}

# Function for safe calculation with bc
safe_calc() {
    local expression=$1
    if command -v bc >/dev/null 2>&1; then
        echo "$expression" | bc 2>/dev/null || echo "0"
    else
        # Simple replacement if bc is not installed
        local result=$(echo "$expression" | sed 's/\.//g' | awk '{print int($1)}')
        echo "${result:-0}"
    fi
}

# Function to check confirmation with Russian layout support
check_confirmation() {
    local confirm="$1"
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || [ "$confirm" = "д" ] || [ "$confirm" = "Д" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check cancellation with Russian layout support
check_cancel() {
    local input="$1"
    if [[ "$input" == "c" || "$input" == "C" || "$input" == "с" || "$input" == "С" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to display disk statistics (for images) - FIXED
show_disk_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📦 DOCKER IMAGES                       📊 SYSTEM STATISTICS                     ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Get disk statistics
    local disk_info=$(df / | tail -1 2>/dev/null)
    if [ -n "$disk_info" ]; then
        local disk_total=$(echo "$disk_info" | awk '{print $2}')
        local disk_used=$(echo "$disk_info" | awk '{print $3}')
        local disk_available=$(echo "$disk_info" | awk '{print $4}')
        local disk_total_bytes=$((disk_total * 1024))
        local disk_used_bytes=$((disk_used * 1024))
        local disk_available_bytes=$((disk_available * 1024))
        
        # FIX: Use docker system df to get REAL image size
        local images_info=$(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null | grep -w "Images")
        local total_images_size="0B"
        
        if [ -n "$images_info" ]; then
            total_images_size=$(echo "$images_info" | awk '{print $2}')
        else
            # Fallback: manual calculation if docker system df doesn't work
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
        
        # Convert image size to bytes for percentage calculation
        local total_images_bytes=$(size_to_bytes "$total_images_size")
        
        local images_percent=0
        if [ "$disk_total_bytes" -gt 0 ] && [ "$total_images_bytes" -gt 0 ]; then
            images_percent=$(safe_calc "scale=1; $total_images_bytes * 100 / $disk_total_bytes")
        fi
        
        # FIX: Use real size from docker system df
        echo -e "${CYAN}║ ${GREEN}• Images:${NC} $total_images_size ${CYAN}• Disk:${NC} $(format_bytes $disk_used_bytes)/$(format_bytes $disk_total_bytes) ${CYAN}• Free:${NC} $(format_bytes $disk_available_bytes) "
        echo -e "${CYAN}║ ${GREEN}• Used by images:${NC} ${images_percent}% ${CYAN}• Total images:${NC} $total_images_count "
    else
        echo -e "${CYAN}║ ${RED}Failed to get disk information${NC}"
    fi
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to display container statistics - FIXED BOUNDARIES
show_containers_stats() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🐳 DOCKER CONTAINERS                   📊 SYSTEM STATISTICS                      ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Get general container information
    local total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    local running_containers=$(docker ps -q 2>/dev/null | wc -l)
    local stopped_containers=$((total_containers - running_containers))
    
    # Get total container memory usage
    local total_memory_bytes=$(get_total_containers_memory)
    
    # Get general system memory statistics
    read -r total_ram available_ram used_ram <<< "$(get_memory_stats)"
    
    local containers_ram_percent=0
    if [ "$total_ram" -gt 0 ] && [ "$total_memory_bytes" -gt 0 ]; then
        containers_ram_percent=$(safe_calc "scale=1; $total_memory_bytes * 100 / $total_ram")
    fi
    
    # Format sizes for display
    local total_ram_display=$(format_bytes $total_ram)
    local available_ram_display=$(format_bytes $available_ram)
    local containers_memory_display=$(format_bytes $total_memory_bytes)
    
    # Simple two-line layout without closing borders
    echo -e "${CYAN}║ ${GREEN}• Containers:${NC} $containers_memory_display ${CYAN}• RAM:${NC} ${containers_ram_percent}% ${CYAN}• Free:${NC} $available_ram_display ${CYAN}• Total RAM:${NC} $total_ram_display"
    echo -e "${CYAN}║ ${GREEN}• Running:${NC} $running_containers ${CYAN}• Stopped:${NC} $stopped_containers ${CYAN}• Total:${NC} $total_containers"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to display header
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           Simple Linux Docker Manager v.1.0.1    ║"
    echo "║           DOCKER IMAGES AND CONTAINERS           ║"
    echo "║          https://github.com/rjohny55/            ║"
    echo "║           Simple-Linux-Docker-Manager            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Function to wait for Enter key press
press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    safe_read "" dummy_input
}

# Function to show all images with creation date and pagination
show_images() {
    local page=${1:-1}
    local page_size=50
    local start_index=$(( (page - 1) * page_size + 1 ))
    local end_index=$(( page * page_size ))
    
    echo -e "${YELLOW}📦 Docker images list (Page $page):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    local display_counter=0
    declare -g image_ids=()
    declare -g image_names=()
    declare -g image_tags=()
    
    # Get all images
    local all_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    local total_images=$(echo "$all_images" | wc -l)
    local total_pages=$(( (total_images + page_size - 1) / page_size ))

    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            # Pagination: show only items for current page
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                image_ids[$display_counter]=$id
                image_names[$display_counter]="$repository"
                image_tags[$display_counter]="$tag"
                
                # Format date (keep only date, remove time)
                short_created=$(echo "$created" | cut -d' ' -f1)
                printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-25s${NC} ${RED}%-10s${NC} ${ORANGE}%s${NC}\n" \
                    "$display_counter" "${repository:0:30}" "${tag:0:25}" "$size" "$short_created"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_images"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Display page navigation if needed
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Page ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Total images: ${YELLOW}$total_images${NC}"
        echo -e "${CYAN}🔍 Use menu navigation to switch between pages${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 No Docker images.${NC}"
        return 1
    fi
    
    # Save pagination information for use in menu
    IMAGES_CURRENT_PAGE=$page
    IMAGES_TOTAL_PAGES=$total_pages
    IMAGES_TOTAL_ITEMS=$total_images
    
    return 0
}

# Function to show all containers with pagination - SIMPLIFIED
show_containers() {
    local page=${1:-1}
    local page_size=50
    local start_index=$(( (page - 1) * page_size + 1 ))
    local end_index=$(( page * page_size ))
    
    echo -e "${YELLOW}🐳 Docker Containers List (Page $page):${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    local display_counter=0
    declare -g container_ids=()
    declare -g container_names=()
    declare -g container_status=()
    
    # Get total number of containers for pagination
    local all_containers=$(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}" | tail -n +2)
    local total_containers=$(echo "$all_containers" | wc -l)
    local total_pages=$(( (total_containers + page_size - 1) / page_size ))
    
    # Table header - adjusted widths
    printf "${GREEN}%-3s${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${BLUE}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
        "No" "CONTAINER ID" "NAMES" "STATUS" "IP" "MEMORY"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    while IFS='|' read -r id image status names; do
        if [ -n "$id" ] && [ "$id" != "CONTAINER ID" ]; then
            # Pagination: show only items for current page
            if [ $counter -ge $start_index ] && [ $counter -le $end_index ]; then
                container_ids[$display_counter]=$id
                container_names[$display_counter]="$names"
                container_status[$display_counter]="$status"
                
                # Get IP and memory for container
                local ip=$(get_container_ip "$id")
                local memory=$(get_container_memory "$id" "$status")
                
                # Determine status color
                status_color=$GREEN
                if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"Dead"* ]]; then
                    status_color=$RED
                elif [[ "$status" == *"Up"* ]]; then
                    status_color=$GREEN
                else
                    status_color=$YELLOW
                fi
                
                # Adjusted row formatting with more space for STATUS
                printf "${GREEN}%-3d${NC} ${PURPLE}%-12s${NC} ${CYAN}%-22s${NC} ${status_color}%-21s${NC} ${YELLOW}%-15s${NC} ${RED}%-8s${NC}\n" \
                    "$display_counter" "${id:0:12}" "${names:0:20}" "${status:0:19}" "$ip" "$memory"
                
                ((display_counter++))
            fi
            ((counter++))
        fi
    done <<< "$all_containers"
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Show page navigation if needed
    if [ $total_pages -gt 1 ]; then
        echo -e "${CYAN}📄 Page ${YELLOW}$page${CYAN} of ${YELLOW}$total_pages${CYAN}. Total containers: ${YELLOW}$total_containers${NC}"
        echo -e "${CYAN}🔍 Use menu navigation to switch between pages${NC}"
    fi
    
    echo ""
    
    if [ $display_counter -eq 0 ]; then
        echo -e "${RED}📭 No Docker containers found.${NC}"
        return 1
    fi
    
    # Save pagination information for use in menu
    CONTAINERS_CURRENT_PAGE=$page
    CONTAINERS_TOTAL_PAGES=$total_pages
    CONTAINERS_TOTAL_ITEMS=$total_containers
    
    return 0
}

# Function to update selected image - NEW FUNCTION
update_selected_image() {
    echo -e "${YELLOW}🔄 Updating image from repository${NC}"
    echo -e "${CYAN}Enter image number to update:${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 10; then
        return 1
    fi
    
    # Check for cancellation
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Check if number
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid number. Enter a number.${NC}"
        return 1
    fi
    
    if [ -z "${image_ids[$input]}" ]; then
        echo -e "${RED}❌ Invalid image number.${NC}"
        return 1
    fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    # Check that image has repository (not <none>)
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Cannot update image without repository.${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}🔄 Updating image: ${CYAN}$full_image_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Perform image update
    if docker pull "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Image successfully updated${NC}"
        
        # Show information about new image
        echo ""
        echo -e "${CYAN}📊 Updated image information:${NC}"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$image_name" | head -1
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Error updating image${NC}"
    fi
}

# Function to push selected image - NEW FUNCTION
push_selected_image() {
    echo -e "${YELLOW}📤 Pushing image to repository${NC}"
    echo -e "${CYAN}Enter image number to push:${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 10; then
        return 1
    fi
    
    # Check for cancellation
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Check if number
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid number. Enter a number.${NC}"
        return 1
    fi
    
    if [ -z "${image_ids[$input]}" ]; then
        echo -e "${RED}❌ Invalid image number.${NC}"
        return 1
    fi
    
    local image_name="${image_names[$input]}"
    local image_tag="${image_tags[$input]}"
    local full_image_name="$image_name:$image_tag"
    
    # Check that image has repository (not <none>)
    if [ "$image_name" = "<none>" ] || [ "$image_tag" = "<none>" ]; then
        echo -e "${RED}❌ Cannot push image without repository.${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}📤 Preparing to push image: ${CYAN}$full_image_name${NC}"
    echo ""
    
    # Request credentials
    echo -e "${YELLOW}🔐 Enter Docker registry credentials:${NC}"
    echo -e "${CYAN}Username:${NC}"
    if ! safe_read "> " docker_username 50; then
        return 1
    fi
    
    echo -e "${CYAN}Password:${NC}"
    if ! safe_read -s "> " docker_password 50; then
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}🔐 Authenticating to Docker registry...${NC}"
    
    # Authenticate to Docker registry
    if echo "$docker_password" | docker login --username "$docker_username" --password-stdin; then
        echo -e "${GREEN}✅ Authentication successful${NC}"
    else
        echo -e "${RED}❌ Authentication error${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}📤 Pushing image: ${CYAN}$full_image_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Perform image push
    if docker push "$full_image_name"; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Image successfully pushed${NC}"
        
        # Logout for security
        docker logout
        echo -e "${YELLOW}🔒 Logged out from account${NC}"
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Error pushing image${NC}"
        
        # Logout anyway
        docker logout
        echo -e "${YELLOW}🔒 Logged out from account${NC}"
    fi
}

# Updated images operations menu with new functions
show_images_menu() {
    echo -e "${CYAN}🛠️  Image operations:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 🗑️  Delete selected images${NC}"
    echo -e "${YELLOW}2. 🧹  Delete unused images${NC}"
    echo -e "${RED}3. 💥  Delete ALL images${NC}"
    echo -e "${ORANGE}4. 🔍  Delete images with <none> tag${NC}"
    echo -e "${PURPLE}5. 🛠️  Delete Docker build cache${NC}"
    echo -e "${BLUE}6. 🔄  Refresh images list${NC}"
    echo -e "${CYAN}7. 🔄  Update selected image (pull)${NC}"
    echo -e "${GREEN}8. 📤  Push selected image (push)${NC}"
    
    # Add page navigation if there are multiple pages
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
            echo -e "${CYAN}9. 📄  Next page${NC}"
        fi
        if [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            echo -e "${CYAN}10. 📄  Previous page${NC}"
        fi
    fi
    
    echo -e "${GREEN}11. 🐳  Switch to container management${NC}"
    echo -e "${GREEN}0. 🏠  Back to main menu${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    # Determine maximum allowed choice depending on page presence
    local max_choice=11
    if [ "${IMAGES_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ] && [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Select operation [0-11]: ${NC}" choice 2
        elif [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
            safe_read "${CYAN}🎯 Select operation [0-10,11]: ${NC}" choice 2
        elif [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Select operation [0-8,10,11]: ${NC}" choice 2
        else
            safe_read "${CYAN}🎯 Select operation [0-11]: ${NC}" choice 2
        fi
    else
        safe_read "${CYAN}🎯 Select operation [0-11]: ${NC}" choice 2
    fi
}

# Function to display container operations menu with pagination support
show_containers_menu() {
    echo -e "${CYAN}🛠️  Container operations:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. ⏹️   Stop selected containers${NC}"
    echo -e "${YELLOW}2. 🗑️   Delete selected containers${NC}"
    echo -e "${RED}3. 💀   Stop and delete selected containers${NC}"
    echo -e "${GREEN}4. ▶️   Start selected containers${NC}"
    echo -e "${BLUE}5. 🔄   Refresh containers list${NC}"
    
    # Add page navigation if there are multiple pages
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
            echo -e "${CYAN}6. 📄  Next page${NC}"
        fi
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            echo -e "${CYAN}7. 📄  Previous page${NC}"
        fi
    fi
    
    echo -e "${GREEN}8. 📦   Switch to image management${NC}"
    echo -e "${GREEN}0. 🏠   Back to main menu${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    
    local max_choice=8
    if [ "${CONTAINERS_TOTAL_PAGES:-1}" -gt 1 ]; then
        if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ] && [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Select operation [0-8]: ${NC}" choice 1
        elif [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
            safe_read "${CYAN}🎯 Select operation [0-6,8,0]: ${NC}" choice 1
        elif [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
            safe_read "${CYAN}🎯 Select operation [0-5,7,8,0]: ${NC}" choice 1
        else
            safe_read "${CYAN}🎯 Select operation [0-8]: ${NC}" choice 1
        fi
    else
        safe_read "${CYAN}🎯 Select operation [0-8]: ${NC}" choice 1
    fi
}

# Function to delete selected images
delete_selected_images() {
    echo -e "${YELLOW}🗑️ Enter image numbers to delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Check for cancellation with Russian layout support
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Check for empty input
    if [ -z "$input" ]; then
        echo -e "${RED}❌ No images selected.${NC}"
        return 1
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}🗑️ The following images will be deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${image_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
        fi
    done
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${image_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Deleting ${image_names[$num]}:${image_tags[$num]}...${NC}"
                if docker rmi -f "${image_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Successfully deleted${NC}"
                else
                    echo -e "${RED}❌ Error deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Invalid number: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Deletion cancelled.${NC}"
        return 1
    fi
}

# Function to stop selected containers
stop_selected_containers() {
    echo -e "${YELLOW}⏹️ Enter container numbers to stop (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Check for cancellation with Russian layout support
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}⏹️ The following containers will be stopped:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}■${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}⏹️ Stopping ${container_names[$num]}...${NC}"
                if docker stop "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Successfully stopped${NC}"
                else
                    echo -e "${RED}❌ Error stopping${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Invalid number: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Stop cancelled.${NC}"
        return 1
    fi
}

# Function to start selected containers
start_selected_containers() {
    echo -e "${YELLOW}▶️  Enter container numbers to start (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Check for cancellation with Russian layout support
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}▶️  The following containers will be started:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${GREEN}▶${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}▶️  Starting ${container_names[$num]}...${NC}"
                if docker start "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Successfully started${NC}"
                else
                    echo -e "${RED}❌ Error starting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Invalid number: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Start cancelled.${NC}"
        return 1
    fi
}

# Function to delete selected containers
delete_selected_containers() {
    echo -e "${YELLOW}🗑️ Enter container numbers to delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Check for cancellation with Russian layout support
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${YELLOW}🗑️ The following containers will be deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}🗑️ Deleting ${container_names[$num]}...${NC}"
                if docker rm "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Successfully deleted${NC}"
                else
                    echo -e "${RED}❌ Error deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Invalid number: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Deletion cancelled.${NC}"
        return 1
    fi
}

# Function to stop and delete selected containers
stop_and_delete_containers() {
    echo -e "${YELLOW}💀 Enter container numbers to stop and delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    
    if ! safe_read "> " input 50; then
        return 1
    fi
    
    # Check for cancellation with Russian layout support
    if check_cancel "$input"; then
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    echo ""
    echo -e "${RED}💀 The following containers will be stopped and deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}☠${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    safe_read "Are you sure? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}💀 Stopping and deleting ${container_names[$num]}...${NC}"
                
                # Stop container (if running)
                docker stop "${container_ids[$num]}" 2>/dev/null
                
                # Delete container
                if docker rm "${container_ids[$num]}" 2>/dev/null; then
                    echo -e "${GREEN}✅ Successfully stopped and deleted${NC}"
                else
                    echo -e "${RED}❌ Error stopping/deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}❌ Invalid number: $num${NC}"
            fi
        done
        return 0
    else
        echo -e "${GREEN}✅ Operation cancelled.${NC}"
        return 1
    fi
}

# Function to delete unused images
delete_unused_images() {
    echo -e "${YELLOW}🧹 Deleting unused images...${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    if docker image prune -a -f; then
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ Done!${NC}"
    else
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${RED}❌ Error deleting unused images${NC}"
    fi
}

# Function to delete all images
delete_all_images() {
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ⚠️ DANGEROUS OPERATION ⚠️       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo -e "${RED}🚨 ALL Docker images will be deleted!${NC}"
    echo ""
    
    safe_read "Are you sure? (enter 'DELETE' to confirm): " confirm 10
    
    if [ "$confirm" = "DELETE" ]; then
        echo -e "${RED}🗑️ Deleting all images...${NC}"
        all_images=$(docker images -q)
        if [ -n "$all_images" ]; then
            if docker rmi -f $all_images 2>/dev/null; then
                echo -e "${GREEN}✅ All images deleted.${NC}"
            else
                echo -e "${RED}❌ Error deleting some images${NC}"
            fi
        else
            echo -e "${YELLOW}📭 No images to delete.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Deletion cancelled.${NC}"
    fi
}

# Function to delete images with <none> tag - FIXED VERSION
delete_none_images() {
    echo -e "${YELLOW}🔍 Searching for images with <none> tag...${NC}"
    
    # Get IDs of all dangling images (images with <none> tag)
    dangling_images=$(docker images -f "dangling=true" -q)
    
    if [ -z "$dangling_images" ]; then
        echo -e "${GREEN}✅ No images with <none> tag.${NC}"
        # REMOVE press_enter_to_continue call here
        return
    fi
    
    echo ""
    echo -e "${RED}🗑️ Images with <none> tag (intermediate images):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Show information about dangling images
    docker images -f "dangling=true" --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Count number of images
    image_count=$(echo "$dangling_images" | wc -l)
    echo -e "${YELLOW}🗑️ Found ${image_count} images with <none> tag${NC}"
    
    echo ""
    safe_read "Delete all images with <none> tag? (y/N): " confirm 1
    
    if check_confirmation "$confirm"; then
        echo ""
        echo -e "${YELLOW}🧹 Deleting images with <none> tag...${NC}"
        
        # Delete all dangling images (images with <none> tag)
        if docker image prune -f; then
            echo -e "${GREEN}✅ All images with <none> tag deleted${NC}"
        else
            echo -e "${RED}❌ Error deleting images with <none> tag${NC}"
        fi
    else
        echo -e "${GREEN}✅ Deletion cancelled.${NC}"
    fi
}

# Function to delete Docker build cache - FIXED FOR BUILDX
delete_build_cache() {
    echo -e "${YELLOW}🧹 Deleting Docker build cache...${NC}"
    echo -e "${RED}⚠️ Warning: This will free up space but may increase build times for subsequent builds.${NC}"
    echo ""

    # Use buildx instead of builder
    echo -e "${CYAN}🔍 Scanning build cache...${NC}"
    local cache_output
    cache_output=$(docker buildx prune --dry-run 2>&1)
    
    # Check if there's anything to delete
    if echo "$cache_output" | grep -q "Total"; then
        # Extract the line with Total size
        local total_line=$(echo "$cache_output" | grep "Total")
        echo -e "${CYAN}📊 Will be freed: ${YELLOW}$total_line${NC}"
    else
        # If Total not found, show all output
        echo -e "${CYAN}📊 Cache information:${NC}"
        echo "$cache_output"
    fi

    echo ""

    # If there are cache IDs in the output, show them
    if echo "$cache_output" | grep -q -E "^[a-zA-Z0-9]"; then
        echo -e "${YELLOW}Cache objects to be deleted:${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo "$cache_output" | grep -E "^[a-zA-Z0-9]" | head -10
        local total_objects=$(echo "$cache_output" | grep -E "^[a-zA-Z0-9]" | wc -l)
        if [ "$total_objects" -gt 10 ]; then
            echo -e "${CYAN}... and $((total_objects - 10)) more objects${NC}"
        fi
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo ""
    fi

    safe_read "Delete all build cache? (y/N): " confirm 1

    if check_confirmation "$confirm"; then
        echo ""
        echo -e "${YELLOW}🧹 Deleting build cache...${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        
        # Use buildx prune
        local delete_output
        delete_output=$(docker buildx prune -f 2>&1)
        
        # Show deletion result
        echo "$delete_output"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        
        if echo "$delete_output" | grep -q "Total"; then
            echo -e "${GREEN}✅ Build cache deleted.${NC}"
        else
            echo -e "${GREEN}✅ Operation completed.${NC}"
        fi
    else
        echo -e "${GREEN}✅ Deletion cancelled.${NC}"
    fi
}

# Main menu for working with images with pagination and new functions - SIMPLIFIED
images_submenu() {
    local current_page=${1:-1}
    
    while true; do
        print_header
        show_disk_stats  # This now shows all the image statistics
        if show_images "$current_page"; then
            # Removed duplicate disk usage analysis - already shown in show_disk_stats
            echo ""  # Just spacing for beauty
        fi
        show_images_menu
        
        case $choice in
            1)
                if delete_selected_images; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
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
                # Refresh list on first page
                current_page=1
                ;;
            7)
                # New function: update selected image
                if update_selected_image; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            8)
                # New function: push selected image
                if push_selected_image; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            9)
                # Next page
                if [ "${IMAGES_CURRENT_PAGE:-1}" -lt "${IMAGES_TOTAL_PAGES}" ]; then
                    current_page=$((IMAGES_CURRENT_PAGE + 1))
                else
                    echo -e "${YELLOW}ℹ️ This is the last page${NC}"
                    press_enter_to_continue
                fi
                ;;
            10)
                # Previous page
                if [ "${IMAGES_CURRENT_PAGE:-1}" -gt 1 ]; then
                    current_page=$((IMAGES_CURRENT_PAGE - 1))
                else
                    echo -e "${YELLOW}ℹ️ This is the first page${NC}"
                    press_enter_to_continue
                fi
                ;;
            11)
                # Switch to container management
                return 1
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Main menu for container management with pagination - SIMPLIFIED
containers_submenu() {
    local current_page=${1:-1}
    
    while true; do
        print_header
        show_containers_stats  # Only statistics at the top
        if show_containers "$current_page"; then
            # Removed detailed statistics at the bottom
            echo ""
        fi
        show_containers_menu
        
        case $choice in
            1)
                if stop_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            2)
                if delete_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            3)
                if stop_and_delete_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            4)
                if start_selected_containers; then
                    echo ""
                    echo -e "${GREEN}✅ Operation completed${NC}"
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                ;;
            5)
                # Refresh list on first page
                current_page=1
                ;;
            6)
                # Next page
                if [ "${CONTAINERS_CURRENT_PAGE:-1}" -lt "${CONTAINERS_TOTAL_PAGES}" ]; then
                    current_page=$((CONTAINERS_CURRENT_PAGE + 1))
                else
                    echo -e "${YELLOW}ℹ️  This is the last page${NC}"
                    press_enter_to_continue
                fi
                ;;
            7)
                # Previous page
                if [ "${CONTAINERS_CURRENT_PAGE:-1}" -gt 1 ]; then
                    current_page=$((CONTAINERS_CURRENT_PAGE - 1))
                else
                    echo -e "${YELLOW}ℹ️  This is the first page${NC}"
                    press_enter_to_continue
                fi
                ;;
            8)
                # Switch to image management
                return 1
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Function to display main menu
show_main_menu() {
    print_header
    echo -e "${CYAN}🏠 Main menu:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 📦  Show all images${NC}"
    echo -e "${GREEN}2. 🐳  Show all containers${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}3. 🧹  Docker system cleanup${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}0. 🚪  Exit${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Select menu item [0-3]: ${NC}" choice 1
}

# Function for Docker system cleanup
cleanup_docker_system() {
    print_header
    echo -e "${YELLOW}🧹 Docker system cleanup:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1. 🗑️   Delete unused images${NC}"
    echo -e "${ORANGE}2. 🔍   Delete images with <none> tag${NC}"
    echo -e "${PURPLE}3. 🛠️   Delete Docker build cache${NC}"
    echo -e "${RED}4. 💥   Full system cleanup${NC}"
    echo -e "${GREEN}0. 🏠   Back to main menu${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    safe_read "${CYAN}🎯 Select operation [0-4]: ${NC}" choice 1
    
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
            echo -e "${RED}🚨 Full Docker system cleanup...${NC}"
            echo -e "${YELLOW}This will delete:${NC}"
            echo -e "  • All stopped containers"
            echo -e "  • All unused networks"
            echo -e "  • All unused images"
            echo -e "  • All unused builds"
            echo -e "  • All unused caches"
            echo ""
            safe_read "Are you sure? (enter 'CLEAN' to confirm): " confirm 10
            if [ "$confirm" = "CLEAN" ]; then
                echo ""
                docker system prune -a -f
                echo -e "${GREEN}✅ Full cleanup completed${NC}"
            else
                echo -e "${GREEN}✅ Cleanup cancelled${NC}"
            fi
            press_enter_to_continue
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid choice.${NC}"
            sleep 2
            ;;
    esac
}

# Main program loop
while true; do
    show_main_menu
    
    case $choice in
        1)
            if images_submenu; then
                # Return to main menu
                continue
            else
                # Switch to containers
                containers_submenu
            fi
            ;;
        2)
            if containers_submenu; then
                # Return to main menu
                continue
            else
                # Switch to images
                images_submenu
            fi
            ;;
        3)
            cleanup_docker_system
            ;;
        0)
            echo -e "${GREEN}👋 Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid choice. Try again.${NC}"
            sleep 2
            ;;
    esac
done
