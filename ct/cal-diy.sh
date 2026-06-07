#!/usr/bin/env bash
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/build.func)
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
