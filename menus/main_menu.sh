# File: /opt/imagitech/menus/main_menu.sh
# Purpose: Interactive HUD. Contains NO business logic.

#!/bin/bash
source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/system.sh

# --- Root Enforcement ---
if [ "${EUID}" -ne 0 ]; then
    echo -e "\033[0;31m[FATAL] You must be root to access the Imagitech Dashboard.\033[0m"
    echo -e "\033[0;33mType this command to become root: sudo su -\033[0m"
    exit 1
fi

# --- ANSI Color Palette ---
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

draw_top() { echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"; }

# --- Live Data Harvesters ---
get_system_stats() {
    OS_INFO=$(grep -w PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
}

get_db_stats() {
    TOTAL_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    ACTIVE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='ACTIVE';")
    EXPIRED_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='EXPIRED';")
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

# --- Sub-Routines (Calling the API) ---
execute_add_user() {
    while true; do
        clear
        echo -e "${CYAN}=== CREATE ISP BYPASS ACCOUNT ===${NC}"
        
        read -p "Username: " USERNAME
        if [[ -z "$USERNAME" ]]; then 
            echo -e "${RED}[ERROR] Missing arguments for user creation. Username cannot be empty.${NC}"
            sleep 1.5; continue
        fi

        read -p "Password: " PASSWORD
        if [[ -z "$PASSWORD" ]]; then 
            echo -e "${RED}[ERROR] Missing arguments for user creation. Password cannot be empty.${NC}"
            sleep 1.5; continue
        fi

        read -p "Duration (Days): " DAYS
        if [[ -z "$DAYS" ]]; then 
            echo -e "${RED}[ERROR] Missing arguments for user creation. Duration cannot be empty.${NC}"
            sleep 1.5; continue
        fi

        # Call the backend API and suppress output
        /opt/imagitech/bin/imagitech user add "$USERNAME" "$PASSWORD" "$DAYS" > /dev/null 2>&1
        API_STATUS=$?
        
        if [ $API_STATUS -eq 2 ]; then
            echo -e "\n${ORANGE}[!] User '${USERNAME}' already exists.${NC}"
            read -p "Do you want to create another user? (y/n): " RETRY
            if [[ "$RETRY" =~ ^[Yy] ]]; then
                continue
            else
                show_dashboard
                return
            fi
        elif [ $API_STATUS -ne 0 ]; then
            echo -e "\n${RED}[-] Failed to create account. Check logs at /opt/imagitech/logs/imagitech.log${NC}"
            read -n 1 -s -r -p "Press any key to return to dashboard..."
            show_dashboard
            return
        fi
        
        # If successful, break the loop and show the receipt
        break
    done

    # Fetch dynamic data for the payload printout
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    PUB_KEY=$(cat /opt/imagitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
    EXP_DATE_FORMATTED=$(date -d "+${DAYS} days" +"%B %d, %Y")

    clear
    echo -e "${GREEN}Account provisioned successfully${NC}       "
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Username      : ${GREEN}${USERNAME}${NC}"
    echo -e "Password      : ${GREEN}${PASSWORD}${NC}"
    echo -e "Expires On    : ${ORANGE}${EXP_DATE_FORMATTED}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "         ${BOLD}SERVER INFORMATION${NC}          "
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "IP            : ${GREEN}${IP_ADDR}${NC}"
    echo -e "Host          : ${GREEN}${PRIMARY_DOMAIN}${NC}"
    echo -e "Nameserver    : ${GREEN}${NS_DOMAIN}${NC}"
    echo -e "PubKey        : ${ORANGE}${PUB_KEY}${NC}"
    echo -e "OpenSSH       : ${PORT_SSH:-22}"
    echo -e "SSH-WS        : ${PORT_WS_HTTP:-80}"
    echo -e "Custom SSH    : 8880"
    echo -e "SSH-SSL-WS    : ${PORT_WS_HTTPS:-443}"
    echo -e "Dropbear      : ${PORT_DROPBEAR:-109}, 143"
    echo -e "SSL/TLS       : 447, 777"
    echo -e "SOCKS5        : ${PORT_SOCKS:-1080}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "SSH-80        : ${PRIMARY_DOMAIN}:80@${USERNAME}:${PASSWORD}"
    echo -e "SSH-8880      : ${PRIMARY_DOMAIN}:8880@${USERNAME}:${PASSWORD}"
    echo -e "SSH-443       : ${PRIMARY_DOMAIN}:443@${USERNAME}:${PASSWORD}"
    echo -e "SOCKS5        : ${PRIMARY_DOMAIN}:1080:${USERNAME}:${PASSWORD}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${ORANGE}(Payload WSS)${NC}"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload WS - Port 80)${NC}"
    echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload Custom Bypass - Port 8880)${NC}"
    echo -e "GET http://${PRIMARY_DOMAIN}:8880 HTTP/1.1[crlf]Host: [ISP_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "     ${RED}${BOLD}NO SPAM | NO DDOS | NO TORRENT${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to dashboard..."
    show_dashboard
}



execute_del_user() {
    clear
    echo -e "${CYAN}=== DELETE VPN ACCOUNT ===${NC}"
    
    # Check if there are any users to delete
    local user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    if [ "$user_count" -eq 0 ]; then
        echo -e "\n${ORANGE}[!] No active users found in the database.${NC}"
        sleep 2
        show_dashboard
        return
    fi

    # Print the table header
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "EXPIRES ON"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Fetch users into an array for easy selection
    mapfile -t USER_LIST < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date FROM users;")
    
    local i=1
    for user_data in "${USER_LIST[@]}"; do
        local uname=$(echo "$user_data" | cut -d'|' -f1)
        # Extract just the YYYY-MM-DD part for the table display
        local exp=$(echo "$user_data" | cut -d'|' -f2 | cut -d' ' -f1)
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$exp"
        ((i++))
    done
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${ORANGE}[0] Cancel and return to dashboard${NC}\n"

    read -p "Select S/N or type Username to delete: " TARGET_USER
    
    if [[ "$TARGET_USER" == "0" ]]; then
        show_dashboard
        return
    fi

    local FINAL_USERNAME=""
    local FINAL_EXPIRY=""

    # Check if the input is a valid S/N number
    if [[ "$TARGET_USER" =~ ^[0-9]+$ ]] && [ "$TARGET_USER" -le "${#USER_LIST[@]}" ] && [ "$TARGET_USER" -gt 0 ]; then
        local index=$((TARGET_USER - 1))
        FINAL_USERNAME=$(echo "${USER_LIST[$index]}" | cut -d'|' -f1)
        FINAL_EXPIRY=$(echo "${USER_LIST[$index]}" | cut -d'|' -f2)
    else
        # Otherwise, check if the input matches a username exactly
        for user_data in "${USER_LIST[@]}"; do
            local uname=$(echo "$user_data" | cut -d'|' -f1)
            if [[ "$uname" == "$TARGET_USER" ]]; then
                FINAL_USERNAME="$uname"
                FINAL_EXPIRY=$(echo "$user_data" | cut -d'|' -f2)
                break
            fi
        done
    fi

    # Reject if we couldn't match the input to a user
    if [[ -z "$FINAL_USERNAME" ]]; then
        echo -e "\n${RED}[-] Invalid selection or user does not exist.${NC}"
        sleep 2
        execute_del_user
        return
    fi

    # Call the backend API
    /opt/imagitech/bin/imagitech user del "$FINAL_USERNAME" > /dev/null 2>&1
    
    # Format the expiry date for the receipt
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")

    clear
    echo -e "${GREEN}Account deleted successfully${NC}       "
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Username      : ${RED}${FINAL_USERNAME}${NC}"
    echo -e "Expires On    : ${ORANGE}${EXP_DATE_FORMATTED}${NC}"
    echo -e "Status        : ${RED}Deleted${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to dashboard..."
    show_dashboard
}

execute_restart() {
    clear
    echo -e "${CYAN}=== RESTARTING SERVICES ===${NC}"
    echo -e "Sending restart signals via API..."
    
    /opt/imagitech/bin/imagitech service restart dropbear
    /opt/imagitech/bin/imagitech service restart stunnel4
    /opt/imagitech/bin/imagitech service restart imagitech-ws
    /opt/imagitech/bin/imagitech service restart imagitech-dnstt
    
    echo -e "${GREEN}[+] Services restarted successfully.${NC}"
    sleep 2
    show_dashboard
}

# --- The Interactive Dashboard (HUD) ---
show_dashboard() {
    clear
    get_system_stats
    get_db_stats

    draw_top
    echo -e "${CYAN}│${NC} ${BOLD}${GREEN}        IMAGITECH ENTERPRISE DASHBOARD          ${NC} ${CYAN}│${NC}"
    draw_mid
    echo -e "  ${ORANGE}✦ Server Uptime${NC}   : ${GREEN}${UPTIME}${NC}"
    echo -e "  ${ORANGE}✦ Operating Sys${NC}   : ${CYAN}${OS_INFO}${NC}"
    echo -e "  ${ORANGE}✦ RAM / CPU Load${NC}  : ${GREEN}${RAM_USED}MB / ${RAM_TOTAL}MB${NC}  |  ${CYAN}${CPU_USAGE}${NC}"
    echo -e "  ${ORANGE}✦ Primary Domain${NC}  : ${GREEN}${PRIMARY_DOMAIN}${NC}"
    draw_mid
    
    # Service Matrix Mapping to our new systemd units
    printf "  ${CYAN}WS-Proxy: %b   Stunnel : %b   Dropbear: %b${NC}\n" "$(check_service imagitech-ws)" "$(check_service stunnel4)" "$(check_service dropbear)"
    printf "  ${CYAN}Dante   : %b   BadVPN  : %b   DNSTT   : %b${NC}\n" "$(check_service danted)" "$(check_service imagitech-badvpn-7100)" "$(check_service imagitech-dnstt)"
    printf "  ${CYAN}Monitor : %b${NC}\n" "$(check_service imagitech-monitor)"
    draw_mid
    
    echo -e "  ${CYAN}[ Database Overview ]${NC}"
    echo -e "  Active Users : ${GREEN}${ACTIVE_USERS}${NC} / ${TOTAL_USERS}    Expired : ${RED}${EXPIRED_USERS}${NC}"
    draw_mid
    
    echo -e "  ${CYAN}[01]${NC} Create VPN Account    ${CYAN}[04]${NC} View Logs (Tail)"
    echo -e "  ${CYAN}[02]${NC} Delete VPN Account    ${CYAN}[05]${NC} Restart Services"
    echo -e "  ${CYAN}[03]${NC} Monitor Connections   ${CYAN}[00]${NC} Exit"
    draw_bot
    echo ""
    read -p " Select Option : " opt

    case $opt in
        1) execute_add_user ;;
        2) execute_del_user ;;
        3) 
           clear
           echo -e "${CYAN}Tracking active sessions... (Press CTRL+C to exit)${NC}"
           tail -f /opt/imagitech/logs/imagitech.log | grep -i "Violation"
           ;;
        4) 
           clear
           tail -n 50 /opt/imagitech/logs/imagitech.log
           read -n 1 -s -r -p "Press any key to return..."
           show_dashboard
           ;;
        5) execute_restart ;;
        0) clear; exit 0 ;;
        *) show_dashboard ;;
    esac
}

# Boot the HUD
show_dashboard

