# File: /opt/imagitech/lib/db.sh
# Purpose: Database interaction layer.

source /opt/imagitech/core/imagitech.conf
source /opt/imagitech/lib/system.sh

init_database() {
    log_event "INFO" "Initializing database schema at $DB_PATH"
    
    mkdir -p "$(dirname "$DB_PATH")"
    
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    uuid TEXT,
    protocols TEXT DEFAULT 'ssh,ws,socks',
    expiry_date TEXT NOT NULL,
    max_logins INTEGER DEFAULT 2,
    bandwidth_limit_mb INTEGER DEFAULT 0,
    bandwidth_used_mb INTEGER DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
    chmod 600 "$DB_PATH"

    # Migration: Safely add the precision byte-tracking column if it doesn't exist
    local col_exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info(users);" | grep "data_usage")
    if [[ -z "$col_exists" ]]; then
        sqlite3 "$DB_PATH" "ALTER TABLE users ADD COLUMN data_usage BIGINT DEFAULT 0;"
    fi
}

db_query() {
    local query="$1"
    sqlite3 "$DB_PATH" "$query"
}
