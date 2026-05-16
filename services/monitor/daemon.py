#!/usr/bin/env python3
# File: /opt/imagitech/services/monitor/daemon.py
# Purpose: Real-time Multi-Login, Precision Expiry, and Live Monitoring

import os
import time
import sqlite3
import subprocess
import datetime
from collections import defaultdict

# --- CONFIGURATION ---
DB_PATH = "/opt/imagitech/core/database.db"
ONLINE_FILE = "/opt/imagitech/core/online_users.txt"
CHECK_INTERVAL = 30  # Seconds between checks

class ImagitechMonitor:
    def __init__(self):
        self.db_path = DB_PATH
        self.user_policies = {}  # { 'username': {'max_logins': X, 'expiry': Y} }
        self.active_sessions = defaultdict(list)

    def log_event(self, level, msg):
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {msg}")

    def fetch_user_policies(self):
        """Loads expiry and max_login constraints from SQLite."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT username, max_logins, expiry_date FROM users WHERE status='ACTIVE'")
            self.user_policies = {
                row[0]: {'max_logins': row[1], 'expiry': row[2]} 
                for row in cursor.fetchall()
            }
            conn.close()
        except Exception as e:
            self.log_event("ERROR", f"Database access failed: {e}")

    def reconcile_state(self):
        """Hard-checks the system for actual running Dropbear/SSH processes per user."""
        self.active_sessions.clear()
        try:
            cmd = "ps -eo user,pid,comm | grep -E 'dropbear|sshd'"
            output = subprocess.check_output(cmd, shell=True, text=True)
            
            for line in output.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3:
                    user, pid = parts[0], parts[1]
                    if user not in ['root', 'nobody', 'syslog', 'stunnel4', 'messagebus']:
                        self.active_sessions[user].append(pid)
        except subprocess.CalledProcessError:
            pass # No active connections

    def enforce_expiry(self):
        """Checks exact minute-by-minute timestamps for Trial and regular users."""
        now = datetime.datetime.now()
        conn = None
        
        try:
            # list() forces a copy so we can delete from the dictionary safely during the loop
            for user, policy in list(self.user_policies.items()):
                try:
                    expiry_date = datetime.datetime.strptime(policy['expiry'], "%Y-%m-%d %H:%M:%S")
                    if now >= expiry_date:
                        self.log_event("INFO", f"User '{user}' expired exactly at {policy['expiry']}. Locking account.")
                        
                        # 1. Lock OS Account instantly
                        subprocess.run(["usermod", "-L", "-E", "1", user], check=False, stderr=subprocess.DEVNULL)
                        # 2. Kill active sessions
                        subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                        
                        # 3. Update DB
                        if not conn:
                            conn = sqlite3.connect(self.db_path)
                        conn.cursor().execute("UPDATE users SET status='EXPIRED' WHERE username=?", (user,))
                        conn.commit()
                        
                        # Remove from memory so we don't check it again
                        del self.user_policies[user]
                except Exception as e:
                    self.log_event("ERROR", f"Date parsing error for {user}: {e}")
        finally:
            if conn:
                conn.close()

    def enforce_limits(self):
        """Kills processes if a user exceeds their max_logins limit."""
        for user, pids in self.active_sessions.items():
            policy = self.user_policies.get(user)
            
            # If user is not in the active database at all (deleted or expired), kill them
            if not policy:
                self.log_event("WARN", f"Unauthorized ghost session detected: {user}. Terminating.")
                subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                continue
                
            max_allowed = policy['max_logins']
            
            # 0 means UNLIMITED. Only enforce if max_allowed > 0.
            if max_allowed > 0 and len(pids) > max_allowed:
                self.log_event("WARN", f"Violation detected: {user} has {len(pids)} sessions (Max: {max_allowed}). Terminating.")
                subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)

    def write_ui_report(self):
        """Writes the current live state to a text file for the Bash UI to read instantly."""
        try:
            with open(ONLINE_FILE, "w") as f:
                if not self.active_sessions:
                    f.write("No active VPN connections right now.\n")
                else:
                    for user, pids in self.active_sessions.items():
                        f.write(f"{user}|{len(pids)}\n")
        except IOError:
            pass

    def run(self):
        self.log_event("INFO", "Imagitech Monitor Daemon started (V2 Engine).")
        while True:
            self.fetch_user_policies()
            self.reconcile_state()
            self.enforce_expiry()
            self.enforce_limits()
            self.write_ui_report()
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    monitor = ImagitechMonitor()
    monitor.run()
