import os
from typing import Union

BANDWIDTH_DIR = '/etc/nova-xtunnel/bandwidth'

def get_user_bandwidth_used(username: str) -> int:
    """Get bandwidth used by a user in bytes"""
    usage_file = os.path.join(BANDWIDTH_DIR, f"{username}.usage")
    if os.path.exists(usage_file):
        try:
            with open(usage_file, 'r') as f:
                content = f.read().strip()
                return int(content) if content else 0
        except (ValueError, IOError):
            return 0
    return 0

def get_total_bandwidth() -> int:
    """Get total bandwidth used by all users"""
    if not os.path.exists(BANDWIDTH_DIR):
        return 0
    total = 0
    try:
        for file in os.listdir(BANDWIDTH_DIR):
            if file.endswith('.usage'):
                total += get_user_bandwidth_used(file.replace('.usage', ''))
    except OSError:
        pass
    return total

def format_bytes(size_bytes: Union[int, float]) -> str:
    """Format bytes to human readable format"""
    if size_bytes == 0:
        return "0.00 B"

    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    i = 0
    while size_bytes >= 1024 and i < len(units) - 1:
        size_bytes /= 1024
        i += 1
    return f"{size_bytes:.2f} {units[i]}"
