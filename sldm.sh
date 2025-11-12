#!/bin/bash

# Colors for menu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Function to display header
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║               DOCKER MANAGER                     ║"
    echo "║           IMAGE AND CONTAINER MANAGEMENT         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to wait for Enter and return to menu
press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Press Enter to return to main menu...${NC}"
    read
}

# Function to show all images with creation date
show_images() {
    echo -e "${YELLOW}Docker Images List:${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Get images and save to arrays
    local counter=1
    declare -g image_ids=()
    declare -g image_names=()
    declare -g image_tags=()
    
    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            image_ids[$counter]=$id
            image_names[$counter]="$repository"
            image_tags[$counter]="$tag"
            # Format date (keep only date, remove time)
            short_created=$(echo "$created" | cut -d' ' -f1)
            printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-25s${NC} ${RED}%-10s${NC} ${ORANGE}%s${NC}\n" \
                "$counter" "${repository:0:30}" "${tag:0:25}" "$size" "$short_created"
            ((counter++))
        fi
    done < <(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $counter -eq 1 ]; then
        echo -e "${RED}No Docker images found.${NC}"
        return 1
    fi
    return 0
}

# Function to show all containers
show_containers() {
    echo -e "${YELLOW}Docker Containers List:${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local counter=1
    declare -g container_ids=()
    declare -g container_names=()
    declare -g container_status=()
    
    while IFS='|' read -r id image status names; do
        if [ -n "$id" ] && [ "$id" != "CONTAINER ID" ]; then
            container_ids[$counter]=$id
            container_names[$counter]="$names"
            container_status[$counter]="$status"
            
            # Determine status color
            status_color=$GREEN
            if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"Dead"* ]]; then
                status_color=$RED
            elif [[ "$status" == *"Up"* ]]; then
                status_color=$GREEN
            else
                status_color=$YELLOW
            fi
            
            printf "${GREEN}%2d.${NC} ${PURPLE}%-12s${NC} ${status_color}%-30s${NC} ${CYAN}%-40s${NC}\n" \
                "$counter" "$id" "${status:0:30}" "${names:0:40}"
            ((counter++))
        fi
    done < <(docker ps -a --format "table {{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}" | tail -n +2)
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $counter -eq 1 ]; then
        echo -e "${RED}No Docker containers found.${NC}"
        return 1
    fi
    return 0
}

# Function to delete selected images
delete_selected_images() {
    if ! show_images; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Enter image numbers to delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    read -p "> " input
    
    # Check for cancel
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Operation cancelled.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}No images selected.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}The following images will be deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${image_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
        fi
    done
    
    echo ""
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${image_ids[$num]}" ]; then
                echo -e "${YELLOW}Deleting ${image_names[$num]}:${image_tags[$num]}...${NC}"
                docker rmi -f "${image_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully deleted${NC}"
                else
                    echo -e "${RED}✗ Error deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Invalid number: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Deletion cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to stop selected containers
stop_selected_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Enter container numbers to stop (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    read -p "> " input
    
    # Check for cancel
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Operation cancelled.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}No containers selected.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}The following containers will be stopped:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}■${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Stopping ${container_names[$num]}...${NC}"
                docker stop "${container_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully stopped${NC}"
                else
                    echo -e "${RED}✗ Error stopping${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Invalid number: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Stop cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to delete selected containers
delete_selected_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Enter container numbers to delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    read -p "> " input
    
    # Check for cancel
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Operation cancelled.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}No containers selected.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}The following containers will be deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Deleting ${container_names[$num]}...${NC}"
                docker rm "${container_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully deleted${NC}"
                else
                    echo -e "${RED}✗ Error deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Invalid number: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Deletion cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to stop and delete selected containers
stop_and_delete_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Enter container numbers to stop and delete (space separated):${NC}"
    echo -e "${CYAN}Example: 1 3 5${NC}"
    echo -e "${ORANGE}Or enter 'c' to cancel${NC}"
    read -p "> " input
    
    # Check for cancel
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Operation cancelled.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Convert input to array
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}No containers selected.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${RED}The following containers will be stopped and deleted:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}☠${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Are you sure? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Stopping and deleting ${container_names[$num]}...${NC}"
                
                # Stop container (if running)
                docker stop "${container_ids[$num]}" 2>/dev/null
                
                # Delete container
                docker rm "${container_ids[$num]}" 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully stopped and deleted${NC}"
                else
                    echo -e "${RED}✗ Error stopping/deleting${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Invalid number: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Operation cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to delete unused images
delete_unused_images() {
    echo -e "${YELLOW}Deleting unused images...${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    docker image prune -a -f
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}Done!${NC}"
    press_enter_to_continue
}

# Function to delete all images
delete_all_images() {
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           DANGEROUS OPERATION          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo -e "${RED}ALL Docker images will be deleted!${NC}"
    echo ""
    
    show_images
    
    read -p "Are you sure? (type 'DELETE' to confirm): " confirm
    
    if [ "$confirm" = "DELETE" ]; then
        echo -e "${RED}Deleting all images...${NC}"
        all_images=$(docker images -q)
        if [ -n "$all_images" ]; then
            docker rmi -f $all_images 2>/dev/null
            echo -e "${GREEN}All images deleted.${NC}"
        else
            echo -e "${YELLOW}No images to delete.${NC}"
        fi
    else
        echo -e "${GREEN}Deletion cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to delete images with <none> tag
delete_none_images() {
    echo -e "${YELLOW}Searching for images with <none> tag...${NC}"
    
    # Get images with <none> tag or repository
    none_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | grep "<none>")
    
    if [ -z "$none_images" ] || [ "$(echo "$none_images" | wc -l)" -le 1 ]; then
        echo -e "${GREEN}No images with <none> tag found.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${RED}Images with <none> tag (intermediate images):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    counter=1
    declare -a none_image_ids
    declare -a none_image_info
    
    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            none_image_ids[$counter]=$id
            short_created=$(echo "$created" | cut -d' ' -f1)
            none_image_info[$counter]="$repository:$tag ($size, created: $short_created)"
            printf "${GREEN}%2d.${NC} ${PURPLE}%-12s${NC} ${RED}%-30s${NC} ${YELLOW}%-15s${NC} ${ORANGE}%s${NC}\n" \
                "$counter" "$id" "${repository:0:30}" "$tag" "$short_created"
            ((counter++))
        fi
    done <<< "$none_images"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}The following intermediate images will be deleted:${NC}"
    for ((i=1; i<counter; i++)); do
        echo -e "  ${RED}×${NC} ${none_image_info[$i]}"
    done
    
    echo ""
    read -p "Delete all images with <none> tag? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Deleting images with <none> tag...${NC}"
        
        # Delete all dangling images (images with <none> tag)
        docker image prune -f
        
        # Additionally delete images with <none> repository
        dangling_images=$(docker images -f "dangling=true" -q)
        if [ -n "$dangling_images" ]; then
            docker rmi $dangling_images 2>/dev/null
        fi
        
        echo -e "${GREEN}✓ All images with <none> tag deleted${NC}"
    else
        echo -e "${GREEN}Deletion cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to delete Docker build cache
delete_build_cache() {
    echo -e "${YELLOW}Deleting Docker build cache...${NC}"
    echo -e "${RED}Warning: This will free up space but may increase build times for next builds.${NC}"
    echo ""
    
    # Show current cache size
    cache_size=$(docker system df | grep "Build Cache" | awk '{print $4}')
    echo -e "${CYAN}Current build cache size: ${YELLOW}$cache_size${NC}"
    echo ""
    
    read -p "Delete all build cache? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Deleting build cache...${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        docker builder prune -f
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}Build cache deleted.${NC}"
        
        # Show new system size
        echo ""
        echo -e "${CYAN}Updated Docker statistics:${NC}"
        docker system df
    else
        echo -e "${GREEN}Deletion cancelled.${NC}"
    fi
    
    press_enter_to_continue
}

# Function to display main menu
show_menu() {
    print_header
    echo -e "${CYAN}Main Menu:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1.${NC} Show all images"
    echo -e "${GREEN}2.${NC} Delete selected images"
    echo -e "${YELLOW}3.${NC} Delete unused images"
    echo -e "${RED}4.${NC} Delete ALL images"
    echo -e "${ORANGE}5.${NC} Delete images with <none> tag"
    echo -e "${PURPLE}6.${NC} Delete Docker build cache"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${CYAN}7.${NC} Show all containers"
    echo -e "${CYAN}8.${NC} Stop selected containers"
    echo -e "${CYAN}9.${NC} Delete selected containers"
    echo -e "${RED}10.${NC} Stop and delete selected containers"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}0.${NC} Exit"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -n -e "${CYAN}Choose menu option [0-10]: ${NC}"
}

# Main program loop
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            print_header
            show_images
            press_enter_to_continue
            ;;
        2)
            print_header
            delete_selected_images
            ;;
        3)
            print_header
            delete_unused_images
            ;;
        4)
            print_header
            delete_all_images
            ;;
        5)
            print_header
            delete_none_images
            ;;
        6)
            print_header
            delete_build_cache
            ;;
        7)
            print_header
            show_containers
            press_enter_to_continue
            ;;
        8)
            print_header
            stop_selected_containers
            ;;
        9)
            print_header
            delete_selected_containers
            ;;
        10)
            print_header
            stop_and_delete_containers
            ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            sleep 2
            ;;
    esac
done
