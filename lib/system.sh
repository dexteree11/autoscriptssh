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
