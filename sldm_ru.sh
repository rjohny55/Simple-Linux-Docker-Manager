#!/bin/bash

# Цвета для меню
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Функция для отображения заголовка
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║               DOCKER MANAGER                     ║"
    echo "║           УПРАВЛЕНИЕ ОБРАЗАМИ И КОНТЕЙНЕРАМИ     ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Функция для ожидания нажатия Enter и возврата в меню
press_enter_to_continue() {
    echo ""
    echo -e "${CYAN}Нажмите Enter для возврата в главное меню...${NC}"
    read
}

# Функция для показа всех образов с датой создания
show_images() {
    echo -e "${YELLOW}Список Docker образов:${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Получаем образы и сохраняем в массивы
    local counter=1
    declare -g image_ids=()
    declare -g image_names=()
    declare -g image_tags=()
    
    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            image_ids[$counter]=$id
            image_names[$counter]="$repository"
            image_tags[$counter]="$tag"
            # Форматируем дату (оставляем только дату, убираем время)
            short_created=$(echo "$created" | cut -d' ' -f1)
            printf "${GREEN}%2d.${NC} ${PURPLE}%-30s${NC} ${YELLOW}%-25s${NC} ${RED}%-10s${NC} ${ORANGE}%s${NC}\n" \
                "$counter" "${repository:0:30}" "${tag:0:25}" "$size" "$short_created"
            ((counter++))
        fi
    done < <(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | tail -n +2)
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $counter -eq 1 ]; then
        echo -e "${RED}Нет Docker образов.${NC}"
        return 1
    fi
    return 0
}

# Функция для показа всех контейнеров
show_containers() {
    echo -e "${YELLOW}Список Docker контейнеров:${NC}"
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
            
            # Определяем цвет статуса
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
        echo -e "${RED}Нет Docker контейнеров.${NC}"
        return 1
    fi
    return 0
}

# Функция для удаления выбранных образов
delete_selected_images() {
    if ! show_images; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Введите номера образов для удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    read -p "> " input
    
    # Проверка на отмену
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Отмена операции.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}Не выбрано ни одного образа.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Будут удалены следующие образы:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${image_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${image_names[$num]}:${image_tags[$num]}"
        fi
    done
    
    echo ""
    read -p "Вы уверены? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${image_ids[$num]}" ]; then
                echo -e "${YELLOW}Удаляем ${image_names[$num]}:${image_tags[$num]}...${NC}"
                docker rmi -f "${image_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Успешно удален${NC}"
                else
                    echo -e "${RED}✗ Ошибка при удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Неверный номер: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Отмена удаления.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для остановки выбранных контейнеров
stop_selected_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Введите номера контейнеров для остановки (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    read -p "> " input
    
    # Проверка на отмену
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Отмена операции.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}Не выбрано ни одного контейнера.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Будут остановлены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}■${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Вы уверены? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Останавливаем ${container_names[$num]}...${NC}"
                docker stop "${container_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Успешно остановлен${NC}"
                else
                    echo -e "${RED}✗ Ошибка при остановке${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Неверный номер: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Отмена остановки.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для удаления выбранных контейнеров
delete_selected_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Введите номера контейнеров для удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    read -p "> " input
    
    # Проверка на отмену
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Отмена операции.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}Не выбрано ни одного контейнера.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Будут удалены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}×${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Вы уверены? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Удаляем ${container_names[$num]}...${NC}"
                docker rm "${container_ids[$num]}" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Успешно удален${NC}"
                else
                    echo -e "${RED}✗ Ошибка при удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Неверный номер: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Отмена удаления.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для остановки и удаления выбранных контейнеров
stop_and_delete_containers() {
    if ! show_containers; then
        press_enter_to_continue
        return
    fi
    
    echo -e "${YELLOW}Введите номера контейнеров для остановки и удаления (через пробел):${NC}"
    echo -e "${CYAN}Пример: 1 3 5${NC}"
    echo -e "${ORANGE}Или введите 'c' для отмены${NC}"
    read -p "> " input
    
    # Проверка на отмену
    if [[ "$input" == "c" || "$input" == "C" ]]; then
        echo -e "${GREEN}Отмена операции.${NC}"
        press_enter_to_continue
        return
    fi
    
    # Преобразуем ввод в массив
    read -a selected_numbers <<< "$input"
    
    if [ ${#selected_numbers[@]} -eq 0 ]; then
        echo -e "${RED}Не выбрано ни одного контейнера.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${RED}Будут остановлены и удалены следующие контейнеры:${NC}"
    for num in "${selected_numbers[@]}"; do
        if [ -n "${container_ids[$num]}" ]; then
            echo -e "  ${RED}☠${NC} ${container_names[$num]} (${container_status[$num]})"
        fi
    done
    
    echo ""
    read -p "Вы уверены? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        for num in "${selected_numbers[@]}"; do
            if [ -n "${container_ids[$num]}" ]; then
                echo -e "${YELLOW}Останавливаем и удаляем ${container_names[$num]}...${NC}"
                
                # Останавливаем контейнер (если он запущен)
                docker stop "${container_ids[$num]}" 2>/dev/null
                
                # Удаляем контейнер
                docker rm "${container_ids[$num]}" 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Успешно остановлен и удален${NC}"
                else
                    echo -e "${RED}✗ Ошибка при остановке/удалении${NC}"
                fi
                echo ""
            else
                echo -e "${RED}Неверный номер: $num${NC}"
            fi
        done
    else
        echo -e "${GREEN}Отмена операции.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для удаления неиспользуемых образов
delete_unused_images() {
    echo -e "${YELLOW}Удаляем неиспользуемые образы...${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    docker image prune -a -f
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}Готово!${NC}"
    press_enter_to_continue
}

# Функция для удаления всех образов
delete_all_images() {
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ОПАСНАЯ ОПЕРАЦИЯ            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo -e "${RED}Будут удалены ВСЕ Docker образы!${NC}"
    echo ""
    
    show_images
    
    read -p "Вы уверены? (введите 'DELETE' для подтверждения): " confirm
    
    if [ "$confirm" = "DELETE" ]; then
        echo -e "${RED}Удаляем все образы...${NC}"
        all_images=$(docker images -q)
        if [ -n "$all_images" ]; then
            docker rmi -f $all_images 2>/dev/null
            echo -e "${GREEN}Все образы удалены.${NC}"
        else
            echo -e "${YELLOW}Нет образов для удаления.${NC}"
        fi
    else
        echo -e "${GREEN}Отмена удаления.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для удаления образов с тегом <none>
delete_none_images() {
    echo -e "${YELLOW}Поиск образов с тегом <none>...${NC}"
    
    # Получаем образы с тегом <none> или репозиторием <none>
    none_images=$(docker images --format "table {{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" | grep "<none>")
    
    if [ -z "$none_images" ] || [ "$(echo "$none_images" | wc -l)" -le 1 ]; then
        echo -e "${GREEN}Нет образов с тегом <none>.${NC}"
        press_enter_to_continue
        return
    fi
    
    echo ""
    echo -e "${RED}Образы с тегом <none> (промежуточные образы):${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    
    counter=1
    declare -a none_image_ids
    declare -a none_image_info
    
    while IFS='|' read -r id repository tag size created; do
        if [ -n "$id" ] && [ "$id" != "IMAGE ID" ]; then
            none_image_ids[$counter]=$id
            short_created=$(echo "$created" | cut -d' ' -f1)
            none_image_info[$counter]="$repository:$tag ($size, создан: $short_created)"
            printf "${GREEN}%2d.${NC} ${PURPLE}%-12s${NC} ${RED}%-30s${NC} ${YELLOW}%-15s${NC} ${ORANGE}%s${NC}\n" \
                "$counter" "$id" "${repository:0:30}" "$tag" "$short_created"
            ((counter++))
        fi
    done <<< "$none_images"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}Будут удалены следующие промежуточные образы:${NC}"
    for ((i=1; i<counter; i++)); do
        echo -e "  ${RED}×${NC} ${none_image_info[$i]}"
    done
    
    echo ""
    read -p "Удалить все образы с тегом <none>? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Удаляем образы с тегом <none>...${NC}"
        
        # Удаляем все dangling images (образы с тегом <none>)
        docker image prune -f
        
        # Дополнительно удаляем образы с репозиторием <none>
        dangling_images=$(docker images -f "dangling=true" -q)
        if [ -n "$dangling_images" ]; then
            docker rmi $dangling_images 2>/dev/null
        fi
        
        echo -e "${GREEN}✓ Все образы с тегом <none> удалены${NC}"
    else
        echo -e "${GREEN}Отмена удаления.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для удаления кеша сборок Docker
delete_build_cache() {
    echo -e "${YELLOW}Удаление кеша сборок Docker...${NC}"
    echo -e "${RED}Внимание: Это освободит место, но может увеличить время следующих сборок.${NC}"
    echo ""
    
    # Показываем текущий размер кеша
    cache_size=$(docker system df | grep "Build Cache" | awk '{print $4}')
    echo -e "${CYAN}Текущий размер кеша сборок: ${YELLOW}$cache_size${NC}"
    echo ""
    
    read -p "Удалить весь кеш сборок? (y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo -e "${YELLOW}Удаляем кеш сборок...${NC}"
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        docker builder prune -f
        echo -e "${BLUE}════════════════════════════════════════${NC}"
        echo -e "${GREEN}Кеш сборок удален.${NC}"
        
        # Показываем новый размер системы
        echo ""
        echo -e "${CYAN}Обновленная статистика Docker:${NC}"
        docker system df
    else
        echo -e "${GREEN}Отмена удаления.${NC}"
    fi
    
    press_enter_to_continue
}

# Функция для отображения главного меню
show_menu() {
    print_header
    echo -e "${CYAN}Главное меню:${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}1.${NC} Показать все образы"
    echo -e "${GREEN}2.${NC} Удалить выбранные образы"
    echo -e "${YELLOW}3.${NC} Удалить неиспользуемые образы"
    echo -e "${RED}4.${NC} Удалить ВСЕ образы"
    echo -e "${ORANGE}5.${NC} Удалить образы с тегом <none>"
    echo -e "${PURPLE}6.${NC} Удалить кеш сборок Docker"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${CYAN}7.${NC} Показать все контейнеры"
    echo -e "${CYAN}8.${NC} Остановить выбранные контейнеры"
    echo -e "${CYAN}9.${NC} Удалить выбранные контейнеры"
    echo -e "${RED}10.${NC} Остановить и удалить выбранные контейнеры"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${GREEN}0.${NC} Выход"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -n -e "${CYAN}Выберите пункт меню [0-10]: ${NC}"
}

# Основной цикл программы
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
            echo -e "${GREEN}Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
