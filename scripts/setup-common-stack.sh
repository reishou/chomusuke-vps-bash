#!/usr/bin/env bash
set -euo pipefail

QUIET_MODE=0
if [[ "${1:-}" == "--quiet" ]]; then
  QUIET_MODE=1
  shift
fi

# === install-common-stack.sh ===
# Purpose: Install common stack (Nginx, PHP 8.4, Composer, Node.js/pnpm, Supervisor, Redis, PostgreSQL)
# Run on VPS after cloning repo: sudo bash scripts/install-common-stack.sh
# Based on: https://reishou.gitbook.io/n/vps/manual-operations/installing-common-stack

# Load utils
if [ ! -f "$(dirname "$0")/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m utils.sh not found in the scripts/ directory.."
    echo "Expected path: $(dirname "$0")/utils.sh"
    echo "Please check if the file exists in your repository."
    exit 1
fi

source "$(dirname "$0")/utils.sh"

print_header "Install Common Stack"

check_root

log_info "This script installs the common stack for VPS:"
log_info "- Nginx"
log_info "- PHP 8.4 + FPM + extensions"
log_info "- Composer"
log_info "- Node.js LTS + pnpm"
log_info "- Supervisor"
log_info "- Redis"
log_info "- PostgreSQL"
echo ""
log_warning "All steps are optional (y/n, default y). You can skip any step."
echo ""

# Step 1: Update system
echo ""
if ask_confirm "Do you want to update and upgrade the system first?" "Y"; then
    log_info "Updating package list and upgrading system..."
    apt update -y
    apt upgrade -y
    apt autoremove -y
    log_success "System updated."
else
    log_info "System update skipped."
fi

# Step 2: Install Nginx
echo ""
if ask_confirm "Do you want to install Nginx?" "Y"; then
    log_info "Installing Nginx..."
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    nginx -v
    log_success "Nginx installed and running."
else
    log_info "Nginx installation skipped."
fi

# Step 3: Install PHP 8.4 + FPM + extensions
echo ""
if ask_confirm "Do you want to install PHP 8.4 + FPM + common extensions?" "Y"; then
    log_info "Adding Ondřej Surý PPA for PHP 8.4..."
    add-apt-repository ppa:ondrej/php -y
    apt update -y

    log_info "Installing PHP 8.4..."
    apt install -y php8.4 php8.4-fpm php8.4-cli php8.4-common \
        php8.4-mysql php8.4-curl php8.4-gd php8.4-mbstring \
        php8.4-xml php8.4-zip php8.4-bcmath php8.4-intl

    systemctl enable php8.4-fpm
    systemctl start php8.4-fpm
    php -v
    log_success "PHP 8.4 installed."
else
    log_info "PHP installation skipped."
fi

# Step 4: Install Composer
echo ""
if ask_confirm "Do you want to install Composer?" "Y"; then
    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    composer --version
    log_success "Composer installed."
else
    log_info "Composer installation skipped."
fi

# Step 5: Install Node.js LTS + pnpm
echo ""
if ask_confirm "Do you want to install Node.js LTS + pnpm?" "Y"; then
    log_info "Installing Node.js LTS..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs

    log_info "Installing pnpm..."
    npm install -g pnpm
    pnpm --version
    log_success "Node.js LTS + pnpm installed."
else
    log_info "Node.js + pnpm installation skipped."
fi

# Step 6: Install Supervisor
echo ""
if ask_confirm "Do you want to install Supervisor?" "Y"; then
    log_info "Installing Supervisor..."
    apt install -y supervisor
    systemctl enable supervisor
    systemctl start supervisor
    supervisorctl status
    log_success "Supervisor installed."
else
    log_info "Supervisor installation skipped."
fi

# Step 7: Install Redis
echo ""
if ask_confirm "Do you want to install Redis?" "Y"; then
    log_info "Installing Redis..."
    apt install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server
    redis-cli ping
    log_success "Redis installed."
else
    log_info "Redis installation skipped."
fi

# Step 8: Install PostgreSQL
echo ""
if ask_confirm "Do you want to install PostgreSQL?" "Y"; then
    log_info "Installing PostgreSQL..."
    apt install -y postgresql postgresql-contrib
    systemctl enable postgresql
    systemctl start postgresql
    sudo -u postgres psql -c "SELECT version();"
    log_success "PostgreSQL installed."
else
    log_info "PostgreSQL installation skipped."
fi

# Final instructions
if [[ $QUIET_MODE -eq 0 ]]; then
  echo ""
  log_success "Common Stack Installation completed!"
  echo "Next steps:"
  echo "1. Test services: nginx -v, php -v, node -v, pnpm --version, redis-cli ping, psql --version"
  echo "2. Continue with deployment scripts in this repo."
  echo "Repo: https://github.com/reishou/chomusuke-vps-bash"

  print_footer
else
  echo ""
fi
