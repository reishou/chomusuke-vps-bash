#!/usr/bin/env bash
set -euo pipefail

QUIET_MODE=0
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET_MODE=1
  shift
fi

# === ssh-setup-basic-security.sh ===
# Purpose: Apply basic SSH security hardening + optional UFW, Fail2Ban, Unattended Upgrades
# Run on VPS after cloning repo: sudo bash scripts/ssh-setup-basic-security.sh
# Based on: https://reishou.gitbook.io/n/vps/getting-started/essential-initial-security-hardening

# Load utils
if [ ! -f "$(dirname "$0")/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m utils.sh not found in the scripts/ directory.."
    echo "Expected path: $(dirname "$0")/utils.sh"
    echo "Please check if the file exists in your repository."
    exit 1
fi

source "$(dirname "$0")/utils.sh"

print_header "SSH Basic Security Hardening & Additional Security Tools"

check_root

log_info "This script helps secure your VPS by:"
log_info "- Disabling password login (key-only authentication)"
log_info "- Optional: Setup UFW, Fail2Ban, Unattended Upgrades"

log_warning "WARNING: Disabling password login will disconnect your current session if you are using password!"
log_warning "Make sure your SSH public key is already added to ~/.ssh/authorized_keys of the user you are using."
echo ""

# Confirm overall execution
if ! ask_confirm "Do you want to proceed with SSH hardening?" "Y"; then
    log_info "Cancelled. No changes made."
    print_footer
    exit 0
fi

# Step 1: Disable password login (key-only)
echo ""
nopasswd_login_choice=""
if ask_confirm "Do you want to disable password login (allow key-only authentication)?" "Y"; then
    log_info "Disabling password authentication..."
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # Restart SSH service
    if systemctl is-active ssh >/dev/null 2>&1; then
        systemctl restart ssh
    elif systemctl is-active sshd >/dev/null 2>&1; then
        systemctl restart sshd
    else
        log_error "Could not restart SSH service. Restart manually after this script."
    fi

    nopasswd_login_choice="y"
    log_success "Password login disabled. Key-only authentication enabled."
    log_warning "Test new SSH connection before closing this session!"
else
    nopasswd_login_choice="n"
    log_info "Password login remains enabled."
fi

# Step 2: Optional - Setup UFW
echo ""
if ask_confirm "Do you want to setup UFW (Uncomplicated Firewall) now?" "Y"; then
    if command -v ufw >/dev/null 2>&1; then
        log_info "UFW already installed. Skipping installation."
    else
        log_info "Installing UFW..."
        apt update -y
        apt install -y ufw
    fi

    log_info "Configuring UFW..."
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
    ufw --force enable
    ufw status

    log_success "UFW enabled with OpenSSH & Nginx allowed."
else
    log_info "UFW setup skipped."
fi

# Step 3: Optional - Install Fail2Ban
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

    # ────────────────────────────────────────────────
    # Configure Fail2Ban with custom SSH port
    # ────────────────────────────────────────────────
    echo -e "${GREEN}Configuring Fail2Ban for custom SSH port...${NC}"

    # Default SSH port from previous steps or fallback
    DEFAULT_SSH_PORT=2204

    # Prompt user for SSH port (interactive mode)
    read -r -p "Enter custom SSH port (default $DEFAULT_SSH_PORT): " SSH_PORT
    SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}

    # Validate port (basic check: number between 1024-65535)
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
        echo -e "${RED}Invalid port: $SSH_PORT. Using default $DEFAULT_SSH_PORT.${NC}"
        SSH_PORT=$DEFAULT_SSH_PORT
    fi

    # Path to template and target
    TEMPLATE_FILE="./config/fail2ban/jail.local"
    TARGET_FILE="/etc/fail2ban/jail.local"

    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo -e "${RED}Template file not found: $TEMPLATE_FILE${NC}"
        echo -e "${YELLOW}Skipping Fail2Ban custom config.${NC}"
    else
        # Copy template to temp file for editing
        cp "$TEMPLATE_FILE" /tmp/jail.local.tmp

        # Replace port in [sshd] section
        # Use sed to find line 'port = ...' under [sshd] and update
        sed -i "/^\[sshd\]/,/^\[/ s/^port\s*=.*/port = $SSH_PORT/" /tmp/jail.local.tmp

        # Also update any comment like '# port = ssh' if exists
        sed -i "s/#\s*port\s*=.*/# port = $SSH_PORT # Updated by setup script/" /tmp/jail.local.tmp

        # Copy to system location with proper permissions
        cp /tmp/jail.local.tmp "$TARGET_FILE"
        chown root:root "$TARGET_FILE"
        chmod 644 "$TARGET_FILE"
        rm -f /tmp/jail.local.tmp

        echo -e "${GREEN}Fail2Ban jail.local updated with SSH port: $SSH_PORT${NC}"

        # Restart Fail2Ban to apply changes
        if systemctl is-active --quiet fail2ban; then
            systemctl restart fail2ban
            echo -e "${GREEN}Fail2Ban restarted successfully.${NC}"
        else
            echo -e "${YELLOW}Fail2Ban not active yet. Will apply on next start.${NC}"
        fi
    fi

    echo ""

    systemctl status fail2ban --no-pager | head -n 5
    log_success "Fail2Ban setup completed."
else
    log_info "Fail2Ban installation skipped."
fi

# Step 4: Optional - Enable Unattended Upgrades
echo ""
if ask_confirm "Do you want to enable Unattended Upgrades (automatic security updates)?" "Y"; then
    log_info "Installing and configuring Unattended Upgrades..."
    apt update -y
    apt install -y unattended-upgrades

    dpkg-reconfigure --priority=low unattended-upgrades

    log_info "Unattended Upgrades enabled (auto security updates)."
    log_success "Unattended Upgrades setup completed."
else
    log_info "Unattended Upgrades skipped."
fi

# === Final summary ===
if [[ $QUIET_MODE -eq 0 ]]; then
  echo ""
  log_success "SSH & Basic Security Hardening completed!"
  echo "Password login disabled: $([[ "$nopasswd_login_choice" != "n" ]] && echo "Yes" || echo "No")"
  echo ""
  echo "Next steps:"
  echo "1. Test new SSH connection (especially if disabled password login)."
  echo "2. Continue with other setup scripts in this repo."
  echo "Repo: https://github.com/reishou/chomusuke-vps-bash"

  print_footer
else
  echo ""
fi
