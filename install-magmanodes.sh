#!/bin/bash
# ============================================================
#  MagmaNodes VPS Bot — Installer
#  Sets up LXD/LXC, Python dependencies, and the bot service.
# ============================================================

set -e

# ---------- MagmaNodes theme ----------
RED='\033[0;31m'; ORG='\033[0;33m'; GRN='\033[0;32m'
CYN='\033[0;36m'; WHT='\033[1;37m'; NC='\033[0m'

ascii_banner() {
    echo -e "${ORG} __  __                         _   _           _           ${NC}"
    echo -e "${ORG}|  \/  |                       | \ | |         | |          ${NC}"
    echo -e "${RED}| \  / | __ _  __ _ _ __ ___   |  \| | ___   __| | ___  ___ ${NC}"
    echo -e "${ORG}| |\/| |/ _\` |/ _\` | '_ \` _ \  | . \` |/ _ \ / _\` |/ _ \/ __|${NC}"
    echo -e "${RED}| |  | | (_| | (_| | | | | | | | |\  | (_) | (_| |  __/\\__ \\${NC}"
    echo -e "${ORG}|_|  |_|\\__,_|\\__, |_| |_| |_| |_| \\_|\\___/ \\__,_|\\___||___/${NC}"
    echo -e "${ORG}                 __/ |                                      ${NC}"
    echo -e "${ORG}                |___/       VPS MANAGEMENT                  ${NC}"
    echo ""
}

banner() {
    clear
    ascii_banner
    echo -e "${WHT}  ─────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${ORG}MagmaNodes VPS Discord Bot Installer${NC}"
    echo -e "  ${CYN}Ubuntu & Debian supported | Automated setup${NC}"
    echo -e "  ${ORG}MagmaNodes${NC}  |  ${CYN}Community VPS Bot${NC}"
    echo -e "${WHT}  ─────────────────────────────────────────────────────────────${NC}\n"
}

step() { echo -e "${GRN}[+]${NC} $1"; }
warn() { echo -e "${ORG}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

need_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Please run this script as root (sudo ./install-magmanodes.sh)"
        exit 1
    fi
}

choose_os() {
    echo -e "${WHT}Select your OS:${NC}"
    echo -e "  ${ORG}1)${NC} Ubuntu"
    echo -e "  ${ORG}2)${NC} Debian"
    read -rp "$(echo -e "${CYN}Enter choice [1-2]: ${NC}")" OS_CHOICE
}

install_lxd_ubuntu() {
    step "Updating system (Ubuntu)..."
    apt update && apt upgrade -y
    step "Installing LXC utilities..."
    apt install lxc lxc-utils -y
    step "Installing snapd..."
    apt install snapd -y
    systemctl enable --now snapd.socket
    step "Installing LXD via snap..."
    snap install lxd
    step "Adding ${SUDO_USER:-$USER} to lxd group..."
    usermod -aG lxd "${SUDO_USER:-$USER}" || true
    step "Initializing LXD (automatic minimal configuration)..."
    lxd init --auto
    step "Installing bridge/uidmap utilities..."
    apt update
    apt install lxc lxc-utils bridge-utils uidmap -y
}

install_lxd_debian() {
    step "Updating system (Debian)..."
    apt update && apt upgrade -y
    step "Installing snapd..."
    apt install snapd -y
    systemctl enable --now snapd.socket
    step "Linking snap directory..."
    ln -sf /var/lib/snapd/snap /snap
    step "Installing LXD via snap..."
    snap install lxd
    step "Adding ${SUDO_USER:-$USER} to lxd group..."
    usermod -aG lxd "${SUDO_USER:-$USER}" || true
    step "Initializing LXD (automatic minimal configuration)..."
    lxd init --auto
}

install_python_stack() {
    step "Installing Python 3 / pip..."
    apt install python3-pip -y
    step "Configuring pip for system package installation..."
    mkdir -p /root/.config/pip
    printf '[global]\nbreak-system-packages = true\n' > /root/.config/pip/pip.conf
    step "Installing Python dependencies (discord.py, requests)..."
    pip3 install -U discord.py requests
}

deploy_bot() {
    step "Deploying bot.py to /root ..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    BOT_SOURCE="$SCRIPT_DIR/bot.py"
    # Keep the original upstream URL until a MagmaNodes repository is provided.
    if [ ! -f "$BOT_SOURCE" ]; then
        step "bot.py not found locally; downloading the bot source..."
        BOT_SOURCE="$(mktemp)"
        BOT_URL="https://raw.githubusercontent.com/ask-developer/bot/main/bot.py"
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fL --retry 3 --connect-timeout 15 "$BOT_URL" -o "$BOT_SOURCE"; then
                rm -f "$BOT_SOURCE"
                err "Could not download bot.py. Check the source URL and internet connection."
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -O "$BOT_SOURCE" "$BOT_URL"; then
                rm -f "$BOT_SOURCE"
                err "Could not download bot.py. Check the source URL and internet connection."
                exit 1
            fi
        else
            rm -f "$BOT_SOURCE"
            err "Neither curl nor wget is installed; cannot download bot.py."
            exit 1
        fi
    fi
    if [ ! -s "$BOT_SOURCE" ]; then
        err "Downloaded bot.py is empty; refusing to install."
        exit 1
    fi
    if [ "$(readlink -f "$BOT_SOURCE")" = "$(readlink -f /root/bot.py 2>/dev/null || true)" ]; then
        step "bot.py is already in /root; skipping copy."
    else
        install -m 0644 "$BOT_SOURCE" /root/bot.py
        step "bot.py installed at /root/bot.py"
    fi
    [ "$BOT_SOURCE" = "$SCRIPT_DIR/bot.py" ] || rm -f "$BOT_SOURCE"
}

configure_env() {
    echo -e "\n${WHT}────────── MagmaNodes Bot Configuration ──────────${NC}"
    read -rsp "$(echo -e "${CYN}Enter your Discord Bot Token: ${NC}")" DISCORD_TOKEN
    echo
    read -rp "$(echo -e "${CYN}Enter your Main Admin Discord ID: ${NC}")" MAIN_ADMIN_ID
    if [ -z "$DISCORD_TOKEN" ] || [ -z "$MAIN_ADMIN_ID" ]; then
        err "Token and Admin ID cannot be empty."
        exit 1
    fi
}

create_service() {
    step "Creating systemd service..."
    cat > /etc/systemd/system/bot.service <<EOF_SERVICE
[Unit]
Description=MagmaNodes Discord VPS Bot
After=network.target

[Service]
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/bot.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=DISCORD_TOKEN=${DISCORD_TOKEN}
Environment=MAIN_ADMIN_ID=${MAIN_ADMIN_ID}
Environment=BOT_NAME=MagmaNodes

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    step "Reloading systemd daemon..."
    systemctl daemon-reload
    step "Starting bot service..."
    systemctl restart bot
    step "Enabling bot service on boot..."
    systemctl enable bot
}

final_message() {
    echo -e "\n${WHT}────────────────────────────────────────${NC}"
    echo -e "${GRN}  MagmaNodes installation complete!${NC}"
    echo -e "${WHT}────────────────────────────────────────${NC}"
    echo -e "  ${CYN}Service name:${NC} bot.service"
    echo -e "  ${CYN}Status:${NC}       systemctl status bot"
    echo -e "  ${CYN}Logs:${NC}         journalctl -u bot -f"
    echo -e "  ${CYN}Restart:${NC}      systemctl restart bot"
    echo -e "${WHT}────────────────────────────────────────${NC}\n"
}

main() {
    banner
    need_root
    choose_os
    case "$OS_CHOICE" in
        1) install_lxd_ubuntu ;;
        2) install_lxd_debian ;;
        *) err "Invalid choice. Exiting."; exit 1 ;;
    esac
    install_python_stack
    deploy_bot
    configure_env
    create_service
    final_message
}

main "$@"
