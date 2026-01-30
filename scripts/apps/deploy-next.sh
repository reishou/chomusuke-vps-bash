#!/usr/bin/env bash
# deploy-next.sh
# Auto deploy script for Next.js applications
# - Checks prerequisites (nginx, pm2, node, pnpm, postgresql)
# - Configures .env (POSTGRES_URL, AUTH_SECRET, AUTH_URL) BEFORE build
# - Optional PostgreSQL DB and user creation
# - Clones repo, installs deps, builds with pnpm
# - Rsync build output to /var/www
# - Uses utils.sh functions for domain, web root, SSL, Nginx config
# - Starts app with existing PM2 ecosystem.config.js

set -euo pipefail

# Source utility functions
if [ -f "./scripts/utils.sh" ]; then
    source "./scripts/utils.sh"
else
    log_error "utils.sh not found in ./scripts/"
fi

# Save repo root
REPO_ROOT="$(pwd)"

echo -e "${GREEN}=== Next.js Auto Deploy Script ===${NC}"
echo "This script will clone your Next.js repo, configure .env first,"
echo "build the app, set up Nginx and PM2."
echo "Running from repo root: $REPO_ROOT"
echo ""

# ────────────────────────────────────────────────
# Step 1: Check and install prerequisites
# ────────────────────────────────────────────────
check_prerequisites "nginx pm2 node pnpm psql"

# ────────────────────────────────────────────────
# Step 2: Optional - Create PostgreSQL DB and user
# ────────────────────────────────────────────────
create_postgres_db

# ────────────────────────────────────────────────
# Step 3: Git repository URL, folder name, clone
# ────────────────────────────────────────────────
readarray -t clone_output < <(clone_repository)

folder_name="${clone_output[0]}"
PROJECT_PATH="${clone_output[1]}"

if [ -z "$PROJECT_PATH" ]; then
    log_error "Failed to get project path from clone_repository."
fi

log_info "Cloned to folder: $folder_name"
log_info "Project path: $PROJECT_PATH"

cd "$PROJECT_PATH" || log_error "Cannot cd into $PROJECT_PATH"

# ────────────────────────────────────────────────
# Step 4: Configure .env BEFORE build (POSTGRES_URL, AUTH_SECRET, AUTH_URL)
# ────────────────────────────────────────────────
log_info "Configuring .env file (before build)..."

# Default POSTGRES_URL
default_url="postgresql://next_user:Abcd@1234@127.0.0.1:5432/next"

if ask_confirm "Do you want to configure POSTGRES_URL now? (default: $default_url)" "Y"; then
    read -p "POSTGRES_URL (default: $default_url): " postgres_url
    postgres_url=${postgres_url:-$default_url}
    sed -i "s|^POSTGRES_URL=.*|POSTGRES_URL=$postgres_url|" .env || echo "POSTGRES_URL=$postgres_url" >> .env
else
    log_info "Skipping POSTGRES_URL configuration."
fi

# AUTH_SECRET (32 random chars)
if ask_confirm "Do you want to generate AUTH_SECRET (32 chars random)?" "Y"; then
    auth_secret=$(openssl rand -base64 32 | tr -d '\n')
    sed -i "s|^AUTH_SECRET=.*|AUTH_SECRET=$auth_secret|" .env || echo "AUTH_SECRET=$auth_secret" >> .env
    log_success "AUTH_SECRET generated: $auth_secret (save this securely!)"
else
    log_info "Skipping AUTH_SECRET generation."
fi

# AUTH_URL (thêm mới theo yêu cầu)
read -r -p "AUTH_URL (default: empty, e.g. https://next.chomusuke.site): " auth_url
auth_url=${auth_url:-""}
sed -i "s|^AUTH_URL=.*|AUTH_URL=$auth_url|" .env || echo "AUTH_URL=$auth_url" >> .env
log_info "AUTH_URL set to: $auth_url"

# ────────────────────────────────────────────────
# Step 5: Install dependencies and build with pnpm
# ────────────────────────────────────────────────
log_info "Installing dependencies with pnpm..."
pnpm install || log_error "pnpm install failed."

log_info "Building Next.js app..."
pnpm run build || log_error "pnpm run build failed."

# Verify build output
if [ ! -d ".next" ] && [ ! -d "out" ]; then
    log_error "Build output (.next or out) not found. Build may have failed."
fi
log_success "Next.js build completed."

# ────────────────────────────────────────────────
# Step 6: Domain (reused from utils.sh)
# ────────────────────────────────────────────────
domain=$(ask_domain)

# ────────────────────────────────────────────────
# Step 7: Root path & rsync to /var/www (reused from utils.sh)
# ────────────────────────────────────────────────
root_path=$(setup_web_root "$(pwd)" "$folder_name")

# ────────────────────────────────────────────────
# Step 8: SSL handling (reused from utils.sh)
# ────────────────────────────────────────────────
setup_ssl

# ────────────────────────────────────────────────
# Step 9: Generate Nginx config from template (reused from utils.sh)
# ────────────────────────────────────────────────
apply_nginx_config "$REPO_ROOT/config/nginx/next.conf.example" "$domain" "$root_path" "$folder_name"

# ────────────────────────────────────────────────
# Step 10: Start app with PM2 (using existing ecosystem.config.js)
# ────────────────────────────────────────────────
log_info "Starting Next.js app with PM2 (using existing ecosystem.config.js)..."

PM2_ECOSYSTEM="$(pwd)/ecosystem.config.js"

if [ ! -f "$PM2_ECOSYSTEM" ]; then
    log_error "ecosystem.config.js not found in project root. Cannot start PM2."
fi

pm2 start "$PM2_ECOSYSTEM" || log_error "PM2 start failed."
pm2 save || log_info "PM2 save failed (optional)."

log_success "Next.js app started with PM2."
pm2 status

# ────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────
echo ""
log_success "Next.js deployment completed!"
echo -e "Site should be available at:"
echo -e "  - HTTP:  http://$domain"
if [ -n "${SSL_KEY_PATH:-}" ] || certbot certificates --domain "$domain" >/dev/null 2>&1; then
    echo -e "  - HTTPS: https://$domain"
fi
echo ""
echo "App directory: $(pwd)"
echo "Nginx root: $root_path"
echo "Nginx config: /etc/nginx/sites-available/$folder_name.conf"
echo "PM2 app name: $folder_name (check with pm2 status)"
echo ""
echo "Thank you for using the script!"
