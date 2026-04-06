import subprocess
import os
import logging
from typing import List, Optional

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB_FILE = '/etc/nova-xtunnel/users.db'

def create_ssh_user(username: str, password: str, expiry_date: str, connection_limit: int, bandwidth_limit: int) -> bool:
    """
    Create SSH user on system with specified limits.
    Returns True if successful, False otherwise.
    """
    try:
        # Create user with no-login shell and home directory
        subprocess.run(['useradd', '-m', '-s', '/usr/sbin/nologin', username],
                      capture_output=True, check=True)

        # Add to nxtunnel group
        subprocess.run(['usermod', '-aG', 'nxtunnel', username],
                      capture_output=True, check=True)

        # Set password securely without shell=True if possible, but chpasswd usually takes input from stdin
        process = subprocess.Popen(['chpasswd'], stdin=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        _, stderr = process.communicate(input=f'{username}:{password}')
        if process.returncode != 0:
            logger.error(f"Failed to set password for {username}: {stderr}")
            return False

        # Set account expiry
        subprocess.run(['chage', '-E', expiry_date, username],
                      capture_output=True, check=True)

        # Update users.db
        os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
        with open(DB_FILE, 'a') as f:
            f.write(f"{username}:{password}:{expiry_date}:{connection_limit}:{bandwidth_limit}\n")

        logger.info(f"Successfully created SSH user: {username}")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed during user creation: {e.stderr.decode() if e.stderr else str(e)}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error creating user {username}: {str(e)}")
        return False

def delete_ssh_user(username: str) -> bool:
    """
    Delete SSH user from system and kill all their processes.
    """
    try:
        # Forcefully terminate all user processes
        subprocess.run(['pkill', '-u', username], capture_output=True)

        # Delete user and home directory
        subprocess.run(['userdel', '-r', username], capture_output=True)

        # Remove from users.db
        if os.path.exists(DB_FILE):
            lines = []
            with open(DB_FILE, 'r') as f:
                lines = f.readlines()

            with open(DB_FILE, 'w') as f:
                for line in lines:
                    if not line.startswith(f"{username}:"):
                        f.write(line)

        logger.info(f"Deleted user: {username}")
        return True
    except Exception as e:
        logger.error(f"Error deleting user {username}: {str(e)}")
        return False

def get_online_users() -> List[str]:
    """
    Get list of currently logged-in SSH users.
    Excludes root and system users.
    """
    try:
        # Using ps to find sshd processes and their owners
        result = subprocess.run(['ps', '-u', 'root', '-U', 'root', '-o', 'user,cmd'],
                               capture_output=True, text=True)

        online_users = set()
        for line in result.stdout.splitlines():
            if 'sshd: ' in line and '@pts' in line:
                parts = line.split()
                if len(parts) > 0:
                    user = parts[0]
                    if user != 'root':
                        online_users.add(user)
        return list(online_users)
    except Exception as e:
        logger.error(f"Error getting online users: {str(e)}")
        return []
