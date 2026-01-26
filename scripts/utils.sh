#!/usr/bin/env bash
# utils.sh - Common utility functions for Chomusuke Deploy scripts
# Place this file in scripts/utils.sh
# Usage: source "$(dirname "$0")/utils.sh"

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# === Logging ===
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# === Checks ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo."
        exit 1
    fi
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found."
        exit 1
    fi
}

package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

ensure_package() {
    local pkg="$1"
    if ! package_installed "$pkg"; then
        log_info "Installing $pkg..."
        apt update -y
        if apt install -y "$pkg"; then
            log_success "Installed $pkg"
        else
            log_error "Failed to install $pkg. Continuing without it."
        fi
    else
        log_info "$pkg already installed."
    fi
}

update_package() {
    local pkg="$1"
    if package_installed "$pkg"; then
        log_info "Checking updates for $pkg..."
        apt update -y &>/dev/null
        if apt list --upgradable 2>/dev/null | grep -q "^$pkg/"; then
            log_info "Upgrading $pkg..."
            apt upgrade -y "$pkg" && log_success "Upgraded $pkg"
        else
            log_info "$pkg is up to date."
        fi
    else
        log_warning "$pkg not installed. Skipping update."
    fi
}

ask_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    read -p "$prompt [Y/n]: " choice
    choice=${choice:-$default}
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    [[ "$choice" == "y" || "$choice" == "" ]]
}

user_exists() { id "$1" &>/dev/null; }

check_internet() {
    if ! ping -c 1 -W 3 google.com &>/dev/null; then
        log_error "No internet connection."
        exit 1
    fi
    log_info "Internet OK."
}

check_dir_writable() {
    local dir="$1"
    [ -d "$dir" ] || { log_error "Directory '$dir' does not exist."; exit 1; }
    [ -w "$dir" ] || { log_error "Directory '$dir' is not writable."; exit 1; }
    log_info "Directory '$dir' is writable."
}

print_header() {
    echo ""
    echo -e "${CYAN}====================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}====================================${NC}"
    echo ""
}

print_footer() {
    echo ""
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}  Completed successfully!${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo ""
}