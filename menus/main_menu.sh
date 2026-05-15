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
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

draw_top() { echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"; }
draw_line() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# --- Live Data Harvesters ---
get_system_stats() {
    OS_INFO=$(grep -w PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
}

get_db_stats() {
    TOTAL_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    ACTIVE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='ACTIVE';" 2>/dev/null || echo "0")
    EXPIRED_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='EXPIRED';" 2>/dev/null || echo "0")
}

check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

pause() {
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
}

# ==========================================================
# [01] SSH PANEL
# ==========================================================
menu_ssh_panel() {
    while true; do
        clear
        draw_line
        echo -e "                   ${BOLD}SSH ACCOUNT PANEL${NC}                    "
        draw_line
        echo -e "  ${CYAN}[01]${NC} Create SSH Account"
        echo -e "  ${CYAN}[02]${NC} Create Trial SSH"
        echo -e "  ${CYAN}[03]${NC} Renew SSH Account"
        echo -e "  ${CYAN}[04]${NC} Delete SSH Account"
        echo -e "  ${CYAN}[05]${NC} Check Online Users"
        echo -e "  ${CYAN}[06]${NC} List Members"
        echo -e "  ${CYAN}[07]${NC} User Details (Print Credentials)"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) execute_add_user ;;
            2) execute_trial_user ;;
            3) execute_renew_user ;;
            4) execute_del_user ;;
            5) execute_online_users ;;
            6) execute_list_users ;;
            7) execute_user_details ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

execute_add_user() {
    while true; do
        clear
        echo -e "${CYAN}=== CREATE SSH ACCOUNT ===${NC}"
        
        read -p "Username: " USERNAME
        if [[ -z "$USERNAME" ]]; then echo -e "${RED}[ERROR] Username cannot be empty.${NC}"; sleep 1.5; continue; fi
        read -p "Password: " PASSWORD
        if [[ -z "$PASSWORD" ]]; then echo -e "${RED}[ERROR] Password cannot be empty.${NC}"; sleep 1.5; continue; fi
        read -p "Duration (Days): " DAYS
        if [[ -z "$DAYS" ]]; then echo -e "${RED}[ERROR] Duration cannot be empty.${NC}"; sleep 1.5; continue; fi

        /opt/imagitech/bin/imagitech user add "$USERNAME" "$PASSWORD" "$DAYS" > /dev/null 2>&1
        API_STATUS=$?
        
        if [ $API_STATUS -eq 2 ]; then
            echo -e "\n${ORANGE}[!] User '${USERNAME}' already exists.${NC}"
            read -p "Do you want to create another user? (y/n): " RETRY
            if [[ "$RETRY" =~ ^[Yy] ]]; then continue; else return; fi
        elif [ $API_STATUS -ne 0 ]; then
            echo -e "\n${RED}[-] Failed to create account. Check logs.${NC}"; pause; return
        fi
        break
    done

    print_user_receipt "$USERNAME" "$PASSWORD" "$DAYS" "days"
}

execute_trial_user() {
    clear
    echo -e "${CYAN}=== CREATE TRIAL SSH ACCOUNT ===${NC}"
    echo -e "${ORANGE}Note: Trial accounts expire automatically.${NC}"
    
    read -p "Username [default: trial_$(date +%s | tail -c 4)]: " USERNAME
    USERNAME=${USERNAME:-"trial_$(date +%s | tail -c 4)"}
    
    read -p "Password [default: 1234]: " PASSWORD
    PASSWORD=${PASSWORD:-"1234"}
    
    read -p "Duration in Hours [default: 24]: " HOURS
    HOURS=${HOURS:-24}

    # API call to be implemented in Step 2
    echo -e "\n${ORANGE}[API] Routing trial creation to backend...${NC}"
    /opt/imagitech/bin/imagitech user trial "$USERNAME" "$PASSWORD" "$HOURS" > /dev/null 2>&1
    
    print_user_receipt "$USERNAME" "$PASSWORD" "$HOURS" "hours"
}

execute_renew_user() {
    clear
    echo -e "${CYAN}=== RENEW SSH ACCOUNT ===${NC}"
    select_user_from_list
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi

    local OLD_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")

    echo -e "\nUser: ${GREEN}${FINAL_USERNAME}${NC} | Current Expiry: ${ORANGE}${OLD_DATE_FORMATTED}${NC}"
    echo -e "Enter days to add (e.g., 30) or days to deduct (e.g., -5):"
    read -p "Modification (Days): " MOD_DAYS

    # Ensure the input is a valid number (positive or negative)
    if ! [[ "$MOD_DAYS" =~ ^-?[0-9]+$ ]]; then
        echo -e "${RED}[-] Invalid input. Please enter a valid number.${NC}"
        sleep 2; return
    fi

    # Call the API silently
    /opt/imagitech/bin/imagitech user renew "$FINAL_USERNAME" "$MOD_DAYS" > /dev/null 2>&1
    
    # Fetch the newly updated expiry from the database
    local NEW_EXPIRY=$(sqlite3 "$DB_PATH" "SELECT expiry_date FROM users WHERE username='$FINAL_USERNAME';" 2>/dev/null)
    local NEW_DATE_FORMATTED=$(date -d "$NEW_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$NEW_EXPIRY")
    
    # Color code the modification output
    local MOD_DISPLAY=""
    if [ "$MOD_DAYS" -lt 0 ]; then
        MOD_DISPLAY="${RED}${MOD_DAYS} Days${NC}"
    else
        MOD_DISPLAY="${GREEN}+${MOD_DAYS} Days${NC}"
    fi

    clear
    echo -e "${GREEN}Account renewed successfully${NC}       "
    draw_line
    echo -e "Username      : ${GREEN}${FINAL_USERNAME}${NC}"
    echo -e "Modification  : ${MOD_DISPLAY}"
    echo -e "Old Expiry    : ${ORANGE}${OLD_DATE_FORMATTED}${NC}"
    echo -e "New Expiry    : ${GREEN}${NEW_DATE_FORMATTED}${NC}"
    draw_line
    
    pause
}

execute_del_user() {
    clear
    echo -e "${CYAN}=== DELETE SSH ACCOUNT ===${NC}"
    select_user_from_list
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi

    /opt/imagitech/bin/imagitech user del "$FINAL_USERNAME" > /dev/null 2>&1
    
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")
    clear
    echo -e "${GREEN}Account deleted successfully${NC}       "
    draw_line
    echo -e "Username      : ${RED}${FINAL_USERNAME}${NC}"
    echo -e "Expires On    : ${ORANGE}${EXP_DATE_FORMATTED}${NC}"
    echo -e "Status        : ${RED}Deleted${NC}"
    draw_line
    pause
}

execute_list_users() {
    clear
    echo -e "${CYAN}=== SSH MEMBERS LIST ===${NC}"
    draw_line
    printf "${BOLD}%-5s | %-15s | %-15s | %-10s${NC}\n" "S/N" "USERNAME" "EXPIRES ON" "STATUS"
    draw_line
    
    local i=1
    sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date, status FROM users;" | while read -r line; do
        local uname=$(echo "$line" | cut -d'|' -f1)
        local exp=$(echo "$line" | cut -d'|' -f2 | cut -d' ' -f1)
        local status=$(echo "$line" | cut -d'|' -f3)
        
        if [ "$status" == "ACTIVE" ]; then status_color="${GREEN}"; else status_color="${RED}"; fi
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC} | ${status_color}%-10s${NC}\n" "$i" "$uname" "$exp" "$status"
        ((i++))
    done
    draw_line
    pause
}

execute_online_users() {
    clear
    echo -e "${CYAN}=== ACTIVE CONNECTIONS ===${NC}"
    # API hook for the Monitor Daemon
    /opt/imagitech/bin/imagitech monitor online
    pause
}

execute_user_details() {
    clear
    echo -e "${CYAN}=== PRINT USER DETAILS ===${NC}"
    select_user_from_list
    if [[ -z "$FINAL_USERNAME" ]]; then return; fi
    
    # Format the absolute expiry date fetched from the list selection
    local EXP_DATE_FORMATTED=$(date -d "$FINAL_EXPIRY" +"%B %d, %Y" 2>/dev/null || echo "$FINAL_EXPIRY")
    local USERNAME="$FINAL_USERNAME"
    local PASSWORD="[HIDDEN]" # Security constraint: PAM handles auth, DB stores metadata
    
    # Fetch dynamic server data
    local IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    local PUB_KEY=$(cat /opt/imagitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")

    clear
    echo -e "${GREEN}User details fetched successfully${NC}       "
    draw_line
    echo -e "Username      : ${GREEN}${USERNAME}${NC}"
    echo -e "Password      : ${RED}${PASSWORD}${NC} (Encrypted by OS)"
    echo -e "Expires On    : ${ORANGE}${EXP_DATE_FORMATTED}${NC}"
    draw_line
    echo -e "         ${BOLD}SERVER INFORMATION${NC}          "
    draw_line
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
    draw_line
    echo -e "SSH-80        : ${PRIMARY_DOMAIN}:80@${USERNAME}:${PASSWORD}"
    echo -e "SSH-8880      : ${PRIMARY_DOMAIN}:8880@${USERNAME}:${PASSWORD}"
    echo -e "SSH-443       : ${PRIMARY_DOMAIN}:443@${USERNAME}:${PASSWORD}"
    echo -e "SOCKS5        : ${PRIMARY_DOMAIN}:1080:${USERNAME}:${PASSWORD}"
    draw_line
    echo -e "${ORANGE}(Payload WSS)${NC}"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload WS - Port 80)${NC}"
    echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload Custom Bypass - Port 8880)${NC}"
    echo -e "GET http://${PRIMARY_DOMAIN}:8880 HTTP/1.1[crlf]Host: [ISP_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    draw_line
    echo -e "     ${RED}${BOLD}NO SPAM | NO DDOS | NO TORRENT${NC}"
    draw_line
    
    pause
}

# --- Helper function for Interactive Lists ---
select_user_from_list() {
    local user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    if [ "$user_count" -eq 0 ]; then
        echo -e "\n${ORANGE}[!] No users found in the database.${NC}"
        sleep 2; FINAL_USERNAME=""; return
    fi

    draw_line
    printf "${BOLD}%-5s | %-15s | %-15s${NC}\n" "S/N" "USERNAME" "EXPIRES ON"
    draw_line
    
    mapfile -t USER_LIST < <(sqlite3 -separator '|' "$DB_PATH" "SELECT username, expiry_date FROM users;")
    local i=1
    for user_data in "${USER_LIST[@]}"; do
        local uname=$(echo "$user_data" | cut -d'|' -f1)
        local exp=$(echo "$user_data" | cut -d'|' -f2 | cut -d' ' -f1)
        printf "${GREEN}%-5s${NC} | ${CYAN}%-15s${NC} | ${ORANGE}%-15s${NC}\n" "$i" "$uname" "$exp"
        ((i++))
    done
    draw_line
    echo -e "${ORANGE}[0] Cancel${NC}\n"

    read -p "Select S/N or type Username: " TARGET_USER
    if [[ "$TARGET_USER" == "0" || -z "$TARGET_USER" ]]; then FINAL_USERNAME=""; return; fi

    FINAL_USERNAME=""
    if [[ "$TARGET_USER" =~ ^[0-9]+$ ]] && [ "$TARGET_USER" -le "${#USER_LIST[@]}" ] && [ "$TARGET_USER" -gt 0 ]; then
        local index=$((TARGET_USER - 1))
        FINAL_USERNAME=$(echo "${USER_LIST[$index]}" | cut -d'|' -f1)
        FINAL_EXPIRY=$(echo "${USER_LIST[$index]}" | cut -d'|' -f2)
    else
        for user_data in "${USER_LIST[@]}"; do
            local uname=$(echo "$user_data" | cut -d'|' -f1)
            if [[ "$uname" == "$TARGET_USER" ]]; then
                FINAL_USERNAME="$uname"
                FINAL_EXPIRY=$(echo "$user_data" | cut -d'|' -f2)
                break
            fi
        done
    fi

    if [[ -z "$FINAL_USERNAME" ]]; then
        echo -e "\n${RED}[-] Invalid selection.${NC}"; sleep 1; FINAL_USERNAME=""
    fi
}

print_user_receipt() {
    local USERNAME="$1"
    local PASSWORD="$2"
    local TIME_VAL="$3"
    local TIME_TYPE="$4"
    
    IP_ADDR=$(curl -sS ipv4.icanhazip.com)
    PUB_KEY=$(cat /opt/imagitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
    
    if [ "$TIME_TYPE" == "hours" ]; then
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} hours" +"%B %d, %Y - %H:%M")
    else
        EXP_DATE_FORMATTED=$(date -d "+${TIME_VAL} days" +"%B %d, %Y")
    fi

    clear
    echo -e "${GREEN}Account provisioned successfully${NC}       "
    draw_line
    echo -e "Username      : ${GREEN}${USERNAME}${NC}"
    echo -e "Password      : ${GREEN}${PASSWORD}${NC}"
    echo -e "Expires On    : ${ORANGE}${EXP_DATE_FORMATTED}${NC}"
    draw_line
    echo -e "         ${BOLD}SERVER INFORMATION${NC}          "
    draw_line
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
    draw_line
    echo -e "SSH-80        : ${PRIMARY_DOMAIN}:80@${USERNAME}:${PASSWORD}"
    echo -e "SSH-8880      : ${PRIMARY_DOMAIN}:8880@${USERNAME}:${PASSWORD}"
    echo -e "SSH-443       : ${PRIMARY_DOMAIN}:443@${USERNAME}:${PASSWORD}"
    echo -e "SOCKS5        : ${PRIMARY_DOMAIN}:1080:${USERNAME}:${PASSWORD}"
    draw_line
    echo -e "${ORANGE}(Payload WSS)${NC}"
    echo -e "GET wss://bug.com [protocol][crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload WS - Port 80)${NC}"
    echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "\n${ORANGE}(Payload Custom Bypass - Port 8880)${NC}"
    echo -e "GET http://${PRIMARY_DOMAIN}:8880 HTTP/1.1[crlf]Host: [ISP_BUG_HOST][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    draw_line
    echo -e "     ${RED}${BOLD}NO SPAM | NO DDOS | NO TORRENT${NC}"
    draw_line
    pause
}

# ==========================================================
# [02] DOMAIN & SSL
# ==========================================================
menu_domain_ssl() {
    while true; do
        clear
        PUB_KEY=$(cat /opt/imagitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
        draw_line
        echo -e "                   ${BOLD}DOMAIN & SSL${NC}                     "
        draw_line
        echo -e "  Current Host : ${GREEN}${PRIMARY_DOMAIN}${NC}"
        echo -e "  Current NS   : ${CYAN}${NS_DOMAIN}${NC}"
        echo -e "  SlowDNS Pub  : ${ORANGE}${PUB_KEY}${NC}"
        draw_line
        echo -e "  ${CYAN}[01]${NC} Change Host Domain"
        echo -e "  ${CYAN}[02]${NC} Change NS Domain"
        echo -e "  ${CYAN}[03]${NC} Renew SSL Certificate (Let's Encrypt)"
        echo -e "  ${CYAN}[04]${NC} View Certificate Status"
        echo -e "  ${CYAN}[05]${NC} Generate New SlowDNS Key"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) echo "Calling API: imagitech config host..."; pause ;;
            2) echo "Calling API: imagitech config ns..."; pause ;;
            3) echo "Calling API: imagitech cert renew..."; pause ;;
            4) echo "Calling API: imagitech cert status..."; pause ;;
            5) echo "Calling API: imagitech dnstt renew..."; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [03] RUNNING SERVICES
# ==========================================================
menu_services() {
    while true; do
        clear
        draw_line
        echo -e "                 ${BOLD}RUNNING SERVICES${NC}                   "
        draw_line
        echo -e "  ${CYAN}OpenSSH           :${NC} 22"
        echo -e "  ${CYAN}Dropbear          :${NC} 109, 143"
        echo -e "  ${CYAN}Stunnel4          :${NC} 447, 777"
        echo -e "  ${CYAN}SSH-WS (HTTP)     :${NC} 80"
        echo -e "  ${CYAN}Custom SSH (HTTP) :${NC} 8880"
        echo -e "  ${CYAN}SlowDNS (DNSTT)   :${NC} 53, 5300"
        echo -e "  ${CYAN}BadVPN UDPGW      :${NC} 7100, 7200, 7300"
        echo -e "  ${CYAN}SOCKS5 Proxy      :${NC} 1080"
        draw_line
        echo -e "  ${CYAN}[01]${NC} Restart All Services"
        echo -e "  ${CYAN}[02]${NC} Restart Dropbear"
        echo -e "  ${CYAN}[03]${NC} Restart WebSocket Proxy"
        echo -e "  ${CYAN}[04]${NC} Restart Stunnel"
        echo -e "  ${CYAN}[05]${NC} Restart DNSTT"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) /opt/imagitech/bin/imagitech service restart all; pause ;;
            2) /opt/imagitech/bin/imagitech service restart dropbear; pause ;;
            3) /opt/imagitech/bin/imagitech service restart imagitech-ws; pause ;;
            4) /opt/imagitech/bin/imagitech service restart stunnel4; pause ;;
            5) /opt/imagitech/bin/imagitech service restart imagitech-dnstt; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [04] MONITORING
# ==========================================================
menu_monitoring() {
    while true; do
        clear
        draw_line
        echo -e "                    ${BOLD}MONITORING${NC}                      "
        draw_line
        echo -e "  ${CYAN}[01]${NC} Current Bandwidth Usage"
        echo -e "  ${CYAN}[02]${NC} Top Users"
        echo -e "  ${CYAN}[03]${NC} Connection Logs"
        echo -e "  ${CYAN}[04]${NC} Failed Login Attempts"
        echo -e "  ${CYAN}[05]${NC} System Resource Usage"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) echo "Backend tracking module required."; pause ;;
            2) echo "Backend tracking module required."; pause ;;
            3) tail -n 50 /opt/imagitech/logs/imagitech.log; pause ;;
            4) grep "Failed password" /var/log/auth.log | tail -n 20; pause ;;
            5) htop || top -n 1; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# [05] SETTINGS
# ==========================================================
menu_settings() {
    while true; do
        clear
        draw_line
        echo -e "                     ${BOLD}SETTINGS${NC}                       "
        draw_line
        echo -e "  ${CYAN}[01]${NC} Set Auto Reboot"
        echo -e "  ${CYAN}[02]${NC} Change SSH Banner"
        echo -e "  ${CYAN}[03]${NC} Speedtest Server"
        echo -e "  ${CYAN}[04]${NC} Uninstall Script"
        echo -e ""
        echo -e "  ${RED}[00]${NC} Return to Main Menu"
        draw_line
        read -p " Select Option : " opt

        case $opt in
            1) echo "Calling API: imagitech sys autoreboot..."; pause ;;
            2) echo "Calling API: imagitech sys banner..."; pause ;;
            3) 
               echo -e "${CYAN}Running Speedtest...${NC}"
               if ! command -v speedtest-cli &> /dev/null; then apt-get install -y speedtest-cli >/dev/null; fi
               speedtest-cli
               pause ;;
            4) echo "Calling API: imagitech sys uninstall..."; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================================
# MAIN DASHBOARD LOOP
# ==========================================================
show_dashboard() {
    while true; do
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
        
        printf "  ${CYAN}WS-Proxy: %b   Stunnel : %b   Dropbear: %b${NC}\n" "$(check_service imagitech-ws)" "$(check_service stunnel4)" "$(check_service dropbear)"
        printf "  ${CYAN}Dante   : %b   BadVPN  : %b   DNSTT   : %b${NC}\n" "$(check_service danted)" "$(check_service imagitech-badvpn-7100)" "$(check_service imagitech-dnstt)"
        printf "  ${CYAN}Monitor : %b${NC}\n" "$(check_service imagitech-monitor)"
        draw_mid
        
        echo -e "  ${CYAN}[ Database Overview ]${NC}"
        echo -e "  Active Users : ${GREEN}${ACTIVE_USERS}${NC} / ${TOTAL_USERS}    Expired : ${RED}${EXPIRED_USERS}${NC}"
        draw_mid
        
        echo -e "  ${CYAN}[01]${NC} SSH PANEL           ${CYAN}[02]${NC} DOMAIN & SSL"
        echo -e "  ${CYAN}[03]${NC} RUNNING SERVICES    ${CYAN}[04]${NC} MONITORING"
        echo -e "  ${CYAN}[05]${NC} SETTINGS            ${CYAN}[06]${NC} BACKUP & RESTORE"
        echo -e "  ${CYAN}[07]${NC} UPDATE SCRIPT       ${CYAN}[08]${NC} REBOOT"
        echo -e ""
        echo -e "  ${RED}[00]${NC} EXIT"
        draw_bot
        read -p " Select Option : " opt

        case $opt in
            1) menu_ssh_panel ;;
            2) menu_domain_ssl ;;
            3) menu_services ;;
            4) menu_monitoring ;;
            5) menu_settings ;;
            6) echo -e "\n${ORANGE}[!] Backup Module Loading...${NC}"; sleep 1 ;;
            7) echo -e "\n${CYAN}[*] Checking GitHub repository for updates...${NC}"; sleep 1 ;;
            8) 
               read -p "Are you sure you want to reboot the server? (y/n): " confirm
               if [[ "$confirm" =~ ^[Yy] ]]; then reboot; fi
               ;;
            0) clear; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Boot the HUD
show_dashboard
