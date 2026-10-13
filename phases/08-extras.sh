#!/usr/bin/env bash
# ==============================================================================
# Phase 8: System Extras (Mission Control, Control Center, macOS Hotkeys)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

LOCAL_BIN="${HOME}/.local/bin"
XFDASHBOARD_THEME_DIR="${HOME}/.local/share/xfdashboard/themes/Sequoia"
KB_CHANNEL="xfce4-keyboard-shortcuts"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 8
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 8: Removing Extras & macOS Hotkeys..."

    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>c" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>Up" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/F3" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>q" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>m" -r -R 2>/dev/null || true
        xfconf-query -c "${KB_CHANNEL}" -p "/commands/custom/<Super>f" -r -R 2>/dev/null || true
    fi

    rm -f "${LOCAL_BIN}/mission-control.sh"
    rm -f "${LOCAL_BIN}/control-center.sh"
    rm -rf "${XFDASHBOARD_THEME_DIR}"

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase8 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded shortcuts from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial restore warning."
    fi

    log_success "Phase 8 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 8: Configuring Extras (Mission Control, Control Center, Hotkeys)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 8

# ------------------------------------------------------------------------------
# 2. Dependency Checks (playerctl, libnotify-bin)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=(
    "libnotify-bin"
    "playerctl"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Deploy Executable Wrappers
# ------------------------------------------------------------------------------
mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/mission-control.sh" "${LOCAL_BIN}/mission-control.sh"
safe_copy "${SCRIPTS_DIR}/control-center.sh" "${LOCAL_BIN}/control-center.sh"
chmod +x "${LOCAL_BIN}/mission-control.sh" "${LOCAL_BIN}/control-center.sh"

# ------------------------------------------------------------------------------
# 4. Deploy xfdashboard Theme (if source exists)
# ------------------------------------------------------------------------------
if [[ -d "${CONFIG_DIR}/xfdashboard" ]]; then
    mkdir -p "${XFDASHBOARD_THEME_DIR}"
    safe_sync_dir "${CONFIG_DIR}/xfdashboard" "${XFDASHBOARD_THEME_DIR}"
fi

# ------------------------------------------------------------------------------
# 5. Bind macOS-Style System Hotkeys
# ------------------------------------------------------------------------------
log_info "Configuring macOS-style hotkeys via xfconf..."

# Mission Control: Super+Up and F3
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>Up" "string" "${LOCAL_BIN}/mission-control.sh"
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F3" "string" "${LOCAL_BIN}/mission-control.sh"

# Control Center: Super+C
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>c" "string" "${LOCAL_BIN}/control-center.sh"

# Window Control Hotkeys:
# Super+Q: Close active window (mapped to Alt+F4 equivalent via xdotool or xfwm4)
if command -v xdotool &>/dev/null; then
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>q" "string" "xdotool getactivewindow windowclose"
fi

# Set xfwm4 window manager keys
set_xfconf_prop "xfwm4" "/general/cycle_windows_key" "string" "<Super>Tab"
set_xfconf_prop "xfwm4" "/general/hide_window_key" "string" "<Super>m"
set_xfconf_prop "xfwm4" "/general/fullscreen_key" "string" "<Super>f"

log_success "Phase 8 Complete: Mission Control, Control Center, and hotkeys active."
log_info "Undo this phase anytime with: ./phases/08-extras.sh --undo (or ./uninstall.sh -p 8)"
