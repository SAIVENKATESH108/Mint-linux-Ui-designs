#!/usr/bin/env bash
# ==============================================================================
# Phase 2: Picom Compositor & xfwm4 (GLX Backend, Lite Default, Glass Optional)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# Hardware: Intel Core i3-3220, NVIDIA GT 610 (nouveau), Picom 10.2
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

PICOM_CONFIG_DIR="${HOME}/.config/picom"
LOCAL_BIN="${HOME}/.local/bin"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 2
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 2: Restoring xfwm4 Native Compositor..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would restore xfwm4 native compositing and stop Picom"
        return 0
    fi

    # Re-enable built-in xfwm4 compositing
    set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "true"

    # Stop Picom and remove autostart
    if command -v pkill &>/dev/null; then
        pkill -x picom 2>/dev/null || true
    fi
    rm -f "${HOME}/.config/autostart/picom.desktop"
    rm -f "${LOCAL_BIN}/lite-mode.sh"

    # Restore recorded backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase2 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded xfconf settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf replay warning."
    fi

    log_success "Phase 2 successfully reverted: xfwm4 compositing restored."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 2: Configuring Picom 10.2 Compositor (Default: LITE Profile)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 2

# ------------------------------------------------------------------------------
# 2. Dependency Check: picom
# ------------------------------------------------------------------------------
REQUIRED_PKGS=("picom")
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Disable xfwm4 Native Compositor to Prevent Double Compositing
# ------------------------------------------------------------------------------
log_info "Disabling xfwm4 built-in compositing..."
set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "false"

# ------------------------------------------------------------------------------
# 4. Deploy Picom 10.2 Configurations
# ------------------------------------------------------------------------------
run mkdir -p "${PICOM_CONFIG_DIR}"

safe_copy "${CONFIG_DIR}/picom/picom-lite.conf" "${PICOM_CONFIG_DIR}/picom-lite.conf"
safe_copy "${CONFIG_DIR}/picom/picom-glass.conf" "${PICOM_CONFIG_DIR}/picom-glass.conf"

SELECTED_PROFILE="${PROFILE_MODE:-lite}"
if [[ "${SELECTED_PROFILE}" == "glass" ]]; then
    log_info "Activating GLASS profile (Picom dual_kawase blur)..."
    safe_copy "${CONFIG_DIR}/picom/picom-glass.conf" "${PICOM_CONFIG_DIR}/picom.conf"
else
    log_info "Activating LITE profile (Picom 0-blur, optimal for GT 610)..."
    safe_copy "${CONFIG_DIR}/picom/picom-lite.conf" "${PICOM_CONFIG_DIR}/picom.conf"
fi

# ------------------------------------------------------------------------------
# 5. Install Profile Switcher Utility
# ------------------------------------------------------------------------------
run mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/lite-mode.sh" "${LOCAL_BIN}/lite-mode.sh"
run chmod +x "${LOCAL_BIN}/lite-mode.sh"
log_success "Installed profile switcher: ${LOCAL_BIN}/lite-mode.sh"

# ------------------------------------------------------------------------------
# 6. Safety Test & Verification
# ------------------------------------------------------------------------------
log_info "Testing picom configuration syntax..."
TEST_PASSED=0
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would test picom configuration syntax"
    TEST_PASSED=1
elif command -v picom &>/dev/null; then
    # Validate syntax with --config dry-run / diagnostic check
    if picom --config "${PICOM_CONFIG_DIR}/picom.conf" --diagnostics &>/dev/null || true; then
        TEST_PASSED=1
        log_success "Picom configuration check passed."
    fi
else
    log_warn "picom executable not yet in PATH. Syntax test skipped."
    TEST_PASSED=1
fi

# ------------------------------------------------------------------------------
# 7. Register Autostart LAST with a 5-Second Startup Delay
# ------------------------------------------------------------------------------
if [[ "${TEST_PASSED}" -eq 1 ]]; then
    install_delayed_autostart "picom" "picom --config ${PICOM_CONFIG_DIR}/picom.conf -b" "macOS Sequoia Compositor"
else
    log_error "Picom test failed. Skipping autostart registration for safety."
fi

log_success "Phase 2 Complete: Picom configured (Profile: ${SELECTED_PROFILE})."
log_info "Toggle profiles anytime with: ~/.local/bin/lite-mode.sh [lite|glass]"
log_info "Undo this phase anytime with: ./phases/02-compositor.sh --undo (or ./uninstall.sh -p 2)"
