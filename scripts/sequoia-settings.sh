#!/usr/bin/env bash
# ==============================================================================
# Sequoia Settings Control Panel (On-Demand GUI)
# Fast, lightweight graphical configuration panel using YAD.
# Zero resident background processes; exits immediately after applying.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL_BIN="${SCRIPT_DIR}/sequoia-ctl"

if ! command -v yad &>/dev/null; then
    if command -v zenity &>/dev/null; then
        CHOICE="$(zenity --list --title="Sequoia Theme Presets" --column="Preset" \
            "default" "vibrant" "sequoia-dark" "enterprise" --height=260 --width=300 || true)"
        if [[ -n "${CHOICE}" ]]; then
            "${CTL_BIN}" preset "${CHOICE}"
            zenity --info --text="Preset '${CHOICE}' applied successfully!" --timeout=3 || true
        fi
        exit 0
    else
        echo "GUI helper requires 'yad' or 'zenity'. Use 'sequoia-ctl' in terminal."
        "${CTL_BIN}" status
        exit 0
    fi
fi

# YAD multi-field form
RESULT=$(yad --form --title="macOS Sequoia Desktop Settings" \
    --window-icon="preferences-desktop-theme" \
    --width=460 --height=400 --center --separator="|" \
    --text="<b>Configure Appearance, Top Bar Glass, Widgets, and Layout</b>" \
    --field="Theme Preset:CB" "vibrant!default!sequoia-dark!enterprise" \
    --field="Top Bar Transparent Glass:CHK" TRUE \
    --field="Widgets Borderless Floating:CHK" TRUE \
    --field="Widgets Vibrant High-Contrast:CHK" TRUE \
    --field="Compositor Profile:CB" "lite (0-blur, fast)!glass (kawase blur)" \
    --field="Edit Mode (Unlock Panel Dragging):CHK" FALSE \
    --field="Compositor Safe Mode (Fallback):CHK" FALSE \
    --button="gtk-cancel:1" \
    --button="Apply Settings:0" || true)

[[ -z "${RESULT}" ]] && exit 0

PRESET="$(echo "${RESULT}" | cut -d'|' -f1)"
TOP_TRANS="$(echo "${RESULT}" | cut -d'|' -f2)"
WID_BORDERLESS="$(echo "${RESULT}" | cut -d'|' -f3)"
WID_VIBRANT="$(echo "${RESULT}" | cut -d'|' -f4)"
COMP_PROFILE="$(echo "${RESULT}" | cut -d'|' -f5)"
EDIT_MODE="$(echo "${RESULT}" | cut -d'|' -f6)"
SAFE_MODE="$(echo "${RESULT}" | cut -d'|' -f7)"

# 1. Apply preset
if [[ -n "${PRESET}" ]]; then
    "${CTL_BIN}" preset "${PRESET}"
fi

# 2. Toggle Edit Mode
if [[ "${EDIT_MODE}" == "TRUE" ]]; then
    "${CTL_BIN}" edit on
else
    "${CTL_BIN}" edit off
fi

# 3. Toggle Safe Mode
if [[ "${SAFE_MODE}" == "TRUE" ]]; then
    "${CTL_BIN}" safe-mode on
else
    # 4. Check profile switcher
    if [[ "${COMP_PROFILE}" =~ glass ]]; then
        "${SCRIPT_DIR}/lite-mode.sh" glass || true
    else
        "${SCRIPT_DIR}/lite-mode.sh" lite || true
    fi
fi

yad --info --title="Settings Applied" --text="Settings applied successfully!" --timeout=2 --no-buttons || true
exit 0
