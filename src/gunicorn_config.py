# NOVA-XTUNNEL Web Panel - Gunicorn Configuration
# Version: 2.0.0

import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5000"
backlog = 2048

# Worker processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
threads = 2
max_requests = 1000
max_requests_jitter = 50
timeout = 120
graceful_timeout = 30
keepalive = 5

# Security
limit_request_line = 4094
limit_request_fields = 100
limit_request_field_size = 8190

# Logging
accesslog = "/var/log/nova-xtunnel-panel/access.log"
errorlog = "/var/log/nova-xtunnel-panel/error.log"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "nova-xtunnel-panel"

# Server mechanics
daemon = False
pidfile = "/var/run/nova-xtunnel-panel.pid"
umask = 0o027
user = "root"
group = "root"
tmp_upload_dir = "/tmp"

# SSL (if using Gunicorn directly - not recommended, use Nginx instead)
# keyfile = "/etc/ssl/private/panel.key"
# certfile = "/etc/ssl/certs/panel.crt"

# Environment variables
raw_env = [
    "FLASK_ENV=production",
    "PYTHONUNBUFFERED=1",
]

# Hooks
def on_starting(server):
    """Called just before the master process is initialized"""
    server.log.info("Starting NOVA-XTUNNEL Web Panel v2.0.0")
    server.log.info(f"Workers: {workers}, Threads: {threads}")

def on_reload(server):
    """Called just before the master process is reloaded"""
    server.log.info("Reloading NOVA-XTUNNEL Web Panel")

def when_ready(server):
    """Called just after the server is started"""
    server.log.info("NOVA-XTUNNEL Web Panel is ready to accept connections")

def on_exit(server):
    """Called just before the master process exits"""
    server.log.info("Shutting down NOVA-XTUNNEL Web Panel")

# Pre-fork hook
def pre_fork(server, worker):
    """Called just before a worker is forked"""
    pass

# Post-fork hook
def post_fork(server, worker):
    """Called just after a worker has been forked"""
    server.log.info(f"Worker {worker.pid} spawned")

# Worker exit hook
def worker_exit(server, worker):
    """Called just after a worker has been exited"""
    server.log.info(f"Worker {worker.pid} exited")

# Pre-request hook
def pre_request(worker, req):
    """Called just before a request is processed"""
    worker.log.debug(f"Processing request: {req.method} {req.path}")

# Post-request hook
def post_request(worker, req, environ, resp):
    """Called after a request is processed"""
    pass

# Child process exit hook
def child_exit(server, worker):
    """Called just after a worker has been exited"""
    pass