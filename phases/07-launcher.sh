#!/usr/bin/env bash
# ==============================================================================
# Phase 7: Application Launchers (Rofi Spotlight & Launchpad)
# Keybindings: Super+Space (Spotlight), Super+A and F4 (Launchpad)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

ROFI_CONFIG_DIR="${HOME}/.config/rofi"
LOCAL_BIN="${HOME}/.local/bin"
KB_CHANNEL="xfce4-keyboard-shortcuts"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 7
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 7: Removing Rofi Themes & Shortcuts..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would revert Rofi themes, scripts, and shortcut keybindings"
        return 0
    fi

    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>space" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>a" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/F4" -r -R 2>/dev/null || true
    fi

    rm -f "${ROFI_CONFIG_DIR}/spotlight.rasi"
    rm -f "${ROFI_CONFIG_DIR}/launchpad.rasi"
    rm -f "${LOCAL_BIN}/spotlight.sh"
    rm -f "${LOCAL_BIN}/launchpad.sh"

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase7 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded shortcuts from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial restore warning."
    fi

    log_success "Phase 7 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 7: Configuring Launchers (Spotlight: Super+Space, Launchpad: Super+A)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 7

# ------------------------------------------------------------------------------
# 2. Dependency Checks (rofi)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=("rofi")
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Deploy Rofi Themes
# ------------------------------------------------------------------------------
run mkdir -p "${ROFI_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/rofi/spotlight.rasi" "${ROFI_CONFIG_DIR}/spotlight.rasi"
safe_copy "${CONFIG_DIR}/rofi/launchpad.rasi" "${ROFI_CONFIG_DIR}/launchpad.rasi"

# ------------------------------------------------------------------------------
# 4. Deploy Launcher Executables
# ------------------------------------------------------------------------------
run mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/spotlight.sh" "${LOCAL_BIN}/spotlight.sh"
safe_copy "${SCRIPTS_DIR}/launchpad.sh" "${LOCAL_BIN}/launchpad.sh"
run chmod +x "${LOCAL_BIN}/spotlight.sh" "${LOCAL_BIN}/launchpad.sh"

# ------------------------------------------------------------------------------
# 5. Apply Desktop Shortcuts via Central Shortcuts Manager
# ------------------------------------------------------------------------------
log_info "Applying desktop keyboard shortcuts via sequoia-ctl keys..."
if [[ -x "${LOCAL_BIN}/sequoia-ctl" ]]; then
    "${LOCAL_BIN}/sequoia-ctl" keys apply || true
elif [[ -x "${SCRIPTS_DIR}/sequoia-ctl" ]]; then
    "${SCRIPTS_DIR}/sequoia-ctl" keys apply || true
fi

log_success "Phase 7 Complete: Spotlight & Launchpad installed."
log_info "Test directly with: ~/.local/bin/spotlight.sh or ~/.local/bin/launchpad.sh"
log_info "Undo this phase anytime with: ./phases/07-launcher.sh --undo (or ./uninstall.sh -p 7)"
