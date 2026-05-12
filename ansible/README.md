# Ansible — Infrastructure as Code for StatusPulse

## Overview
This Ansible playbook configures a fresh Ubuntu 22.04+ VM into a complete StatusPulse production server.

## What It Does
1. Updates system packages and installs dependencies
2. Creates a non-root `deploy` user with SSH key access
3. Hardens SSH (disables root login, password auth, changes port to 2222)
4. Configures UFW firewall (allows only SSH/2222, HTTP/80, HTTPS/443)
5. Creates 2GB swap space
6. Installs Docker and Docker Compose
7. Deploys StatusPulse (app + PostgreSQL + Redis + Caddy)
8. Deploys Uptime Kuma monitoring
9. Sets up cron jobs for health monitoring (every 5 min) and backups (daily at 2AM)

## Prerequisites
- Ansible installed on your local machine: `brew install ansible` (macOS) or `pip install ansible`
- SSH access to your target server (root for initial setup)
- An SSH key pair: `ssh-keygen -t rsa -b 4096`

## Usage

### 1. Configure your server
Edit `inventory.ini` and replace `your-server-ip` with your server's IP address.

### 2. Configure variables
Edit `vars.yml` and set your domain, passwords, and SSH key path.

### 3. Run the playbook
```bash
ansible-playbook -i inventory.ini playbook.yml
```

### 4. Verify idempotency (run again — should show changed=0)
```bash
ansible-playbook -i inventory.ini playbook.yml
```

## File Structure
```
ansible/
├── inventory.ini    # Server list
├── playbook.yml     # Main playbook
├── vars.yml         # Configuration variables
└── README.md        # This file
```
