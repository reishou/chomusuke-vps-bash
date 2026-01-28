#!/usr/bin/env bash
# setup-vps-ssh.sh
# Script to generate SSH key pair for VPS user and display public key
# - Allows user to input custom key name (filename without extension)
# - Checks for existing key
# - Generates ed25519 key if needed
# - Shows public key for easy copy to GitHub
# - Uses ./utils.sh for logging and ask_confirm

set -euo pipefail

# Source utility functions
if [ -f "./utils.sh" ]; then
    source "./utils.sh"
else
    log_error "utils.sh not found in current directory."
fi

echo -e "${GREEN}=== VPS SSH Key Setup Script ===${NC}"
echo "This script generates an SSH key pair (ed25519) for your VPS user"
echo "and displays the public key so you can add it to GitHub."
echo ""

# ────────────────────────────────────────────────
# Default paths (standard for non-root user)
# ────────────────────────────────────────────────
SSH_DIR="$HOME/.ssh"

# ────────────────────────────────────────────────
# Step 1: Ask for custom key name
# ────────────────────────────────────────────────
default_key_name="id_ed25519"
read -p "Enter SSH key name (filename without extension, default: $default_key_name): " key_name
key_name=${key_name:-$default_key_name}

# Basic validation: no spaces, no special chars that break filenames
if [[ "$key_name" =~ [[:space:]/\\*?\"\'\`] ]] || [ -z "$key_name" ]; then
    log_error "Invalid key name (cannot contain spaces, /, \\, *, ?, \", ', \`)."
fi

PRIVATE_KEY="$SSH_DIR/$key_name"
PUBLIC_KEY="$SSH_DIR/$key_name.pub"

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
# Function to generate new key
# ────────────────────────────────────────────────
generate_new_key() {
    # Create .ssh directory if not exists
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # Ask if user wants a passphrase
    if ask_confirm "Do you want to set a passphrase for the key? (recommended for extra security)" "N"; then
        read -s -p "Enter passphrase: " passphrase
        echo ""
        read -s -p "Confirm passphrase: " passphrase_confirm
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
# Step 3: Display public key for copy
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
