# File: /opt/imagitech/lib/services.sh
# Purpose: Safe service orchestration and restarts.

source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/system.sh

restart_service() {
    local service_name="$1"
    
    # Strict whitelist to prevent arbitrary systemctl execution
    case "$service_name" in
        dropbear|stunnel4|imagitech-ws|imagitech-dnstt|imagitech-monitor|danted)
            log_event "INFO" "Restarting service: $service_name"
            systemctl restart "$service_name"
            
            if systemctl is-active --quiet "$service_name"; then
                log_event "INFO" "Successfully restarted $service_name."
                return 0
            else
                log_event "ERROR" "Failed to restart $service_name. Check journalctl -xe."
                return 1
            fi
            ;;
        *)
            log_event "WARN" "Attempted to restart unauthorized/unknown service: $service_name"
            return 1
            ;;
    esac
}

