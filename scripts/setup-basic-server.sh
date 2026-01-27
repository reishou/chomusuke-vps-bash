#!/usr/bin/env bash
set -euo pipefail

QUIET_MODE=0
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET_MODE=1
  shift
fi

# === basic-server-setup.sh ===
# Purpose: Perform basic server setup (update, timezone, hostname, swap, timezone, NTP, fail2ban)
# Run on VPS after cloning repo: sudo bash scripts/basic-server-setup.sh
# Based on: https://reishou.gitbook.io/n/vps/getting-started/basic-server-setup

# Load utils (require running from repo root)
if [ ! -f "$(pwd)/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run from the repository root directory."
    echo "cd into chomusuke-vps-bash/ then run:"
    echo "  sudo bash scripts/basic-server-setup.sh"
    exit 1
fi

source "$(pwd)/utils.sh"

print_header "Basic Server Setup"

check_root

log_info "This script automates basic server setup:"
log_info "- Update & upgrade system"
log_info "- Set timezone"
log_info "- Set hostname"
log_info "- Create swap file"
log_info "- Enable NTP time sync"
log_info "- Install Fail2Ban"
echo ""
log_warning "All steps are optional (y/n, default y). You can skip any step."
echo ""

# Step 1: Update & upgrade system
echo ""
if ask_confirm "Do you want to update and upgrade the system now?" "Y"; then
    log_info "Updating package list and upgrading system..."
    apt update -y
    apt upgrade -y
    apt autoremove -y
    log_success "System updated and upgraded."
else
    log_info "System update skipped."
fi

# Step 2: Set timezone
# === Optional: Set timezone with filter ===
echo ""
if ask_confirm "Do you want to set timezone?" "Y"; then
    log_info "Type part of timezone (e.g. 'Asia', 'Ho_Chi', 'Europe') to filter, or Enter to list all."

    while true; do
        read -r -p "Filter timezone: " filter
        if [[ -z "$filter" ]]; then
            mapfile -t timezones < <(timedatectl list-timezones)
        else
            mapfile -t timezones < <(timedatectl list-timezones | grep -i "$filter")
        fi

        if [ ${#timezones[@]} -eq 0 ]; then
            log_warning "No timezone matches '$filter'. Try again."
            continue
        fi

        if [ ${#timezones[@]} -gt 30 ]; then
            log_info "${#timezones[@]} results found. Showing first 30."
            timezones=("${timezones[@]:0:30}")
        fi

        PS3="Select timezone (enter number): "
        select tz in "${timezones[@]}"; do
            if [[ -n "$tz" ]]; then
                timedatectl set-timezone "$tz"
                timedatectl
                log_success "Timezone set to $tz."
                break 2
            else
                echo "Invalid selection."
            fi
        done
    done
else
    log_info "Timezone setup skipped."
fi

# Step 3: Set hostname
echo ""
if ask_confirm "Do you want to set a new hostname?" "Y"; then
    read -r -p "Enter new hostname (e.g. mavuika-server): " NEW_HOSTNAME
    NEW_HOSTNAME="${NEW_HOSTNAME:-mavuika-server}"

    log_info "Setting hostname to $NEW_HOSTNAME..."
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "$NEW_HOSTNAME" > /etc/hostname
    sed -i "s/127.0.1.1 .*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts

    log_success "Hostname set to $NEW_HOSTNAME."
    echo "Reboot recommended to apply changes."
else
    log_info "Hostname setup skipped."
fi

# Step 4: Create swap file
echo ""
if ask_confirm "Do you want to create a swap file (recommended for low RAM VPS)?" "Y"; then
    read -r -p "Enter swap size in GB (default: 2): " SWAP_SIZE
    SWAP_SIZE="${SWAP_SIZE:-2}"

    log_info "Creating ${SWAP_SIZE}GB swap file..."
    fallocate -l "${SWAP_SIZE}G" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Make swap permanent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    log_success "Swap file created and enabled (${SWAP_SIZE}GB)."
    swapon --show
else
    log_info "Swap file creation skipped."
fi

# Step 5: Enable NTP time sync
echo ""
if ask_confirm "Do you want to enable NTP time synchronization?" "Y"; then
    log_info "Installing and enabling chrony (NTP client)..."
    apt update -y
    apt install -y chrony
    systemctl enable chronyd
    systemctl start chronyd
    chronyc tracking
    log_success "NTP time sync enabled."
else
    log_info "NTP setup skipped."
fi

# Step 6: Install Fail2Ban
echo ""
if ask_confirm "Do you want to install Fail2Ban (protect against brute-force attacks)?" "Y"; then
    if command -v fail2ban-client >/dev/null 2>&1; then
        log_info "Fail2Ban already installed. Skipping."
    else
        log_info "Installing Fail2Ban..."
        apt update -y
        apt install -y fail2ban
    fi

    log_info "Fail2Ban installed and running."
    systemctl status fail2ban --no-pager | head -n 5
    log_success "Fail2Ban setup completed."
else
    log_info "Fail2Ban installation skipped."
fi

# Final instructions
if [[ $QUIET_MODE -eq 0 ]]; then
  echo ""
  log_success "Basic Server Setup completed!"
  echo "Next steps:"
  echo "1. Reboot the server if you changed hostname or swap (recommended): sudo reboot"
  echo "2. Continue with other setup scripts in this repo."
  echo "Repo: https://github.com/reishou/chomusuke-vps-bash"

  print_footer
else
  echo ""
fi
