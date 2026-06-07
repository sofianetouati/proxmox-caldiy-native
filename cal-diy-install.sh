#!/usr/bin/env bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
CT_ID="${CT_ID:-$(pvesh get /cluster/nextid)}"
CT_NAME="${CT_NAME:-cal-diy}"
CT_DISK="${CT_DISK:-20}"
CT_CORES="${CT_CORES:-4}"
CT_RAM="${CT_RAM:-4096}"
CT_SWAP="${CT_SWAP:-1024}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_TEMPLATE="${CT_TEMPLATE:-debian-12-standard_12.12-1_amd64.tar.zst}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
CAL_IMAGE="${CAL_IMAGE:-calcom/cal.com:v6.2.0}"

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
  apt-get install -y -qq curl ca-certificates openssl
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
" >/dev/null 2>&1
msg_ok

# ── Create compose file & .env ──────────────────────────────────────────────
msg_info "Creating docker-compose.yml & .env"

DB_PASS=$(pct exec "$CT_ID" -- openssl rand -base64 18)
NEXT_SECRET=$(pct exec "$CT_ID" -- openssl rand -base64 32)
ENC_KEY=$(pct exec "$CT_ID" -- openssl rand -base64 24)

pct exec "$CT_ID" -- bash -c "
  mkdir -p /opt/cal.diy
  cat > /opt/cal.diy/docker-compose.yml <<'EOF'
services:
  database:
    image: postgres:16-alpine
    restart: always
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: caldiy
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: calendso

  calcom:
    image: ${CAL_IMAGE}
    restart: always
    ports:
      - 3000:3000
    env_file: .env
    environment:
      DATABASE_URL: postgresql://caldiy:${DB_PASS}@database/calendso
      DATABASE_DIRECT_URL: postgresql://caldiy:${DB_PASS}@database/calendso
    depends_on:
      - database

volumes:
  pgdata:
EOF

  cat > /opt/cal.diy/.env <<EOF
NEXT_PUBLIC_WEBAPP_URL=http://${IP_ADDR}:3000
NEXTAUTH_URL=http://${IP_ADDR}:3000
NEXTAUTH_SECRET=${NEXT_SECRET}
CALENDSO_ENCRYPTION_KEY=${ENC_KEY}
CALCOM_TELEMETRY_DISABLED=1
NEXT_PUBLIC_LICENSE_CONSENT=true
EOF
" >/dev/null 2>&1
msg_ok

# ── Pull & Start ────────────────────────────────────────────────────────────
msg_info "Pulling Docker images"
pct exec "$CT_ID" -- bash -c "
  cd /opt/cal.diy
  docker compose pull
" >/dev/null 2>&1
msg_ok

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
docker compose pull
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
echo "  Image:         ${CAL_IMAGE}"
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
