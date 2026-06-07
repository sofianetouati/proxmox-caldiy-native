#!/usr/bin/env bash
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Sofiane Touati | https://github.com/sofianetouati
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

REPO_URL="https://raw.githubusercontent.com/sofianetouati/proxmox-caldiy-native/refs/heads/main"

# Patch build.func to fetch install script from this repo instead of community-scripts
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func |
  sed "s|https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/|${REPO_URL}/install/|g")

APP="Cal.diy"
var_tags="calendar;productivity;booking"
var_cpu="4"
var_ram="8192"
var_disk="30"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

# Override var_install to match the actual install script filename (cal-diy-install.sh)
var_install="cal-diy-install"

function default_settings() {
  CT_TYPE="$var_unprivileged"
  PW=""
  CT_ID=$(pvesh get /cluster/nextid)
  CT_NAME="cal-diy"
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRIDGE="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIPV6="no"
  MTU=""
  SD=""
  NS=""
  SEARCHDOMAIN=""
  HOSTNAME="$CT_NAME"
  SSH="no"
  VERBOSE="no"
  echo_default
}

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/cal.diy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  cd /opt/cal.diy
  git fetch --all --tags
  git pull --ff-only
  docker compose pull
  docker compose up -d
  git rev-parse HEAD >/opt/${APP}_version.txt
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description
msg_ok "Completed Successfully!"
