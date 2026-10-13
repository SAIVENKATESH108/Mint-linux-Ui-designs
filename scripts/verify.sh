#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Transformation Verification Script
# Audits system state across all 8 phases and prints [PASS] / [FAIL] summary
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_BLUE="\033[1;34m"

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check_item() {
    local desc="$1"
    local condition="$2"

    TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
    if eval "${condition}"; then
        printf "  ${C_GREEN}[PASS]${C_RESET} %s\n" "${desc}"
        PASSED_CHECKS=$(( PASSED_CHECKS + 1 ))
    else
        printf "  ${C_RED}[FAIL]${C_RESET} %s\n" "${desc}"
        FAILED_CHECKS=$(( FAILED_CHECKS + 1 ))
    fi
}

echo "=========================================================="
printf "${C_BLUE}${C_BOLD}%s${C_RESET}\n" " macOS Sequoia Transformation Integrity Audit"
echo " Target: Linux Mint 22.3 XFCE (HDMI-1 1280x1024 @ 60Hz)"
echo "=========================================================="

# ------------------------------------------------------------------------------
# Phase 1: Theme & Visual Assets
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 1: Theme & Visual Assets${C_RESET}\n"
check_item "WhiteSur-Dark GTK theme installed in ~/.themes" \
    "[[ -d '${HOME}/.themes/WhiteSur-Dark' ]]"
check_item "WhiteSur icon theme installed in ~/.icons" \
    "[[ -d '${HOME}/.icons/WhiteSur-dark' || -d '${HOME}/.icons/WhiteSur' ]]"
check_item "Apple logo SVG installed" \
    "[[ -f '${HOME}/.local/share/icons/apple-logo.svg' ]]"
check_item "xfconf xsettings ThemeName set to WhiteSur-Dark" \
    "[[ \"\$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)\" =~ WhiteSur ]]"
check_item "xfconf xfwm4 button_layout set to left 'CHM|'" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/button_layout 2>/dev/null || true)\" == 'CHM|' ]]"
check_item "xfconf xsettings FontName set to Inter 10" \
    "[[ \"\$(xfconf-query -c xsettings -p /Gtk/FontName 2>/dev/null || true)\" =~ Inter ]]"
check_item "Theme toggle script executable at ~/.local/bin/toggle-theme.sh" \
    "[[ -x '${HOME}/.local/bin/toggle-theme.sh' ]]"

# ------------------------------------------------------------------------------
# Phase 2: Compositor (Picom 10.2)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 2: Compositor (Picom 10.2)${C_RESET}\n"
check_item "Picom package installed" \
    "command -v picom &>/dev/null"
check_item "Picom active config exists at ~/.config/picom/picom.conf" \
    "[[ -f '${HOME}/.config/picom/picom.conf' ]]"
check_item "Picom lite config exists at ~/.config/picom/picom-lite.conf" \
    "[[ -f '${HOME}/.config/picom/picom-lite.conf' ]]"
check_item "xfwm4 native compositing disabled (/general/use_compositing = false)" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || true)\" == 'false' ]]"
check_item "Profile switcher executable at ~/.local/bin/lite-mode.sh" \
    "[[ -x '${HOME}/.local/bin/lite-mode.sh' ]]"
if [[ -n "${DISPLAY:-}" ]]; then
    check_item "Picom compositor process currently running" \
        "pgrep -x picom &>/dev/null"
fi

# ------------------------------------------------------------------------------
# Phase 3: Top Menu Bar (xfce4-panel 28px)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 3: Top Menu Bar${C_RESET}\n"
check_item "Custom GTK3 stylesheet exists at ~/.config/gtk-3.0/gtk.css" \
    "[[ -f '${HOME}/.config/gtk-3.0/gtk.css' ]]"
check_item "xfce4-panel panel-1 size set to 28px" \
    "[[ \"\$(xfconf-query -c xfce4-panel -p /panels/panel-1/size 2>/dev/null || true)\" == '28' ]]"
if [[ -n "${DISPLAY:-}" ]]; then
    check_item "xfce4-panel process running" \
        "pgrep -x xfce4-panel &>/dev/null"
fi

# ------------------------------------------------------------------------------
# Phase 4: Plank Dock
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 4: Plank Dock${C_RESET}\n"
check_item "Plank package installed" \
    "command -v plank &>/dev/null"
check_item "Sequoia dock theme installed at ~/.local/share/plank/themes/Sequoia" \
    "[[ -f '${HOME}/.local/share/plank/themes/Sequoia/dock.theme' ]]"
check_item "10 dock launchers present in ~/.config/plank/dock1/launchers/" \
    "[[ \$(ls '${HOME}/.config/plank/dock1/launchers/' 2>/dev/null | grep -c '\.dockitem$') -ge 8 ]]"
if [[ -n "${DISPLAY:-}" ]]; then
    check_item "Plank process currently running" \
        "pgrep -x plank &>/dev/null"
fi

# ------------------------------------------------------------------------------
# Phase 5: Left Sidebar
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 5: Left Sidebar (76px)${C_RESET}\n"
check_item "xfce4-panel panel-2 configured with size 76px" \
    "[[ \"\$(xfconf-query -c xfce4-panel -p /panels/panel-2/size 2>/dev/null || true)\" == '76' ]]"
check_item "xfwm4 workspace_count configured to 4 spaces" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)\" == '4' ]]"

# ------------------------------------------------------------------------------
# Phase 6: Desktop Widgets (Conky)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 6: Desktop Widgets (Conky)${C_RESET}\n"
check_item "conky package installed" \
    "command -v conky &>/dev/null"
check_item "Conky Window 1 config (clock-weather.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/clock-weather.conkyrc' ]]"
check_item "Conky Window 2 config (calendar-system.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/calendar-system.conkyrc' ]]"
check_item "Conky Window 3 config (media-notes.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/media-notes.conkyrc' ]]"
check_item "Weather cache script executable at ~/.local/bin/weather-cache.sh" \
    "[[ -x '${HOME}/.local/bin/weather-cache.sh' ]]"
check_item "Conky manager script executable at ~/.local/bin/conky-manager.sh" \
    "[[ -x '${HOME}/.local/bin/conky-manager.sh' ]]"
if [[ -n "${DISPLAY:-}" ]]; then
    check_item "3 Conky windows currently running" \
        "[[ \$(pgrep -c -x conky || echo 0) -ge 3 ]]"
fi

# ------------------------------------------------------------------------------
# Phase 7: Launchers (Rofi)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 7: Launchers (Rofi)${C_RESET}\n"
check_item "Rofi package installed" \
    "command -v rofi &>/dev/null"
check_item "Spotlight theme exists at ~/.config/rofi/spotlight.rasi" \
    "[[ -f '${HOME}/.config/rofi/spotlight.rasi' ]]"
check_item "Launchpad theme exists at ~/.config/rofi/launchpad.rasi" \
    "[[ -f '${HOME}/.config/rofi/launchpad.rasi' ]]"
check_item "Super+Space shortcut bound to spotlight.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>space' 2>/dev/null || true)\" =~ spotlight.sh ]]"
check_item "Super+A shortcut bound to launchpad.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>a' 2>/dev/null || true)\" =~ launchpad.sh ]]"

# ------------------------------------------------------------------------------
# Phase 8: Extras & Hotkeys
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 8: Extras & Hotkeys${C_RESET}\n"
check_item "Mission Control wrapper executable at ~/.local/bin/mission-control.sh" \
    "[[ -x '${HOME}/.local/bin/mission-control.sh' ]]"
check_item "Control Center menu executable at ~/.local/bin/control-center.sh" \
    "[[ -x '${HOME}/.local/bin/control-center.sh' ]]"
check_item "Super+C shortcut bound to control-center.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>c' 2>/dev/null || true)\" =~ control-center.sh ]]"

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo ""
echo "=========================================================="
printf "Audit Result: %d / %d checks PASSED" "${PASSED_CHECKS}" "${TOTAL_CHECKS}"
if [[ "${FAILED_CHECKS}" -eq 0 ]]; then
    printf " ${C_GREEN}[ALL PASS - 100%% READY]${C_RESET}\n"
else
    printf " ${C_RED}[%d CHECKS FAILED]${C_RESET}\n" "${FAILED_CHECKS}"
fi
echo "=========================================================="
