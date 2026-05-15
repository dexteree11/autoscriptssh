# File: /opt/imagitech/lib/users.sh
# Purpose: Business logic for user lifecycle.

source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/system.sh
source /opt/imagitech/lib/db.sh

create_vpn_user() {
    local username="$1"
    local password="$2"
    local days="$3"
    
    if [[ -z "$username" || -z "$password" || -z "$days" ]]; then
        log_event "ERROR" "Missing arguments for user creation."
        return 1
    fi

    # Check if user already exists in DB
    local exists=$(db_query "SELECT COUNT(*) FROM users WHERE username='$username';")
    if [ "$exists" -gt 0 ]; then
        log_event "WARN" "User $username already exists."
        return 2
    fi

    local exp_date=$(date -d "+${days} days" +"%Y-%m-%d %H:%M:%S")
    local os_exp_date=$(date -d "+${days} days" +"%Y-%m-%d")

    # 1. Create Linux PAM User (Business logic)
    useradd -e "$os_exp_date" -s /bin/false -M "$username" >/dev/null 2>&1
    echo "$username:$password" | chpasswd

    # 2. Insert metadata to SQLite
    local uuid=$(uuidgen)
    db_query "INSERT INTO users (username, uuid, expiry_date) VALUES ('$username', '$uuid', '$exp_date');"

    log_event "INFO" "Successfully provisioned user: $username for $days days."
    return 0
}

delete_vpn_user() {
    local username="$1"
    
    userdel -f "$username" >/dev/null 2>&1
    db_query "DELETE FROM users WHERE username='$username';"
    log_event "INFO" "Deleted user: $username."
}

