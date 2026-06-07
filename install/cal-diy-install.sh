#!/usr/bin/env bash
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Sofiane Touati | https://github.com/sofianetouati
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

APP="Cal.diy"

# ── Fallback functions (VM standalone mode) ──────────────────────────────────
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH" 2>/dev/null || true

if ! declare -f msg_info >/dev/null 2>&1; then
  YW=$(echo "\033[33m")
  YWB=$(echo "\033[93m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  DGN=$(echo "\033[32m")
  CL=$(echo "\033[m")
  BFR="\\r\\033[K"
  BOLD=$(echo "\033[1m")
  HOLD=" "
  TAB="  "
  CM="${TAB}[OK]${CL}"
  CROSS="${TAB}[!!]${CL}"

  msg_info() { echo -ne "${TAB}${YW}${HOLD}${1}${HOLD}"; }
  msg_ok() { echo -e "${BFR}${CM}${GN}${1}${CL}"; }
  msg_error() { echo -e "${BFR}${CROSS}${RD}${1}${CL}"; }
  STD=""
fi

# ── Color if not set ─────────────────────────────────────────────────────────
if ! declare -f color >/dev/null 2>&1 && declare -f msg_info >/dev/null 2>&1; then
  :
fi
# ── catch_errors fallback ────────────────────────────────────────────────────
if ! declare -f catch_errors >/dev/null 2>&1; then
  catch_errors() { set -e; trap 'msg_error "Error on line $LINENO"' ERR; }
fi
# ── setting_up_container fallback ────────────────────────────────────────────
if ! declare -f setting_up_container >/dev/null 2>&1; then
  setting_up_container() { :; }
fi
# ── network_check fallback ───────────────────────────────────────────────────
if ! declare -f network_check >/dev/null 2>&1; then
  network_check() {
    for i in $(seq 1 10); do
      ping -c 1 8.8.8.8 >/dev/null 2>&1 && return 0
      sleep 2
    done
    msg_error "Network unreachable"
    exit 1
  }
fi
# ── update_os fallback ───────────────────────────────────────────────────────
if ! declare -f update_os >/dev/null 2>&1; then
  update_os() {
    msg_info "Updating OS"
    apt-get update -y
    apt-get upgrade -y
    msg_ok "Updated OS"
  }
fi
# ── motd_ssh fallback ────────────────────────────────────────────────────────
if ! declare -f motd_ssh >/dev/null 2>&1; then
  motd_ssh() { :; }
fi
# ── customize fallback ───────────────────────────────────────────────────────
if ! declare -f customize >/dev/null 2>&1; then
  customize() { :; }
fi
# ── cleanup_lxc / cleanup_vm fallback ────────────────────────────────────────
if ! declare -f cleanup_lxc >/dev/null 2>&1; then
  cleanup_lxc() { :; }
fi

catch_errors

# ── Configuration (non-interactive) ──────────────────────────────────────────
IP_ADDR=$(hostname -I | awk '{print $1}')
PUBLIC_URL="${PUBLIC_URL:-http://${IP_ADDR}:3000}"
USE_LOCAL_DB="${USE_LOCAL_DB:-Y}"
NEXTAUTH_SECRET=$(openssl rand -base64 32)
CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 24)
NEXTAUTH_URL="http://localhost:3000/api/auth"

if [[ "$USE_LOCAL_DB" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
  DATABASE_URL="${DATABASE_URL:-postgresql://unicorn_user:magical_password@database:5432/calendso}"
  DB_MODE="local"
else
  DATABASE_URL="${DATABASE_URL:?Remote DATABASE_URL is required when USE_LOCAL_DB != Y}"
  DB_MODE="remote"
fi

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

msg_info "Cloning ${APP} (1.1 GiB, may take a few minutes)"
mkdir -p /opt
if [[ -d /opt/cal.diy/.git ]]; then
  git -C /opt/cal.diy fetch --all --tags --quiet
  git -C /opt/cal.diy pull --ff-only --quiet
else
  git clone --recursive --quiet https://github.com/calcom/cal.diy.git /opt/cal.diy
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

msg_info "Starting Docker Stack (build may take 10-30 minutes)"
docker compose up -d
msg_ok "Started Docker Stack"

msg_info "Creating Helper Commands"
cat >/usr/local/bin/caldiy-update <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/cal.diy
git fetch --all --tags
git pull --ff-only
docker compose up -d --build
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

# ── Disable first-boot service if present ────────────────────────────────────
if systemctl is-enabled caldiy-firstboot &>/dev/null; then
  systemctl disable --now caldiy-firstboot 2>/dev/null || true
  rm -f /etc/systemd/system/caldiy-firstboot.service
  rm -f /root/caldiy-firstboot.sh
  systemctl daemon-reload
fi

# ── Recap ─────────────────────────────────────────────────────────────────────
cat <<EOF | tee -a /root/caldiy-install.log 2>/dev/null

============================================
  ${APP} installation complete
============================================

  Application:    ${APP}
  Path:           /opt/cal.diy
  Public URL:     ${PUBLIC_URL}
  Local URL:      http://${IP_ADDR}:3000
  Database mode:  ${DB_MODE}

  Helper commands:
    caldiy-update  - Update ${APP}
    caldiy-logs    - Follow logs

  [!] On first access, a setup wizard will
      guide you through creating your admin
      account. Calendar integration can be
      skipped and configured later.

  [*] Environment variables:
      PUBLIC_URL   (default: http://<IP>:3000)
      USE_LOCAL_DB (default: Y)
      DATABASE_URL (required if USE_LOCAL_DB=N)

============================================
EOF
