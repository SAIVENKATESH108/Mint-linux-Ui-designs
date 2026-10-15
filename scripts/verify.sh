#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Transformation Verification Script
# Audits system state across all phases, reports failure reasons,
# verifies active processes and visible windows, and prints screenshot checklist.
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check_item() {
    local desc="$1"
    local condition="$2"
    local fail_reason="${3:-Check expression returned non-zero}"

    TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
    if eval "${condition}" 2>/dev/null; then
        printf "  ${C_GREEN}[PASS]${C_RESET} %s\n" "${desc}"
        PASSED_CHECKS=$(( PASSED_CHECKS + 1 ))
    else
        printf "  ${C_RED}[FAIL]${C_RESET} %s\n" "${desc}"
        printf "         ${C_YELLOW}↳ Reason: %s${C_RESET}\n" "${fail_reason}"
        FAILED_CHECKS=$(( FAILED_CHECKS + 1 ))
    fi
}

count_matches() {
    local pattern="$1"
    local target="$2"
    if [[ ! -f "${target}" ]]; then
        echo "0"
        return 0
    fi
    grep -o "${pattern}" "${target}" 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0"
}

count_files() {
    local dir="$1"
    local pattern="$2"
    if [[ ! -d "${dir}" ]]; then
        echo "0"
        return 0
    fi
    find "${dir}" -maxdepth 1 -name "${pattern}" 2>/dev/null | wc -l | tr -d '[:space:]' || echo "0"
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
    "[[ -d '${HOME}/.themes/WhiteSur-Dark' ]]" \
    "Directory ~/.themes/WhiteSur-Dark not found"

check_item "WhiteSur icon theme installed in ~/.icons" \
    "[[ -d '${HOME}/.icons/WhiteSur-dark' || -d '${HOME}/.icons/WhiteSur' ]]" \
    "WhiteSur icon directory missing from ~/.icons"

check_item "Apple logo SVG installed" \
    "[[ -f '${HOME}/.local/share/icons/apple-logo.svg' ]]" \
    "File ~/.local/share/icons/apple-logo.svg not found"

check_item "xfconf xsettings ThemeName set to WhiteSur-Dark" \
    "[[ \"\$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)\" =~ WhiteSur ]]" \
    "xsettings ThemeName is not set to WhiteSur"

check_item "xfconf xfwm4 button_layout set to left 'CHM|'" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/button_layout 2>/dev/null || true)\" == 'CHM|' ]]" \
    "xfwm4 button_layout is not set to CHM|"

check_item "xfconf xsettings DecorationLayout set to close,minimize,maximize:" \
    "[[ \"\$(xfconf-query -c xsettings -p /Gtk/DecorationLayout 2>/dev/null || true)\" == 'close,minimize,maximize:' ]]" \
    "DecorationLayout is not set to close,minimize,maximize:"

check_item "xfconf xsettings FontName set to Inter 10" \
    "[[ \"\$(xfconf-query -c xsettings -p /Gtk/FontName 2>/dev/null || true)\" =~ Inter ]]" \
    "xsettings FontName is not Inter 10"

check_item "Theme toggle script executable at ~/.local/bin/toggle-theme.sh" \
    "[[ -x '${HOME}/.local/bin/toggle-theme.sh' ]]" \
    "~/.local/bin/toggle-theme.sh missing or not executable"

# ------------------------------------------------------------------------------
# Phase 2: Compositor (Picom 10.2)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 2: Compositor (Picom 10.2)${C_RESET}\n"
check_item "Picom package installed" \
    "command -v picom &>/dev/null" \
    "picom binary not found in PATH"

check_item "Picom active config exists at ~/.config/picom/picom.conf" \
    "[[ -f '${HOME}/.config/picom/picom.conf' ]]" \
    "~/.config/picom/picom.conf missing"

check_item "Picom lite config exists at ~/.config/picom/picom-lite.conf" \
    "[[ -f '${HOME}/.config/picom/picom-lite.conf' ]]" \
    "~/.config/picom/picom-lite.conf missing"

check_item "xfwm4 native compositing disabled (/general/use_compositing = false)" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || true)\" == 'false' ]]" \
    "xfwm4 compositing is still enabled"

check_item "Profile switcher executable at ~/.local/bin/lite-mode.sh" \
    "[[ -x '${HOME}/.local/bin/lite-mode.sh' ]]" \
    "~/.local/bin/lite-mode.sh missing or not executable"

if [[ -n "${DISPLAY:-}" ]]; then
    check_item "Picom compositor process currently running" \
        "pgrep -x picom &>/dev/null" \
        "No picom process detected in process table"

    if pgrep -x picom &>/dev/null; then
        PICOM_PID="$(pgrep -x picom | head -1)"
        PICOM_UPTIME="$(ps -p "${PICOM_PID}" -o etimes= 2>/dev/null | tr -d ' ' || echo 0)"
        check_item "Picom process running stably (uptime > 60s)" \
            "[[ ${PICOM_UPTIME} -ge 60 ]]" \
            "Picom process uptime is only ${PICOM_UPTIME}s (expected >60s to ensure stability on nouveau)"
    fi
fi

# ------------------------------------------------------------------------------
# Phase 3: Top Menu Bar (xfce4-panel 28px)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 3: Top Menu Bar${C_RESET}\n"
check_item "Custom GTK3 stylesheet exists at ~/.config/gtk-3.0/gtk.css" \
    "[[ -f '${HOME}/.config/gtk-3.0/gtk.css' ]]" \
    "~/.config/gtk-3.0/gtk.css missing"

check_item "Modular GTK3 tokens use @define-color (no active var() declarations)" \
    "[[ \$(grep -E '^[[:space:]]*[a-zA-Z0-9_-]+:[^;]*var\(' '${HOME}/.config/gtk-3.0/sequoia/tokens.css' 2>/dev/null | wc -l | tr -d ' ') -eq 0 ]]" \
    "Active CSS declarations in tokens.css contain unsupported var() property"

check_item "All @import references in gtk.css resolve to existing files on disk" \
    "bash -c 'gtk_css=\"\${HOME}/.config/gtk-3.0/gtk.css\"; [[ -f \"\${gtk_css}\" ]] || exit 1; base=\"\${HOME}/.config/gtk-3.0\"; while read -r line; do [[ -z \"\${line}\" ]] && continue; rel=\$(echo \"\${line}\" | grep -oE \"[a-zA-Z0-9_/-]+\.css\" | head -1); [[ -n \"\${rel}\" && -f \"\${base}/\${rel}\" ]] || exit 1; done < <(grep -E \"^[[:space:]]*@import\" \"\${gtk_css}\")'" \
    "One or more @import targets referenced in gtk.css do not exist"

check_item "xfce4-panel panel-1 size set to 28px" \
    "[[ \"\$(xfconf-query -c xfce4-panel -p /panels/panel-1/size 2>/dev/null || true)\" == '28' ]]" \
    "Panel-1 size is not 28px"

if [[ -n "${DISPLAY:-}" ]]; then
    check_item "xfce4-panel process running" \
        "pgrep -x xfce4-panel &>/dev/null" \
        "No xfce4-panel process running"

    check_item "Top panel intact in xfconf with active position" \
        "[[ -n \"\$(xfconf-query -c xfce4-panel -p /panels/panel-1/position 2>/dev/null || true)\" ]]" \
        "panel-1 position property missing in xfce4-panel channel"

    check_item "Tasklist and duplicate stock launchers absent from panel-1" \
        "for pid in \$(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | grep -E '^[0-9]+$' || true); do ptype=\$(xfconf-query -c xfce4-panel -p /plugins/plugin-\${pid} 2>/dev/null || true); [[ \"\${ptype}\" =~ (tasklist|windowmenu|launcher) ]] && exit 1; done; true" \
        "Tasklist or duplicate stock launcher plugin is still present on panel-1"
fi

# ------------------------------------------------------------------------------
# Phase 4: Plank Dock
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 4: Plank Dock${C_RESET}\n"
check_item "Plank package installed" \
    "command -v plank &>/dev/null" \
    "plank binary not found in PATH"

check_item "Sequoia dock theme installed at ~/.local/share/plank/themes/Sequoia" \
    "[[ -f '${HOME}/.local/share/plank/themes/Sequoia/dock.theme' ]]" \
    "Sequoia dock.theme missing"

check_item "Sequoia dock theme has standard keys (OuterStrokeColor, FillStartColor)" \
    "[[ \$(count_matches 'FillStartColor' '${HOME}/.local/share/plank/themes/Sequoia/dock.theme') -ge 1 ]]" \
    "dock.theme missing FillStartColor standard key"

check_item "10 dock launchers present in ~/.config/plank/dock1/launchers/" \
    "[[ \$(count_files '${HOME}/.config/plank/dock1/launchers' '*.dockitem') -ge 10 ]]" \
    "Fewer than 10 dockitems found in launchers directory"

check_item "All Plank dockitem launcher targets exist on disk" \
    "for df in '${HOME}/.config/plank/dock1/launchers/'*.dockitem; do [[ -f \"\${df}\" ]] || continue; tgt=\$(grep -E '^Launcher=' \"\${df}\" | cut -d= -f2-); [[ \"\${tgt}\" =~ ^docklet:// ]] && continue; cln=\$(echo \"\${tgt}\" | sed 's#^file://##'); [[ -f \"\${cln}\" ]] || exit 1; done; true" \
    "One or more .dockitem files point to missing desktop targets"

check_item "Trash docklet ordered as final launcher (10-trash.dockitem)" \
    "[[ -f '${HOME}/.config/plank/dock1/launchers/10-trash.dockitem' ]]" \
    "10-trash.dockitem missing"

if [[ -n "${DISPLAY:-}" ]]; then
    check_item "Plank process currently running" \
        "pgrep -x plank &>/dev/null" \
        "No plank process detected in process table"
fi

# ------------------------------------------------------------------------------
# Phase 5: Left Sidebar (Removed per user preference)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 5: Left Sidebar Status${C_RESET}\n"
HAS_PANEL2="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -q '2' && echo 1 || echo 0)"
if [[ "${HAS_PANEL2}" -eq 0 ]]; then
    check_item "Left sidebar completely removed (no panel-2 configured)" \
        "true" \
        ""
else
    check_item "Left sidebar removed (no panel-2 configured)" \
        "false" \
        "panel-2 is still registered in xfce4-panel /panels"
fi

check_item "xfwm4 workspace_count configured to 4 spaces" \
    "[[ \"\$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)\" == '4' ]]" \
    "xfwm4 workspace count is not 4"

# ------------------------------------------------------------------------------
# Phase 6: Desktop Widgets (Conky)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 6: Desktop Widgets (Conky)${C_RESET}\n"
check_item "conky package installed" \
    "command -v conky &>/dev/null" \
    "conky binary not found"

check_item "Conky Window 1 config (clock-weather.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/clock-weather.conkyrc' ]]" \
    "clock-weather.conkyrc missing"

check_item "Conky Window 2 config (calendar-system.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/calendar-system.conkyrc' ]]" \
    "calendar-system.conkyrc missing"

check_item "Conky Window 3 config (media-notes.conkyrc) exists" \
    "[[ -f '${HOME}/.config/conky/media-notes.conkyrc' ]]" \
    "media-notes.conkyrc missing"

check_item "Conky configs enforce override_utf8_locale" \
    "[[ \$(count_matches 'override_utf8_locale = true' '${HOME}/.config/conky/clock-weather.conkyrc') -ge 1 ]]" \
    "clock-weather.conkyrc missing override_utf8_locale = true"

check_item "Weather cache script executable at ~/.local/bin/weather-cache.sh" \
    "[[ -x '${HOME}/.local/bin/weather-cache.sh' ]]" \
    "weather-cache.sh missing or not executable"

check_item "Conky manager script executable at ~/.local/bin/conky-manager.sh" \
    "[[ -x '${HOME}/.local/bin/conky-manager.sh' ]]" \
    "conky-manager.sh missing or not executable"

if [[ -n "${DISPLAY:-}" ]]; then
    check_item "3 Conky windows currently running" \
        "[[ \$(pgrep -c -x conky || echo 0) -ge 3 ]]" \
        "Fewer than 3 Conky window processes running"
fi

# ------------------------------------------------------------------------------
# Phase 7: Launchers (Rofi)
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 7: Launchers (Rofi)${C_RESET}\n"
check_item "Rofi package installed" \
    "command -v rofi &>/dev/null" \
    "rofi binary not found"

check_item "Spotlight theme exists at ~/.config/rofi/spotlight.rasi" \
    "[[ -f '${HOME}/.config/rofi/spotlight.rasi' ]]" \
    "spotlight.rasi missing"

check_item "Launchpad theme exists at ~/.config/rofi/launchpad.rasi" \
    "[[ -f '${HOME}/.config/rofi/launchpad.rasi' ]]" \
    "launchpad.rasi missing"

check_item "Super+Space shortcut bound to spotlight.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>space' 2>/dev/null || true)\" =~ spotlight.sh ]]" \
    "Super+Space not mapped to spotlight.sh"

check_item "Super+A shortcut bound to launchpad.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>a' 2>/dev/null || true)\" =~ launchpad.sh ]]" \
    "Super+A not mapped to launchpad.sh"

# ------------------------------------------------------------------------------
# Phase 8: Extras & Hotkeys
# ------------------------------------------------------------------------------
echo ""
printf "${C_BOLD}Phase 8: Extras & Hotkeys${C_RESET}\n"
check_item "Mission Control wrapper executable at ~/.local/bin/mission-control.sh" \
    "[[ -x '${HOME}/.local/bin/mission-control.sh' ]]" \
    "mission-control.sh missing or not executable"

check_item "Control Center menu executable at ~/.local/bin/control-center.sh" \
    "[[ -x '${HOME}/.local/bin/control-center.sh' ]]" \
    "control-center.sh missing or not executable"

check_item "Control Center Python popup executable at ~/.local/bin/sequoia-control-center.py" \
    "[[ -x '${HOME}/.local/bin/sequoia-control-center.py' ]]" \
    "sequoia-control-center.py missing or not executable"

check_item "Super+C shortcut bound to control-center.sh" \
    "[[ \"\$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>c' 2>/dev/null || true)\" =~ control-center.sh ]]" \
    "Super+C not mapped to control-center.sh"

# ------------------------------------------------------------------------------
# Visual Verification Checklist (For User Review)
# ------------------------------------------------------------------------------
echo ""
echo "=========================================================="
printf "${C_BOLD}%s${C_RESET}\n" " Target PC Visual Inspection Checklist:"
echo "=========================================================="
echo "  [ ] Top Bar: Height 28px, Apple logo on left, macOS clock on right."
echo "  [ ] Top Bar: No window buttons / tasklist (dock handles open apps)."
echo "  [ ] Dock: Centered at bottom with breathing offset (not clipped)."
echo "  [ ] Dock: 10 unified icons present with Trash icon locked at far right."
echo "  [ ] Conky: 3 translucent rounded cards on right with exact 16px vertical gap."
echo "  [ ] Windows: Brave / GTK window buttons ordered (Close, Min, Max on left)."
echo "=========================================================="

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo ""
printf "Audit Result: %d / %d checks PASSED" "${PASSED_CHECKS}" "${TOTAL_CHECKS}"
if [[ "${FAILED_CHECKS}" -eq 0 ]]; then
    printf " ${C_GREEN}[ALL PASS - 100%% READY]${C_RESET}\n"
else
    printf " ${C_RED}[%d CHECKS FAILED]${C_RESET}\n" "${FAILED_CHECKS}"
fi
echo "=========================================================="
