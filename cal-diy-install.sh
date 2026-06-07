#!/usr/bin/env bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
CT_ID="${CT_ID:-$(pvesh get /cluster/nextid)}"
CT_NAME="${CT_NAME:-cal-diy}"
CT_DISK="${CT_DISK:-40}"
CT_CORES="${CT_CORES:-4}"
CT_RAM="${CT_RAM:-8192}"
CT_SWAP="${CT_SWAP:-4096}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_TEMPLATE="${CT_TEMPLATE:-debian-12-standard_12.12-1_amd64.tar.zst}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
PUBLIC_URL="${PUBLIC_URL:-}"
USE_LOCAL_DB="${USE_LOCAL_DB:-Y}"
DATABASE_URL="${DATABASE_URL:-}"

REPO_URL="https://github.com/calcom/cal.diy.git"

# ── Colors ──────────────────────────────────────────────────────────────────
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")

msg_info() { echo -ne "  ${YW}[INFO]${CL} ${1}... "; }
msg_ok()   { echo -e "${GN}OK${CL}"; }
msg_error(){ echo -e "${RD}FAILED${CL}"; exit 1; }

# ── Check root & Proxmox ────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on Proxmox VE"
  exit 1
fi

if ! command -v pvesh &>/dev/null; then
  echo "This script must be run on a Proxmox VE host"
  exit 1
fi

# ── Create CT ───────────────────────────────────────────────────────────────
msg_info "Creating LXC container (${CT_NAME}, ${CT_CORES} CPU, ${CT_RAM}MiB RAM, ${CT_DISK}G disk)"
pct create "$CT_ID" "${TEMPLATE_STORAGE}:vztmpl/${CT_TEMPLATE}" \
  --hostname "$CT_NAME" \
  --cores "$CT_CORES" \
  --memory "$CT_RAM" \
  --swap "$CT_SWAP" \
  --rootfs "${STORAGE}:${CT_DISK}" \
  --net0 name=eth0,bridge=${CT_BRIDGE},ip=dhcp \
  --unprivileged 1 \
  --ostype debian \
  --onboot 1 \
  --features keyctl=1,nesting=1 \
  >/dev/null
msg_ok

# ── Start CT ────────────────────────────────────────────────────────────────
msg_info "Starting container"
pct start "$CT_ID"
sleep 3
msg_ok

# ── Wait for network ────────────────────────────────────────────────────────
msg_info "Waiting for network"
for i in $(seq 1 30); do
  if pct exec "$CT_ID" -- ping -c 1 8.8.8.8 &>/dev/null; then
    msg_ok; break
  fi
  sleep 2
done

IP_ADDR=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}')

# ── Install Docker ──────────────────────────────────────────────────────────
msg_info "Installing Docker"
pct exec "$CT_ID" -- bash -c "
  set -e
  apt-get update -qq
  apt-get install -y -qq curl git openssl ca-certificates
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
" >/dev/null 2>&1
msg_ok

# ── Clone Cal.diy ───────────────────────────────────────────────────────────
msg_info "Cloning Cal.diy (1.1 GiB)"
pct exec "$CT_ID" -- bash -c "
  mkdir -p /opt
  git clone --recursive --quiet ${REPO_URL} /opt/cal.diy
" >/dev/null 2>&1
msg_ok

# ── Configure .env ──────────────────────────────────────────────────────────
msg_info "Configuring environment"
pct exec "$CT_ID" -- bash -c "
  cd /opt/cal.diy
  cp .env.example .env

  NEXTAUTH_SECRET=\$(openssl rand -base64 32)
  CALENDSO_ENCRYPTION_KEY=\$(openssl rand -base64 24)

  sed -i \
    -e \"s|^NEXT_PUBLIC_WEBAPP_URL=.*|NEXT_PUBLIC_WEBAPP_URL=http://${IP_ADDR}:3000|\" \
    -e \"s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=\${NEXTAUTH_SECRET}|\" \
    -e \"s|^CALENDSO_ENCRYPTION_KEY=.*|CALENDSO_ENCRYPTION_KEY=\${CALENDSO_ENCRYPTION_KEY}|\" \
    .env
" >/dev/null 2>&1
msg_ok

# ── Build & Start ───────────────────────────────────────────────────────────
echo ""
echo "  ${YW}Building Cal.diy Docker images (30-40 min)...${CL}"
echo "  Progress: pct enter ${CT_ID} -- docker compose -f /opt/cal.diy/docker-compose.yml logs -f"
echo ""

pct exec "$CT_ID" -- bash -c "
  cd /opt/cal.diy
  export NEXT_TYPECHECK=false
  export SKIP_TYPECHECK=1
  docker compose build
" 2>&1 | tail -5

msg_info "Starting Cal.diy"
pct exec "$CT_ID" -- bash -c "
  cd /opt/cal.diy
  docker compose up -d
" >/dev/null 2>&1
msg_ok

# ── Helper commands ─────────────────────────────────────────────────────────
msg_info "Creating helper commands"
pct exec "$CT_ID" -- bash -c "
  cat > /usr/local/bin/caldiy-update <<'EOS'
cd /opt/cal.diy
git fetch --all --tags --quiet
git pull --ff-only --quiet
export NEXT_TYPECHECK=false
export SKIP_TYPECHECK=1
docker compose build --quiet
docker compose up -d
EOS
  chmod +x /usr/local/bin/caldiy-update

  cat > /usr/local/bin/caldiy-logs <<'EOS'
cd /opt/cal.diy
exec docker compose logs -f --tail=200
EOS
  chmod +x /usr/local/bin/caldiy-logs
" >/dev/null 2>&1
msg_ok

# ── Recap ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Cal.diy installation complete"
echo "============================================"
echo ""
echo "  CT ID:         ${CT_ID}"
echo "  Hostname:      ${CT_NAME}"
echo "  IP:            ${IP_ADDR:-<DHCP assigned>}"
echo "  URL:           http://${IP_ADDR:-<IP>}:3000"
echo "  Path:          /opt/cal.diy"
echo ""
echo "  Helper commands (inside CT):"
echo "    caldiy-update    - Update Cal.diy"
echo "    caldiy-logs      - Follow logs"
echo ""
echo "  Access:"
echo "    pct enter ${CT_ID}"
echo "    ssh root@${IP_ADDR:-<IP>}"
echo ""
echo "============================================"
