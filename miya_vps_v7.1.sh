#!/usr/bin/env bash
set -euo pipefail

# miya_vps_v7.1.sh

SCRIPT_VERSION="7.1"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

pause() {
  read -r -p "Press Enter to continue..." _
}

update_system() {
  echo "Updating system packages..."
  apt-get update -y
  apt-get upgrade -y
  echo "System update complete."
}

install_docker() {
  echo "Installing Docker from the official apt repository..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  echo "Docker installation complete."
}

show_system_info() {
  echo "=== System Information ==="
  uname -a
  echo
  lsb_release -a 2>/dev/null || true
  echo
  df -h /
}

main_menu() {
  while true; do
    clear
    cat <<MENU
=====================================
  Miya VPS Script v${SCRIPT_VERSION}
=====================================
1) Update system packages
2) Install Docker
3) Show system info
0) Exit
MENU

    read -r -p "Select an option: " choice
    case "$choice" in
      1)
        update_system
        pause
        ;;
      2)
        install_docker
        pause
        ;;
      3)
        show_system_info
        pause
        ;;
      0)
        echo "Goodbye."
        exit 0
        ;;
      *)
        echo "Invalid option: $choice"
        pause
        ;;
    esac
  done
}

require_root
main_menu
