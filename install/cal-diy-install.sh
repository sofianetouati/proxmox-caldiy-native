#!/usr/bin/env bash
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Sofiane Touati | https://github.com/sofianetouati
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y curl git jq sudo openssl ca-certificates gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
$STD apt update -y
$STD apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable -q --now docker
msg_ok "Installed Dependencies"

msg_info "Collecting Configuration"
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
else
  read -rsp "Remote PostgreSQL DATABASE_URL: " DATABASE_URL
  echo
  while [[ -z "$DATABASE_URL" ]]; do
    read -rsp "DATABASE_URL cannot be empty. Enter Remote PostgreSQL DATABASE_URL: " DATABASE_URL
    echo
  done
fi
msg_ok "Collected Configuration"

msg_info "Cloning ${APP}"
mkdir -p /opt
if [[ -d /opt/cal.diy/.git ]]; then
  git -C /opt/cal.diy fetch --all --tags
  git -C /opt/cal.diy pull --ff-only
else
  git clone --recursive https://github.com/calcom/cal.diy.git /opt/cal.diy
fi
cd /opt/cal.diy
msg_ok "Cloned ${APP}"

msg_info "Configuring Environment"
if [[ ! -f .env.example ]]; then
  msg_error ".env.example not found"
  exit 1
fi
cp .env.example .env
sed -i -e "s|^NEXT_PUBLIC_WEBAPP_URL=.*|NEXT_PUBLIC_WEBAPP_URL=${PUBLIC_URL}|" \
       -e "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=${NEXTAUTH_URL}|" \
       -e "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=${NEXTAUTH_SECRET}|" \
       -e "s|^CALENDSO_ENCRYPTION_KEY=.*|CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}|" \
       -e "s|^DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|" .env
grep -q "^NEXT_PUBLIC_WEBAPP_URL=" .env || echo "NEXT_PUBLIC_WEBAPP_URL=${PUBLIC_URL}" >>.env
grep -q "^NEXTAUTH_URL=" .env || echo "NEXTAUTH_URL=${NEXTAUTH_URL}" >>.env
grep -q "^NEXTAUTH_SECRET=" .env || echo "NEXTAUTH_SECRET=${NEXTAUTH_SECRET}" >>.env
grep -q "^CALENDSO_ENCRYPTION_KEY=" .env || echo "CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}" >>.env
grep -q "^DATABASE_URL=" .env || echo "DATABASE_URL=${DATABASE_URL}" >>.env
msg_ok "Configured Environment"

msg_info "Starting Docker Stack"
$STD docker compose pull
$STD docker compose up -d
msg_ok "Started Docker Stack"

msg_info "Creating Helper Commands"
cat >/usr/local/bin/caldiy-update <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/cal.diy
git fetch --all --tags
git pull --ff-only
docker compose pull
docker compose up -d
EOS
chmod +x /usr/local/bin/caldiy-update

cat >/usr/local/bin/caldiy-logs <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/cal.diy
exec docker compose logs -f --tail=200
EOS
chmod +x /usr/local/bin/caldiy-logs
msg_ok "Created Helper Commands"

git rev-parse HEAD >/opt/${APP}_version.txt

motd_ssh
customize
cleanup_lxc
