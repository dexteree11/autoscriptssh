# File: /opt/imagitech/services/monitor/daemon.py
# Purpose: Real-time Multi-Login & Expiry Enforcement Daemon

import os
import time
import sqlite3
import subprocess
import re
from collections import defaultdict

# --- CONFIGURATION ---
DB_PATH = "/opt/imagitech/core/database.db"
CHECK_INTERVAL = 30  # Seconds between hard state reconciliations
DROPBEAR_REGEX = re.compile(r"dropbear.*\[\d+\].*Password auth succeeded for '([^']+)'")

class ImagitechMonitor:
    def __init__(self):
        self.db_path = DB_PATH
        self.user_limits = {}  # { 'username': max_logins }
        self.active_sessions = defaultdict(list) # { 'username': [pid1, pid2] }

    def log_event(self, level, msg):
        print(f"[{level}] {msg}")

    def fetch_user_policies(self):
        """Loads expiry and max_login constraints from SQLite."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            # Fetch active users and their login limits
            cursor.execute("SELECT username, max_logins FROM users WHERE status='ACTIVE'")
            self.user_limits = {row[0]: row[1] for row in cursor.fetchall()}
            conn.close()
        except Exception as e:
            self.log_event("ERROR", f"Database access failed: {e}")

    def reconcile_state(self):
        """
        Hard-checks the system for actual running Dropbear/SSH processes per user.
        This prevents drift if log parsing misses a disconnect event.
        """
        self.active_sessions.clear()
        
        try:
            # We look for Dropbear payload processes running under user accounts
            # dropbear spawns a child process for each connection under the authenticated user's UID
            cmd = "ps -eo user,pid,comm | grep -E 'dropbear|sshd'"
            output = subprocess.check_output(cmd, shell=True, text=True)
            
            for line in output.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3:
                    user, pid, comm = parts[0], parts[1], parts[2]
                    # Ignore root and nobody (used by system and Dante/BadVPN)
                    if user not in ['root', 'nobody', 'syslog']:
                        self.active_sessions[user].append(pid)
        except subprocess.CalledProcessError:
            pass # grep returned 1 (no matches)

    def enforce_limits(self):
        """Kills processes if a user exceeds their max_logins."""
        for user, pids in self.active_sessions.items():
            max_allowed = self.user_limits.get(user, 0)
            
            # If max_allowed is 0, the user shouldn't be active at all (expired/deleted)
            if max_allowed == 0 or len(pids) > max_allowed:
                self.log_event("WARN", f"Violation detected: {user} has {len(pids)} sessions (Max: {max_allowed})")
                
                # Sort PIDs to kill the newest ones first, keeping the original connection alive
                # Or kill all to force them to reconnect and drop shared users. (We choose kill all for stricter enforcement)
                self.log_event("INFO", f"Enforcing limit for {user}. Terminating sessions.")
                
                try:
                    # Kill all processes owned by the user to forcefully terminate all tunnels
                    subprocess.run(["pkill", "-u", user], check=False)
                    self.active_sessions[user] = []
                except Exception as e:
                    self.log_event("ERROR", f"Failed to terminate user {user}: {e}")

    def run(self):
        self.log_event("INFO", "Imagitech Monitor Daemon started.")
        while True:
            # 1. Update our knowledge of who is allowed to do what
            self.fetch_user_policies()
            
            # 2. Reconcile what is actually happening on the server
            self.reconcile_state()
            
            # 3. Drop the hammer on violators
            self.enforce_limits()
            
            # 4. Sleep until next cycle
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    monitor = ImagitechMonitor()
    monitor.run()

