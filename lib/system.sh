# File: /opt/imagitech/lib/system.sh
# Purpose: Core system utilities and logging.

# Safely source config ONLY if it exists (prevents errors on fresh install)
if [ -f /opt/imagitech/core/imagitech.conf ]; then
    source /opt/imagitech/core/imagitech.conf
fi

# Fallback values for early execution before config is generated
LOG_DIR="${LOG_DIR:-/opt/imagitech/logs}"
DB_PATH="${DB_PATH:-/opt/imagitech/core/database.db}"

log_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_file="${LOG_DIR}/imagitech.log"
    
    # Ensure log directory exists safely
    mkdir -p "$LOG_DIR"
    
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Print to stdout if running interactively
    if [ -t 1 ]; then
        case "$level" in
            "INFO")  echo -e "\033[0;32m[INFO]\033[0m $message" ;;
            "WARN")  echo -e "\033[0;33m[WARN]\033[0m $message" ;;
            "ERROR") echo -e "\033[0;31m[ERROR]\033[0m $message" ;;
            *)       echo -e "[$level] $message" ;;
        esac
    fi
}

check_root() {
    if [ "${EUID}" -ne 0 ]; then
        log_event "ERROR" "Execution attempted without root privileges."
        exit 1
    fi
}

change_host_domain() {
    local new_domain="$1"
    if [[ -z "$new_domain" ]]; then return 1; fi
    
    # Safely update the global configuration
    sed -i "s/PRIMARY_DOMAIN=.*/PRIMARY_DOMAIN=\"$new_domain\"/" /opt/imagitech/core/imagitech.conf
    log_event "INFO" "Primary Host Domain updated to: $new_domain"
}

change_ns_domain() {
    local new_ns="$1"
    if [[ -z "$new_ns" ]]; then return 1; fi
    
    # 1. Update global config
    sed -i "s/NS_DOMAIN=.*/NS_DOMAIN=\"$new_ns\"/" /opt/imagitech/core/imagitech.conf
    source /opt/imagitech/core/imagitech.conf
    
    # 2. Re-write the systemd service to use the new NS domain
    cat <<EOF > /etc/systemd/system/imagitech-dnstt.service
[Unit]
Description=Imagitech DNSTT Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/imagitech/bin/dnstt-server -udp :5300 -privkey-file /opt/imagitech/core/keys/dnstt.key ${new_ns} 127.0.0.1:${PORT_DROPBEAR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 3. Apply changes
    systemctl daemon-reload
    systemctl restart imagitech-dnstt
    log_event "INFO" "NS Domain updated to $new_ns and DNSTT Service restarted."
}

renew_ssl_cert() {
    local domain="$1"
    [[ -z "$domain" ]] && domain=$(grep PRIMARY_DOMAIN /opt/imagitech/core/imagitech.conf | cut -d'"' -f2)
    
    log_event "INFO" "Initiating Let's Encrypt SSL generation for: $domain"
    
    # 1. Free Port 80 by killing the WS proxy temporarily
    systemctl stop imagitech-ws stunnel4 nginx apache2 >/dev/null 2>&1
    
    # 2. Install acme.sh if not present
    if [ ! -d "/root/.acme.sh" ]; then
        log_event "INFO" "Installing acme.sh client..."
        curl -sL https://get.acme.sh | sh -s email=admin@$domain >/dev/null 2>&1
    fi
    
    local ACME="/root/.acme.sh/acme.sh"
    
    # 3. Issue and Install Certificate
    $ACME --issue -d "$domain" --standalone --server letsencrypt --force
    $ACME --installcert -d "$domain" \
        --fullchain-file /opt/imagitech/core/keys/fullchain.cer \
        --key-file /opt/imagitech/core/keys/private.key
        
    # 4. Bundle for Stunnel and Verify
    if [ -s /opt/imagitech/core/keys/fullchain.cer ]; then
        cat /opt/imagitech/core/keys/fullchain.cer /opt/imagitech/core/keys/private.key > /opt/imagitech/core/keys/stunnel.pem
        chmod 600 /opt/imagitech/core/keys/stunnel.pem
        log_event "INFO" "TLS Certificate successfully bundled and secured."
    else
        log_event "ERROR" "Failed to generate TLS Certificate. Is the domain pointing to this server IP?"
    fi
    
    # 5. Restore Services
    systemctl start imagitech-ws stunnel4
    log_event "INFO" "Data plane services restored."
}

generate_dnstt_key() {
    log_event "INFO" "Generating fresh DNSTT cryptographic keys..."
    cd /opt/imagitech/core/keys
    rm -f dnstt.key dnstt.pub
    
    /opt/imagitech/bin/dnstt-server -gen-key -privkey-file dnstt.key -pubkey-file dnstt.pub
    systemctl restart imagitech-dnstt
    
    log_event "INFO" "New DNSTT keys generated. Public key is ready for client payloads."
}

set_auto_reboot() {
    local hours="$1"
    
    # Safely remove any existing Imagitech reboot cron jobs
    crontab -l 2>/dev/null | grep -v "/sbin/reboot" | crontab -
    
    if [ "$hours" -gt 0 ]; then
        # Schedule the new reboot (e.g., 0 */6 * * * means minute 0, every 6th hour)
        (crontab -l 2>/dev/null; echo "0 */$hours * * * /sbin/reboot") | crontab -
        log_event "INFO" "Server auto-reboot scheduled for every $hours hours."
    else
        log_event "INFO" "Server auto-reboot has been disabled."
    fi
}

change_banner() {
    # Open the file directly in nano for the user
    nano /etc/issue.net
    
    # Once the user exits nano, restart daemons to apply changes instantly
    systemctl restart dropbear >/dev/null 2>&1
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
    systemctl restart ssh.socket >/dev/null 2>&1 # Ubuntu 24.04 fix
    
    log_event "INFO" "SSH Banner updated and services restarted successfully."
}

uninstall_script() {
    log_event "WARN" "Initiating complete uninstallation of Imagitech VPN Platform..."
    
    # 1. Stop and Disable all managed services
    local services=(imagitech-ws imagitech-dnstt imagitech-monitor imagitech-badvpn-7100 imagitech-badvpn-7200 imagitech-badvpn-7300 stunnel4 dropbear danted)
    for svc in "${services[@]}"; do
        systemctl stop "$svc" >/dev/null 2>&1
        systemctl disable "$svc" >/dev/null 2>&1
    done
    
    # 2. Remove Systemd Unit Files
    rm -f /etc/systemd/system/imagitech-*.service
    systemctl daemon-reload
    
    # 3. Clean routing rules & accounting chains
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null
    iptables -D INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -j IMAGITECH-ACCT 2>/dev/null
    iptables -F IMAGITECH-ACCT 2>/dev/null
    iptables -X IMAGITECH-ACCT 2>/dev/null
    
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    
    # 4. Remove Bashrc bindings and Global CLI commands
    sed -i '/menu/d' /root/.bashrc
    rm -f /usr/local/bin/imagitech /usr/local/sbin/menu
    
    # Clean up the installer script from the root directory
    rm -f /root/install.sh
    
    # 5. Remove all created VPN users (those with /bin/false shell)
    log_event "INFO" "Removing VPN users..."
    for u in $(awk -F: '/\/bin\/false/{print $1}' /etc/passwd); do
        if [[ "$u" != "syslog" && "$u" != "messagebus" && "$u" != "systemd-"* ]]; then
            userdel -f "$u" 2>/dev/null
        fi
    done

    # 6. Clean SSH config
    rm -f /etc/ssh/sshd_config.d/99-imagitech-banner.conf
    sed -i '/Banner \/etc\/issue.net/d' /etc/ssh/sshd_config
    sed -i '/MaxStartups/d' /etc/ssh/sshd_config
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

    # 7. Nuke the Architecture Directory
    rm -rf /opt/imagitech
    
    log_event "INFO" "Uninstallation complete. Your VPS is now clean."
    log_event "INFO" "Note: Please disconnect and reconnect to your server to clear your terminal's command cache."
}

# Move this OUTSIDE to prevent nested function errors
safe_fetch() {
    local repo_url="https://raw.githubusercontent.com/dexteree11/autoscriptssh/main"
    local file_path="$1"
    local target_path="$2"
    local tmp_dir="/tmp/imagitech_update"
    local filename=$(basename "$file_path")
    
    echo -e "  \033[0;36m-> Fetching ${filename}...\033[0m"
    curl -sS -L -o "$tmp_dir/$filename" "$repo_url/$file_path"
    
    # regex bracket protects the code from the quine bug
    if [ -s "$tmp_dir/$filename" ] && ! grep -q "404: N[o]t Found" "$tmp_dir/$filename"; then
        cp -f "$tmp_dir/$filename" "$target_path"
        chmod +x "$target_path" 2>/dev/null || true
    else
        log_event "ERROR" "Failed to fetch $file_path. Skipping."
        echo -e "  \033[0;31m[!] Failed to fetch $filename\033[0m"
    fi
}

update_script() {
    log_event "INFO" "Initiating platform update from GitHub..."
    local tmp_dir="/tmp/imagitech_update"

    # Ensure a fresh staging area
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    echo -e "\033[0;33m[*] Downloading latest core files...\033[0m"
    
    # 1. Update Core Libraries
    safe_fetch "lib/system.sh" "/opt/imagitech/lib/system.sh"
    safe_fetch "lib/users.sh" "/opt/imagitech/lib/users.sh"
    safe_fetch "lib/services.sh" "/opt/imagitech/lib/services.sh"
    safe_fetch "lib/db.sh" "/opt/imagitech/lib/db.sh"
    safe_fetch "lib/installer_utils.sh" "/opt/imagitech/lib/installer_utils.sh"
    
    # 2. Update APIs and Menus
    safe_fetch "bin/imagitech" "/opt/imagitech/bin/imagitech"
    safe_fetch "menus/main_menu.sh" "/opt/imagitech/menus/main_menu.sh"
    
    # 3. Update Python Services
    safe_fetch "services/monitor/daemon.py" "/opt/imagitech/services/monitor/daemon.py"
    safe_fetch "services/routing/async-ws-proxy.py" "/opt/imagitech/services/routing/ws-proxy.py"

    # 4. Database Migrations (Direct query to avoid infinite sourcing loop)
    echo -e "  \033[0;36m-> Running database migrations...\033[0m"
    local DB_PATH="/opt/imagitech/core/database.db"
    local col_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_usage")
    if [[ -z "$col_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_usage BIGINT DEFAULT 0;"
    fi

    # Clean up staging area
    rm -rf "$tmp_dir"

    # Restart background daemons to restore services
    systemctl daemon-reload
    systemctl restart imagitech-ws imagitech-monitor >/dev/null 2>&1

    log_event "INFO" "Platform update complete."
    echo -e "\n\033[0;32m[+] Update applied successfully! System is running the latest version.\033[0m"
}

create_backup() {
    local backup_dir="/opt/imagitech/backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/imagitech_backup_$timestamp.tar.gz"
    local encrypted_file="${backup_file}.enc"

    cd /opt/imagitech
    
    # Safely extract VPN users' credentials for backup
    grep "/bin/false" /etc/passwd > core/vpn_passwd.bak 2>/dev/null || true
    grep -f <(awk -F: '/\/bin\/false/{print $1}' /etc/passwd) /etc/shadow > core/vpn_shadow.bak 2>/dev/null || true
    
    tar -czf "$backup_file" core/database.db core/imagitech.conf core/keys/ core/vpn_passwd.bak core/vpn_shadow.bak >/dev/null 2>&1
    
    # Cleanup staging files
    rm -f core/vpn_passwd.bak core/vpn_shadow.bak

    echo -e "\n\033[0;36m=== SECURE BACKUP ===\033[0m"
    read -s -p "Enter encryption password: " ENC_PASS
    echo
    read -s -p "Confirm password: " ENC_PASS2
    echo
    
    if [ "$ENC_PASS" != "$ENC_PASS2" ]; then
        echo -e "\033[0;31m[-] Passwords do not match. Aborting.\033[0m"
        rm -f "$backup_file"
        return 1
    fi

    openssl enc -aes-256-cbc -pbkdf2 -in "$backup_file" -out "$encrypted_file" -k "$ENC_PASS" >/dev/null 2>&1
    rm -f "$backup_file"

    echo -e "\n\033[0;32m[+] Encrypted backup saved to:\033[0m $encrypted_file"
    log_event "INFO" "Encrypted backup created: $encrypted_file"
}

restore_backup() {
    local encrypted_file="$1"
    
    if [ ! -f "$encrypted_file" ]; then
        log_event "ERROR" "Backup file not found: $encrypted_file"
        return 1
    fi

    echo -e "\n\033[0;36m=== DECRYPT BACKUP ===\033[0m"
    read -s -p "Enter decryption password: " ENC_PASS
    echo

    local temp_archive="/tmp/restored_backup.tar.gz"
    
    # Attempt decryption
    if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "$encrypted_file" -out "$temp_archive" -k "$ENC_PASS" 2>/dev/null; then
        echo -e "\033[0;31m[-] Incorrect password or corrupted archive.\033[0m"
        rm -f "$temp_archive"
        return 1
    fi

    log_event "WARN" "Restoring system state from encrypted archive..."
    tar -xzf "$temp_archive" -C /opt/imagitech >/dev/null 2>&1
    rm -f "$temp_archive"

    # Restore VPN Linux users safely
    if [ -f /opt/imagitech/core/vpn_passwd.bak ]; then
        log_event "INFO" "Restoring VPN user system accounts..."
        while IFS= read -r line; do
            local uname=$(echo "$line" | cut -d: -f1)
            # Remove user if they already exist to prevent duplicates
            if grep -q "^$uname:" /etc/passwd; then
                userdel -f "$uname" 2>/dev/null
            fi
            echo "$line" >> /etc/passwd
        done < /opt/imagitech/core/vpn_passwd.bak
        rm -f /opt/imagitech/core/vpn_passwd.bak
    fi

    if [ -f /opt/imagitech/core/vpn_shadow.bak ]; then
        while IFS= read -r line; do
            local uname=$(echo "$line" | cut -d: -f1)
            sed -i "/^$uname:/d" /etc/shadow
            echo "$line" >> /etc/shadow
        done < /opt/imagitech/core/vpn_shadow.bak
        rm -f /opt/imagitech/core/vpn_shadow.bak
    fi

    chmod 600 /opt/imagitech/core/keys/* 2>/dev/null || true
    systemctl restart imagitech-ws imagitech-dnstt stunnel4 dropbear >/dev/null 2>&1
    log_event "INFO" "System state successfully restored."
}

install_fail2ban() {
    log_event "INFO" "Initiating Fail2Ban deployment..."

    # 1. Install the package if missing
    if ! command -v fail2ban-server &> /dev/null; then
        echo -e "\033[0;33m[*] Installing Fail2Ban package (this may take a moment)...\033[0m"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update >/dev/null 2>&1
        apt-get install -y fail2ban iptables >/dev/null 2>&1
    fi

    # 2. Deploy the custom Jail configuration
    echo -e "\033[0;36m[*] Writing strict SSH security rules...\033[0m"
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = iptables-multiport

[sshd]
enabled = true
port    = ${PORT_SSH:-22}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

    # 3. Apply and start the bouncer
    systemctl daemon-reload
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1

    log_event "INFO" "Fail2Ban successfully configured to protect OpenSSH."
    echo -e "\n\033[0;32m[+] Deployment complete! Fail2Ban is now actively terminating botnets.\033[0m"
}
