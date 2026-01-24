#!/usr/bin/env bash
set -euo pipefail

# Load common utils
source "$(dirname "$0")/common/utils.sh"

print_header "Create Non-Root User"

check_root

log_info "This script creates a new non-root user with sudo privileges."

# === Ask for new username ===
read -p "Enter new non-root username (default: vps-user): " input_user
NEW_USER="${input_user:-vps-user}"

# === Check if user already exists ===
if user_exists "$NEW_USER"; then
    log_info "User '$NEW_USER' already exists. Skipping creation."
    print_footer
    exit 0
fi

# === Create the user ===
log_info "Creating new non-root user: $NEW_USER"
adduser --gecos "" --disabled-password "$NEW_USER"

echo ""
echo "Enter password for user $NEW_USER (input will be hidden):"
passwd "$NEW_USER"

# === Add to sudo group ===
usermod -aG sudo "$NEW_USER"
log_success "User '$NEW_USER' added to sudo group."

# === Ask for NOPASSWD sudo ===
echo ""
if ask_confirm "Do you want $NEW_USER to run sudo without password?" "Y"; then
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/$NEW_USER >/dev/null
    chmod 0440 /etc/sudoers.d/$NEW_USER
    log_success "NOPASSWD enabled for $NEW_USER (convenient but less secure)."
else
    log_info "NOPASSWD skipped. User will need to enter password for sudo."
fi

# === Final summary ===
echo ""
log_success "User creation completed!"
echo "Username: $NEW_USER"
echo "Sudo: Yes"
echo "NOPASSWD: $(if ask_confirm "" "Y" >/dev/null; then echo "Yes"; else echo "No"; fi)"  # Lấy lại giá trị trước đó
echo ""
echo "You can now login as this user:"
echo "  ssh $NEW_USER@your-vps-ip"

print_footer
