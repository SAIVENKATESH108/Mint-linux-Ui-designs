#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Theme Mode Switcher (Light / Dark)
# Switches GTK application theme, icon theme, and xfwm4 window decorations
# ==============================================================================

set -euo pipefail

# Determine requested target or toggle current
TARGET="${1:-toggle}"

if ! command -v xfconf-query &>/dev/null; then
    echo "✖ Error: xfconf-query not found. This script must run inside an XFCE session." >&2
    exit 1
fi

CURRENT_THEME="$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo "WhiteSur-Dark")"

if [[ "${TARGET}" == "toggle" ]]; then
    if [[ "${CURRENT_THEME}" =~ [Dd]ark ]]; then
        TARGET="light"
    else
        TARGET="dark"
    fi
fi

case "${TARGET,,}" in
    light)
        echo "==> Switching to macOS Sequoia Light Mode..."
        xfconf-query -c xsettings -p /Net/ThemeName -s "WhiteSur-Light"
        # Check if WhiteSur or WhiteSur-light icon pack is installed
        if [[ -d "${HOME}/.icons/WhiteSur" || -d "/usr/share/icons/WhiteSur" ]]; then
            xfconf-query -c xsettings -p /Net/IconThemeName -s "WhiteSur"
        fi
        xfconf-query -c xfwm4 -p /general/theme -s "WhiteSur-Light"
        echo "✔ Light mode active: WhiteSur-Light"
        ;;
    dark)
        echo "==> Switching to macOS Sequoia Dark Mode..."
        xfconf-query -c xsettings -p /Net/ThemeName -s "WhiteSur-Dark"
        if [[ -d "${HOME}/.icons/WhiteSur-dark" || -d "/usr/share/icons/WhiteSur-dark" ]]; then
            xfconf-query -c xsettings -p /Net/IconThemeName -s "WhiteSur-dark"
        fi
        xfconf-query -c xfwm4 -p /general/theme -s "WhiteSur-Dark"
        echo "✔ Dark mode active: WhiteSur-Dark"
        ;;
    *)
        echo "Usage: $0 [light|dark|toggle]" >&2
        exit 1
        ;;
esac
