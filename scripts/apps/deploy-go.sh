#!/usr/bin/env bash
# deploy-go.sh
# Auto deploy script for Go applications (optimized for Pagoda starter like chomusuke-demo-go)
# - Checks prerequisites (nginx, go)
# - Clones repo, copies .env, asks for main.go path, builds Go binary
# - Rsync full app to /var/www
# - Creates dbs/ folder + fixes permissions for SQLite, logs, cache
# - Configures Nginx from template
# - Handles SSL (manual or Certbot)
# - Creates systemd service from template (optional)
# - Uses utils.sh functions and REPO_ROOT

set -euo pipefail

# Source utility functions
if [ -f "./scripts/utils.sh" ]; then
    source "./scripts/utils.sh"
else
    log_error "utils.sh not found in ./scripts/"
fi

# Save repo root
REPO_ROOT="$(pwd)"

echo -e "${GREEN}=== Go Auto Deploy Script ===${NC}"
echo "This script will clone your Go repo, build the binary,"
echo "configure .env (if needed), set up Nginx and systemd service."
echo "Running from repo root: $REPO_ROOT"
echo ""

# ────────────────────────────────────────────────
# Step 1: Check and install prerequisites
# ────────────────────────────────────────────────
check_prerequisites "nginx go"

# ────────────────────────────────────────────────
# Step 2: Git repository URL, folder name, clone
# ────────────────────────────────────────────────
readarray -t clone_output < <(clone_repository)

folder_name="${clone_output[0]}"
PROJECT_PATH="${clone_output[1]}"
var_www_path="/var/www/$folder_name"

if [ -z "$PROJECT_PATH" ] || [ ! -d "$PROJECT_PATH" ]; then
    log_error "Failed to clone or get project path."
fi

log_info "Cloned to folder: $folder_name"
log_info "Project path: $PROJECT_PATH"

cd "$PROJECT_PATH" || log_error "Cannot cd into $PROJECT_PATH"

# ────────────────────────────────────────────────
# Step 3: Copy .env (if exists) and configure basic fields
# ────────────────────────────────────────────────
log_info "Configuring .env file (if needed)..."

if [ -f ".env.example" ]; then
    cp .env.example .env || log_error "Failed to copy .env.example to .env."
    log_success ".env created from .env.example."

    if ask_confirm "Do you want to edit .env manually now?" "N"; then
        nano .env
    fi
else
    log_info "No .env.example found. Assuming .env is already set up or not needed."
fi

# ────────────────────────────────────────────────
# Step 4: Build Go binary
# ────────────────────────────────────────────────
log_info "Building Go application..."

default_main="cmd/web/main.go"
read -r -p "Enter the path to main Go file (default: $default_main): " main_path
main_path=${main_path:-$default_main}

if [ ! -f "$main_path" ]; then
    log_error "Main Go file not found: $main_path"
fi

go build -o app "$main_path" || log_error "Go build failed."

if [ ! -f "app" ]; then
    log_error "Go binary 'app' not found after build."
fi

log_success "Go binary built successfully: $(pwd)/app"

# ────────────────────────────────────────────────
# Step 5: Domain (reused from utils.sh)
# ────────────────────────────────────────────────
domain=$(ask_domain)

# ────────────────────────────────────────────────
# Step 6: Root path & rsync to /var/www (reused from utils.sh)
# ────────────────────────────────────────────────
setup_web_root "$(pwd)" "$folder_name" "$(pwd)"

# ────────────────────────────────────────────────
# Step 6.5: Fix SQLite dbs folder + permissions (Pagoda-specific)
# ────────────────────────────────────────────────
log_info "Fixing SQLite dbs folder and permissions (for Pagoda starter)..."

sudo mkdir -p "$var_www_path/dbs"

sudo find . -maxdepth 2 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) -exec cp {} "$var_www_path/dbs/" \;

sudo chown -R www-data:www-data "$var_www_path/dbs" "$var_www_path/storage" "$var_www_path/.cache"
sudo chmod -R 775 "$var_www_path/dbs" "$var_www_path/storage" "$var_www_path/.cache"
sudo chmod 664 "$var_www_path/dbs"/*.db "$var_www_path/dbs"/*.sqlite*

log_success "SQLite dbs folder and permissions fixed."

# ────────────────────────────────────────────────
# Step 7: SSL handling (reused from utils.sh)
# ────────────────────────────────────────────────
setup_ssl

# ────────────────────────────────────────────────
# Step 8: Generate Nginx config from template (reused from utils.sh)
# ────────────────────────────────────────────────
apply_nginx_config "$REPO_ROOT/config/nginx/go.conf.example" "$domain" "/var/www/$folder_name" "$folder_name" "/var/www/$folder_name"

# ────────────────────────────────────────────────
# Step 9: Create systemd service from template (optional)
# ────────────────────────────────────────────────
GO_SERVICE="/etc/systemd/system/$folder_name.service"

if ask_confirm "Do you want to create a systemd service for the Go app?" "Y"; then
    SERVICE_TEMPLATE="$REPO_ROOT/config/service/go.service.example"

    if [ ! -f "$SERVICE_TEMPLATE" ]; then
        log_error "Service template not found: $SERVICE_TEMPLATE"
    fi

    sudo cp "$SERVICE_TEMPLATE" "$GO_SERVICE"
    sudo sed -i "s|{APP_NAME}|$folder_name|g" "$GO_SERVICE"
    sudo sed -i "s|{USER}|www-data|g" "$GO_SERVICE"
    sudo sed -i "s|{GROUP}|www-data|g" "$GO_SERVICE"
    sudo sed -i "s|{APP_PATH}|$var_www_path|g" "$GO_SERVICE"

    log_info "Setting up writable Go cache directories for www-data..."
    sudo mkdir -p /var/cache/go-build /var/cache/go-mod
    sudo chown -R www-data:www-data /var/cache/go-build /var/cache/go-mod
    sudo chmod -R 775 /var/cache/go-build /var/cache/go-mod
    log_success "Go cache directories created and fixed."

    sudo sed -i "/\[Service\]/a Environment=GOCACHE=/var/cache/go-build" "$GO_SERVICE"
    sudo sed -i "/\[Service\]/a Environment=GOMODCACHE=/var/cache/go-mod" "$GO_SERVICE"

    sudo systemctl daemon-reload
    sudo systemctl enable "$folder_name.service"
    sudo systemctl restart "$folder_name.service"
    log_success "Systemd service created, reloaded, and restarted: $folder_name.service"
    sudo systemctl status "$folder_name.service" --no-pager
else
    log_info "Skipping systemd service. Run the app manually:"
    log_info "cd $var_www_path && sudo -u www-data ./app"
fi

# ────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────
echo ""
log_success "Go deployment completed!"
echo -e "Site should be available at:"
echo -e "  - HTTP:  http://$domain"
if [ -n "${SSL_KEY_PATH:-}" ] || certbot certificates --domain "$domain" >/dev/null 2>&1; then
    echo -e "  - HTTPS: https://$domain"
fi
echo ""
echo "App directory: $var_www_path"
echo "Binary: $var_www_path/app"
echo "Nginx root: /var/www/$folder_name"
echo "Nginx config: /etc/nginx/sites-available/$folder_name.conf"
echo "Systemd service: $GO_SERVICE (if created)"
echo ""
echo "Thank you for using the script!"
