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
git clone "$git_url" "$folder_name"

cd "$folder_name" || log_error "Cannot cd into folder."

# ────────────────────────────────────────────────
# Step 4: Build (normal user)
# ────────────────────────────────────────────────
log_info "Installing dependencies..."
npm install --production || log_error "npm install failed."

log_info "Building Astro site..."
npm run build || log_error "Build failed."

# ────────────────────────────────────────────────
# Step 5: Domain (normal user)
# ────────────────────────────────────────────────
read -r -p "Enter domain (e.g., example.com): " domain
[ -z "$domain" ] || ! [[ "$domain" =~ \.[a-z]{2,}$ ]] && log_error "Invalid domain."

# ────────────────────────────────────────────────
# Step 6: Root path & rsync to /var/www (needs sudo for chown)
# ────────────────────────────────────────────────
default_root="$(pwd)/dist"
read -r -p "Nginx root path (default: $default_root): " root_path
root_path=${root_path:-$default_root}

[ ! -d "$root_path" ] && log_error "Root path does not exist: $root_path"

var_www_path="/var/www/$folder_name"
sudo mkdir -p "$var_www_path"
sudo rsync -a --delete "$root_path/" "$var_www_path/"
sudo chown -R www-data:www-data "$var_www_path"
log_success "Synced to $var_www_path with correct permissions"

root_path="$var_www_path"

# ────────────────────────────────────────────────
# Step 7: SSL (Certbot needs sudo, manual files don't)
# ────────────────────────────────────────────────
ssl_key_path=""
ssl_cert_path=""

if ask_confirm "Do you have existing SSL key/cert files?" "Y"; then
    read -r -p "Private key path: " ssl_key_path
    read -r -p "Full cert path: " ssl_cert_path

    if [ ! -f "$ssl_key_path" ] || [ ! -f "$ssl_cert_path" ]; then
        log_info "Files not found. Skipping manual SSL."
        ssl_key_path=""
        ssl_cert_path=""
    fi
fi

if [ -z "$ssl_key_path" ] && [ -z "$ssl_cert_path" ]; then
    if ask_confirm "Use Certbot for free SSL?" "Y"; then
        if ! command -v certbot >/dev/null; then
            log_info "Installing Certbot (requires sudo)..."
            sudo apt update -y
            sudo apt install -y certbot python3-certbot-nginx
        fi
        sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email "admin@$domain" || {
            log_info "Certbot failed. Skipping SSL."
        }
    else
        log_info "Skipping SSL. Site will be HTTP only."
    fi
fi

# ────────────────────────────────────────────────
# Step 8: Nginx config (needs sudo)
# ────────────────────────────────────────────────
TEMPLATE_PATH="./config/astro.conf.example"
NGINX_CONF="/etc/nginx/sites-available/$domain"

[ ! -f "$TEMPLATE_PATH" ] && log_error "Template not found."

sudo cp "$TEMPLATE_PATH" "$NGINX_CONF"
sudo sed -i "s|{DOMAIN}|$domain|g" "$NGINX_CONF"
sudo sed -i "s|{ROOT_PATH}|$root_path|g" "$NGINX_CONF"
sudo sed -i "s|{FOLDER_NAME}|$folder_name|g" "$NGINX_CONF"

# SSL manual (if provided)
if [ -n "$ssl_key_path" ] && [ -n "$ssl_cert_path" ]; then
    sudo sed -i "s|# listen 443 ssl http2;|listen 443 ssl http2;|g" "$NGINX_CONF"
    sudo sed -i "s|# listen [::]:443 ssl http2;|listen [::]:443 ssl http2;|g" "$NGINX_CONF"
    sudo sed -i "s|{SSL_CERT_PATH}|$ssl_cert_path|g" "$NGINX_CONF"
    sudo sed -i "s|{SSL_KEY_PATH}|$ssl_key_path|g" "$NGINX_CONF"
    sudo sed -i "s|# return 301 https://\$host\$request_uri;|return 301 https://\$host\$request_uri;|g" "$NGINX_CONF"
fi

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

if sudo nginx -t; then
    sudo systemctl reload nginx
    log_success "Nginx config applied."
else
    log_error "Nginx test failed. Check $NGINX_CONF"
fi

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
