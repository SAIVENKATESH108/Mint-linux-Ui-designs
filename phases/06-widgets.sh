#!/usr/bin/env bash
# ==============================================================================
# Phase 6: Desktop Widgets (3 Conky Windows + Caching Weather)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# Hardware: Intel Core i3-3220 (update_interval=3.5s, max 3 windows)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

CONKY_CONFIG_DIR="${HOME}/.config/conky"
LOCAL_BIN="${HOME}/.local/bin"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 6
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 6: Stopping Conky Widgets..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would stop Conky, remove widget configs and autostart"
        return 0
    fi

    if command -v pkill &>/dev/null; then
        pkill -x conky 2>/dev/null || true
    fi

    rm -f "${HOME}/.config/autostart/conky.desktop"
    rm -f "${LOCAL_BIN}/conky-manager.sh"
    rm -f "${LOCAL_BIN}/weather-cache.sh"
    rm -f "/tmp/wttr_cache.txt"
    rm -rf "${CONKY_CONFIG_DIR}"

    log_success "Phase 6 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 6: Starting Conky Widgets Configuration (3 Windows, 3.5s Interval)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 6

# ------------------------------------------------------------------------------
# 2. Dependency Checks (conky-all, curl, lm-sensors, playerctl)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=(
    "conky-all"
    "curl"
    "lm-sensors"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Deploy Conky Helper Utilities
# ------------------------------------------------------------------------------
run mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/weather-cache.sh" "${LOCAL_BIN}/weather-cache.sh"
run chmod +x "${LOCAL_BIN}/weather-cache.sh"

safe_copy "${SCRIPTS_DIR}/conky-manager.sh" "${LOCAL_BIN}/conky-manager.sh"
run chmod +x "${LOCAL_BIN}/conky-manager.sh"

# Pre-populate weather cache
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would populate weather cache via weather-cache.sh"
else
    bash "${LOCAL_BIN}/weather-cache.sh" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 4. Deploy 3 Conky Window Configurations
# ------------------------------------------------------------------------------
run mkdir -p "${CONKY_CONFIG_DIR}"

safe_copy "${CONFIG_DIR}/conky/clock-weather.conkyrc" "${CONKY_CONFIG_DIR}/clock-weather.conkyrc"
safe_copy "${CONFIG_DIR}/conky/calendar-system.conkyrc" "${CONKY_CONFIG_DIR}/calendar-system.conkyrc"
safe_copy "${CONFIG_DIR}/conky/media-notes.conkyrc" "${CONKY_CONFIG_DIR}/media-notes.conkyrc"

# ------------------------------------------------------------------------------
# 5. Safety Test & Register Delayed Autostart
# ------------------------------------------------------------------------------
TEST_PASSED=0
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would verify conky binary"
    TEST_PASSED=1
elif command -v conky &>/dev/null; then
    TEST_PASSED=1
    log_success "Conky binary verified."
fi

if [[ "${TEST_PASSED}" -eq 1 ]]; then
    install_delayed_autostart "conky" "${LOCAL_BIN}/conky-manager.sh start" "macOS Sequoia Conky Widgets"
fi

# Reload in active X11 session if present
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would start Conky widget manager"
elif [[ -n "${DISPLAY:-}" ]] && command -v conky &>/dev/null; then
    bash "${LOCAL_BIN}/conky-manager.sh" start || log_warn "Conky start deferred."
fi

log_success "Phase 6 Complete: 3 Conky widget windows configured (Cached weather & sensors)."
log_info "Manage widgets anytime with: ~/.local/bin/conky-manager.sh [start|stop|restart]"
log_info "Undo this phase anytime with: ./phases/06-widgets.sh --undo (or ./uninstall.sh -p 6)"
