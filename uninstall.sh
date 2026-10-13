#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Transformation Reversal Tool
# Supports: --phase <1-8> or --all
# Matches undo steps for all 8 phases in ./phases/
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

verify_environment

TARGET_PHASE="all"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            export DRY_RUN=1
            log_warn "DRY-RUN MODE ACTIVE: No files or xfconf settings will change."
            shift
            ;;
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

restore_latest_xfconf() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would replay latest xfconf restore script"
        return 0
    fi

    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/* 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying xfconf restore script from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf restore errors."
    fi
}

undo_phase_1() {
    log_info "Undoing Phase 1: Resetting Themes & Window Controls to Mint Defaults..."
    bash "${SCRIPT_DIR}/phases/01-theme.sh" --undo 2>/dev/null || {
        set_xfconf_prop "xsettings" "/Net/ThemeName" "string" "Mint-Y-Dark"
        set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "Mint-Y"
        set_xfconf_prop "xfwm4" "/general/theme" "string" "Mint-Y-Dark"
        set_xfconf_prop "xsettings" "/Gtk/CursorThemeName" "string" "DMZ-White"
        set_xfconf_prop "xsettings" "/Gtk/FontName" "string" "Ubuntu 10"
        set_xfconf_prop "xfwm4" "/general/title_font" "string" "Ubuntu Bold 9"
        set_xfconf_prop "xfwm4" "/general/button_layout" "string" "O|HMC"
        set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "left"
        set_xfconf_prop "xsettings" "/Gtk/DecorationLayout" "string" ":minimize,maximize,close"
        run rm -f "${HOME}/.local/bin/toggle-theme.sh"
    }
    log_success "Phase 1 undone."
}

undo_phase_2() {
    log_info "Undoing Phase 2: Restoring xfwm4 Native Compositor..."
    bash "${SCRIPT_DIR}/phases/02-compositor.sh" --undo 2>/dev/null || {
        set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "true"
        run rm -f "${HOME}/.config/autostart/picom.desktop"
        run rm -f "${HOME}/.local/bin/lite-mode.sh"
        if command -v pkill &>/dev/null; then
            run pkill -x picom 2>/dev/null || true
        fi
    }
    log_success "Phase 2 undone."
}

undo_phase_3() {
    log_info "Undoing Phase 3: Removing GTK3 custom CSS and resetting panel-1..."
    bash "${SCRIPT_DIR}/phases/03-top-bar.sh" --undo 2>/dev/null || {
        run rm -f "${HOME}/.config/gtk-3.0/gtk.css"
        set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "24"
        if command -v xfce4-panel &>/dev/null; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_dry "Would reload xfce4-panel"
            else
                xfce4-panel -r 2>/dev/null || true
            fi
        fi
    }
    log_success "Phase 3 undone."
}

undo_phase_4() {
    log_info "Undoing Phase 4: Stopping Plank and removing autostart..."
    bash "${SCRIPT_DIR}/phases/04-dock.sh" --undo 2>/dev/null || {
        run rm -f "${HOME}/.config/autostart/plank.desktop"
        run rm -rf "${HOME}/.local/share/plank/themes/Sequoia"
        run rm -rf "${HOME}/.config/plank/dock1/launchers"
        if command -v pkill &>/dev/null; then
            run pkill -x plank 2>/dev/null || true
        fi
    }
    log_success "Phase 4 undone."
}

undo_phase_5() {
    log_info "Undoing Phase 5: Removing Left Workspace Sidebar..."
    bash "${SCRIPT_DIR}/phases/05-left-sidebar.sh" --undo 2>/dev/null || {
        if command -v xfconf-query &>/dev/null; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_dry "Would remove panel-2 and set panel count to 1"
            else
                xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
                for pid in 20 21 22 23; do
                    xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" -r -R 2>/dev/null || true
                done
                set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
            fi
        fi
        if command -v xfce4-panel &>/dev/null; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_dry "Would reload xfce4-panel"
            else
                xfce4-panel -r 2>/dev/null || true
            fi
        fi
    }
    log_success "Phase 5 undone."
}

undo_phase_6() {
    log_info "Undoing Phase 6: Stopping Conky Widgets..."
    bash "${SCRIPT_DIR}/phases/06-widgets.sh" --undo 2>/dev/null || {
        run rm -f "${HOME}/.config/autostart/conky.desktop"
        run rm -f "${HOME}/.local/bin/conky-manager.sh"
        run rm -f "${HOME}/.local/bin/weather-cache.sh"
        run rm -rf "${HOME}/.config/conky"
        if command -v pkill &>/dev/null; then
            run pkill -x conky 2>/dev/null || true
        fi
    }
    log_success "Phase 6 undone."
}

undo_phase_7() {
    log_info "Undoing Phase 7: Removing Rofi Launchers & Shortcuts..."
    bash "${SCRIPT_DIR}/phases/07-launcher.sh" --undo 2>/dev/null || {
        if command -v xfconf-query &>/dev/null; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_dry "Would remove Rofi custom shortcuts"
            else
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>space" -r -R 2>/dev/null || true
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>a" -r -R 2>/dev/null || true
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/F4" -r -R 2>/dev/null || true
            fi
        fi
        run rm -f "${HOME}/.config/rofi/spotlight.rasi"
        run rm -f "${HOME}/.config/rofi/launchpad.rasi"
        run rm -f "${HOME}/.local/bin/spotlight.sh"
        run rm -f "${HOME}/.local/bin/launchpad.sh"
    }
    log_success "Phase 7 undone."
}

undo_phase_8() {
    log_info "Undoing Phase 8: Removing Extras & Hotkeys..."
    bash "${SCRIPT_DIR}/phases/08-extras.sh" --undo 2>/dev/null || {
        if command -v xfconf-query &>/dev/null; then
            if [[ "${DRY_RUN}" -eq 1 ]]; then
                log_dry "Would remove extras keyboard shortcuts"
            else
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>c" -r -R 2>/dev/null || true
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>Up" -r -R 2>/dev/null || true
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/F3" -r -R 2>/dev/null || true
                xfconf-query -c "xfce4-keyboard-shortcuts" -p "/commands/custom/<Super>q" -r -R 2>/dev/null || true
            fi
        fi
        run rm -f "${LOCAL_BIN}/mission-control.sh"
        run rm -f "${LOCAL_BIN}/control-center.sh"
    }
    log_success "Phase 8 undone."
}

case "${TARGET_PHASE}" in
    1) undo_phase_1 ;;
    2) undo_phase_2 ;;
    3) undo_phase_3 ;;
    4) undo_phase_4 ;;
    5) undo_phase_5 ;;
    6) undo_phase_6 ;;
    7) undo_phase_7 ;;
    8) undo_phase_8 ;;
    all)
        undo_phase_8
        undo_phase_7
        undo_phase_6
        undo_phase_5
        undo_phase_4
        undo_phase_3
        undo_phase_2
        undo_phase_1
        restore_latest_xfconf
        log_success "All 8 phases reverted successfully."
        ;;
    *)
        log_error "Invalid phase number: ${TARGET_PHASE}"
        exit 1
        ;;
esac
