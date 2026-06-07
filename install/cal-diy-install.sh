#!/usr/bin/env bash
source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)"
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Perplexity
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

APP="Cal.diy"
APP_DIR="/opt/cal.diy"
HELPER_UPDATE="/usr/local/bin/caldiy-update"
HELPER_LOGS="/usr/local/bin/caldiy-logs"

header_info "$APP"
color
catch_errors

if [[ ! -f /etc/os-release ]]; then
  msg_error "Unsupported OS"
  exit 1
fi
. /etc/os-release
if [[ "$ID" != "debian" || "$VERSION_CODENAME" != "bookworm" ]]; then
  msg_error "This script supports Debian 12 Bookworm only"
  exit 1
fi

msg_info "Updating container"
apt-get update -y
apt-get upgrade -y
msg_ok "Updated container"

msg_info "Installing dependencies"
apt-get install -y curl git ca-certificates gnupg openssl jq sudo python3
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
cat >/etc/apt/sources.list.d/docker.list <<APT
 deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable
APT
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
msg_ok "Installed dependencies"

msg_info "Collecting configuration"
read -rp "Public URL for Cal.diy (example: https://cal.example.com or http://192.168.1.10:3000): " PUBLIC_URL
while [[ -z "$PUBLIC_URL" ]]; do
  read -rp "Public URL cannot be empty. Enter PUBLIC_URL: " PUBLIC_URL
done

read -rp "Use bundled PostgreSQL from Docker Compose? [Y/n]: " USE_LOCAL_DB
USE_LOCAL_DB=${USE_LOCAL_DB:-Y}

NEXTAUTH_SECRET=$(openssl rand -base64 32)
CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 24)
NEXTAUTH_URL="http://localhost:3000/api/auth"

if [[ "$USE_LOCAL_DB" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
  DATABASE_URL="postgresql://unicorn_user:magical_password@database:5432/calendso"
  DB_MODE="local"
else
  read -rsp "Remote PostgreSQL DATABASE_URL: " DATABASE_URL
  echo
  while [[ -z "$DATABASE_URL" ]]; do
    read -rsp "DATABASE_URL cannot be empty. Enter Remote PostgreSQL DATABASE_URL: " DATABASE_URL
    echo
  done
  DB_MODE="remote"
fi
msg_ok "Collected configuration"

msg_info "Cloning $APP"
mkdir -p /opt
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch --all --tags
  git -C "$APP_DIR" pull --ff-only
else
  git clone --recursive https://github.com/calcom/cal.diy.git "$APP_DIR"
fi
cd "$APP_DIR"
msg_ok "Cloned $APP"

msg_info "Configuring environment"
if [[ ! -f .env.example ]]; then
  msg_error ".env.example not found"
  exit 1
fi
cp .env.example .env
PUBLIC_URL="$PUBLIC_URL" \
NEXTAUTH_URL="$NEXTAUTH_URL" \
NEXTAUTH_SECRET="$NEXTAUTH_SECRET" \
CALENDSO_ENCRYPTION_KEY="$CALENDSO_ENCRYPTION_KEY" \
DATABASE_URL="$DATABASE_URL" \
python3 <<'PY'
from pathlib import Path
import os
p = Path('.env')
text = p.read_text()
updates = {
    'NEXT_PUBLIC_WEBAPP_URL': os.environ['PUBLIC_URL'],
    'NEXTAUTH_URL': os.environ['NEXTAUTH_URL'],
    'NEXTAUTH_SECRET': os.environ['NEXTAUTH_SECRET'],
    'CALENDSO_ENCRYPTION_KEY': os.environ['CALENDSO_ENCRYPTION_KEY'],
    'DATABASE_URL': os.environ['DATABASE_URL'],
}
lines = text.splitlines()
out = []
seen = set()
for line in lines:
    stripped = line.lstrip()
    if '=' in line and not stripped.startswith('#'):
        key = line.split('=', 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
p.write_text('\n'.join(out) + '\n')
PY
msg_ok "Configured environment"

msg_info "Starting Docker stack"
if [[ "$DB_MODE" == "local" ]]; then
  docker compose pull
  docker compose up -d
else
  docker compose pull calcom studio
  docker compose up -d calcom studio
fi
msg_ok "Started Docker stack"

msg_info "Creating helper commands"
cat >"$HELPER_UPDATE" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/cal.diy
git fetch --all --tags
git pull --ff-only
docker compose pull
docker compose up -d
EOS
chmod +x "$HELPER_UPDATE"

cat >"$HELPER_LOGS" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/cal.diy
exec docker compose logs -f --tail=200
EOS
chmod +x "$HELPER_LOGS"
msg_ok "Created helper commands"

IP_ADDR=$(hostname -I | awk '{print $1}')
motd_ssh
customize
msg_info "Access information"
echo "Application: $APP"
echo "Path: $APP_DIR"
echo "Public URL: $PUBLIC_URL"
echo "Local URL: http://$IP_ADDR:3000"
echo "Database mode: $DB_MODE"
echo "Update command: caldiy-update"
echo "Logs command: caldiy-logs"
msg_ok "Installation completed"
