#!/usr/bin/env bash
# setup-vps.sh
# Main provisioning script that orchestrates child setup scripts
# Usage:
#   ./setup-vps.sh              # normal mode (with colors + footers)
#   ./setup-vps.sh --quiet      # quiet mode (suppress child footers)

set -euo pipefail

# Source utility functions
source ./util.sh 2>/dev/null || source ./scripts/util.sh 2>/dev/null || {
    echo "Error: util.sh not found in ./ or ./scripts/" >&2
    exit 1
}

# ────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────

QUIET=false
if [[ "${1:-}" == "--quiet" || "${1:-}" == "-q" ]]; then
    QUIET=true
    shift
fi

# ────────────────────────────────────────────────
# Main execution
# ────────────────────────────────────────────────

print_info ""
print_info "🚀 Starting VPS provisioning"
print_info "   Quiet mode : ${QUIET:+ON}${QUIET:-- OFF}"
print_info "   Timestamp  : $(date '+%Y-%m-%d %H:%M:%S')"
print_info ""

# List of scripts to run in order
scripts_dir="./scripts"
declare -a setup_steps=(
    "setup-basic-security.sh:Basic Security Setup"
    "setup-basic-server.sh:Basic Server Setup"
    "setup-common-stack.sh:Common Stack Setup (nginx / php / ...)"
)

# Check all required scripts exist
for entry in "${setup_steps[@]}"; do
    script_name="${entry%%:*}"
    script_path="$scripts_dir/$script_name"
    check_file_exists "$script_path"
done

# Execute each step
for entry in "${setup_steps[@]}"; do
    script_name="${entry%%:*}"
    step_title="${entry#*:}"
    script_path="$scripts_dir/$script_name"

    run_script_quiet "$script_path" "$step_title"
done

# Final summary
echo -e "\033[0;32m════════════════════════════════════════════════════════════\033[0m"
print_success "ALL STEPS COMPLETED SUCCESSFULLY"
echo -e "\033[0;32m════════════════════════════════════════════════════════════\033[0m"
echo ""
print_info "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
print_info "Enjoy your stable VPS! 🚀"
echo ""
