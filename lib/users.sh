# File: /opt/imagitech/lib/users.sh
# Purpose: Business logic for user lifecycle.

source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/system.sh
source /opt/imagitech/lib/db.sh

create_vpn_user() {
    local username="$1"
    local password="$2"
    local days="$3"
    local max_logins="${4:-2}"
    
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
    db_query "INSERT INTO users (username, uuid, expiry_date, max_logins) VALUES ('$username', '$uuid', '$exp_date', $max_logins);"
    
    log_event "INFO" "Successfully provisioned user: $username for $days days (Max Logins: $max_logins)."
    return 0
}

create_trial_user() {
    local username="$1"
    local password="$2"
    local hours="$3"
    
    if [[ -z "$username" || -z "$password" || -z "$hours" ]]; then
        log_event "ERROR" "Missing arguments for trial user creation."
        return 1
    fi

    # Check if user already exists in DB
    local exists=$(db_query "SELECT COUNT(*) FROM users WHERE username='$username';")
    if [ "$exists" -gt 0 ]; then
        log_event "WARN" "User $username already exists."
        return 2
    fi

    # Calculate exact expiry timestamp for the database (hours/minutes)
    local exp_date=$(date -d "+${hours} hours" +"%Y-%m-%d %H:%M:%S")
    
    # Calculate OS expiry (days) to satisfy the Linux PAM requirement.
    # We round up to ensure the OS doesn't kill it before the Python Daemon does.
    local os_days=$(( (hours + 23) / 24 ))
    local os_exp_date=$(date -d "+${os_days} days" +"%Y-%m-%d")

    # 1. Create Linux PAM User
    useradd -e "$os_exp_date" -s /bin/false -M "$username" >/dev/null 2>&1
    echo "$username:$password" | chpasswd

    # 2. Insert precise metadata to SQLite
    local uuid=$(uuidgen)
    db_query "INSERT INTO users (username, uuid, expiry_date) VALUES ('$username', '$uuid', '$exp_date');"

    log_event "INFO" "Successfully provisioned trial user: $username for $hours hours."
    return 0
}

renew_user() {
    local username="$1"
    local mod_days="$2"

    if [[ -z "$username" || -z "$mod_days" ]]; then
        log_event "ERROR" "Missing arguments for user renewal."
        return 1
    fi

    # 1. Fetch current expiry from database
    local current_expiry=$(db_query "SELECT expiry_date FROM users WHERE username='$username';")
    if [[ -z "$current_expiry" ]]; then
        log_event "ERROR" "User $username not found in database."
        return 2
    fi

    # 2. Bulletproof Date Math (Convert to Epoch seconds, apply math, convert back)
    local current_epoch=$(date -d "$current_expiry" +%s)
    local mod_seconds=$(( mod_days * 86400 ))
    local new_epoch=$(( current_epoch + mod_seconds ))
    
    local new_exp_date=$(date -d "@$new_epoch" +"%Y-%m-%d %H:%M:%S")
    local os_exp_date=$(date -d "@$new_epoch" +"%Y-%m-%d")

    # 4. Update the Linux PAM Account
    usermod -e "$os_exp_date" "$username" >/dev/null 2>&1

    # 5. Update the Database
    db_query "UPDATE users SET expiry_date='$new_exp_date', status='ACTIVE' WHERE username='$username';"

    log_event "INFO" "Successfully modified user $username. Expiry shifted by $mod_days days to $new_exp_date."
    return 0
}

delete_vpn_user() {
    local username="$1"
    
    userdel -f "$username" >/dev/null 2>&1
    db_query "DELETE FROM users WHERE username='$username';"
    log_event "INFO" "Deleted user: $username."
}

