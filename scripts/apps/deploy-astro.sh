#!/usr/bin/env bash
# deploy-astro.sh
# Auto deploy script for Astro static sites
# - Runs as normal user where possible
# - Uses sudo only for system-level operations
# - Uses ./scripts/utils.sh

set -euo pipefail

# Source utils
if [ -f "./scripts/utils.sh" ]; then
    source "./scripts/utils.sh"
else
    echo -e "\033[0;31m[ERROR]\033[0m utils.sh not found in ./scripts/"
    exit 1
fi

REPO_ROOT="$(pwd)"

echo -e "${GREEN}=== Astro Auto Deploy Script ===${NC}"
echo "This script runs as your current user for git/npm, and uses sudo only when needed."
echo "Do NOT run with sudo unless prompted."
echo ""

# ────────────────────────────────────────────────
# Step 1: Check and install Nginx (needs sudo)
# ────────────────────────────────────────────────
if ! command -v nginx >/dev/null 2>&1; then
    log_info "Nginx is not installed (this requires sudo)."
    if ask_confirm "Do you want to install Nginx now? (requires sudo)" "Y"; then
        sudo apt update -y
        sudo apt install -y nginx
        sudo systemctl enable nginx
        sudo systemctl start nginx
        log_success "Nginx installed and started."
    else
        log_error "Nginx is required. Script aborted."
    fi
else
    log_success "Nginx is already installed."
fi

# ────────────────────────────────────────────────
# Step 1.5: Check and install pnpm + rsync (if missing)
# ────────────────────────────────────────────────
log_info "Checking required tools: pnpm and rsync..."

# Check rsync
if ! command -v rsync >/dev/null 2>&1; then
    log_info "rsync is not installed."
    if ask_confirm "Do you want to install rsync now? (requires sudo)" "Y"; then
        sudo apt update -y
        sudo apt install -y rsync
        log_success "rsync installed."
    else
        log_error "rsync is required for syncing build output to /var/www. Script aborted."
    fi
else
    log_success "rsync is already installed."
fi

# Check pnpm
if ! command -v pnpm >/dev/null 2>&1; then
    log_info "pnpm is not installed."
    if ask_confirm "Do you want to install pnpm now? (global install via corepack)" "Y"; then
        # Use corepack (recommended way since Node.js 16.9+)
        if ! command -v corepack >/dev/null 2>&1; then
            log_info "corepack not found. Enabling it..."
            sudo corepack enable || log_error "Failed to enable corepack. Try manual install."
        fi

        # Enable and install latest pnpm
        corepack prepare pnpm@latest --activate
        log_success "pnpm installed and activated via corepack."
    else
        log_error "pnpm is required for Astro dependency management. Script aborted."
        exit 1
    fi
else
    log_success "pnpm is already installed (version: $(pnpm --version))."
fi

echo ""  # empty line for readability

# ────────────────────────────────────────────────
# Step 2: Git repository URL (runs as normal user)
# ────────────────────────────────────────────────
read -r -p "Enter the Git repository URL (e.g., https://github.com/user/my-astro-site.git or git@github.com:user/repo.git): " git_url
git_url=$(echo "$git_url" | xargs)
[ -z "$git_url" ] && log_error "Git URL cannot be empty."

log_info "Verifying repository accessibility..."
if ! git ls-remote --exit-code --heads "$git_url" >/dev/null 2>&1; then
    log_error "Cannot access repository. Possible causes:
  - Private repo → ensure SSH key is added to GitHub (run setup-vps-ssh.sh)
  - Typo in URL
  - HTTPS private repo needs token
  - Network issue"
  exit 1
fi
log_success "Repository accessible."

# ────────────────────────────────────────────────
# Step 3: Folder name & clone (normal user)
# ────────────────────────────────────────────────
default_folder=$(basename "$git_url" .git)
read -r -p "Enter folder name to clone into (default: $default_folder): " folder_name
folder_name=${folder_name:-$default_folder}

if [[ "$folder_name" =~ [/\\*] ]] || [ -z "$folder_name" ]; then
    log_error "Invalid folder name."
    exit 1
fi

if [ -d "$folder_name" ]; then
    if ask_confirm "Folder $folder_name exists. Delete and re-clone?" "N"; then
        rm -rf "$folder_name"
    else
        log_error "Aborted."
    fi
fi

log_info "Cloning repository..."
git clone "$git_url" "$HOME/$folder_name"

cd "$HOME/$folder_name" || log_error "Cannot cd into folder."

# ────────────────────────────────────────────────
# Step 4: Build (normal user)
# ────────────────────────────────────────────────
log_info "Installing dependencies..."
pnpm install --production || log_error "pnpm install failed."

log_info "Building Astro site..."
pnpm run build || log_error "Build failed."

# ────────────────────────────────────────────────
# Step 4: Domain
# ────────────────────────────────────────────────
domain=$(ask_domain)

# ────────────────────────────────────────────────
# Step 5: Root path & sync to /var/www
# ────────────────────────────────────────────────
root_path=$(setup_web_root "$(pwd)" "$folder_name" "$(pwd)/dist")

# ────────────────────────────────────────────────
# Step 6: SSL handling
# ────────────────────────────────────────────────
setup_ssl

# ────────────────────────────────────────────────
# Step 7: Apply Nginx config
# ────────────────────────────────────────────────
apply_nginx_config "$REPO_ROOT/config/nginx/astro.conf.example" "$domain" "$root_path" "$folder_name"

# ────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────
echo ""
log_success "Astro deployment completed!"
echo -e "Site available at: http://$domain (https if SSL set up)"
echo "Site directory: $(pwd)"
echo "Nginx root: $root_path"
echo "Nginx config: $NGINX_CONF"
echo ""
echo "Thank you for using the script!"
