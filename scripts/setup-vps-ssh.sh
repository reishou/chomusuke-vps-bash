#!/usr/bin/env bash
# setup-vps-ssh.sh
# Script to generate SSH key pair for VPS user and display public key
# - Allows custom key name
# - Optionally creates GitHub-specific entry in ~/.ssh/config for custom keys
# - Uses ./utils.sh for logging and ask_confirm

set -euo pipefail

# Source utility functions
if [ -f "$(dirname "$0")/utils.sh" ]; then
    source "$(dirname "$0")/utils.sh"
else
    echo "Error: util.sh not found in ./ or ./scripts/" >&2
    exit 1
fi

echo -e "${GREEN}=== VPS SSH Key Setup Script ===${NC}"
echo "This script generates an SSH key pair (ed25519) for your VPS user"
echo "and displays the public key so you can add it to GitHub."
echo ""

# ────────────────────────────────────────────────
# Get real user's home (handles sudo correctly)
# ────────────────────────────────────────────────
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(eval echo ~"$SUDO_USER")
else
    REAL_HOME="$HOME"
fi

SSH_DIR="$REAL_HOME/.ssh"

# ────────────────────────────────────────────────
# Step 1: Ask for custom key name
# ────────────────────────────────────────────────
default_key_name="id_ed25519"
read -r -p "Enter SSH key name (filename without extension, default: $default_key_name): " key_name
key_name=${key_name:-$default_key_name}

# Basic validation
if [[ "$key_name" =~ [[:space:]/\\*?\"\'\`] ]] || [ -z "$key_name" ]; then
    log_error "Invalid key name (cannot contain spaces, /, \\, *, ?, \", ', \`)."
fi

PRIVATE_KEY="$SSH_DIR/$key_name"
PUBLIC_KEY="$SSH_DIR/$key_name.pub"

# ────────────────────────────────────────────────
# Function to generate new key
# ────────────────────────────────────────────────
generate_new_key() {
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    if ask_confirm "Do you want to set a passphrase for the key? (recommended for extra security)" "N"; then
        read -r -s -p "Enter passphrase: " passphrase
        echo ""
        read -r -s -p "Confirm passphrase: " passphrase_confirm
        echo ""

        if [ "$passphrase" != "$passphrase_confirm" ]; then
            log_error "Passphrases do not match. Aborted."
        fi

        ssh-keygen -t ed25519 -C "$(whoami)@$(hostname) - $(date +%Y-%m-%d)" \
            -f "$PRIVATE_KEY" -N "$passphrase" || log_error "SSH key generation failed."
    else
        ssh-keygen -t ed25519 -C "$(whoami)@$(hostname) - $(date +%Y-%m-%d)" \
            -f "$PRIVATE_KEY" -N "" || log_error "SSH key generation failed."
    fi

    chmod 600 "$PRIVATE_KEY"
    chmod 644 "$PUBLIC_KEY"

    log_success "New SSH key pair generated:"
    log_info "Private key: $PRIVATE_KEY"
    log_info "Public key:  $PUBLIC_KEY"
}

# ────────────────────────────────────────────────
# Step 2: Check if key already exists
# ────────────────────────────────────────────────
if [ -f "$PRIVATE_KEY" ] && [ -f "$PUBLIC_KEY" ]; then
    log_info "SSH key pair already exists:"
    log_info "Private key: $PRIVATE_KEY"
    log_info "Public key:  $PUBLIC_KEY"

    if ask_confirm "Do you want to generate a new key pair (old key will be overwritten)?" "N"; then
        log_info "Keeping existing keys."
    else
        log_info "Generating new SSH key pair..."
        generate_new_key
    fi
else
    log_info "No SSH key found with name '$key_name'."
    if ask_confirm "Do you want to generate a new SSH key pair now?" "Y"; then
        generate_new_key
    else
        log_info "Skipping SSH key generation."
        exit 0
    fi
fi

# ────────────────────────────────────────────────
# Step 3: Optional - Create GitHub config entry for custom key
# ────────────────────────────────────────────────
CONFIG_FILE="$SSH_DIR/config"

if [ "$key_name" != "$default_key_name" ]; then
    log_info "Custom key name detected: $key_name"
    if ask_confirm "Do you want to create a GitHub-specific entry in ~/.ssh/config (recommended for custom keys)?" "Y"; then
        # Backup config if exists
        [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"

        # Check if Host github.com already exists
        if grep -q "^Host github.com" "$CONFIG_FILE" 2>/dev/null; then
            log_info "Host github.com already exists in config. Appending IdentityFile only."
            # shellcheck disable=SC2129
            echo "" >> "$CONFIG_FILE"
            echo "# Added for custom key $key_name" >> "$CONFIG_FILE"
            echo "Host github.com" >> "$CONFIG_FILE"
            echo "    IdentityFile $PRIVATE_KEY" >> "$CONFIG_FILE"
        else
            # Create full entry
            # shellcheck disable=SC2129
            echo "" >> "$CONFIG_FILE"
            echo "# GitHub entry for custom key $key_name" >> "$CONFIG_FILE"
            echo "Host github.com" >> "$CONFIG_FILE"
            echo "    HostName github.com" >> "$CONFIG_FILE"
            echo "    User git" >> "$CONFIG_FILE"
            echo "    IdentityFile $PRIVATE_KEY" >> "$CONFIG_FILE"
        fi

        chmod 600 "$CONFIG_FILE"
        log_success "GitHub config entry added to $CONFIG_FILE"
        log_info "You can now use git clone git@github.com:user/repo.git without -i flag."
    else
        log_info "Skipping GitHub config entry."
    fi
fi

# ────────────────────────────────────────────────
# Step 4: Display public key for copy
# ────────────────────────────────────────────────
if [ -f "$PUBLIC_KEY" ]; then
    echo ""
    log_success "Your public key (ready to copy):"
    echo -e "${YELLOW}----------------------------------------------------------------${NC}"
    cat "$PUBLIC_KEY"
    echo -e "${YELLOW}----------------------------------------------------------------${NC}"
    echo ""
    log_info "Copy the line above and add it to:"
    log_info "  GitHub → Settings → SSH and GPG keys → New SSH key"
    log_info "  Title suggestion: VPS-$(hostname) - $key_name - $(date +%Y-%m-%d)"
    echo ""
    log_success "Done! You can now use git clone with SSH."
else
    log_error "Public key not found. Generation may have failed."
fi

echo ""
log_success "SSH setup completed."
echo "Run 'ssh -T git@github.com' to test authentication after adding the key."