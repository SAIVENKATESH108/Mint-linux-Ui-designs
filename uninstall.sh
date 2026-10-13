#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Desktop Reversal & Rollback Tool
# Matches undo steps for all phases in ./phases/
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

verify_environment

log_info "Initiating Rollback / Uninstall Process"

TARGET_PHASE="all"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase|-p)
            TARGET_PHASE="$2"
            shift 2
            ;;
        --all)
            TARGET_PHASE="all"
            shift
            ;;
        *)
            log_warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Attempt to execute latest xfconf restore script if available
restore_latest_xfconf() {
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/* 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying xfconf restore script from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf restore errors."
    fi
}

undo_phase_1() {
    log_info "Undoing Phase 1: Resetting Themes to Linux Mint Defaults..."
    set_xfconf_prop "xsettings" "/Net/ThemeName" "string" "Mint-Y-Dark"
    set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "Mint-Y"
    set_xfconf_prop "xfwm4" "/general/theme" "string" "Mint-Y-Dark"
    set_xfconf_prop "xsettings" "/Gtk/CursorThemeName" "string" "DMZ-White"
    set_xfconf_prop "xsettings" "/Gtk/FontName" "string" "Ubuntu 10"
    log_success "Phase 1 undone."
}

undo_phase_2() {
    log_info "Undoing Phase 2: Restoring xfwm4 and stopping Picom..."
    # Re-enable xfwm4 native compositing
    set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "true"
    # Restore traditional button layout (Option, Title | Minimize, Maximize, Close)
    set_xfconf_prop "xfwm4" "/general/button_layout" "string" "O|HMC"
    set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "left"
    
    # Remove picom autostart and kill running instances
    rm -f "${HOME}/.config/autostart/picom.desktop"
    killall picom 2>/dev/null || true
    log_success "Phase 2 undone."
}

undo_phase_3() {
    log_info "Undoing Phase 3: Removing GTK3 custom CSS and resetting panel..."
    rm -f "${HOME}/.config/gtk-3.0/gtk.css"
    # If a backup of xfce4-panel.xml exists, point user or reload
    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r 2>/dev/null || true
    fi
    log_success "Phase 3 undone."
}

undo_phase_4() {
    log_info "Undoing Phase 4: Stopping Plank and removing autostart..."
    rm -f "${HOME}/.config/autostart/plank.desktop"
    rm -rf "${HOME}/.local/share/plank/themes/Sequoia"
    killall plank 2>/dev/null || true
    log_success "Phase 4 undone."
}

undo_phase_5() {
    log_info "Undoing Phase 5: Removing Rofi configs and shortcuts..."
    rm -f "${HOME}/.config/rofi/spotlight.rasi"
    rm -f "${HOME}/.config/rofi/launchpad.rasi"
    rm -f "${HOME}/.local/bin/spotlight.sh"
    rm -f "${HOME}/.local/bin/launchpad.sh"
    rm -f "${HOME}/.local/bin/mission-control.sh"
    rm -rf "${HOME}/.local/share/xfdashboard/themes/Sequoia"

    # Reset shortcuts
    xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>space" -r -R 2>/dev/null || true
    xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/F4" -r -R 2>/dev/null || true
    xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>a" -r -R 2>/dev/null || true
    xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/F3" -r -R 2>/dev/null || true
    xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>Up" -r -R 2>/dev/null || true
    log_success "Phase 5 undone."
}

undo_phase_6() {
    log_info "Undoing Phase 6: Stopping Conky and removing widget..."
    rm -f "${HOME}/.config/autostart/conky-sequoia.desktop"
    rm -f "${HOME}/.config/conky/sequoia-glance.conkyrc"
    killall conky 2>/dev/null || true
    log_success "Phase 6 undone."
}

case "${TARGET_PHASE}" in
    1) undo_phase_1 ;;
    2) undo_phase_2 ;;
    3) undo_phase_3 ;;
    4) undo_phase_4 ;;
    5) undo_phase_5 ;;
    6) undo_phase_6 ;;
    all)
        undo_phase_6
        undo_phase_5
        undo_phase_4
        undo_phase_3
        undo_phase_2
        undo_phase_1
        restore_latest_xfconf
        log_success "All phases reverted successfully."
        ;;
    *)
        log_error "Invalid phase number: ${TARGET_PHASE}"
        exit 1
        ;;
esac
