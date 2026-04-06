/**
 * NOVA-XTUNNEL Premium Dashboard Logic
 * Handles real-time updates, section navigation, and API interactions.
 */

const App = {
    // Current application state
    state: {
        activeSection: 'dashboard',
        isRefreshing: false,
        onlineUsers: []
    },

    // Initialization
    init() {
        console.log('Nova-XTunnel UI Engine Initialized');
        this.setupEventListeners();
        this.startPulsing();

        // Initial data fetch if on a relevant page
        if (document.getElementById('ssh-accounts-list')) {
            this.loadSSHAccounts();
        }
    },

    // Global UI updates
    setupEventListeners() {
        // Auto-refresh online status every 10 seconds
        setInterval(() => this.refreshNodeStatus(), 10000);
    },

    async refreshNodeStatus() {
        if (this.state.isRefreshing) return;
        this.state.isRefreshing = true;

        try {
            const response = await fetch('/api/stats');
            const data = await response.json();

            // Update counter with animation
            const counter = document.getElementById('online-count');
            if (counter) {
                const start = parseInt(counter.innerText);
                this.animateValue(counter, start, data.online_count, 500);
            }

            // Update live list if exists
            const container = document.getElementById('online-users-list');
            if (container) {
                if (data.online_users.length > 0) {
                    container.innerHTML = data.online_users.map(user => `
                        <div class="status-badge status-active animate-fade">
                            <i class="fas fa-user"></i> ${user}
                        </div>
                    `).join('');
                } else {
                    container.innerHTML = '<div style="color: var(--text-dim); font-style: italic;">No active sessions detected.</div>';
                }
            }
        } catch (err) {
            console.error('Pulse check failed:', err);
        } finally {
            this.state.isRefreshing = false;
        }
    },

    // Value animation helper
    animateValue(obj, start, end, duration) {
        if (start === end) return;
        let startTimestamp = null;
        const step = (timestamp) => {
            if (!startTimestamp) startTimestamp = timestamp;
            const progress = Math.min((timestamp - startTimestamp) / duration, 1);
            obj.innerHTML = Math.floor(progress * (end - start) + start);
            if (progress < 1) {
                window.requestAnimationFrame(step);
            }
        };
        window.requestAnimationFrame(step);
    },

    // Navigation logic
    showSection(sectionId, element) {
        const sections = ['dashboard', 'resellers', 'accounts', 'zivpn', 'settings'];

        sections.forEach(s => {
            const el = document.getElementById(s + '-section');
            if (el) el.style.display = 'none';
        });

        const target = document.getElementById(sectionId + '-section');
        if (target) {
            target.style.display = 'block';
            target.classList.add('animate-fade');
        }

        // Update nav UI
        document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
        if (element) element.classList.add('active');

        // Dynamic loading based on section
        if (sectionId === 'accounts') this.loadSSHAccounts();
        if (sectionId === 'resellers') this.loadResellers();
    },

    // API: Load SSH Accounts
    async loadSSHAccounts() {
        const container = document.getElementById('ssh-accounts-list');
        if (!container) return;

        try {
            const response = await fetch('/api/ssh_accounts');
            const data = await response.json();

            container.innerHTML = data.map(acc => `
                <tr class="animate-fade">
                    <td>
                        <div style="font-weight: 600;">${acc.username}</div>
                        <div style="font-size: 11px; color: var(--text-dim)">ID: #${acc.id}</div>
                    </td>
                    <td style="color: var(--text-muted)">${acc.expiry_date}</td>
                    <td><span class="status-badge" style="background: rgba(102, 126, 234, 0.1)">${acc.connection_limit} Max</span></td>
                    <td>
                        <div style="font-size: 13px;">${acc.bandwidth_used_gb} GB / ${acc.bandwidth_limit_gb > 0 ? acc.bandwidth_limit_gb + ' GB' : '∞'}</div>
                        <div class="progress-bar" style="width: 80px; height: 4px; margin-top: 5px;">
                            <div class="progress-fill" style="width: ${acc.bandwidth_limit_gb > 0 ? (acc.bandwidth_used_gb/acc.bandwidth_limit_gb*100) : 5}%"></div>
                        </div>
                    </td>
                    <td>
                        <span class="status-badge ${acc.status === 'active' ? 'status-active' : 'status-locked'}">
                            ${acc.status.toUpperCase()}
                        </span>
                    </td>
                    <td style="text-align: right;">
                        <div style="display: flex; gap: 8px; justify-content: flex-end;">
                            <button class="btn-premium" style="padding: 8px 12px; font-size: 12px;" onclick="location.href='/account/${acc.id}/info'" title="View Details">
                                <i class="fas fa-eye"></i>
                            </button>
                            <button class="btn-premium" style="padding: 8px 12px; font-size: 12px; background: rgba(239, 68, 68, 0.1); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.2);" onclick="App.deleteAccount(${acc.id})" title="Delete">
                                <i class="fas fa-trash-can"></i>
                            </button>
                        </div>
                    </td>
                </tr>
            `).join('');
        } catch (err) {
            this.notify('Failed to load accounts', 'danger');
        }
    },

    // Account deletion
    async deleteAccount(id) {
        if (!confirm('This will permanently revoke system access for this user. Continue?')) return;

        try {
            const response = await fetch(`/account/${id}/delete`, { method: 'POST' });
            if (response.ok) {
                this.notify('User account purged successfully', 'success');
                this.loadSSHAccounts();
            } else {
                throw new Error();
            }
        } catch (err) {
            this.notify('Security Error: Could not delete account', 'danger');
        }
    },

    // Notifications
    notify(message, type = 'primary') {
        const toast = document.createElement('div');
        toast.className = `glass-card animate-fade`;
        toast.style = `
            position: fixed; bottom: 30px; right: 30px;
            padding: 15px 25px; z-index: 2000;
            border-left: 4px solid var(--${type === 'danger' ? 'danger' : 'primary'});
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
        `;
        toast.innerHTML = `
            <div style="display: flex; align-items: center; gap: 12px;">
                <i class="fas fa-${type === 'danger' ? 'triangle-exclamation' : 'circle-check'}" style="color: var(--${type === 'danger' ? 'danger' : 'primary'})"></i>
                <span style="font-size: 14px; font-weight: 500;">${message}</span>
            </div>
        `;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 4000);
    },

    startPulsing() {
        this.refreshNodeStatus();
    }
};

// Global exports
window.showSection = (id, el) => App.showSection(id, el);
document.addEventListener('DOMContentLoaded', () => App.init());
