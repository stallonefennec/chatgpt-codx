#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ===============================
# Golden Values
# ===============================
DOMAIN="${DOMAIN:-mem.fennec-lucky.com}"
NAIVE_USER="${NAIVE_USER:-stallone}"
NAIVE_PASS="${NAIVE_PASS:-198964}"
BACKUP_REPO_OWNER="${BACKUP_REPO_OWNER:-fennec-lucky}"
BACKUP_REPO_NAME="${BACKUP_REPO_NAME:-miya-backup}"
BACKUP_FILE="${BACKUP_FILE:-miya_full_backup_latest.tar.gz}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CADDY_BIN_CACHE="${CADDY_BIN_CACHE:-$OPENCLAW_DIR/bin/caddy}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_DATA_DIR="${CADDY_DATA_DIR:-/var/lib/caddy}"
LOG_FILE="${LOG_FILE:-/var/log/miya-master.log}"
CADDY_SVC_USER="${CADDY_SVC_USER:-caddy}"
GO_VERSION="${GO_VERSION:-1.22.5}"

mkdir -p "$(dirname "$LOG_FILE")"
: > /tmp/miya-master-init.log
exec > >(tee -a "$LOG_FILE") 2>&1

# ===============================
# Utility
# ===============================
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}"
}

err() {
    echo -e "${RED}[ERROR] $*${NC}" >&2
}

pause_screen() {
    read -rp "Press Enter to continue..."
}

banner() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗"
    echo "║           Miya VPS Ultimate Master v7.1                    ║"
    echo "║           Industrial-Grade Self-Healing Framework          ║"
    echo "╚══════════════════════════════════════════════════════════════╝${NC}"
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        err "This script must be run as root."
        exit 1
    fi
}

is_command_available() {
    command -v "$1" >/dev/null 2>&1
}

get_base_domain() {
    local domain="$1"
    IFS='.' read -r -a parts <<< "$domain"
    if [[ ${#parts[@]} -ge 2 ]]; then
        echo "${parts[-2]}.${parts[-1]}"
    else
        echo "$domain"
    fi
}

# ===============================
# MODULE A: System Hardening
# ===============================
setup_swap() {
    log "A1: Checking swap space..."

    if swapon --show | grep -q '^'; then
        log "  Swap already active. Skipping."
        return
    fi

    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    log "  Total RAM: ${total_ram_mb}MB. Creating 2GB swap..."

    if ! fallocate -l 2G /swapfile 2>/dev/null; then
        warn "fallocate failed, falling back to dd..."
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    fi

    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile

    if ! grep -q '^/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    if swapon --show | grep -q '/swapfile'; then
        log "  Swap enabled successfully."
    else
        err "  Swap setup verification failed."
        exit 1
    fi
}

install_core_dependencies() {
    log "A2: Installing core dependency chain..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y -qq \
        curl wget jq git ca-certificates ufw \
        build-essential libcap2-bin software-properties-common

    if ! is_command_available docker; then
        log "  Installing Docker from official script..."
        curl -fsSL https://get.docker.com | sh
    else
        log "  Docker already installed."
    fi

    if ! docker compose version >/dev/null 2>&1; then
        apt-get install -y -qq docker-compose-plugin || warn "docker-compose-plugin install failed or unavailable"
    else
        log "  docker-compose-plugin already available."
    fi

    if [[ ! -d /root/.nvm ]]; then
        log "  Installing NVM..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    else
        log "  NVM already installed."
    fi

    # shellcheck disable=SC1091
    source /root/.nvm/nvm.sh
    if ! nvm ls --no-colors --lts | grep -q 'v'; then
        log "  Installing Node.js LTS via NVM..."
        nvm install --lts
    else
        log "  Node.js LTS already installed."
    fi
}

configure_firewall() {
    log "A3: Configuring UFW firewall..."

    local ssh_port
    ssh_port=$(ss -tlnp | awk '/sshd/ {split($4,a,":"); print a[length(a)]}' | head -n1)
    ssh_port=${ssh_port:-22}

    ufw --force reset >/dev/null
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    ufw allow "$ssh_port"/tcp comment 'SSH dynamic port' >/dev/null
    ufw allow 80/tcp comment 'HTTP' >/dev/null
    ufw allow 443/tcp comment 'HTTPS' >/dev/null

    for port in 3000 5001 3001 8080 9090 12138 5230 8880 8888; do
        ufw allow "$port"/tcp comment 'Docker app service' >/dev/null
    done

    ufw --force enable >/dev/null
    log "  UFW configured and enabled. SSH port: ${ssh_port}"
}

module_a() {
    echo "========== MODULE A: System Hardening =========="
    setup_swap
    install_core_dependencies
    configure_firewall
}

# ===============================
# MODULE B: Resurrection Engine
# ===============================
install_go_if_needed() {
    if is_command_available go && go version | grep -q "go${GO_VERSION}"; then
        log "  Go ${GO_VERSION} already installed."
        return
    fi

    local arch goarch tarball
    arch=$(uname -m)
    case "$arch" in
        x86_64) goarch="amd64" ;;
        aarch64|arm64) goarch="arm64" ;;
        *) err "Unsupported architecture: $arch"; exit 1 ;;
    esac

    tarball="go${GO_VERSION}.linux-${goarch}.tar.gz"
    log "  Installing Go ${GO_VERSION} (${goarch})..."
    curl -fsSL "https://go.dev/dl/${tarball}" -o "/tmp/${tarball}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${tarball}"
    export PATH="/usr/local/go/bin:$PATH"
}

build_or_get_caddy() {
    log "B1: Getting Caddy binary with Naive plugin..."
    mkdir -p "$(dirname "$CADDY_BIN_CACHE")"

    if [[ -x "$CADDY_BIN_CACHE" ]] && "$CADDY_BIN_CACHE" list-modules | grep -q '^http.handlers.forward_proxy$'; then
        log "  Using cached Caddy binary: $CADDY_BIN_CACHE"
        install -m 0755 "$CADDY_BIN_CACHE" /usr/bin/caddy
        return
    fi

    warn "  Cached binary missing/invalid. Building with xcaddy..."
    install_go_if_needed
    export PATH="/usr/local/go/bin:/root/go/bin:$PATH"

    if ! is_command_available xcaddy; then
        /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    fi

    local build_dir
    build_dir=$(mktemp -d)
    pushd "$build_dir" >/dev/null
    xcaddy build --with github.com/caddyserver/forwardproxy@naive
    install -m 0755 caddy /usr/bin/caddy
    install -m 0755 caddy "$CADDY_BIN_CACHE"
    popd >/dev/null
    rm -rf "$build_dir"
}

setup_caddy_capabilities() {
    log "B2: Applying capability for privileged port binding..."
    setcap 'cap_net_bind_service=+ep' /usr/bin/caddy
}

generate_caddyfile() {
    log "B3: Generating Caddyfile..."
    mkdir -p /etc/caddy /var/www/html /var/log/caddy

    if [[ -f "$CADDYFILE" ]] && grep -q 'forward_proxy' "$CADDYFILE"; then
        log "  Existing forward_proxy config detected. Skipping generation."
        return
    fi

    cat > "$CADDYFILE" <<EOC
{
    order forward_proxy before file_server
    admin off
    log {
        output file /var/log/caddy/access.log
        level INFO
    }
}

:443, ${DOMAIN} {
    tls {
        protocols tls1.2 tls1.3
        ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
    }

    forward_proxy {
        basic_auth ${NAIVE_USER} ${NAIVE_PASS}
        hide_ip
        hide_via
        probe_resistance
    }

    root * /var/www/html
    file_server
}
EOC

    echo 'It works!' > /var/www/html/index.html
    chmod 0644 "$CADDYFILE"
}

setup_caddy_systemd() {
    log "B4: Configuring caddy systemd service..."

    if ! id "$CADDY_SVC_USER" >/dev/null 2>&1; then
        useradd --system --home "$CADDY_DATA_DIR" --shell /usr/sbin/nologin "$CADDY_SVC_USER"
    fi

    mkdir -p "$CADDY_DATA_DIR" /etc/caddy /var/log/caddy
    chown -R "$CADDY_SVC_USER":"$CADDY_SVC_USER" "$CADDY_DATA_DIR" /etc/caddy /var/log/caddy

    cat > /etc/systemd/system/caddy.service <<'EOS'
[Unit]
Description=Caddy web server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=120
StartLimitBurst=10

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOS

    systemctl daemon-reload
    systemctl enable --now caddy
    sleep 2
    if ! systemctl is-active --quiet caddy; then
        err "Caddy failed to start. Check: journalctl -u caddy"
        exit 1
    fi
}

module_b() {
    echo "========== MODULE B: Resurrection Engine =========="
    build_or_get_caddy
    setup_caddy_capabilities
    generate_caddyfile
    setup_caddy_systemd
}

# ===============================
# MODULE C: Soul Injection
# ===============================
restore_backup_from_github() {
    log "C1: Restoring backup from GitHub..."
    local token="${GITHUB_PAT:-}"

    if [[ -z "$token" ]]; then
        read -rsp "Enter GitHub PAT: " token
        echo
    fi

    local tmpdir api_url asset_url download_url backup_path
    tmpdir=$(mktemp -d)
    backup_path="$tmpdir/$BACKUP_FILE"
    api_url="https://api.github.com/repos/${BACKUP_REPO_OWNER}/${BACKUP_REPO_NAME}/releases/latest"

    asset_url=$(curl -fsSL -H "Authorization: token ${token}" "$api_url" | jq -r --arg n "$BACKUP_FILE" '.assets[] | select(.name==$n) | .url' || true)

    if [[ -n "${asset_url:-}" && "$asset_url" != "null" ]]; then
        log "  Downloading backup from latest release asset..."
        curl -fL \
            -H "Authorization: token ${token}" \
            -H "Accept: application/octet-stream" \
            "$asset_url" -o "$backup_path"
    else
        warn "  Release asset not found. Falling back to raw main branch file..."
        download_url="https://raw.githubusercontent.com/${BACKUP_REPO_OWNER}/${BACKUP_REPO_NAME}/main/${BACKUP_FILE}"
        curl -fL -H "Authorization: token ${token}" "$download_url" -o "$backup_path"
    fi

    if [[ ! -s "$backup_path" ]]; then
        err "Downloaded backup is empty or missing."
        rm -rf "$tmpdir"
        exit 1
    fi

    tar -xzpf "$backup_path" -C "$HOME"
    rm -rf "$tmpdir"
    log "  Backup restored successfully."
}

module_c() {
    echo "========== MODULE C: Soul Injection =========="
    restore_backup_from_github
}

# ===============================
# MODULE D: App Store
# ===============================
declare -A APP_MAP=(
    ["memos"]="note:5230:5230:neosmemo/memos:stable"
    ["vaultwarden"]="pass:8880:80:vaultwarden/server:latest"
    ["uptime-kuma"]="status:3001:3001:louislam/uptime-kuma:1"
    ["stirling-pdf"]="pdf:8080:8080:frooodle/s-pdf:latest"
    ["linkding"]="link:9090:9090:sissbruecker/linkding:latest"
    ["it-tools"]="tools:8888:80:corentinth/it-tools:latest"
)

inject_reverse_proxy() {
    local subdomain="$1"
    local port="$2"
    local base_domain fqdn

    base_domain=$(get_base_domain "$DOMAIN")
    fqdn="${subdomain}.${base_domain}"

    if grep -q "^${fqdn}[[:space:]]*{" "$CADDYFILE" 2>/dev/null; then
        log "  Reverse proxy for ${fqdn} already exists. Skipping."
        return
    fi

    cat >> "$CADDYFILE" <<EOR

${fqdn} {
    reverse_proxy localhost:${port}
    tls {
        protocols tls1.2 tls1.3
    }
}
EOR
}

deploy_docker_app() {
    local app_name="$1"
    local image="$2"
    local host_port="$3"
    local container_port="$4"
    local extra_opts="${5:-}"

    local data_dir
    data_dir="$OPENCLAW_DIR/apps/${app_name}"
    mkdir -p "$data_dir"

    if docker ps -a --format '{{.Names}}' | grep -qx "$app_name"; then
        log "  Removing existing container: $app_name"
        docker rm -f "$app_name" >/dev/null
    fi

    log "  Deploying ${app_name} (${image})..."
    # shellcheck disable=SC2086
    docker run -d \
        --name "$app_name" \
        --restart unless-stopped \
        -p "127.0.0.1:${host_port}:${container_port}" \
        -v "${data_dir}:/data" \
        $extra_opts \
        "$image" >/dev/null
}

deploy_blinko() {
    log "Deploying Blinko (special two-container mode)..."
    local data_dir network secret base_domain
    data_dir="$OPENCLAW_DIR/apps/blinko"
    network="blinko-net"
    base_domain=$(get_base_domain "$DOMAIN")
    secret=$(openssl rand -hex 32)

    mkdir -p "$data_dir/pgdata"
    docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null

    docker rm -f blinko-postgres >/dev/null 2>&1 || true
    docker rm -f blinko >/dev/null 2>&1 || true

    docker run -d \
        --name blinko-postgres \
        --restart unless-stopped \
        --network "$network" \
        -e POSTGRES_DB=blinko \
        -e POSTGRES_USER=blinko \
        -e POSTGRES_PASSWORD=blinko_secure_pwd_2024 \
        -v "$data_dir/pgdata:/var/lib/postgresql/data" \
        postgres:16-alpine >/dev/null

    sleep 5

    docker run -d \
        --name blinko \
        --restart unless-stopped \
        --network "$network" \
        -p 127.0.0.1:12138:3000 \
        -e DATABASE_URL='postgresql://blinko:blinko_secure_pwd_2024@blinko-postgres:5432/blinko' \
        -e NEXTAUTH_SECRET="$secret" \
        -e NEXT_PUBLIC_BASE_URL="https://blinko.${base_domain}" \
        blinkospace/blinko:latest >/dev/null

    inject_reverse_proxy "blinko" 12138
    systemctl reload caddy
}

deploy_named_app() {
    local app_name="$1"
    local cfg subdomain host_port container_port image
    cfg="${APP_MAP[$app_name]}"

    IFS=':' read -r subdomain host_port container_port image <<< "$cfg"
    deploy_docker_app "$app_name" "$image" "$host_port" "$container_port"
    inject_reverse_proxy "$subdomain" "$host_port"
    systemctl reload caddy
}

deploy_all_apps() {
    deploy_named_app memos
    deploy_named_app vaultwarden
    deploy_named_app uptime-kuma
    deploy_named_app stirling-pdf
    deploy_named_app linkding
    deploy_named_app it-tools
    deploy_blinko
}

app_store_menu() {
    while true; do
        cat <<'EOM'
╔══════════════════════════════════════════╗
║        App Store (Docker Ecosystem)      ║
╠══════════════════════════════════════════╣
║  1)  Memos          (note.*)             ║
║  2)  Vaultwarden    (pass.*)             ║
║  3)  Uptime Kuma    (status.*)           ║
║  4)  Stirling-PDF   (pdf.*)              ║
║  5)  Linkding       (link.*)             ║
║  6)  IT-Tools       (tools.*)            ║
║  7)  Blinko         (blinko.*)           ║
║  8)  Deploy ALL Apps                     ║
║  0)  Back to Main Menu                   ║
╚══════════════════════════════════════════╝
EOM
        read -rp "Select option [0-8]: " app_choice
        case "$app_choice" in
            1) deploy_named_app memos ;;
            2) deploy_named_app vaultwarden ;;
            3) deploy_named_app uptime-kuma ;;
            4) deploy_named_app stirling-pdf ;;
            5) deploy_named_app linkding ;;
            6) deploy_named_app it-tools ;;
            7) deploy_blinko ;;
            8) deploy_all_apps ;;
            0) break ;;
            *) warn "Invalid selection. Try again." ;;
        esac
    done
}

module_d() {
    echo "========== MODULE D: App Store =========="
    app_store_menu
}

# ===============================
# Status & Menu
# ===============================
show_system_status() {
    local swap_info docker_info caddy_state ufw_state
    swap_info=$(swapon --show --bytes | awk 'NR==2 {printf "%.1fG", $3/1024/1024/1024}' || true)
    swap_info=${swap_info:-none}
    docker_info=$(docker --version 2>/dev/null || echo "not installed")
    caddy_state=$(systemctl is-active caddy 2>/dev/null || echo "inactive")
    ufw_state=$(ufw status | head -n1 2>/dev/null || echo "unknown")

    echo "──── System Status ────"
    echo "  Swap:     $swap_info"
    echo "  Docker:   $docker_info"
    echo "  Caddy:    $caddy_state"
    echo "  UFW:      $ufw_state"
    echo
    echo "──── Running Containers ────"
    docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    echo
    echo "──── NaiveProxy Info ────"
    echo "  Domain:   $DOMAIN"
    echo "  User:     $NAIVE_USER"
    echo "  Protocol: naive+https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}:443"
}

full_system_setup() {
    module_a
    module_b
}

full_deploy() {
    module_a
    module_b
    module_c
    deploy_all_apps
}

main_menu() {
    while true; do
        banner
        cat <<'EOM'
Layer 1: Core Operations
  1)  Full System Setup (A+B combined)
  2)  Module A: System Hardening Only
  3)  Module B: Caddy/NaiveProxy Only
  4)  Module C: Soul Injection (Restore Backup)

Layer 2: Application Layer
  5)  Module D: App Store

Utilities
  6)  Show System Status
  7)  Full Deploy (A+B+C+D)
  0)  Exit
EOM
        read -rp "Select option [0-7]: " choice

        case "$choice" in
            1) full_system_setup ;;
            2) module_a ;;
            3) module_b ;;
            4) module_c ;;
            5) module_d ;;
            6) show_system_status ;;
            7) full_deploy ;;
            0) log "Bye."; exit 0 ;;
            *) warn "Invalid option." ;;
        esac
        pause_screen
    done
}

main() {
    require_root
    mkdir -p "$OPENCLAW_DIR" "$OPENCLAW_DIR/bin" "$OPENCLAW_DIR/tmp" "$OPENCLAW_DIR/apps"
    main_menu
}

main "$@"
