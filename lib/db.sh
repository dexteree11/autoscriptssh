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
    max_logins INTEGER DEFAULT $MAX_LOGINS_DEFAULT,
    bandwidth_limit_mb INTEGER DEFAULT 0,
    bandwidth_used_mb INTEGER DEFAULT 0,
    status TEXT DEFAULT 'ACTIVE',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
    chmod 600 "$DB_PATH"
}

db_query() {
    local query="$1"
    sqlite3 "$DB_PATH" "$query"
}

