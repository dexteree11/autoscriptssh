#!/usr/bin/env python3
# File: /opt/imagitech/services/monitor/daemon.py
# Purpose: Real-time Multi-Login, Bandwidth Accounting, and OS Reaper

import os
import time
import sqlite3
import subprocess
import datetime
import pwd
from collections import defaultdict

# --- CONFIGURATION ---
DB_PATH = "/opt/imagitech/core/database.db"
ONLINE_FILE = "/opt/imagitech/core/online_users.txt"
CHECK_INTERVAL = 30  

class ImagitechMonitor:
    def __init__(self):
        self.db_path = DB_PATH
        self.user_policies = {} 
        self.active_sessions = defaultdict(list)
        self.setup_iptables()

    def log_event(self, level, msg):
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {msg}")

    def setup_iptables(self):
        try:
            subprocess.run("iptables -N IMAGITECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
            check_link = subprocess.run("iptables -C OUTPUT -j IMAGITECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
            if check_link.returncode != 0:
                subprocess.run("iptables -I OUTPUT -j IMAGITECH-ACCT", shell=True, stderr=subprocess.DEVNULL)
        except Exception as e:
            self.log_event("ERROR", f"IPTables setup failed: {e}")

    def fetch_user_policies(self):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT username, max_logins, expiry_date FROM users WHERE status='ACTIVE'")
            self.user_policies = {row[0]: {'max_logins': row[1], 'expiry': row[2]} for row in cursor.fetchall()}
            conn.close()
        except Exception as e:
            self.log_event("ERROR", f"Database access failed: {e}")

    def reconcile_state(self):
        self.active_sessions.clear()
        try:
            cmd = "ps -eo user:32,pid,command | grep -E 'dropbear|sshd' | grep -v grep"
            output = subprocess.check_output(cmd, shell=True, text=True)
            
            for line in output.strip().split('\n'):
                if not line.strip(): continue
                parts = line.split()
                if len(parts) >= 3:
                    user, pid = parts[0], parts[1]
                    ignored_users = ['root', 'nobody', 'syslog', 'stunnel4', 'messagebus', 'danted', 'systemd-resolve']
                    if user in ignored_users: continue
                        
                    try:
                        if pwd.getpwnam(user).pw_shell != '/bin/false': continue
                    except KeyError:
                        pass 

                    self.active_sessions[user].append(pid)
        except subprocess.CalledProcessError:
            pass 

    def process_bandwidth(self):
        conn = None
        try:
            existing_rules = subprocess.check_output("iptables -S IMAGITECH-ACCT", shell=True, text=True)
            for user in self.user_policies.keys():
                if f"--uid-owner {user}" not in existing_rules:
                    subprocess.run(f"iptables -A IMAGITECH-ACCT -m owner --uid-owner {user} -j RETURN", shell=True)

            output = subprocess.check_output("iptables -Z IMAGITECH-ACCT -n -v -x", shell=True, text=True)
            
            usage_updates = {}
            for line in output.strip().split('\n')[2:]:
                parts = line.split()
                if len(parts) >= 10 and 'owner' in parts and 'UID' in parts:
                    bytes_used = int(parts[1])
                    if bytes_used == 0: continue
                    
                    uid_str = parts[-1]
                    try:
                        username = pwd.getpwuid(int(uid_str)).pw_name
                        usage_updates[username] = bytes_used
                    except KeyError:
                        pass # User already reaped from OS

            if usage_updates:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                for user, data_bytes in usage_updates.items():
                    cursor.execute("UPDATE users SET data_usage = data_usage + ? WHERE username = ?", (data_bytes, user))
                conn.commit()

        except Exception as e:
            self.log_event("ERROR", f"Bandwidth tracking failed: {e}")
        finally:
            if conn: conn.close()

    def enforce_expiry_and_limits(self):
        now = datetime.datetime.now()
        conn = None
        try:
            for user, policy in list(self.user_policies.items()):
                try:
                    expiry_date = datetime.datetime.strptime(policy['expiry'], "%Y-%m-%d %H:%M:%S")
                    if now >= expiry_date:
                        self.log_event("INFO", f"User '{user}' expired. Executing OS wipe.")
                        subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                        # The Reaper: Eradicate the Linux account entirely
                        subprocess.run(["userdel", "-f", user], check=False, stderr=subprocess.DEVNULL)
                        
                        if not conn: conn = sqlite3.connect(self.db_path)
                        conn.cursor().execute("UPDATE users SET status='EXPIRED' WHERE username=?", (user,))
                        conn.commit()
                        del self.user_policies[user]
                except Exception as e:
                    pass

            for user, pids in self.active_sessions.items():
                policy = self.user_policies.get(user)
                if not policy:
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    continue
                max_allowed = policy['max_logins']
                if max_allowed > 0 and len(pids) > max_allowed:
                    self.log_event("WARN", f"Multi-login violation: {user}. Terminating.")
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
        finally:
            if conn: conn.close()

    def purge_ghost_accounts(self):
        """Hunts down users marked as EXPIRED in the DB and ensures they are wiped from the OS."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT username FROM users WHERE status != 'ACTIVE'")
            inactive_users = cursor.fetchall()
            conn.close()

            for (user,) in inactive_users:
                try:
                    pwd.getpwnam(user) # Throws KeyError if they are already wiped
                    self.log_event("INFO", f"Reaping ghost OS account for expired user: {user}")
                    subprocess.run(["pkill", "-u", user], check=False, stderr=subprocess.DEVNULL)
                    subprocess.run(["userdel", "-f", user], check=False, stderr=subprocess.DEVNULL)
                except KeyError:
                    pass # System is clean
        except Exception as e:
            pass

    def write_ui_report(self):
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
        self.log_event("INFO", "Monitor Daemon started.")
        while True:
            try:
                self.fetch_user_policies()
                self.reconcile_state()
                self.enforce_expiry_and_limits()
                self.process_bandwidth()
                self.write_ui_report()
            except Exception as e:
                self.log_event("ERROR", f"Daemon cycle failed: {e}. Recovering in 15s.")
                time.sleep(15)
            time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    monitor = ImagitechMonitor()
    monitor.run()
