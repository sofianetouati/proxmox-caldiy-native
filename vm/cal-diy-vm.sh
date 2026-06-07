#!/usr/bin/env bash
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Sofiane Touati | https://github.com/sofianetouati
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

REPO_URL="https://raw.githubusercontent.com/sofianetouati/proxmox-caldiy-native/refs/heads/main"

source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/api.func) 2>/dev/null
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/vm-core.func) 2>/dev/null
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/cloud-init.func) 2>/dev/null || true
load_functions

APP="Cal.diy"
APP_TYPE="vm"
NSAPP="cal-diy-vm"
var_os="debian"
var_version="12"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
DISK_SIZE="50G"
USE_CLOUD_INIT="yes"
OS_TYPE="debian"
OS_VERSION="12"
OS_CODENAME="bookworm"
OS_DISPLAY="Debian 12 (Bookworm)"
THIN="discard=on,ssd=1,"

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${exit_code}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_image_url() {
  local arch=$(dpkg --print-architecture)
  if [ "$USE_CLOUD_INIT" = "yes" ]; then
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
  else
    echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
  fi
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=""
  MACHINE=" -machine q35"
  DISK_CACHE=""
  DISK_SIZE="50G"
  HN="cal-diy"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="8192"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}Q35 (Modern)${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${CLOUD:-☁️}${TAB}${CL}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Cal.diy VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  configure_cloudinit_ssh_keys || true
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $VMID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit_script
    fi
  done

  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 50, 100)" 8 58 50 --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size.${CL}"
      exit_script
    fi
  else
    exit_script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 cal-diy --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      HN="cal-diy"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Hostname adjusted to:\n\n  $HN" 10 58
      fi
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit_script
  fi

  while true; do
    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 4 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$CORE_COUNT" ]; then CORE_COUNT="4"; fi
      if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer." 8 58
    else
      exit_script
    fi
  done

  while true; do
    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$RAM_SIZE" ]; then RAM_SIZE="8192"; fi
      if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM must be a positive integer in MiB." 8 58
    else
      exit_script
    fi
  done

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRG ]; then BRG="vmbr0"; fi
    echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
  else
    exit_script
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a Cal.diy VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a Cal.diy VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

header_info
check_root
arch_check
pve_check

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Cal.diy VM" --yesno "This will create a New Cal.diy VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

start_script
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')

VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
  apt-get -qq install dhcpcd-base -y >/dev/null 2>&1 || true
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the ${OS_DISPLAY} Qcow2 Disk Image"
URL=$(get_image_url)
CACHE_DIR="/var/lib/vz/template/cache"
mkdir -p "$CACHE_DIR"
msg_ok "${CL}${BL}${URL}${CL}"

CACHE_FILE="${CACHE_DIR}/$(basename "$URL")"
if [[ ! -s "$CACHE_FILE" ]]; then
  curl -f#SL -o "$CACHE_FILE" "$URL"
  echo -en "\e[1A\e[0K"
  msg_ok "Downloaded ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
else
  msg_ok "Using cached image ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
fi

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="--format raw"
  ;;
esac

msg_info "Preparing ${OS_DISPLAY} image with Docker"
WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"
export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

msg_info "Installing base packages in image"
if virt-customize -a "$WORK_FILE" --install qemu-guest-agent,curl,ca-certificates,git,openssl,jq,sudo,gnupg >/dev/null 2>&1; then
  msg_ok "Installed base packages"

  msg_info "Installing Docker (may take 2-5 minutes)"
  if virt-customize -q -a "$WORK_FILE" --run-command "curl -fsSL https://get.docker.com | sh" >/dev/null 2>&1 &&
    virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable docker" >/dev/null 2>&1; then
    msg_ok "Installed Docker"

    msg_info "Configuring Docker daemon"
    virt-customize -q -a "$WORK_FILE" --run-command "mkdir -p /etc/docker" >/dev/null 2>&1
    virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF' >/dev/null 2>&1
    msg_ok "Configured Docker daemon"
  else
    msg_warn "Docker installation failed, will retry on first boot"
  fi
else
  msg_warn "Base package installation failed, will install on first boot"
fi

msg_info "Creating first-boot Cal.diy installer service"
virt-customize -q -a "$WORK_FILE" --run-command 'cat > /root/caldiy-firstboot.sh << "INSTALLSCRIPT"
#!/bin/bash
exec > /var/log/caldiy-install.log 2>&1
echo "[$(date)] Starting Cal.diy installation"

for i in {1..30}; do
  ping -c 1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

if ! command -v docker &>/dev/null; then
  echo "[$(date)] Installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

echo "[$(date)] Downloading Cal.diy install script"
curl -fsSL '${REPO_URL}/install/cal-diy-install.sh' -o /opt/cal-diy-install.sh
chmod +x /opt/cal-diy-install.sh

export FUNCTIONS_FILE_PATH=""
cd /opt
bash /opt/cal-diy-install.sh

touch /root/.caldiy-installed
echo "[$(date)] Cal.diy installation completed"
INSTALLSCRIPT
chmod +x /root/caldiy-firstboot.sh' >/dev/null 2>&1 || true

virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/caldiy-firstboot.service << "SERVICE"
[Unit]
Description=Cal.diy First Boot Installer
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/root/.caldiy-installed

[Service]
Type=oneshot
ExecStart=/root/caldiy-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable caldiy-firstboot.service' >/dev/null 2>&1 || true
msg_ok "Created first-boot installer service"

msg_info "Finalizing image"
virt-customize -q -a "$WORK_FILE" --hostname "${HN}" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
msg_ok "Finalized image"

msg_info "Resizing disk image to ${DISK_SIZE}"
qemu-img resize "$WORK_FILE" "${DISK_SIZE}" >/dev/null 2>&1
msg_ok "Resized disk image"

msg_info "Creating Cal.diy VM shell"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

msg_info "Importing disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi

IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "$WORK_FILE" "$STORAGE" ${DISK_IMPORT:-} 2>&1 || true)"
DISK_REF_IMPORTED="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF_IMPORTED" ]] && DISK_REF_IMPORTED="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF_IMPORTED" ]] && {
  msg_error "Unable to determine imported disk reference."
  echo "$IMPORT_OUT"
  exit 226
}
msg_ok "Imported disk (${CL}${BL}${DISK_REF_IMPORTED}${CL})"
rm -f "$WORK_FILE"

msg_info "Attaching EFI and root disk"
qm set "$VMID" \
  --efidisk0 "${STORAGE}:0,efitype=4m" \
  --scsi0 "${DISK_REF_IMPORTED},${DISK_CACHE}${THIN%,}" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null
qm set $VMID --agent enabled=1 >/dev/null
msg_ok "Attached EFI and root disk"

set_description

msg_info "Configuring Cloud-Init"
setup_cloud_init "$VMID" "$STORAGE" "$HN" "yes"
msg_ok "Cloud-Init configured"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Cal.diy VM"
  qm start $VMID >/dev/null 2>&1
  msg_ok "Started Cal.diy VM"
fi

VM_IP=""
if [ "$START_VM" == "yes" ]; then
  set +e
  for i in {1..10}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null |
      jq -r '.[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' 2>/dev/null |
      grep -v "^127\." | head -1) || true
    [ -n "$VM_IP" ] && break
    sleep 3
  done
  set -e
fi

echo -e "\n${INFO}${BOLD}${GN}Cal.diy VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}OS: ${BGN}${OS_DISPLAY}${CL}"
echo -e "${TAB}${DGN}CPU: ${BGN}${CORE_COUNT} cores${CL}"
echo -e "${TAB}${DGN}RAM: ${BGN}${RAM_SIZE} MiB${CL}"
echo -e "${TAB}${DGN}Disk: ${BGN}${DISK_SIZE}${CL}"
[ -n "$VM_IP" ] && echo -e "${TAB}${DGN}IP Address: ${BGN}${VM_IP}${CL}"
echo -e "${TAB}${DGN}Docker: ${BGN}Pre-installed${CL}"
echo -e ""
echo -e "${TAB}${YW}\u26a0\ufe0f  Cal.diy is being installed on first boot ($(test -n "$VM_IP" && echo "~30-40 min" || echo "after first start"))${CL}"
echo -e "${TAB}${YW}   Check progress:${CL}"
echo -e "${TAB}${BL}   ssh root@${VM_IP:-<IP>} 'tail -f /var/log/caldiy-install.log'${CL}"
echo -e "${TAB}${BL}   # or via Proxmox Shell: qm terminal ${VMID}${CL}"
echo -e ""
echo -e "${TAB}${GN}Cal.diy will be available at http://${VM_IP:-<IP>}:3000 after the build completes.${CL}"

display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
