# File: install.sh
# Purpose: Master Orchestrator for Imagitech Enterprise Platform.

#!/bin/bash

# ==========================================================
# ⚠️ CRITICAL: Ensure your GitHub repository structure matches
# the new /opt/imagitech/ architecture we built!
# ==========================================================
REPO_URL="https://raw.githubusercontent.com/dexteree11/imagitech-vpn/main"

# --- UI Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH ENTERPRISE DEPLOYMENT PIPELINE        ${NC}"
echo -e "${CYAN}======================================================${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[FATAL] Please run as root. (Type: sudo su -)${NC}"
    exit 1
fi

# Ensure basic fetch tools are present before we even start
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget >/dev/null 2>&1

# --- 1. System Scaffolding ---
echo -e "${CYAN}[*] Bootstrapping Base Architecture...${NC}"
mkdir -p /opt/imagitech/{bin,lib,logs,menus,services,core}
mkdir -p /opt/imagitech/core/keys
mkdir -p /opt/imagitech/services/{monitor,routing}
mkdir -p /root/imagitech-tmp
cd /root/imagitech-tmp

# --- 2. Secure Fetch Function ---
# This function guarantees we don't accidentally execute a 404 HTML page.
fetch_file() {
    local remote_path="$1"
    local local_path="$2"
    
    echo -e "  -> Fetching: ${remote_path}"
    curl -sS -L -o "$local_path" "${REPO_URL}/${remote_path}"
    
    if [ ! -s "$local_path" ] || grep -q "404: Not Found" "$local_path"; then
        echo -e "${RED}[FATAL] Failed to download ${remote_path}. Halting to prevent system corruption.${NC}"
        exit 1
    fi
}

# --- 3. Stage Libraries & Core Files ---
echo -e "\n${CYAN}[*] Staging Core Libraries & APIs...${NC}"

# Fetching the libraries we built
fetch_file "lib/system.sh" "/opt/imagitech/lib/system.sh"
fetch_file "lib/installer_utils.sh" "/opt/imagitech/lib/installer_utils.sh"
fetch_file "lib/db.sh" "/opt/imagitech/lib/db.sh"
fetch_file "lib/users.sh" "/opt/imagitech/lib/users.sh"

# Fetching the CLI router and Menu
fetch_file "bin/imagitech" "/opt/imagitech/bin/imagitech"
fetch_file "menus/main_menu.sh" "/opt/imagitech/menus/main_menu.sh"

# Apply execution permissions to bin/menus
chmod +x /opt/imagitech/bin/imagitech
chmod +x /opt/imagitech/menus/main_menu.sh

# Fetching the Python services
fetch_file "services/monitor/daemon.py" "/opt/imagitech/services/monitor/daemon.py"
fetch_file "services/routing/async-ws-proxy.py" "/opt/imagitech/services/routing/ws-proxy.py"

# --- 4. Fetch & Execute Deployment Phases ---
echo -e "\n${GREEN}[*] Initiating Deployment Phases...${NC}"

PHASES=(
    "01-core-setup.sh"
    "02-deploy-routing.sh"
    "03-deploy-sidecars.sh"
    "04-deploy-monitor.sh"
)

for PHASE in "${PHASES[@]}"; do
    fetch_file "installers/${PHASE}" "/root/imagitech-tmp/${PHASE}"
    chmod +x "/root/imagitech-tmp/${PHASE}"
    
    echo -e "\n${ORANGE}>>> Executing Phase: ${PHASE} <<<${NC}"
    /root/imagitech-tmp/"${PHASE}"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FATAL] Phase ${PHASE} failed. Halting installation to protect OS integrity.${NC}"
        exit 1
    fi
done

# --- 5. Symlink Global Commands ---
echo -e "\n${CYAN}[*] Binding Global CLI Interfaces...${NC}"

# Safely remove old hardcoded binaries if they exist from the v1 script
rm -f /usr/bin/menu /usr/local/sbin/menu /usr/local/bin/imagitech

# Symlink the new modular paths globally
ln -sf /opt/imagitech/menus/main_menu.sh /usr/local/sbin/menu
ln -sf /opt/imagitech/bin/imagitech /usr/local/bin/imagitech

# --- 6. Cleanup & Finalization ---
cd /root
rm -rf /root/imagitech-tmp

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${GREEN}      IMAGITECH DEPLOYMENT COMPLETE                   ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo -e "Your infrastructure is now running safely in ${ORANGE}/opt/imagitech${NC}"
echo -e "Type ${GREEN}menu${NC} to access the UI dashboard."
echo -e "Type ${GREEN}imagitech${NC} to access the headless API commands."

