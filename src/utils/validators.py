import re
from typing import Any, Union

def validate_username(username: str) -> bool:
    """
    Validate username format.
    - 3 to 32 characters
    - Starts with a letter
    - Contains only lowercase letters, numbers, and underscores
    """
    if not username or not isinstance(username, str):
        return False
    if len(username) < 3 or len(username) > 32:
        return False
    # Standard Linux username requirements
    return bool(re.match(r'^[a-z_][a-z0-9_-]*$', username))

def validate_password(password: str) -> bool:
    """Validate password strength (minimum 6 characters)"""
    return bool(password and isinstance(password, str) and len(password) >= 6)

def validate_port(port: Any) -> bool:
    """Validate port number (1-65535)"""
    try:
        p = int(port)
        return 1 <= p <= 65535
    except (ValueError, TypeError):
        return False

def validate_domain(domain: str) -> bool:
    """Validate domain name format using a robust regex"""
    if not domain or not isinstance(domain, str):
        return False
    pattern = r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    return bool(re.match(pattern, domain))

def validate_ipv4(ip: str) -> bool:
    """Validate IPv4 address format"""
    if not ip or not isinstance(ip, str):
        return False
    pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    if not re.match(pattern, ip):
        return False
    return all(0 <= int(part) <= 255 for part in ip.split('.'))

def validate_expiry_date(date_str: str) -> bool:
    """Validate date format YYYY-MM-DD"""
    if not date_str or not isinstance(date_str, str):
        return False
    try:
        from datetime import datetime
        datetime.strptime(date_str, '%Y-%m-%d')
        return True
    except ValueError:
        return False
