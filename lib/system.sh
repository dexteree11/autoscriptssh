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
