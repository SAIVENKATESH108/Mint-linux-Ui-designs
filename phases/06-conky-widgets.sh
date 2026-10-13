#!/usr/bin/env bash
# ==============================================================================
# Phase 6: Desktop Widgets (Conky Sequoia Glance)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 6: Starting Conky Desktop Widgets Configuration"

# Check mode flag: --lite or --full
MODE="lite"
for arg in "$@"; do
    case "${arg}" in
        --full)
            MODE="full"
            ;;
        --lite)
            MODE="lite"
            ;;
    esac
done

# 1. Dependency Checks
REQUIRED_PKGS=("conky-all")
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Install Conky Configuration
CONKY_CONFIG_DIR="${HOME}/.config/conky"
mkdir -p "${CONKY_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/conky/sequoia-glance.conkyrc" "${CONKY_CONFIG_DIR}/sequoia-glance.conkyrc"

# In lite mode, tweak update_interval to 3.5s to minimize CPU wakeups on i3-3220
if [[ "${MODE}" == "lite" ]]; then
    sed -i "s/update_interval = .*/update_interval = 3.5,/" "${CONKY_CONFIG_DIR}/sequoia-glance.conkyrc"
    log_info "Applied lite mode: Conky update interval set to 3.5s."
fi

# 3. Enable Conky Autostart
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"
safe_copy "${CONFIG_DIR}/autostart/conky-sequoia.desktop" "${AUTOSTART_DIR}/conky-sequoia.desktop"

# 4. Restart Conky if running inside X11 session
if [[ -n "${DISPLAY:-}" ]]; then
    log_info "Reloading Conky in current session..."
    killall conky 2>/dev/null || true
    conky -c "${CONKY_CONFIG_DIR}/sequoia-glance.conkyrc" -d &>/dev/null || log_warn "Conky failed to launch."
fi

log_success "Phase 6 Complete: Conky Sequoia widget configured and active."
