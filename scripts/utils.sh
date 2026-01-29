#!/usr/bin/env bash
# utils.sh - Common utility functions for Chomusuke Deploy scripts
# Place this file in scripts/utils.sh
# Usage: source "$(dirname "$0")/utils.sh"

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# === Logging ===
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# === Checks ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo."
        exit 1
    fi
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found."
        exit 1
    fi
}

package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

ensure_package() {
    local pkg="$1"
    if ! package_installed "$pkg"; then
        log_info "Installing $pkg..."
        apt update -y
        if apt install -y "$pkg"; then
            log_success "Installed $pkg"
        else
            log_error "Failed to install $pkg. Continuing without it."
        fi
    else
        log_info "$pkg already installed."
    fi
}

update_package() {
    local pkg="$1"
    if package_installed "$pkg"; then
        log_info "Checking updates for $pkg..."
        apt update -y &>/dev/null
        if apt list --upgradable 2>/dev/null | grep -q "^$pkg/"; then
            log_info "Upgrading $pkg..."
            apt upgrade -y "$pkg" && log_success "Upgraded $pkg"
        else
            log_info "$pkg is up to date."
        fi
    else
        log_warning "$pkg not installed. Skipping update."
    fi
}

ask_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local response

    read -p "$prompt [Y/n] " -r response

    response="${response:-$default}"

    if [[ -z "$response" && "$default" == "Y" ]] || \
       [[ "$response" =~ ^[Yy]$ ]] || \
       [[ "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

user_exists() { id "$1" &>/dev/null; }

check_internet() {
    if ! ping -c 1 -W 3 google.com &>/dev/null; then
        log_error "No internet connection."
        exit 1
    fi
    log_info "Internet OK."
}

check_dir_writable() {
    local dir="$1"
    [ -d "$dir" ] || { log_error "Directory '$dir' does not exist."; exit 1; }
    [ -w "$dir" ] || { log_error "Directory '$dir' is not writable."; exit 1; }
    log_info "Directory '$dir' is writable."
}

print_header() {
    echo ""
    echo -e "${CYAN}====================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}====================================${NC}"
    echo ""
}

print_footer() {
    echo ""
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}  Completed successfully!${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo ""
}

run_script_quiet() {
    local script="$1"
    local name="$2"

    print_header "Starting: $name"

    if $QUIET; then
        bash "$script" --quiet 2>&1 | sed '/^─* Setup completed ─*/d; /^Footer .* removed/d' || true
    else
        bash "$script"
    fi

    local status=$?
    if [ $status -eq 0 ]; then
        print_success "Completed: $name"
        echo ""
    else
        print_error "Failed: $name (exit code $status)"
        exit $status
    fi
}

print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m✗ $1\033[0m" >&2
}

print_info() {
    echo -e "\033[1;33m$1\033[0m"
}

check_file_exists() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        print_error "File not found → $path"
        exit 1
    fi
}

# Ask for domain with validation
ask_domain() {
    local domain
    read -r -p "Enter the domain for this site (e.g., example.com): " domain
    if [ -z "$domain" ] || ! [[ "$domain" =~ \.[a-z]{2,}$ ]]; then
        log_error "Invalid domain (must have a valid TLD like .com, .vn)."
    fi
    echo "$domain"
}

# Setup web root: ask root path, rsync to /var/www, chown www-data
# Params: $1 = current project path, $2 = folder_name, $2 = default_root
setup_web_root() {
    local project_path="$1"
    local folder_name="$2"
    local default_root="$3"

    read -r -p "Enter Nginx root path (default: $default_root): " root_path
    root_path=${root_path:-$default_root}

    if [ ! -d "$root_path" ]; then
        log_error "Root path does not exist: $root_path"
    fi

    local var_www_path="/var/www/$folder_name"
    sudo mkdir -p "$var_www_path"
    sudo rsync -a --delete "${project_path}/" "$var_www_path/"
    sudo chown -R www-data:www-data "$var_www_path"
    log_success "Synced app to $var_www_path"

    echo "$var_www_path/public"  # return the actual root path for Nginx
}

# SSL handling: manual files first, then Certbot
# Returns: ssl_key_path and ssl_cert_path (set as global or echo)
setup_ssl() {
    local ssl_key_path=""
    local ssl_cert_path=""

    if ask_confirm "Do you have existing SSL key/cert files?" "Y"; then
        read -r -p "Enter full absolute path to private key (e.g., /etc/ssl/cloudflare/chomusuke.site.key): " ssl_key_path
        read -r -p "Enter full absolute path to full certificate (e.g., /etc/ssl/cloudflare/chomusuke.site.crt): " ssl_cert_path
    fi

    if [ -z "$ssl_key_path" ] && [ -z "$ssl_cert_path" ]; then
        if ask_confirm "Use Certbot for free SSL?" "Y"; then
            if ! command -v certbot >/dev/null 2>&1; then
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

    # Return values (using global variables or echo if preferred)
    export SSL_KEY_PATH="$ssl_key_path"
    export SSL_CERT_PATH="$ssl_cert_path"
}

# Apply Nginx config from template
# Params: $1 = template_path, $2 = domain, $3 = root_path, $4 = folder_name
# utils.sh
apply_nginx_config() {
    local template_path="$1"
    local domain="$2"
    local root_path="$3"
    local folder_name="$4"
    local var_www_path="$5"

    local nginx_conf="/etc/nginx/sites-available/$folder_name"

    if [ ! -f "$template_path" ]; then
        log_error "Nginx template not found: $template_path"
    fi

    log_info "Creating Nginx config for $domain..."
    sudo cp "$template_path" "$nginx_conf"
    log_info 'sudo sed -i "s|{DOMAIN}|$domain|g" "$nginx_conf"'
    sudo sed -i "s|{DOMAIN}|$domain|g" "$nginx_conf"
    log_info 'sudo sed -i "s|{ROOT_PATH}|$root_path|g" "$nginx_conf"'
    sudo sed -i "s|{ROOT_PATH}|$root_path|g" "$nginx_conf"
    log_info 'sudo sed -i "s|{FOLDER_NAME}|$folder_name|g" "$nginx_conf"'
    sudo sed -i "s|{FOLDER_NAME}|$folder_name|g" "$nginx_conf"

    # SSL manual (if provided)
    if [ -n "$SSL_KEY_PATH" ] && [ -n "$SSL_CERT_PATH" ]; then
        log_info 'sudo sed -i "s|# listen 443 ssl http2;|listen 443 ssl http2;|g" "$nginx_conf"'
        sudo sed -i "s|# listen 443 ssl http2;|listen 443 ssl http2;|g" "$nginx_conf"
        log_info 'sudo sed -i "s|# listen [::]:443 ssl http2;|listen [::]:443 ssl http2;|g" "$nginx_conf"'
        sudo sed -i "s|# listen [::]:443 ssl http2;|listen [::]:443 ssl http2;|g" "$nginx_conf"
        log_info 'sudo sed -i "s|{SSL_CERT_PATH}|$|g" "$nginx_conf"'
        sudo sed -i "s|{SSL_CERT_PATH}|$|g" "$nginx_conf"
        log_info 'sudo sed -i "s|{SSL_KEY_PATH}|$SSL_CERT_PATH|g" "$nginx_conf"'
        sudo sed -i "s|{SSL_KEY_PATH}|$SSL_CERT_PATH|g" "$nginx_conf"
        log_info 'sudo sed -i "s|# return 301 https://\$host\$request_uri;|return 301 https://\$host\$request_uri;|g" "$nginx_conf"'
        sudo sed -i "s|# return 301 https://\$host\$request_uri;|return 301 https://\$host\$request_uri;|g" "$nginx_conf"
    fi

    sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/

    if sudo nginx -t; then
        sudo systemctl reload nginx
        log_success "Nginx config applied successfully."
    else
        log_error "Nginx configuration test failed. Check $nginx_conf"
    fi
}
