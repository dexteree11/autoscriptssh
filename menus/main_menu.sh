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
    clear
    echo -e "${CYAN}=== CREATE ISP BYPASS ACCOUNT ===${NC}"
    read -p "Username: " USERNAME
    read -p "Password: " PASSWORD
    read -p "Duration (Days): " DAYS

    # Call the backend API instead of running raw commands
    /opt/imagitech/bin/imagitech user add "$USERNAME" "$PASSWORD" "$DAYS"
    
    if [ $? -eq 0 ]; then
        # Fetch dynamic data for the payload printout
        IP_ADDR=$(curl -sS ipv4.icanhazip.com)
        PUB_KEY=$(cat /opt/imagitech/core/keys/dnstt.pub 2>/dev/null || echo "Missing Key")
        EXP_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d")

        echo -e "\n${GREEN}[+] Account Provisioned Successfully!${NC}"
        echo -e "Copy the details below for your client:"
        echo -e "\n${CYAN}IP            :${NC} ${IP_ADDR}"
        echo -e "${CYAN}Host          :${NC} ${PRIMARY_DOMAIN}"
        echo -e "${CYAN}Nameserver    :${NC} ${NS_DOMAIN}"
        echo -e "${CYAN}PubKey        :${NC} ${PUB_KEY}"
        echo -e "${CYAN}Dropbear      :${NC} ${PORT_DROPBEAR}, 143"
        echo -e "${CYAN}SSH-WS        :${NC} ${PORT_WS_HTTP}"
        echo -e "${CYAN}Custom SSH    :${NC} 8880"
        echo -e "${CYAN}SSH-SSL-WS    :${NC} ${PORT_WS_HTTPS}"
        echo -e "${CYAN}UDPGW         :${NC} 7100, 7200, 7300"
        echo -e "${CYAN}SOCKS5        :${NC} ${PORT_SOCKS}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}SSH-80        :${NC} ${PRIMARY_DOMAIN}:${PORT_WS_HTTP}@${USERNAME}:${PASSWORD}"
        echo -e "${CYAN}SSH-8880      :${NC} ${PRIMARY_DOMAIN}:8880@${USERNAME}:${PASSWORD}"
        echo -e "${CYAN}SSH-443       :${NC} ${PRIMARY_DOMAIN}:${PORT_WS_HTTPS}@${USERNAME}:${PASSWORD}"
        echo -e "${CYAN}SOCKS5        :${NC} ${PRIMARY_DOMAIN}:${PORT_SOCKS}:${USERNAME}:${PASSWORD}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${ORANGE}(Payload WS - Port 80)${NC}"
        echo -e "GET / HTTP/1.1[crlf]Host: ${PRIMARY_DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "\n${CYAN}Expires On    :${NC} ${EXP_DATE}"
    else
        echo -e "\n${RED}[-] Failed to create account. Check logs at /opt/imagitech/logs/imagitech.log${NC}"
    fi
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to dashboard..."
    show_dashboard
}

execute_del_user() {
    clear
    echo -e "${CYAN}=== DELETE VPN ACCOUNT ===${NC}"
    read -p "Username: " USERNAME
    
    /opt/imagitech/bin/imagitech user del "$USERNAME"
    
    echo -e "\n${GREEN}[+] Deletion request processed for $USERNAME.${NC}"
    sleep 2
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

