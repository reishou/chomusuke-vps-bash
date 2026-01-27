#!/usr/bin/env bash
set -euo pipefail

# === change-ssh-port.sh ===
# Purpose: Change SSH port on VPS (run directly on VPS after cloning repo)
# Run with: sudo bash scripts/change-ssh-port.sh

# Load utils
if [ ! -f "$(dirname "$0")/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m utils.sh not found in the scripts/ directory.."
    echo "Expected path: $(dirname "$0")/utils.sh"
    echo "Please check if the file exists in your repository."
    exit 1
fi

source "$(dirname "$0")/utils.sh"

print_header "Change SSH Port on VPS"

# Require root privileges
check_root

log_info "This script changes the SSH port for better security."
log_warning "WARNING: Changing SSH port will disconnect your current SSH session!"
echo "Make sure you have another way to access the VPS (console, rescue mode, or new port)."
echo ""

# Ask for new port
read -r -p "Enter new SSH port (recommended: 2222, 2233, 2244, etc.): " NEW_PORT
NEW_PORT="${NEW_PORT:-2204}"

if [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    log_error "Invalid port number. Must be between 1024 and 65535."
fi

# Confirm change
echo -e "${YELLOW}You are about to change SSH port from current (likely 22) to $NEW_PORT.${NC}"
echo "This will restart SSH service and disconnect your current session."
read -r -p "Are you sure you want to continue? [y/N]: " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

if [[ "$confirm" != "y" ]]; then
    log_info "Port change cancelled."
    print_footer
    exit 0
fi

# Change port in sshd_config
log_info "Updating SSH port to $NEW_PORT..."
sed -i "s/^#*Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config

# Restart SSH service (support both ssh and sshd)
if systemctl is-active ssh >/dev/null 2>&1; then
    systemctl restart ssh
elif systemctl is-active sshd >/dev/null 2>&1; then
    systemctl restart sshd
else
    log_error "Could not find SSH service to restart. Please restart manually."
fi

log_success "SSH port changed to $NEW_PORT!"

# Check and open new port in UFW if enabled
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    log_info "UFW is active. Opening new SSH port $NEW_PORT..."
    ufw allow "$NEW_PORT"/tcp
    ufw reload
    log_success "UFW updated: Port $NEW_PORT opened."
else
    log_info "UFW not active or not installed. Remember to open port $NEW_PORT manually if you have firewall."
fi

# Final instructions
echo ""
log_success "Change completed!"
echo "Reconnect using the new port:"
echo "  ssh -p $NEW_PORT your-user@your-vps-ip"
echo ""
echo "If you have SSH config alias, update Port in ~/.ssh/config.d/..."
echo "Test connection before closing current session!"

print_footer
