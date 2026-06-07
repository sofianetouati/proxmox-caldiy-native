#!/usr/bin/env bash
source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)"
# Copyright (c) 2025-2026 community-scripts ORG
# Author: Perplexity
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/calcom/cal.diy

APP="Cal.diy"
var_tags="calendar;productivity;booking"
var_cpu="2"
var_ram="4096"
var_disk="20"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

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
  APT_CACHER="1"
  APT_CACHER_IP=""
  DISABLEIPV6="no"
  MTU=""
  SD="local-lvm"
  NS="1.1.1.1"
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
  if [[ ! -x /usr/local/bin/caldiy-update ]]; then
    msg_error "Update helper not found: /usr/local/bin/caldiy-update"
    exit 1
  fi
  msg_info "Updating $APP"
  /usr/local/bin/caldiy-update
  msg_ok "Updated $APP"
}

start
build_container
description
msg_ok "Completed Successfully!"
