#!/usr/bin/env bash
set -euo pipefail

# === setup-ssh-vps.sh ===
# Purpose: Generate SSH key, create config alias, copy key to VPS (all optional)
# Run from local: ssh root@YOUR_VPS_IP "bash -s" < setup-ssh-vps.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SSH VPS Setup Tool ===${NC}"
echo "This script helps you:"
echo "1. Generate a new SSH key (optional)"
echo "2. Create a new SSH config alias for your VPS (optional)"
echo "3. Copy the public key to the VPS (optional)"
echo "All steps are optional (y/n, default y)."
echo ""

# Step 1: Generate new SSH key?
read -r -p "Do you want to generate a new SSH key? [Y/n]: " gen_key_choice
gen_key_choice=${gen_key_choice:-Y}
gen_key_choice=$(echo "$gen_key_choice" | tr '[:upper:]' '[:lower:]')

if [[ "$gen_key_choice" == "y" || "$gen_key_choice" == "" ]]; then
    read -r -p "Enter key filename (default: id_ed25519_vps): " KEY_NAME_INPUT
    KEY_NAME="${KEY_NAME_INPUT:-id_ed25519_vps}"
    KEY_PATH="$HOME/.ssh/$KEY_NAME"

    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "vps-$(date +%Y%m%d)"

    PRI_KEY="$KEY_PATH"
    PUB_KEY="$KEY_PATH.pub"

    chmod 600 "$PRI_KEY"
    chmod 644 "$PUB_KEY"

    echo -e "${GREEN}New SSH key created:${NC}"
    echo "  Private key: $PRI_KEY"
    echo "  Public key:  $PUB_KEY"
else
    read -r -p "Enter path to existing private key (e.g. ~/.ssh/id_ed25519): " PRI_KEY
    PRI_KEY="${PRI_KEY:-$HOME/.ssh/id_ed25519}"
    PUB_KEY="${PRI_KEY}.pub"

    if [ ! -f "$PRI_KEY" ] || [ ! -f "$PUB_KEY" ]; then
        echo -e "${RED}Error: Key files not found: $PRI_KEY or $PUB_KEY${NC}"
        exit 1
    fi

    echo "Using existing key:"
    echo "  Private key: $PRI_KEY"
    echo "  Public key:  $PUB_KEY"
fi

# Step 2: Create new SSH config alias?
read -r -p "Do you want to create a new SSH config alias for this VPS? [Y/n]: " config_choice
config_choice=${config_choice:-Y}
config_choice=$(echo "$config_choice" | tr '[:upper:]' '[:lower:]')

if [[ "$config_choice" == "y" || "$config_choice" == "" ]]; then
    read -r -p "Enter alias name (short name for SSH, e.g. mavuika): " ALIAS
    ALIAS="${ALIAS:-vps}"

    read -r -p "Enter VPS hostname/IP: " HOSTNAME
    read -r -p "Enter username on VPS (default: vps-user): " USER
    USER="${USER:-vps-user}"
    read -r -p "Enter SSH port (default: 22): " PORT
    PORT="${PORT:-22}"

    CONFIG_DIR="$HOME/.ssh/config.d"
    mkdir -p "$CONFIG_DIR"
    CONFIG_FILE="$CONFIG_DIR/$ALIAS.conf"

    cat > "$CONFIG_FILE" << EOF
Host $ALIAS
    HostName $HOSTNAME
    User $USER
    Port $PORT
    IdentityFile ~/.ssh/$KEY_NAME
    IdentitiesOnly yes
EOF

    chmod 600 "$CONFIG_FILE"

    MAIN_CONFIG="$HOME/.ssh/config"
    if [ ! -f "$MAIN_CONFIG" ] || ! grep -q "Include ~/.ssh/config.d/*.conf" "$MAIN_CONFIG" 2>/dev/null; then
        # shellcheck disable=SC2129
        echo "" >> "$MAIN_CONFIG"
        echo "# Include custom configs from config.d" >> "$MAIN_CONFIG"
        echo "Include ~/.ssh/config.d/*.conf" >> "$MAIN_CONFIG"
        chmod 600 "$MAIN_CONFIG"
    fi

    echo -e "${GREEN}SSH config created:${NC} $CONFIG_FILE"
    echo "You can now SSH using: ssh $ALIAS"
else
    read -r -p "Enter path to existing SSH config file (or press Enter to skip): " CONFIG_FILE
    CONFIG_FILE="${CONFIG_FILE:-}"
    if [ -n "$CONFIG_FILE" ]; then
        echo "Using existing config: $CONFIG_FILE"
    else
        echo "Skipping SSH config creation."
    fi
fi

# Step 3: Copy public key to VPS?
read -r -p "Do you want to copy the public key to the VPS now? [Y/n]: " copy_choice
copy_choice=${copy_choice:-Y}
copy_choice=$(echo "$copy_choice" | tr '[:upper:]' '[:lower:]')

if [[ "$copy_choice" == "y" || "$copy_choice" == "" ]]; then
    if [ -n "${ALIAS:-}" ]; then
        HOST_TO_USE="$ALIAS"
    else
        read -r -p "Enter VPS user@hostname:port (e.g. vps-user@123.45.67.89:22): " HOST_TO_USE
    fi

    echo "Copying public key to VPS..."

    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -i "$PUB_KEY" "$HOST_TO_USE" && \
            echo -e "${GREEN}Public key copied successfully using ssh-copy-id!${NC}"
    else
        echo -e "${YELLOW}ssh-copy-id not found. Using automatic SSH method (enter password once).${NC}"
        echo ""
        echo "Enter password for $HOST_TO_USE when prompted:"
        echo ""

        ssh "$HOST_TO_USE" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$(cat "$PUB_KEY")' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" && \
            echo -e "${GREEN}Public key copied successfully using SSH!${NC}" || \
            echo -e "${RED}Failed to copy key. Manual copy:${NC}" && \
            echo "  cat $PUB_KEY | ssh $HOST_TO_USE \"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys\""
    fi
else
    echo "Skipping key copy."
    echo "Manual copy later:"
    echo "  cat $PUB_KEY | ssh user@ip \"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys\""
fi

echo ""
echo -e "${GREEN}=== SSH VPS Setup completed! ===${NC}"
echo "Test your connection:"
if [ -n "${ALIAS:-}" ]; then
    echo "  ssh $ALIAS"
else
    echo "  ssh -i $PRIV_KEY $USER@$HOSTNAME -p $PORT"
fi
echo ""
echo "Thank you for using Chomusuke Deploy Tools!"
