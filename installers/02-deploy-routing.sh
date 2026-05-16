# File: /root/imagitech-install/02-deploy-routing.sh
# Purpose: Idempotent deployment of Dropbear, Stunnel, and the Async Proxy.

#!/bin/bash
source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Deploying Phase 2: Data Plane & Routing Engine"

safe_create_dir "/opt/imagitech/services/routing"

# --- 1. Configure Dropbear & OpenSSH ---
log_event "INFO" "Configuring Dropbear and OpenSSH..."

# Write the Premium Default Banner
cat <<'EOF' > /etc/issue.net
<b><font color="#00aaaa">PREMIUM SERVER • POWERED BY †hε drεαmεr</font></b><br>
<font color="#00aaaa">━━━━━━━━━━━━━━━━━━━━━</font><br><br>
<b><font color="#ff00ff">JOIN TELEGRAM 👇 IMAGI TECH</font></b><br>
<font color="#ff00ff">t.me/imagitech001</font><br><br>
<font color="#00aaaa">━━━━━━━━━━━━━━━━━━━━━</font><br><br>
<b><font color="#ff0000">TERMS OF SERVICE</font></b><br><br>
<font color="#ff8800">• NO ABUSE / NO SPAM / NO ILLEGAL USE</font><br>
<font color="#ff8800">• DO NOT SHARE CONFIGS PUBLICLY</font><br>
<font color="#ff8800">• VIOLATION = ACCESS TERMINATED</font><br><br>
<font color="#00aaaa">━━━━━━━━━━━━━━━━━━━━━</font><br><br>
<b><font color="#ff00ff">USE RESPONSIBLY • ENJOY FAST & SECURE ACCESS</font></b>
EOF

# Enforce banner on OpenSSH globally (Debian 11/12 & Ubuntu 22/24 fix)
sed -i 's/#Banner.*/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
fi
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

# Configure Dropbear ports
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=${PORT_DROPBEAR}
DROPBEAR_EXTRA_ARGS="-p 143 -w -g"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl daemon-reload
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

# --- 2. The Async WebSocket Proxy ---
log_event "INFO" "Deploying Async WebSocket Multiplexer..."

# The master installer already placed the file here, just ensure it's executable
chmod +x /opt/imagitech/services/routing/ws-proxy.py

cat <<EOF > /tmp/imagitech-ws.service.tmp

[Unit]
Description=Imagitech Async WS Multiplexer
After=network.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/imagitech/services/routing
ExecStart=/usr/bin/python3 /opt/imagitech/services/routing/ws-proxy.py
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

safe_deploy_systemd "imagitech-ws"

# --- 3. Stunnel (SSL Termination) ---
log_event "INFO" "Configuring Stunnel4 TLS Bridging..."

# Use our idempotent TLS generator
ensure_tls_cert "$PRIMARY_DOMAIN"

cat <<EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /opt/imagitech/core/keys/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssh-ws-ssl]
accept = ${PORT_WS_HTTPS}
connect = 127.0.0.1:${PORT_WS_HTTP}
EOF

# Ensure Stunnel boot flag is enabled
sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4

systemctl enable stunnel4 >/dev/null 2>&1
systemctl restart stunnel4

log_event "INFO" "Routing Engine Deployed Successfully."

