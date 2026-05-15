# File: /root/imagitech-install/03-deploy-sidecars.sh
# Purpose: Idempotent deployment of Dante, BadVPN, and DNSTT.

#!/bin/bash
source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 3: Sidecar Protocols"

# Define your raw binary hosting URL
BINARY_URL="https://raw.githubusercontent.com/dexteree11/autoscriptssh/main/binaries"
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

safe_download_binary() {
    local bin_name="$1"
    local dest_path="/opt/imagitech/bin/$bin_name"
    
    if [ ! -x "$dest_path" ]; then
        log_event "INFO" "Downloading pre-compiled binary: $bin_name"
        wget -qO "$dest_path" "${BINARY_URL}/${bin_name}"
        chmod +x "$dest_path"
        
        # Verify the binary works (prevents corrupted downloads from breaking everything)
        if ! "$dest_path" --help >/dev/null 2>&1 && ! "$dest_path" -h >/dev/null 2>&1; then
            log_event "WARN" "Binary $bin_name downloaded but might not be executable."
        fi
    else
        log_event "INFO" "Binary $bin_name already exists and is executable."
    fi
}

# --- 1. Dante SOCKS5 Proxy ---
log_event "INFO" "Configuring Dante SOCKS5 Server..."

cat <<EOF > /etc/danted.conf
logoutput: syslog
user.privileged: root
user.unprivileged: nobody
internal: 0.0.0.0 port = ${PORT_SOCKS}
external: ${IFACE}
socksmethod: username
clientmethod: none
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
EOF

systemctl enable danted >/dev/null 2>&1
systemctl restart danted

# --- 2. BadVPN-UDPGW (Pre-compiled) ---
log_event "INFO" "Deploying BadVPN UDPGW..."

safe_download_binary "badvpn-udpgw"

for PORT in 7100 7200 7300; do
cat <<EOF > /tmp/imagitech-badvpn-${PORT}.service.tmp
[Unit]
Description=BadVPN UDPGW on port ${PORT}
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/imagitech/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT} --max-clients 500 --max-connections-for-client 10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    safe_deploy_systemd "imagitech-badvpn-${PORT}"
done

# --- 3. DNSTT / SlowDNS (Pre-compiled) ---
log_event "INFO" "Deploying DNSTT SlowDNS Server..."

safe_download_binary "dnstt-server"

# Idempotent Port 53 Release
if systemctl is-active --quiet systemd-resolved; then
    if grep -q "#DNSStubListener=yes" /etc/systemd/resolved.conf; then
        log_event "INFO" "Freeing Port 53 from systemd-resolved..."
        sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        rm -f /etc/resolv.conf
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
fi

# Idempotent DNSTT Key Generation
if [ ! -f "/opt/imagitech/core/keys/dnstt.pub" ]; then
    log_event "INFO" "Generating new DNSTT keys..."
    cd /opt/imagitech/core/keys
    /opt/imagitech/bin/dnstt-server -gen-key -privkey-file dnstt.key -pubkey-file dnstt.pub
else
    log_event "INFO" "DNSTT keys already exist. Skipping generation."
fi

# Idempotent iptables Routing (Check before Insert)
log_event "INFO" "Applying DNSTT iptables routing rules..."

if ! iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
fi

if ! iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null; then
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
fi

# Save iptables safely
ensure_package "iptables-persistent"
netfilter-persistent save >/dev/null 2>&1

cat <<EOF > /tmp/imagitech-dnstt.service.tmp
[Unit]
Description=Imagitech DNSTT Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/imagitech/bin/dnstt-server -udp :5300 -privkey-file /opt/imagitech/core/keys/dnstt.key ${NS_DOMAIN} 127.0.0.1:${PORT_DROPBEAR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "imagitech-dnstt"

log_event "INFO" "Sidecar Protocols Deployed Successfully."

