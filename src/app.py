#!/usr/bin/env python3
# NOVA-XTUNNEL Web Panel - Main Application
# Version: 2.2.0

import os
import sqlite3
import bcrypt
import logging
import secrets
import string
import subprocess
import json
from datetime import datetime, timedelta
from functools import wraps

from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Import refactored utilities
from utils import (
    get_user_bandwidth_used,
    get_online_users,
    create_ssh_user,
    delete_ssh_user,
    validate_username,
    validate_password,
    validate_expiry_date,
    format_bytes
)

# Setup logging
LOG_DIR = "/var/log/nova-xtunnel-panel"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, "app.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(24))
app.config['SESSION_COOKIE_SECURE'] = os.environ.get('FLASK_ENV') == 'production'
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(hours=24)

# Rate limiting
limiter = Limiter(
    app,
    key_func=get_remote_address,
    default_limits=["500 per day", "100 per hour"],
    storage_uri="memory://"
)

# Login manager
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'
login_manager.login_message = 'Please login to access this page'
login_manager.login_message_category = 'warning'

# Constants
DB_PATH = os.environ.get('PANEL_DB_PATH', '/var/www/nova-xtunnel-panel/panel.db')
DB_FILE = '/etc/nova-xtunnel/users.db'
BANDWIDTH_DIR = '/etc/nova-xtunnel/bandwidth'
ZIVPN_CONFIG = '/etc/zivpn/config.json'

# ============================================================
# USER CLASS
# ============================================================

class User(UserMixin):
    def __init__(self, id, username, role, expiry_date, max_users, max_bandwidth_gb, current_bandwidth_gb):
        self.id = id
        self.username = username
        self.role = role
        self.expiry_date = expiry_date
        self.max_users = max_users
        self.max_bandwidth_gb = max_bandwidth_gb
        self.current_bandwidth_gb = current_bandwidth_gb

    @property
    def is_expired(self):
        if self.role == 'admin':
            return False
        if self.expiry_date and self.expiry_date != 'Never':
            try:
                expiry = datetime.strptime(self.expiry_date, '%Y-%m-%d')
                return expiry < datetime.now()
            except (ValueError, TypeError):
                return False
        return False

    @property
    def days_left(self):
        if self.role == 'admin' or not self.expiry_date or self.expiry_date == 'Never':
            return None
        try:
            expiry = datetime.strptime(self.expiry_date, '%Y-%m-%d')
            delta = expiry - datetime.now()
            return max(0, delta.days)
        except (ValueError, TypeError):
            return None

# ============================================================
# DATABASE FUNCTIONS
# ============================================================

def get_db():
    """Get database connection with row factory for easier access"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

# ============================================================
# HELPER FUNCTIONS
# ============================================================

def get_managed_online_users():
    """Get currently online SSH users that exist in our panel DB"""
    system_online = get_online_users()
    if not system_online:
        return []

    conn = get_db()
    try:
        placeholders = ','.join(['?'] * len(system_online))
        query = f"SELECT username FROM ssh_accounts WHERE username IN ({placeholders})"
        rows = conn.execute(query, system_online).fetchall()
        return [row['username'] for row in rows]
    except Exception as e:
        logger.error(f"Error querying online users: {e}")
        return []
    finally:
        conn.close()

def get_reseller_stats(reseller_id):
    """Calculate aggregated stats for a reseller"""
    conn = get_db()
    try:
        users = conn.execute("SELECT username FROM ssh_accounts WHERE reseller_id = ?", (reseller_id,)).fetchall()
        total_bw_bytes = sum(get_user_bandwidth_used(u['username']) for u in users)
        return {
            'user_count': len(users),
            'bandwidth_used_gb': round(total_bw_bytes / (1024**3), 2)
        }
    finally:
        conn.close()

# ============================================================
# DECORATORS
# ============================================================

def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or current_user.role != 'admin':
            flash('Admin access required', 'danger')
            return redirect(url_for('dashboard'))
        return f(*args, **kwargs)
    return decorated_function

def reseller_active_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated:
            return redirect(url_for('login'))
        if current_user.role == 'reseller' and current_user.is_expired:
            flash('Your reseller account has expired. Please contact admin.', 'danger')
            logout_user()
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# ============================================================
# LOGIN MANAGER
# ============================================================

@login_manager.user_loader
def load_user(user_id):
    conn = get_db()
    try:
        user = conn.execute(
            "SELECT id, username, role, expiry_date, max_users, max_bandwidth_gb, current_bandwidth_gb FROM users WHERE id = ?",
            (user_id,)
        ).fetchone()
        if user:
            return User(user['id'], user['username'], user['role'], user['expiry_date'],
                        user['max_users'], user['max_bandwidth_gb'], user['current_bandwidth_gb'])
    finally:
        conn.close()
    return None

# ============================================================
# AUTH ROUTES
# ============================================================

@app.route('/')
@login_required
@reseller_active_required
def index():
    return redirect(url_for('dashboard'))

@app.route('/login', methods=['GET', 'POST'])
@limiter.limit("15 per minute")
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip().lower()
        password = request.form.get('password', '')

        if not username or not password:
            flash('Please enter both username and password', 'danger')
            return render_template('login.html')

        conn = get_db()
        try:
            user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
            if user and bcrypt.checkpw(password.encode('utf-8'), user['password'].encode('utf-8')):
                usr_obj = User(user['id'], user['username'], user['role'], user['expiry_date'],
                               user['max_users'], user['max_bandwidth_gb'], user['current_bandwidth_gb'])

                if usr_obj.is_expired and usr_obj.role != 'admin':
                    flash('Your account has expired. Please contact admin.', 'danger')
                    return render_template('login.html')

                login_user(usr_obj)
                logger.info(f"User {username} logged in from {request.remote_addr}")
                return redirect(request.args.get('next') or url_for('dashboard'))
            else:
                flash('Invalid username or password', 'danger')
        finally:
            conn.close()

    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash('You have been logged out', 'info')
    return redirect(url_for('login'))

# ============================================================
# DASHBOARD
# ============================================================

@app.route('/dashboard')
@login_required
@reseller_active_required
def dashboard():
    online_users = get_managed_online_users()
    conn = get_db()
    try:
        if current_user.role == 'admin':
            total_accounts = conn.execute("SELECT COUNT(*) FROM ssh_accounts").fetchone()[0]
            total_resellers = conn.execute("SELECT COUNT(*) FROM users WHERE role = 'reseller'").fetchone()[0]

            # Global bandwidth usage
            all_accounts = conn.execute("SELECT username FROM ssh_accounts").fetchall()
            total_bw_gb = sum(get_user_bandwidth_used(a['username']) for a in all_accounts) / (1024**3)

            resellers_raw = conn.execute("SELECT * FROM users WHERE role = 'reseller' ORDER BY created_at DESC").fetchall()
            resellers = []
            for r in resellers_raw:
                stats = get_reseller_stats(r['id'])
                resellers.append({
                    **dict(r),
                    'user_count': stats['user_count'],
                    'bandwidth_used_gb': stats['bandwidth_used_gb'],
                    'is_expired': datetime.strptime(r['expiry_date'], '%Y-%m-%d') < datetime.now() if r['expiry_date'] and r['expiry_date'] != 'Never' else False
                })

            return render_template('admin_dashboard.html',
                online_count=len(online_users),
                online_users=online_users,
                total_accounts=total_accounts,
                total_resellers=total_resellers,
                total_bandwidth_gb=round(total_bw_gb, 2),
                resellers=resellers)
        else:
            stats = get_reseller_stats(current_user.id)
            accounts_raw = conn.execute("SELECT * FROM ssh_accounts WHERE reseller_id = ? ORDER BY created_at DESC", (current_user.id,)).fetchall()
            accounts = []
            for acc in accounts_raw:
                used_gb = get_user_bandwidth_used(acc['username']) / (1024**3)
                accounts.append({
                    **dict(acc),
                    'bandwidth_used_gb': round(used_gb, 2),
                    'is_expired': datetime.strptime(acc['expiry_date'], '%Y-%m-%d') < datetime.now()
                })

            return render_template('reseller_dashboard.html',
                online_count=len(online_users),
                online_users=online_users,
                user_count=stats['user_count'],
                max_users=current_user.max_users if current_user.max_users > 0 else '∞',
                bandwidth_used_gb=stats['bandwidth_used_gb'],
                max_bandwidth_gb=current_user.max_bandwidth_gb if current_user.max_bandwidth_gb > 0 else '∞',
                accounts=accounts,
                expiry_date=current_user.expiry_date or 'Never',
                days_left=current_user.days_left)
    finally:
        conn.close()

# ============================================================
# SSH ACCOUNT MANAGEMENT
# ============================================================

@app.route('/account/create', methods=['POST'])
@login_required
@reseller_active_required
def create_account():
    username = request.form.get('username', '').strip().lower()
    password = request.form.get('password', '')
    expiry_days = int(request.form.get('expiry_days', 30))
    connection_limit = int(request.form.get('connection_limit', 1))
    bandwidth_limit = float(request.form.get('bandwidth_limit', 0))

    if not validate_username(username):
        flash('Invalid username. Use 3-32 chars, lowercase/numbers.', 'danger')
        return redirect(url_for('dashboard'))

    if current_user.role == 'reseller':
        stats = get_reseller_stats(current_user.id)
        if current_user.max_users > 0 and stats['user_count'] >= current_user.max_users:
            flash(f'User limit reached ({current_user.max_users})', 'danger')
            return redirect(url_for('dashboard'))
        if current_user.max_bandwidth_gb > 0 and stats['bandwidth_used_gb'] + bandwidth_limit > current_user.max_bandwidth_gb:
            flash('Insufficient reseller bandwidth quota.', 'danger')
            return redirect(url_for('dashboard'))

    conn = get_db()
    try:
        if conn.execute("SELECT 1 FROM ssh_accounts WHERE username = ?", (username,)).fetchone():
            flash(f'Username {username} already exists.', 'danger')
            return redirect(url_for('dashboard'))

        expiry_date = (datetime.now() + timedelta(days=expiry_days)).strftime('%Y-%m-%d')
        if not password:
            password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))

        if create_ssh_user(username, password, expiry_date, connection_limit, int(bandwidth_limit)):
            conn.execute(
                "INSERT INTO ssh_accounts (username, password, reseller_id, expiry_date, connection_limit, bandwidth_limit_gb) VALUES (?, ?, ?, ?, ?, ?)",
                (username, password, current_user.id if current_user.role == 'reseller' else None,
                 expiry_date, connection_limit, bandwidth_limit)
            )
            conn.commit()
            flash(f'Account {username} created. Pass: {password}', 'success')
            logger.info(f"Account {username} created by {current_user.username}")
        else:
            flash('Failed to create system user.', 'danger')
    finally:
        conn.close()
    return redirect(url_for('dashboard'))

@app.route('/account/<int:account_id>/delete', methods=['POST'])
@login_required
@reseller_active_required
def delete_account(account_id):
    conn = get_db()
    try:
        query = "SELECT username FROM ssh_accounts WHERE id = ?"
        params = [account_id]
        if current_user.role == 'reseller':
            query += " AND reseller_id = ?"
            params.append(current_user.id)

        account = conn.execute(query, params).fetchone()
        if not account:
            flash('Account not found.', 'danger')
            return redirect(url_for('dashboard'))

        if delete_ssh_user(account['username']):
            conn.execute("DELETE FROM ssh_accounts WHERE id = ?", (account_id,))
            conn.commit()
            flash(f"Account {account['username']} deleted.", 'success')
        else:
            flash('Error deleting system user.', 'danger')
    finally:
        conn.close()
    return redirect(url_for('dashboard'))

@app.route('/account/<int:account_id>/edit', methods=['POST'])
@login_required
@reseller_active_required
def edit_account(account_id):
    password = request.form.get('password')
    expiry_days = int(request.form.get('expiry_days', 0))
    connection_limit = int(request.form.get('connection_limit', 0))
    bandwidth_limit = float(request.form.get('bandwidth_limit', -1))

    conn = get_db()
    try:
        query = "SELECT username FROM ssh_accounts WHERE id = ?"
        params = [account_id]
        if current_user.role == 'reseller':
            query += " AND reseller_id = ?"
            params.append(current_user.id)

        account = conn.execute(query, params).fetchone()
        if not account:
            flash('Account not found.', 'danger')
            return redirect(url_for('dashboard'))

        username = account['username']
        updates = []
        sql_params = []

        if password:
            updates.append("password = ?")
            sql_params.append(password)
            subprocess.run(['chpasswd'], input=f'{username}:{password}', text=True, capture_output=True)

        if expiry_days > 0:
            new_expiry = (datetime.now() + timedelta(days=expiry_days)).strftime('%Y-%m-%d')
            updates.append("expiry_date = ?")
            sql_params.append(new_expiry)
            subprocess.run(['chage', '-E', new_expiry, username], capture_output=True)

        if connection_limit > 0:
            updates.append("connection_limit = ?")
            sql_params.append(connection_limit)

        if bandwidth_limit >= 0:
            updates.append("bandwidth_limit_gb = ?")
            sql_params.append(bandwidth_limit)

        if updates:
            sql_params.append(account_id)
            conn.execute(f"UPDATE ssh_accounts SET {', '.join(updates)} WHERE id = ?", sql_params)

            # Sync users.db manually for now or use a dedicated sync function
            if os.path.exists(DB_FILE):
                try:
                    with open(DB_FILE, 'r') as f:
                        lines = f.readlines()
                    with open(DB_FILE, 'w') as f:
                        for line in lines:
                            if line.startswith(f"{username}:"):
                                parts = line.strip().split(':')
                                if expiry_days > 0: parts[2] = (datetime.now() + timedelta(days=expiry_days)).strftime('%Y-%m-%d')
                                if connection_limit > 0: parts[3] = str(connection_limit)
                                if bandwidth_limit >= 0: parts[4] = str(bandwidth_limit)
                                f.write(':'.join(parts) + '\n')
                            else:
                                f.write(line)
                except Exception as e:
                    logger.error(f"Failed to sync users.db: {e}")

            conn.commit()
            flash('Account updated successfully', 'success')
    finally:
        conn.close()
    return redirect(url_for('dashboard'))

@app.route('/account/<int:account_id>/toggle', methods=['POST'])
@login_required
@reseller_active_required
def toggle_account(account_id):
    conn = get_db()
    try:
        query = "SELECT username, status FROM ssh_accounts WHERE id = ?"
        params = [account_id]
        if current_user.role == 'reseller':
            query += " AND reseller_id = ?"
            params.append(current_user.id)

        account = conn.execute(query, params).fetchone()
        if not account:
            flash('Account not found.', 'danger')
            return redirect(url_for('dashboard'))

        new_status = 'locked' if account['status'] == 'active' else 'active'
        cmd = ['usermod', '-L' if new_status == 'locked' else '-U', account['username']]

        try:
            subprocess.run(cmd, check=True)
            if new_status == 'locked':
                subprocess.run(['pkill', '-u', account['username']], capture_output=True)

            conn.execute("UPDATE ssh_accounts SET status = ? WHERE id = ?", (new_status, account_id))
            conn.commit()
            flash(f"Account {account['username']} is now {new_status}.", 'success')
        except subprocess.CalledProcessError:
            flash("Failed to update system user status.", 'danger')
    finally:
        conn.close()
    return redirect(url_for('dashboard'))

@app.route('/account/<int:account_id>/reset_bandwidth', methods=['POST'])
@login_required
@reseller_active_required
def reset_bandwidth(account_id):
    conn = get_db()
    try:
        query = "SELECT username FROM ssh_accounts WHERE id = ?"
        params = [account_id]
        if current_user.role == 'reseller':
            query += " AND reseller_id = ?"
            params.append(current_user.id)

        account = conn.execute(query, params).fetchone()
        if account:
            usage_file = os.path.join(BANDWIDTH_DIR, f"{account['username']}.usage")
            try:
                with open(usage_file, 'w') as f:
                    f.write('0')
                subprocess.run(['usermod', '-U', account['username']], capture_output=True)
                flash(f"Bandwidth reset for {account['username']}.", 'success')
            except IOError:
                flash("Could not write usage file.", 'danger')
    finally:
        conn.close()
    return redirect(url_for('dashboard'))

@app.route('/account/<int:account_id>/info')
@login_required
@reseller_active_required
def account_info(account_id):
    conn = get_db()
    try:
        query = "SELECT * FROM ssh_accounts WHERE id = ?"
        params = [account_id]
        if current_user.role == 'reseller':
            query += " AND reseller_id = ?"
            params.append(current_user.id)

        account = conn.execute(query, params).fetchone()
        if not account:
            flash('Account not found.', 'danger')
            return redirect(url_for('dashboard'))

        used_bytes = get_user_bandwidth_used(account['username'])
        used_gb = used_bytes / (1024**3)
        percent = (used_gb / account['bandwidth_limit_gb'] * 100) if account['bandwidth_limit_gb'] > 0 else 0

        try:
            import requests
            server_ip = requests.get('https://api.ipify.org', timeout=3).text
        except:
            server_ip = "Unknown"

        return render_template('account_info.html', account={
            **dict(account),
            'bandwidth_used_gb': round(used_gb, 2),
            'bandwidth_percent': round(percent, 1),
            'server_ip': server_ip,
            'ssh_port': 22
        })
    finally:
        conn.close()

# ============================================================
# ADMIN ROUTES
# ============================================================

@app.route('/admin/resellers')
@login_required
@admin_required
def admin_resellers():
    conn = get_db()
    try:
        resellers_raw = conn.execute("SELECT * FROM users WHERE role = 'reseller' ORDER BY created_at DESC").fetchall()
        resellers = []
        for r in resellers_raw:
            stats = get_reseller_stats(r['id'])
            resellers.append({**dict(r), **stats})
        return render_template('admin_resellers.html', resellers=resellers)
    finally:
        conn.close()

@app.route('/admin/reseller/create', methods=['POST'])
@login_required
@admin_required
def admin_create_reseller():
    username = request.form.get('username', '').strip().lower()
    password = request.form.get('password', '')
    max_users = int(request.form.get('max_users', 0))
    max_bandwidth = float(request.form.get('max_bandwidth', 0))
    expiry_days = int(request.form.get('expiry_days', 0))

    if not validate_username(username) or not password:
        flash('Invalid username or empty password.', 'danger')
        return redirect(url_for('admin_resellers'))

    conn = get_db()
    try:
        if conn.execute("SELECT 1 FROM users WHERE username = ?", (username,)).fetchone():
            flash('Reseller already exists.', 'danger')
            return redirect(url_for('admin_resellers'))

        expiry_date = (datetime.now() + timedelta(days=expiry_days)).strftime('%Y-%m-%d') if expiry_days > 0 else 'Never'
        hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

        conn.execute(
            "INSERT INTO users (username, password, role, expiry_date, max_users, max_bandwidth_gb) VALUES (?, ?, 'reseller', ?, ?, ?)",
            (username, hashed, expiry_date, max_users, max_bandwidth)
        )
        conn.commit()
        flash(f"Reseller {username} created successfully.", 'success')
    finally:
        conn.close()
    return redirect(url_for('admin_resellers'))

@app.route('/admin/reseller/<int:reseller_id>/delete', methods=['POST'])
@login_required
@admin_required
def admin_delete_reseller(reseller_id):
    conn = get_db()
    try:
        users = conn.execute("SELECT username FROM ssh_accounts WHERE reseller_id = ?", (reseller_id,)).fetchall()
        for u in users:
            delete_ssh_user(u['username'])

        conn.execute("DELETE FROM users WHERE id = ? AND role = 'reseller'", (reseller_id,))
        conn.commit()
        flash('Reseller and all associated users deleted.', 'success')
    finally:
        conn.close()
    return redirect(url_for('admin_resellers'))

@app.route('/admin/zivpn_passwords', methods=['GET', 'POST'])
@login_required
@admin_required
def admin_zivpn_passwords():
    if request.method == 'POST':
        action = request.form.get('action')
        password = request.form.get('password')

        if os.path.exists(ZIVPN_CONFIG):
            try:
                with open(ZIVPN_CONFIG, 'r') as f:
                    config = json.load(f)

                if action == 'add' and password:
                    if 'auth' not in config: config['auth'] = {'mode': 'passwords', 'config': []}
                    if password not in config['auth']['config']:
                        config['auth']['config'].append(password)
                elif action == 'remove' and password:
                    if 'auth' in config and password in config['auth']['config']:
                        config['auth']['config'].remove(password)

                with open(ZIVPN_CONFIG, 'w') as f:
                    json.dump(config, f, indent=2)
                subprocess.run(['systemctl', 'restart', 'zivpn.service'], capture_output=True)
                flash('ZiVPN configuration updated.', 'success')
            except Exception as e:
                flash(f'Error updating ZiVPN: {e}', 'danger')

    passwords = []
    if os.path.exists(ZIVPN_CONFIG):
        try:
            with open(ZIVPN_CONFIG, 'r') as f:
                config = json.load(f)
                passwords = config.get('auth', {}).get('config', [])
        except:
            pass
    return render_template('admin_zivpn.html', passwords=passwords)

# ============================================================
# API ENDPOINTS
# ============================================================

@app.route('/api/stats')
@login_required
def api_stats():
    online = get_managed_online_users()
    return jsonify({
        'online_count': len(online),
        'online_users': online
    })

if __name__ == '__main__':
    # Ensure logs and db exist
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    app.run(host='127.0.0.1', port=5000)
