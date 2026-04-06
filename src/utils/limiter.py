#!/usr/bin/env python3
import os
import time
import subprocess
import logging
from datetime import datetime
from typing import Dict, Set

# Configuration
DB_FILE = '/etc/nova-xtunnel/users.db'
BW_DIR = '/etc/nova-xtunnel/bandwidth'
PID_TRACK_DIR = os.path.join(BW_DIR, 'pidtrack')
SCAN_INTERVAL = 30  # seconds

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler("/var/log/nova-xtunnel-panel/limiter.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("Limiter")

def get_sshd_sessions() -> Dict[str, Set[int]]:
    """Returns a mapping of username -> set of SSH PIDs"""
    sessions = {}
    try:
        # ps command to get pid and user of sshd processes, filtering out root/sshd system users
        result = subprocess.run(
            ['ps', '-C', 'sshd', '-o', 'pid=,user='],
            capture_output=True, text=True, check=True
        )
        for line in result.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2:
                pid, user = int(parts[0]), parts[1]
                if user not in ('root', 'sshd'):
                    if user not in sessions:
                        sessions[user] = set()
                    sessions[user].add(pid)
    except Exception as e:
        logger.error(f"Error fetching sshd sessions: {e}")
    return sessions

def get_process_io(pid: int) -> int:
    """Reads rchar + wchar from /proc/pid/io"""
    try:
        with open(f"/proc/{pid}/io", "r") as f:
            data = f.read()
            rchar = int([l for l in data.splitlines() if "rchar:" in l][0].split()[1])
            wchar = int([l for l in data.splitlines() if "wchar:" in l][0].split()[1])
            return rchar + wchar
    except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
        return 0

def lock_user(username: str, reason: str):
    """Locks a system user and kills their sessions"""
    logger.warning(f"Locking user {username}: {reason}")
    subprocess.run(['usermod', '-L', username], capture_output=True)
    subprocess.run(['pkill', '-u', username, '-9'], capture_output=True)

def run_limiter():
    logger.info("Nova-XTunnel Limiter started.")
    os.makedirs(PID_TRACK_DIR, exist_ok=True)

    while True:
        try:
            if not os.path.exists(DB_FILE):
                time.sleep(SCAN_INTERVAL)
                continue

            current_ts = time.time()
            active_sessions = get_sshd_sessions()

            with open(DB_FILE, 'r') as f:
                lines = f.readlines()

            for line in lines:
                if not line.strip() or line.startswith('#'):
                    continue

                parts = line.strip().split(':')
                if len(parts) < 5:
                    continue

                user, _, expiry, conn_limit, bw_limit_gb = parts[0], parts[1], parts[2], int(parts[3]), float(parts[4])

                # 1. Check Expiry
                if expiry != "Never":
                    try:
                        exp_dt = datetime.strptime(expiry, '%Y-%m-%d')
                        if exp_dt.timestamp() < current_ts:
                            lock_user(user, "Account expired")
                            continue
                    except ValueError:
                        pass

                # 2. Check Connection Limit
                user_pids = active_sessions.get(user, set())
                if len(user_pids) > conn_limit:
                    logger.warning(f"User {user} exceeded connection limit ({len(user_pids)}/{conn_limit})")
                    subprocess.run(['pkill', '-u', user, '-9'], capture_output=True)
                    # Temporary lock or just kill? Usually kill is enough for multi-login.
                    # Bash script used to lock for 120s.
                    continue

                # 3. Check Bandwidth
                usage_file = os.path.join(BW_DIR, f"{user}.usage")
                current_usage = 0
                if os.path.exists(usage_file):
                    try:
                        with open(usage_file, 'r') as uf:
                            current_usage = int(uf.read().strip() or 0)
                    except ValueError:
                        pass

                # Calculate delta usage for active PIDs
                delta = 0
                for pid in user_pids:
                    last_io_file = os.path.join(PID_TRACK_DIR, f"{user}_{pid}.last")
                    current_io = get_process_io(pid)

                    if os.path.exists(last_io_file):
                        try:
                            with open(last_io_file, 'r') as lif:
                                last_io = int(lif.read().strip() or 0)
                            if current_io >= last_io:
                                delta += (current_io - last_io)
                            else:
                                delta += current_io # PID might have wrapped or reused
                        except ValueError:
                            pass
                    else:
                        delta += current_io

                    with open(last_io_file, 'w') as lif:
                        lif.write(str(current_io))

                # Cleanup old PID track files
                for f in os.listdir(PID_TRACK_DIR):
                    if f.startswith(f"{user}_") and f.endswith(".last"):
                        fpid = int(f.split('_')[1].split('.')[0])
                        if fpid not in user_pids:
                            os.remove(os.path.join(PID_TRACK_DIR, f))

                if delta > 0:
                    current_usage += delta
                    with open(usage_file, 'w') as uf:
                        uf.write(str(current_usage))

                # Enforcement
                if bw_limit_gb > 0:
                    limit_bytes = int(bw_limit_gb * 1024**3)
                    if current_usage >= limit_bytes:
                        lock_user(user, f"Bandwidth limit reached ({bw_limit_gb} GB)")

        except Exception as e:
            logger.error(f"Limiter loop error: {e}")

        time.sleep(SCAN_INTERVAL)

if __name__ == "__main__":
    run_limiter()
