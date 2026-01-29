#!/usr/bin/env bash
# deploy-laravel.sh
# Auto deploy script for Laravel applications
# - Checks prerequisites (nginx, pnpm, php, extensions, composer, postgresql, rsync)
# - Optional Redis install
# - Optional DB and user creation for PostgreSQL
# - Configures .env (DB, APP_ENV, APP_DEBUG, APP_KEY, Redis if installed)
# - Runs cache commands
# - Configures php-fpm pool
# - Configures Nginx from template
# - Configures Supervisor for queue workers from template
# - Uses REPO_ROOT to handle directory changes safely

set -euo pipefail

# Source utility functions
if [ -f "./scripts/utils.sh" ]; then
    source "./scripts/utils.sh"
else
    log_error "utils.sh not found in ./scripts/"
fi

# Save the root directory of the bash repo (to avoid path issues after cd)
REPO_ROOT="$(pwd)"

echo -e "${GREEN}=== Laravel Auto Deploy Script ===${NC}"
echo "This script will clone your Laravel repo, configure .env, build dependencies,"
echo "set up DB (optional), cache, php-fpm, Nginx, and Supervisor (if queue enabled)."
echo "Running from repo root: $REPO_ROOT"
echo ""

# ────────────────────────────────────────────────
# Step 1: Check and install prerequisites
# ────────────────────────────────────────────────
required_tools=("nginx" "pnpm" "php" "composer" "psql" "rsync")
php_extensions=("bcmath" "mbstring" "pgsql" "curl" "gd" "intl" "xml" "zip")

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_info "$tool is not installed."
        if ask_confirm "Do you want to install $tool now? (requires sudo)" "Y"; then
            sudo apt update -y
            case "$tool" in
                nginx) sudo apt install -y nginx ;;
                pnpm) 
                    if ! command -v corepack >/dev/null 2>&1; then
                        sudo corepack enable
                    fi
                    corepack prepare pnpm@latest --activate ;;
                php) sudo apt install -y php8.4-fpm php8.4-cli ;;
                composer) sudo apt install -y composer ;;
                psql) sudo apt install -y postgresql ;;
                rsync) sudo apt install -y rsync ;;
            esac
            log_success "$tool installed."
        else
            log_error "$tool is required. Script aborted."
        fi
    else
        log_success "$tool is already installed."
    fi
done

# Check PHP extensions
for ext in "${php_extensions[@]}"; do
    if ! php -m | grep -iq "$ext"; then
        log_info "PHP extension php8.4-$ext is not installed."
        if ask_confirm "Do you want to install php8.4-$ext now?" "Y"; then
            sudo apt install -y "php8.4-$ext"
            sudo systemctl restart php8.4-fpm
            log_success "PHP extension $ext installed."
        else
            log_error "PHP extension $ext is required. Script aborted."
        fi
    else
        log_success "PHP extension $ext is already installed."
    fi
done

# ────────────────────────────────────────────────
# Step 2: Optional - Install Redis
# ────────────────────────────────────────────────
if ! command -v redis-server >/dev/null 2>&1; then
    log_info "Redis is not installed (optional for cache/queue)."
    if ask_confirm "Do you want to install Redis now?" "N"; then
        sudo apt update -y
        sudo apt install -y redis-server
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
        log_success "Redis installed and started."
    else
        log_info "Skipping Redis installation."
    fi
else
    log_success "Redis is already installed."
fi

# ────────────────────────────────────────────────
# Step 3: Optional - Create PostgreSQL DB and user
# ────────────────────────────────────────────────
if ask_confirm "Do you want to create a PostgreSQL database and user?" "N"; then
    read -r -p "Enter DB name (default: lara): " db_name
    db_name=${db_name:-lara}

    read -r -p "Enter DB username (default: lara_user): " db_user
    db_user=${db_user:-lara_user}

    read -r -s -p "Enter DB password (default: Abcd@1234): " db_password
    db_password=${db_password:-Abcd@1234}
    echo ""

    sudo -u postgres psql -c "CREATE DATABASE $db_name;" || log_info "DB $db_name already exists or error."
    sudo -u postgres psql -c "CREATE USER $db_user WITH PASSWORD '$db_password';" || log_info "User $db_user already exists or error."
    sudo -u postgres psql -c "ALTER DATABASE $db_name OWNER TO $db_user;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;"
    log_success "PostgreSQL DB '$db_name' and user '$db_user' created (if not existing)."
else
    log_info "Skipping DB creation (assume manual setup)."
fi

# ────────────────────────────────────────────────
# Step 4: Git repository URL, folder name, clone
# ────────────────────────────────────────────────
read -r -p "Enter the Git repository URL: " git_url
git_url=$(echo "$git_url" | xargs)
[ -z "$git_url" ] && log_error "Git URL cannot be empty."

log_info "Verifying repository accessibility..."
if ! git ls-remote --exit-code --heads "$git_url" >/dev/null 2>&1; then
    log_error "Cannot access repository. Check URL, permissions, or SSH key."
fi
log_success "Repository accessible."

default_folder=$(basename "$git_url" .git)
read -r -p "Enter folder name to clone into (default: $default_folder): " folder_name
folder_name=${folder_name:-$default_folder}
var_www_path="/var/www/$folder_name"

if [[ "$folder_name" =~ [/\\*] ]] || [ -z "$folder_name" ]; then
    log_error "Invalid folder name."
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

# Change to project directory for build
cd "$folder_name" || log_error "Cannot cd into folder."

# ────────────────────────────────────────────────
# Step 5: Composer install & Laravel setup
# ────────────────────────────────────────────────
log_info "Installing Composer dependencies..."
composer install --optimize-autoloader --no-dev || log_error "Composer install failed."

if [ ! -f ".env" ]; then
    cp .env.example .env || log_error ".env.example not found."
fi

# ────────────────────────────────────────────────
# Step 6: Configure .env
# ────────────────────────────────────────────────
log_info "Configuring .env file..."

# DB fields
read -r -p "DB_CONNECTION (default: pgsql): " db_connection
db_connection=${db_connection:-pgsql}
sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=$db_connection/" .env

read -r -p "DB_HOST (default: 127.0.0.1): " db_host
db_host=${db_host:-127.0.0.1}
sed -i "s/^DB_HOST=.*/DB_HOST=$db_host/" .env

read -r -p "DB_PORT (default: 5432): " db_port
db_port=${db_port:-5432}
sed -i "s/^DB_PORT=.*/DB_PORT=$db_port/" .env

read -r -p "DB_DATABASE (default: lara): " db_database
db_database=${db_database:-lara}
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$db_database/" .env

read -r -p "DB_USERNAME (default: lara_user): " db_username
db_username=${db_username:-lara_user}
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$db_username/" .env

read -r -s -p "DB_PASSWORD (default: Abcd@1234): " db_password
db_password=${db_password:-Abcd@1234}
echo ""
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$db_password/" .env

# Additional fields
read -r -p "APP_ENV (default: production): " app_env
app_env=${app_env:-production}
sed -i "s/^APP_ENV=.*/APP_ENV=$app_env/" .env

read -r -p "APP_DEBUG (default: false): " app_debug
app_debug=${app_debug:-false}
sed -i "s/^APP_DEBUG=.*/APP_DEBUG=$app_debug/" .env

# APP_KEY
if ask_confirm "Do you want to generate APP_KEY now?" "Y"; then
    php artisan key:generate
    log_success "APP_KEY generated."
else
    log_info "Skipping APP_KEY generation."
fi

# Redis (only if redis installed)
if command -v redis-server >/dev/null 2>&1; then
    log_info "Redis detected. Configuring .env for Redis..."
    sed -i "s/^CACHE_STORE=.*/CACHE_STORE=redis/" .env
    sed -i "s/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/" .env
    sed -i "s/^SESSION_DRIVER=.*/SESSION_DRIVER=redis/" .env

    read -r -p "REDIS_HOST (default: 127.0.0.1): " redis_host
    redis_host=${redis_host:-127.0.0.1}
    sed -i "s/^REDIS_HOST=.*/REDIS_HOST=$redis_host/" .env

    read -r -p "REDIS_PASSWORD (default: null): " redis_password
    redis_password=${redis_password:-null}
    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$redis_password/" .env

    read -r -p "REDIS_PORT (default: 6379): " redis_port
    redis_port=${redis_port:-6379}
    sed -i "s/^REDIS_PORT=.*/REDIS_PORT=$redis_port/" .env
else
    log_info "Redis not detected. Skipping Redis configuration in .env."
fi

# ────────────────────────────────────────────────
# Step 7: Cache commands
# ────────────────────────────────────────────────
log_info "Caching configuration, routes, and views..."
php artisan config:cache
php artisan route:cache
php artisan view:cache
log_success "Caching completed."

# ────────────────────────────────────────────────
# Step 8: Configure php-fpm pool (requires sudo)
# ────────────────────────────────────────────────
PHP_FPM_CONF="/etc/php/8.4/fpm/pool.d/www.conf"

if ask_confirm "Do you want to configure php8.4-fpm pool now? (requires sudo)" "Y"; then
    sudo sed -i "s/^user =.*/user = www-data/" "$PHP_FPM_CONF"
    sudo sed -i "s/^group =.*/group = www-data/" "$PHP_FPM_CONF"
    sudo sed -i "s/^listen =.*/listen = \/run\/php\/php8.4-fpm.sock/" "$PHP_FPM_CONF"
    sudo sed -i "s/^listen.owner =.*/listen.owner = www-data/" "$PHP_FPM_CONF"
    sudo sed -i "s/^listen.group =.*/listen.group = www-data/" "$PHP_FPM_CONF"
    sudo sed -i "s/^listen.mode =.*/listen.mode = 0660/" "$PHP_FPM_CONF"
    sudo sed -i "s/^pm =.*/pm = dynamic/" "$PHP_FPM_CONF"

    sudo systemctl restart php8.4-fpm
    log_success "php8.4-fpm pool configured and restarted."
else
    log_info "Skipping php-fpm configuration."
fi

# ────────────────────────────────────────────────
# Step 9: Domain
# ────────────────────────────────────────────────
domain=$(ask_domain)  # Reuse from utils.sh

# ────────────────────────────────────────────────
# Step 10: Root path & rsync to /var/www
# ────────────────────────────────────────────────
root_path=$(setup_web_root "$(pwd)" "$folder_name" "$(pwd)/public")  # Reuse from utils.sh

# ────────────────────────────────────────────────
# Step 11: SSL handling
# ────────────────────────────────────────────────
setup_ssl  # Reuse from utils.sh

# ────────────────────────────────────────────────
# Step 12: Generate Nginx config from template
# ────────────────────────────────────────────────
# Ở Step 12
apply_nginx_config "$REPO_ROOT/config/nginx/laravel.conf.example" "$domain" "$root_path" "$folder_name" "$var_www_path"

# ────────────────────────────────────────────────
# Step 13: Supervisor for queue workers
# ────────────────────────────────────────────────
if command -v supervisorctl >/dev/null 2>&1; then
    if ask_confirm "Do you want to set up Supervisor for Laravel queue workers?" "Y"; then
        SUPERVISOR_CONF="/etc/supervisor/conf.d/laravel-worker.conf"
        APP_PATH="$var_www_path"

        if [ ! -f "$REPO_ROOT/config/supervisor/laravel-worker.conf.example" ]; then
            log_error "Supervisor template not found: $REPO_ROOT/config/supervisor/laravel-worker.conf.example"
        fi

        sudo cp "$REPO_ROOT/config/supervisor/laravel-worker.conf.example" "$SUPERVISOR_CONF"
        sudo sed -i "s|{APP_PATH}|$APP_PATH|g" "$SUPERVISOR_CONF"

        sudo supervisorctl reread
        sudo supervisorctl update
        sudo supervisorctl restart laravel-worker:*
        log_success "Supervisor configured for Laravel queue workers."
    else
        log_info "Skipping Supervisor setup."
    fi
else
    log_info "Supervisor not installed. Skipping queue worker setup."
fi

# ────────────────────────────────────────────────
# Final summary
# ────────────────────────────────────────────────
echo ""
log_success "Laravel deployment completed!"
echo -e "Site should be available at:"
echo -e "  - HTTP:  http://$domain"
if [ -n "${SSL_KEY_PATH:-}" ] || certbot certificates --domain "$domain" >/dev/null 2>&1; then
    echo -e "  - HTTPS: https://$domain"
fi
echo ""
echo "App directory: $(pwd)"
echo "Nginx root: $root_path"
echo "Nginx config: /etc/nginx/sites-available/$domain"
echo ""
echo "Thank you for using the script!"
