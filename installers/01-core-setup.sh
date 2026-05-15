# File: /root/imagitech-install/01-core-setup.sh
# Purpose: Bootstraps the environment idempotently.

#!/bin/bash
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Starting Phase 1: Core Infrastructure Setup"

# 1. Scaffolding Directories safely
safe_create_dir "/opt/imagitech/bin"
safe_create_dir "/opt/imagitech/core/keys"
safe_create_dir "/opt/imagitech/lib"
safe_create_dir "/opt/imagitech/logs"
safe_create_dir "/opt/imagitech/services/monitor"

# 2. Idempotent Dependency Installation
PACKAGES=(
    "curl" "wget" "git" "cron" "iptables" "lsof" "tar" "unzip" 
    "uuid-runtime" "ca-certificates" "openssl" "sqlite3"
    "dropbear" "stunnel4" "dante-server" "python3"
)

log_event "INFO" "Verifying core dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -y > /dev/null 2>&1
for pkg in "${PACKAGES[@]}"; do
    ensure_package "$pkg"
done

# 3. Safe Configuration Generation
CONF_FILE="/opt/imagitech/core/imagitech.conf"
if [ ! -f "$CONF_FILE" ]; then
    log_event "INFO" "Configuration file missing. Initiating interactive setup."
    
    read -p "Primary VPN Domain (e.g., vpn.imagitech.online): " DOMAIN
    read -p "Nameserver Domain (e.g., ns.imagitech.online): " NS_DOMAIN
    
    cat <<EOF > "$CONF_FILE"
# IMAGITECH GLOBAL CONFIGURATION
BASE_DIR="/opt/imagitech"
PRIMARY_DOMAIN="$DOMAIN"
NS_DOMAIN="$NS_DOMAIN"
MAX_LOGINS_DEFAULT=1
EOF
    log_event "INFO" "Configuration saved to $CONF_FILE."
else
    log_event "INFO" "Existing configuration found. Sourcing values."
    source "$CONF_FILE"
fi

# 4. Safe Database Initialization
# (Calls the function we wrote in Phase 2)
source /opt/imagitech/lib/db.sh
init_database

log_event "INFO" "Phase 1 Complete."

