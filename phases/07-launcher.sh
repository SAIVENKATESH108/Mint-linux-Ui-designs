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
mkdir -p "${ROFI_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/rofi/spotlight.rasi" "${ROFI_CONFIG_DIR}/spotlight.rasi"
safe_copy "${CONFIG_DIR}/rofi/launchpad.rasi" "${ROFI_CONFIG_DIR}/launchpad.rasi"

# ------------------------------------------------------------------------------
# 4. Deploy Launcher Executables
# ------------------------------------------------------------------------------
mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/spotlight.sh" "${LOCAL_BIN}/spotlight.sh"
safe_copy "${SCRIPTS_DIR}/launchpad.sh" "${LOCAL_BIN}/launchpad.sh"
chmod +x "${LOCAL_BIN}/spotlight.sh" "${LOCAL_BIN}/launchpad.sh"

# ------------------------------------------------------------------------------
# 5. Bind macOS Shortcuts via xfconf
# ------------------------------------------------------------------------------
log_info "Binding Super+Space (Spotlight) and Super+A / F4 (Launchpad)..."

# Spotlight: Super+Space
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>space" "string" "${LOCAL_BIN}/spotlight.sh"

# Launchpad: Super+A and F4
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>a" "string" "${LOCAL_BIN}/launchpad.sh"
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F4" "string" "${LOCAL_BIN}/launchpad.sh"

log_success "Phase 7 Complete: Spotlight (Super+Space) & Launchpad (Super+A / F4) active."
log_info "Test directly with: ~/.local/bin/spotlight.sh or ~/.local/bin/launchpad.sh"
log_info "Undo this phase anytime with: ./phases/07-launcher.sh --undo (or ./uninstall.sh -p 7)"
