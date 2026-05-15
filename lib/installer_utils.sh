# File: /opt/imagitech/lib/installer_utils.sh
# Purpose: Idempotent helper functions for safe deployment.

# Ensure we have our logging function
source /opt/imagitech/lib/system.sh 2>/dev/null || echo "Warning: system.sh not found."

ensure_package() {
    local pkg="$1"
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        log_event "INFO" "Installing missing dependency: $pkg"
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1
    else
        log_event "INFO" "Dependency satisfied: $pkg"
    fi
}

safe_create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_event "INFO" "Created directory: $dir"
    fi
}

safe_deploy_systemd() {
    local service_name="$1"
    local service_file="/etc/systemd/system/${service_name}.service"
    local temp_file="/tmp/${service_name}.service.tmp"
    
    # The calling script will write the unit file to the temp location first
    if [ ! -f "$temp_file" ]; then
        log_event "ERROR" "Cannot deploy $service_name. Temp file missing."
        return 1
    fi

    # Check if the service file already exists and is identical
    if [ -f "$service_file" ] && cmp -s "$temp_file" "$service_file"; then
        log_event "INFO" "Service $service_name is unchanged. Skipping deployment."
        rm -f "$temp_file"
    else
        log_event "INFO" "Deploying/Updating service: $service_name"
        mv "$temp_file" "$service_file"
        systemctl daemon-reload
        systemctl enable "$service_name" >/dev/null 2>&1
        systemctl restart "$service_name"
    fi
}

ensure_tls_cert() {
    local domain="$1"
    local cert_path="/opt/imagitech/core/keys/stunnel.pem"
    
    if [ -s "$cert_path" ]; then
        log_event "INFO" "TLS Certificate already exists for $domain. Skipping ACME request."
        return 0
    fi
    
    log_event "INFO" "Requesting Let's Encrypt Certificate for $domain..."
    # We must ensure port 80 is free before running standalone Let's Encrypt
    systemctl stop ws-proxy nginx apache2 2>/dev/null
    
    # Proceed with acme.sh issuance...
    # (Insert your acme.sh logic here, outputting to $cert_path)
}

