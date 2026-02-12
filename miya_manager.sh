#!/usr/bin/env bash
set -euo pipefail

GITHUB_USER="stallonefennec"
PUBLIC_REPO="miya-naive-bin"
PRIVATE_REPO="miya-soul-config"
OPENCLAW_HOME="${HOME}/.openclaw"
ENV_FILE="${OPENCLAW_HOME}/.env"
NVM_DIR="${HOME}/.nvm"
CADDY_BIN="/usr/bin/caddy"
CADDYFILE_PATH="/etc/caddy/Caddyfile"
CADDY_SERVICE_PATH="/etc/systemd/system/caddy.service"
TMP_ROOT="/tmp/miya-soul-body"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

ensure_nvm_loaded() {
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "${NVM_DIR}/nvm.sh"
  fi
}

ensure_token() {
  mkdir -p "${OPENCLAW_HOME}"

  if [ -f "${ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${ENV_FILE}"
    set +a
  fi

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    read -r -s -p "请输入 GITHUB_TOKEN: " GITHUB_TOKEN
    echo
    if [ -z "${GITHUB_TOKEN}" ]; then
      log "GITHUB_TOKEN 不能为空。"
      exit 1
    fi

    if [ -f "${ENV_FILE}" ]; then
      if grep -q '^GITHUB_TOKEN=' "${ENV_FILE}"; then
        sed -i "s#^GITHUB_TOKEN=.*#GITHUB_TOKEN=${GITHUB_TOKEN}#" "${ENV_FILE}"
      else
        printf 'GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN}" >> "${ENV_FILE}"
      fi
    else
      printf 'GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN}" > "${ENV_FILE}"
    fi
    chmod 600 "${ENV_FILE}"
    log "GITHUB_TOKEN 已写入 ${ENV_FILE}"
  fi
}

ensure_base_packages() {
  log "安装基础依赖..."
  sudo apt update
  sudo apt install -y git curl rsync docker.io gh
}

ensure_nvm_node22() {
  if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
    log "检测到 NVM 不存在，开始安装..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi

  if ! grep -q 'export NVM_DIR="\$HOME/.nvm"' "${HOME}/.bashrc"; then
    {
      echo 'export NVM_DIR="$HOME/.nvm"'
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    } >> "${HOME}/.bashrc"
  fi

  awk '!seen[$0]++' "${HOME}/.bashrc" > "${HOME}/.bashrc.tmp" && mv "${HOME}/.bashrc.tmp" "${HOME}/.bashrc"

  ensure_nvm_loaded
  if ! command -v nvm >/dev/null 2>&1; then
    log "nvm 加载失败。"
    exit 1
  fi
  nvm install 22
  nvm use 22
}

install_openclaw() {
  log "安装 OpenClaw..."
  npm install -g openclaw
  sudo ln -sf "$(command -v openclaw)" /usr/local/bin/openclaw
}

restore_body() {
  local temp_body="${TMP_ROOT}/body"
  mkdir -p "${temp_body}"
  rm -rf "${temp_body:?}"/*

  ensure_token

  log "下载 caddy 二进制..."
  git -c http.extraheader="Authorization: Bearer ${GITHUB_TOKEN}" \
    clone "https://github.com/${GITHUB_USER}/${PUBLIC_REPO}.git" "${temp_body}"

  if [ ! -f "${temp_body}/caddy" ]; then
    log "公仓中未找到 caddy 二进制。"
    exit 1
  fi

  sudo install -m 0755 "${temp_body}/caddy" "${CADDY_BIN}"
  sudo mkdir -p /etc/caddy

  sudo tee "${CADDY_SERVICE_PATH}" >/dev/null <<'SERVICE'
[Unit]
Description=Caddy Web Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
SERVICE

  sudo systemctl daemon-reload
  sudo systemctl enable --now caddy
}

extract_env_from_caddyfile() {
  if [ -f "${CADDYFILE_PATH}" ]; then
    local first_line
    first_line="$(head -n 1 "${CADDYFILE_PATH}")"
    DOMAIN="$(echo "${first_line}" | sed -E 's/^:443, *([^ ]+).*/\1/')"
    USER="$(grep -E '^[[:space:]]*basic_auth[[:space:]]' -A2 "${CADDYFILE_PATH}" | awk 'NR==2{print $1}')"
    PASS="$(grep -E '^[[:space:]]*basic_auth[[:space:]]' -A2 "${CADDYFILE_PATH}" | awk 'NR==2{print $2}')"
  fi
}

write_env_value() {
  local key="$1"
  local value="$2"

  if [ -z "${value}" ]; then
    return
  fi

  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

restore_soul() {
  local temp_soul="${TMP_ROOT}/soul"
  mkdir -p "${temp_soul}"
  rm -rf "${temp_soul:?}"/*

  ensure_token
  mkdir -p "${OPENCLAW_HOME}"

  log "拉取私有灵魂仓库..."
  git -c http.extraheader="Authorization: Bearer ${GITHUB_TOKEN}" \
    clone "https://github.com/${GITHUB_USER}/${PRIVATE_REPO}.git" "${temp_soul}"

  rsync -a --delete \
    --exclude 'logs/' --exclude 'tmp/' --exclude 'node_modules/' --exclude 'sessions/' \
    "${temp_soul}/" "${OPENCLAW_HOME}/"

  if [ -f "${ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    . "${ENV_FILE}"
    set +a
  fi

  if [ -z "${DOMAIN:-}" ]; then
    DOMAIN="$(grep -E '^:443,' "${CADDYFILE_PATH}" 2>/dev/null | head -n 1 | sed -E 's/^:443, *([^ ]+).*/\1/' || true)"
    if [ -z "${DOMAIN}" ]; then
      read -r -p "请输入 DOMAIN: " DOMAIN
    fi
  fi

  if [ -z "${USER:-}" ]; then
    read -r -p "请输入 Caddy BasicAuth 用户名(USER): " USER
  fi

  if [ -z "${PASS:-}" ]; then
    read -r -s -p "请输入 Caddy BasicAuth 密码(PASS): " PASS
    echo
  fi

  touch "${ENV_FILE}"
  write_env_value "DOMAIN" "${DOMAIN}"
  write_env_value "USER" "${USER}"
  write_env_value "PASS" "${PASS}"
  chmod 600 "${ENV_FILE}"

  sudo mkdir -p /etc/caddy
  sudo tee "${CADDYFILE_PATH}" >/dev/null <<EOF2
:443, ${DOMAIN}

route {
  forward_proxy {
    basic_auth ${USER} ${PASS}
    hide_ip
    hide_via
    probe_resistance
  }
}
EOF2

  sudo systemctl restart caddy || true
}

cloud_save() {
  local full_sync="false"

  if [ "${1:-}" = "--full" ]; then
    full_sync="true"
  fi

  ensure_token
  mkdir -p "${TMP_ROOT}"

  extract_env_from_caddyfile
  touch "${ENV_FILE}"
  write_env_value "DOMAIN" "${DOMAIN:-}"
  write_env_value "USER" "${USER:-}"
  write_env_value "PASS" "${PASS:-}"

  local temp_soul="${TMP_ROOT}/cloud-soul"
  rm -rf "${temp_soul}"
  mkdir -p "${temp_soul}"

  rsync -a --delete \
    --exclude 'logs/' --exclude 'tmp/' --exclude 'node_modules/' --exclude 'sessions/' \
    "${OPENCLAW_HOME}/" "${temp_soul}/"

  cd "${temp_soul}" || exit 1
  git init
  git remote add origin "https://github.com/${GITHUB_USER}/${PRIVATE_REPO}.git"
  git add .
  git commit -m "chore: cloud save soul config $(date '+%F %T')" || true
  git -c http.extraheader="Authorization: Bearer ${GITHUB_TOKEN}" push -f origin HEAD:main

  if [ "${full_sync}" = "false" ]; then
    read -r -p "是否同步 Body（二进制）到公仓？输入 yes 确认: " answer
    if [ "${answer}" = "yes" ]; then
      full_sync="true"
    fi
  fi

  if [ "${full_sync}" = "true" ]; then
    local temp_body="${TMP_ROOT}/cloud-body"
    rm -rf "${temp_body}"
    mkdir -p "${temp_body}"

    if [ -f "${CADDY_BIN}" ]; then
      cp "${CADDY_BIN}" "${temp_body}/caddy"
      cd "${temp_body}" || exit 1
      git init
      git remote add origin "https://github.com/${GITHUB_USER}/${PUBLIC_REPO}.git"
      git add caddy
      git commit -m "chore: cloud save body binary $(date '+%F %T')" || true
      git -c http.extraheader="Authorization: Bearer ${GITHUB_TOKEN}" push -f origin HEAD:main
      log "Body 二进制已同步。"
    else
      log "未找到 ${CADDY_BIN}，跳过 Body 同步。"
    fi
  fi
}

audit_env() {
  ensure_nvm_loaded

  for bin in git docker node npm gh rsync curl openclaw caddy; do
    if command -v "${bin}" >/dev/null 2>&1; then
      version="$(${bin} --version 2>/dev/null | head -n 1 || true)"
      printf '[OK] %-10s %s\n' "${bin}" "${version}"
    else
      printf '[NO] %-10s 未安装\n' "${bin}"
    fi
  done
}

full_restore() {
  ensure_base_packages
  ensure_nvm_node22
  install_openclaw
  restore_body
  restore_soul
  log "全自动复活部署完成。"
  log "请重新登录 SSH 以激活所有环境变量"
}

show_menu() {
  cat <<'MENU'
==============================
Miya Soul & Body Manager v10.5
==============================
1) 环境审计 (Audit)
2) 全自动复活部署 (Full Restore)
3) 灵魂云端备份 (Cloud Save)
4) 退出
MENU
}

main() {
  mkdir -p "${TMP_ROOT}"

  while true; do
    show_menu
    read -r -p "请选择功能 [1-4]: " choice
    case "${choice}" in
      1)
        audit_env
        ;;
      2)
        full_restore
        ;;
      3)
        read -r -p "是否执行全量备份（含 Body）? [y/N]: " backup_choice
        if [[ "${backup_choice}" =~ ^[Yy]$ ]]; then
          cloud_save --full
        else
          cloud_save
        fi
        ;;
      4)
        exit 0
        ;;
      *)
        log "无效选项，请重新输入。"
        ;;
    esac
  done
}

main "$@"
