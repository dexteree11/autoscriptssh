# File: /root/imagitech-install/04-deploy-monitor.sh

#!/bin/bash
source /opt/imagitech/lib/installer_utils.sh

log_event "INFO" "Deploying Multi-Login Enforcement Daemon..."

# 1. Ensure the Python script is in place (Assuming it was downloaded to /tmp)
cp /tmp/daemon.py /opt/imagitech/services/monitor/daemon.py
chmod +x /opt/imagitech/services/monitor/daemon.py

# 2. Stage the Systemd file to temp
cat <<EOF > /tmp/imagitech-monitor.service.tmp
[Unit]
Description=Imagitech Real-time Multi-Login Enforcer
After=network.target sqlite.target dropbear.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/imagitech/services/monitor
ExecStart=/usr/bin/python3 /opt/imagitech/services/monitor/daemon.py
Restart=always
RestartSec=5
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/imagitech/logs /opt/imagitech/core

[Install]
WantedBy=multi-user.target
EOF

# 3. Safely deploy using our utility function
safe_deploy_systemd "imagitech-monitor"

