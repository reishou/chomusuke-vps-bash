#!/usr/bin/env bash
# deploy-astro.sh
# Auto deploy script for Astro static sites
# - Clones repo, builds site, configures Nginx
# - Handles optional SSL (manual files or Certbot)
# - Uses ./scripts/utils.sh for logging and ask_confirm

set -euo pipefail

# Source utility functions (must exist in repo)
if [ -f "./scripts/utils.sh" ]; then
    source "./scripts/utils.sh"
else
    echo -e "\033[0;31m[ERROR]\033[0m utils.sh not found in ./scripts/"
    exit 1
fi

echo -e "${GREEN}=== Astro Auto Deploy Script ===${NC}"
echo "This script will clone your Astro repo, build the static site,"
echo "configure Nginx, and optionally set up SSL."
echo ""

# ────────────────────────────────────────────────
# Step 1: Check and install Nginx if missing
# ────────────────────────────────────────────────
if ! command -v nginx >/dev/null 2>&1; then
    log_info "Nginx is not installed."
    if ask_confirm "Do you want to install Nginx now?" "Y"; then
        log_info "Updating package list and installing Nginx..."
        apt update -y
        apt install -y nginx
        systemctl enable nginx
        systemctl start nginx
        log_success "Nginx installed and started."
    else
        log_error "Nginx is required to serve the Astro site. Script aborted."
    fi
else
    log_success "Nginx is already installed."
fi

# ────────────────────────────────────────────────
# Step 2: Git repository URL
# ────────────────────────────────────────────────
read -r -p "Enter the Git repository URL (e.g., https://github.com/user/my-astro-site.git): " git_url
[ -z "$git_url" ] && log_error "Git URL cannot be empty."

# Basic URL validation
if ! [[ "$git_url" =~ [](https://|git://|git@[a-zA-Z0-9.-]+:)[a-zA-Z0-9./_-]+$ ]]; then
    log_error "Invalid Git URL. Must be a valid HTTPS, git:// or SSH URL (e.g., git@github.com:user/repo.git)."
    exit 1
fi

# Extract default folder name from repo URL
default_folder=$(basename "$git_url" .git)

# Ask for folder name with default
if ask_confirm "Enter folder name to clone into (default: $default_folder)" "Y"; then
    read -r -p "Folder name: " folder_name
    folder_name=${folder_name:-$default_folder}
else
    folder_name=$default_folder
fi

if [[ "$folder_name" =~ [/\\*] ]] || [ -z "$folder_name" ]; then
    log_error "Invalid folder name (cannot contain /, \\, *)."
fi

if [ -d "$folder_name" ]; then
    log_info "Folder $folder_name already exists."
    if ask_confirm "Do you want to delete and re-clone?" "N"; then
        rm -rf "$folder_name"
    else
        log_error "Aborted because folder already exists."
    fi
fi

# Clone repository
log_info "Cloning repository..."
git clone "$git_url" "$folder_name"

cd "$folder_name" || log_error "Cannot cd into $folder_name."

# ────────────────────────────────────────────────
# Step 3: Install dependencies and build Astro
# ────────────────────────────────────────────────
log_info "Installing dependencies..."
npm install --production || log_error "npm install failed."

log_info "Building Astro site..."
npm run build || log_error "npm run build failed."

# ────────────────────────────────────────────────
# Step 4: Domain name
# ────────────────────────────────────────────────
read -r -p "Enter the domain for this site (e.g., example.com): " domain
if [ -z "$domain" ] || ! [[ "$domain" =~ \.[a-z]{2,}$ ]]; then
    log_error "Invalid domain (must have a valid TLD like .com, .net)."
fi

# ────────────────────────────────────────────────
# Step 5: Root path for Nginx
# ────────────────────────────────────────────────
default_root="$(pwd)/dist"
if ask_confirm "Enter Nginx root path (default: $default_root)" "Y"; then
    read -r -p "Root path: " root_path
    root_path=${root_path:-$default_root}
else
    root_path=$default_root
fi

if [ ! -d "$root_path" ]; then
    log_error "Root path does not exist: $root_path"
fi

# Sync dist to /var/www for better organization and permissions
var_www_path="/var/www/$folder_name"
mkdir -p "$var_www_path"
rsync -a --delete "$root_path/" "$var_www_path/"
chown -R www-data:www-data "$var_www_path"
log_success "Synced dist to $var_www_path"

root_path="$var_www_path"  # Update for Nginx config

# ────────────────────────────────────────────────
# Step 6: SSL handling (manual files first, then Certbot)
# ────────────────────────────────────────────────
ssl_key_path=""
ssl_cert_path=""

if ask_confirm "Do you have existing SSL key and cert files (e.g., from Cloudflare)?" "Y"; then
    read -r -p "Enter path to private key (origin.key): " ssl_key_path
    read -r -p "Enter path to full certificate (origin.crt): " ssl_cert_path

    if [ ! -f "$ssl_key_path" ] || [ ! -f "$ssl_cert_path" ]; then
        log_info "Files not found. Skipping manual SSL."
        ssl_key_path=""
        ssl_cert_path=""
    elif ! grep -q "BEGIN.*PRIVATE KEY" "$ssl_key_path" || \
         ! grep -q "BEGIN CERTIFICATE" "$ssl_cert_path"; then
        log_info "Files do not appear to be in PEM format. Skipping manual SSL."
        ssl_key_path=""
        ssl_cert_path=""
    else
        log_success "Using provided SSL files."
    fi
fi

# If no manual SSL, ask about Certbot
if [ -z "$ssl_key_path" ] && [ -z "$ssl_cert_path" ]; then
    if ask_confirm "Do you want to use Certbot to automatically obtain free SSL?" "Y"; then
        if ! command -v certbot >/dev/null 2>&1; then
            log_info "Installing Certbot..."
            apt update -y
            apt install -y certbot python3-certbot-nginx
        fi

        log_info "Running Certbot for domain $domain..."
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email "admin@$domain" || {
            log_info "Certbot failed (domain may not point to this server). Skipping SSL."
        }
    else
        log_info "Skipping SSL setup. Site will run on HTTP only."
    fi
fi

# ────────────────────────────────────────────────
# Step 7: Generate Nginx config from template
# ────────────────────────────────────────────────
TEMPLATE_PATH="./config/astro.conf.example"
NGINX_CONF="/etc/nginx/sites-available/$domain"

if [ ! -f "$TEMPLATE_PATH" ]; then
    log_error "Nginx template not found: $TEMPLATE_PATH"
fi

cp "$TEMPLATE_PATH" "$NGINX_CONF"

# Replace placeholders
sed -i "s|{DOMAIN}|$domain|g" "$NGINX_CONF"
sed -i "s|{ROOT_PATH}|$root_path|g" "$NGINX_CONF"
sed -i "s|{FOLDER_NAME}|$folder_name|g" "$NGINX_CONF"

# If manual SSL provided, uncomment and fill SSL lines
if [ -n "$ssl_key_path" ] && [ -n "$ssl_cert_path" ]; then
    sed -i "s|# listen 443 ssl http2;|listen 443 ssl http2;|g" "$NGINX_CONF"
    sed -i "s|# listen [::]:443 ssl http2;|listen [::]:443 ssl http2;|g" "$NGINX_CONF"
    sed -i "s|{SSL_CERT_PATH}|$ssl_cert_path|g" "$NGINX_CONF"
    sed -i "s|{SSL_KEY_PATH}|$ssl_key_path|g" "$NGINX_CONF"
    sed -i "s|# return 301 https://\$host\$request_uri;|return 301 https://\$host\$request_uri;|g" "$NGINX_CONF"
fi

# Enable site
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# Test and reload Nginx
if nginx -t; then
    systemctl reload nginx
    log_success "Nginx configuration applied successfully."
else
    log_error "Nginx configuration test failed. Check $NGINX_CONF"
fi

# ────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────
echo ""
log_success "Astro deployment completed!"
echo -e "Site should be available at:"
echo -e "  - HTTP:  http://$domain"
if [ -n "$ssl_key_path" ] || certbot certificates --domain "$domain" >/dev/null 2>&1; then
    echo -e "  - HTTPS: https://$domain"
fi
echo ""
echo "Site directory: $(pwd)"
echo "Nginx root: $root_path"
echo "Nginx config: $NGINX_CONF"
echo ""
echo "Thank you for using the script!"
