#!/usr/bin/env bash
set -euo pipefail

# === create-non-root-user.sh ===
# Purpose: Create a new non-root user with sudo privileges
# This script is independent and can be run anytime

# Load utils (require running from repo root to find utils.sh)
if [ ! -f "$(pwd)/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run from the repository root directory."
    echo "Please cd into chomusuke-vps-bash/ then run:"
    echo "  sudo bash scripts/create-non-root-user.sh"
    exit 1
fi

source "$(pwd)/utils.sh"

print_header "Create Non-Root User"

# Require root privileges
check_root

log_info "This script creates a new non-root user with sudo privileges."

# === Ask for new username ===
read -r -p "Enter new non-root username (default: vps-user): " input_user
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
nopasswd_choice=""
if ask_confirm "Do you want $NEW_USER to run sudo without password?" "Y"; then
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/$NEW_USER >/dev/null
    chmod 0440 /etc/sudoers.d/$NEW_USER
    nopasswd_choice="y"
    log_success "NOPASSWD enabled for $NEW_USER (convenient but less secure)."
else
    nopasswd_choice="n"
    log_info "NOPASSWD skipped. User will need to enter password for sudo."
fi

# === Final summary ===
echo ""
log_success "User creation completed!"
echo "Username: $NEW_USER"
echo "Sudo: Yes"
echo "NOPASSWD: $([[ "$nopasswd_choice" != "n" ]] && echo "Yes" || echo "No")"
echo ""
echo "You can now login as this user:"
echo "  ssh $NEW_USER@your-vps-ip"

print_footer
