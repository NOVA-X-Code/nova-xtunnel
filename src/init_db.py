#!/usr/bin/env python3
# NOVA-XTUNNEL Web Panel - Database Initialization
# Version: 2.1.0

import sqlite3
import bcrypt
import os
import sys
import logging
from datetime import datetime
from typing import Optional

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

DB_PATH = '/var/www/nova-xtunnel-panel/panel.db'

def get_db_connection():
    return sqlite3.connect(DB_PATH)

def init_db():
    """Initialize database with all required tables and indexes"""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    with get_db_connection() as conn:
        c = conn.cursor()

        # Users table (admins and resellers)
        c.execute('''CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('admin', 'reseller')),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expiry_date TEXT,
            max_users INTEGER DEFAULT 0,
            max_bandwidth_gb REAL DEFAULT 0,
            current_bandwidth_gb REAL DEFAULT 0
        )''')

        # SSH Accounts table
        c.execute('''CREATE TABLE IF NOT EXISTS ssh_accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            reseller_id INTEGER,
            expiry_date TEXT NOT NULL,
            connection_limit INTEGER DEFAULT 1,
            bandwidth_limit_gb REAL DEFAULT 0,
            bandwidth_used_bytes INTEGER DEFAULT 0,
            status TEXT DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (reseller_id) REFERENCES users (id) ON DELETE CASCADE
        )''')

        # Bandwidth tracking table
        c.execute('''CREATE TABLE IF NOT EXISTS bandwidth_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            bytes_used INTEGER,
            log_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')

        # Settings table
        c.execute('''CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')

        # Create indexes
        c.execute('CREATE INDEX IF NOT EXISTS idx_ssh_accounts_reseller ON ssh_accounts(reseller_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_ssh_accounts_username ON ssh_accounts(username)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_bandwidth_log_username ON bandwidth_log(username)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_bandwidth_log_date ON bandwidth_log(log_date)')

        # Insert default settings
        c.execute('''INSERT OR IGNORE INTO settings (key, value) VALUES
            ('panel_version', '2.1.0'),
            ('install_date', ?),
            ('last_backup', 'Never')
        ''', (datetime.now().isoformat(),))

        conn.commit()
    logger.info("Database initialized successfully")

def create_admin(username, password):
    """Create initial admin user if none exists"""
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM users WHERE role = 'admin'")
        if c.fetchone():
            logger.warning("Admin user already exists. Skipping.")
            return

        hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        c.execute("""INSERT INTO users (username, password, role, expiry_date, max_users, max_bandwidth_gb)
                     VALUES (?, ?, 'admin', NULL, -1, -1)""",
                  (username, hashed))
        conn.commit()
    logger.info(f"Admin user '{username}' created successfully")

def reset_admin_password(username, new_password):
    """Reset password for a specific admin user"""
    hashed = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    with get_db_connection() as conn:
        c = conn.cursor()
        c.execute("UPDATE users SET password = ? WHERE username = ? AND role = 'admin'",
                  (hashed, username))
        if c.rowcount > 0:
            logger.info(f"Password reset for admin '{username}'")
        else:
            logger.error(f"User '{username}' not found or not an admin")
        conn.commit()

def list_all_users():
    """List all registered panel users"""
    print(f"\n{'ID':<5} | {'Username':<15} | {'Role':<10} | {'Expiry':<12} | {'Max Users':<10}")
    print("-" * 65)
    with get_db_connection() as conn:
        for row in conn.execute("SELECT id, username, role, expiry_date, max_users FROM users"):
            print(f"{row[0]:<5} | {row[1]:<15} | {row[2]:<10} | {str(row[3]):<12} | {row[4]:<10}")

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='NOVA-XTUNNEL DB Initializer')
    parser.add_argument('admin_user', nargs='?', help='Admin username to create')
    parser.add_argument('admin_pass', nargs='?', help='Admin password to create')
    parser.add_argument('--list', action='store_true', help='List all users')
    parser.add_argument('--reset-pass', nargs=2, metavar=('USER', 'PASS'), help='Reset admin password')

    args = parser.parse_args()

    init_db()

    if args.list:
        list_all_users()
    elif args.reset_pass:
        reset_admin_password(args.reset_pass[0], args.reset_pass[1])
    elif args.admin_user and args.admin_pass:
        create_admin(args.admin_user, args.admin_pass)
    else:
        logger.info("Database checked. Use --help for more options.")
