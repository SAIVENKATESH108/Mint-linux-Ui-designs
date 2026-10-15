#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia System-Wide Theme Mode Switcher (Day / Night)
# Harmonizes entire desktop like tailored clothes:
# - GTK Theme & Icons
# - Window decorations (XFWM4 traffic lights)
# - Top Panel glass tokens & font styling
# - Plank Dock (Sequoia Dark / Sequoia Light)
# - DeskWidgets (Glass Dark / Light Card styling)
# ==============================================================================

set -euo pipefail

TARGET="${1:-toggle}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
        echo "==> Coordinating macOS Sequoia Day Mode across whole system..."
        # 1. GTK Application Theme & Icons
        xfconf-query -c xsettings -p /Net/ThemeName -s "WhiteSur-Light"
        if [[ -d "${HOME}/.icons/WhiteSur" || -d "/usr/share/icons/WhiteSur" ]]; then
            xfconf-query -c xsettings -p /Net/IconThemeName -s "WhiteSur"
        fi
        
        # 2. Window Titlebars & Traffic Lights
        xfconf-query -c xfwm4 -p /general/theme -s "WhiteSur-Light"
        
        # 3. Plank Dock Light Theme
        if command -v dconf &>/dev/null; then
            dconf write /net/launchpad/plank/docks/dock1/theme "'Sequoia-Light'" 2>/dev/null || true
        fi

        # 4. Top Panel Light Glass Tokens
        if [[ -f "${HOME}/.config/gtk-3.0/sequoia/tokens-light.css" ]]; then
            cp -f "${HOME}/.config/gtk-3.0/sequoia/tokens-light.css" "${HOME}/.config/gtk-3.0/sequoia/tokens.css"
        elif [[ -f "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-light.css" ]]; then
            cp -f "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-light.css" "${HOME}/.config/gtk-3.0/sequoia/tokens.css"
        fi

        # 5. DeskWidgets Style Coordination
        if [[ -x "${HOME}/.local/bin/deskwidgets-manager.sh" ]]; then
            "${HOME}/.local/bin/deskwidgets-manager.sh" style "light" >/dev/null 2>&1 || true
        elif [[ -x "${SCRIPT_DIR}/deskwidgets-manager.sh" ]]; then
            "${SCRIPT_DIR}/deskwidgets-manager.sh" style "light" >/dev/null 2>&1 || true
        fi

        # 6. Refresh Panel
        xfce4-panel -r 2>/dev/null || true

        if command -v notify-send &>/dev/null; then
            notify-send "macOS Appearance" "Day Mode Active (Clean Light Glass & Deep Contrast)" -i weather-clear-symbolic 2>/dev/null || true
        fi
        echo "✔ macOS Sequoia Day Mode active."
        ;;
    dark)
        echo "==> Coordinating macOS Sequoia Night Mode across whole system..."
        # 1. GTK Application Theme & Icons
        xfconf-query -c xsettings -p /Net/ThemeName -s "WhiteSur-Dark"
        if [[ -d "${HOME}/.icons/WhiteSur-dark" || -d "/usr/share/icons/WhiteSur-dark" ]]; then
            xfconf-query -c xsettings -p /Net/IconThemeName -s "WhiteSur-dark"
        fi

        # 2. Window Titlebars & Traffic Lights
        xfconf-query -c xfwm4 -p /general/theme -s "WhiteSur-Dark"

        # 3. Plank Dock Dark Theme
        if command -v dconf &>/dev/null; then
            dconf write /net/launchpad/plank/docks/dock1/theme "'Sequoia'" 2>/dev/null || true
        fi

        # 4. Top Panel Dark Glass Tokens
        if [[ -f "${HOME}/.config/gtk-3.0/sequoia/tokens-dark.css" ]]; then
            cp -f "${HOME}/.config/gtk-3.0/sequoia/tokens-dark.css" "${HOME}/.config/gtk-3.0/sequoia/tokens.css"
        elif [[ -f "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-dark.css" ]]; then
            cp -f "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-dark.css" "${HOME}/.config/gtk-3.0/sequoia/tokens.css"
        fi

        # 5. DeskWidgets Style Coordination
        if [[ -x "${HOME}/.local/bin/deskwidgets-manager.sh" ]]; then
            "${HOME}/.local/bin/deskwidgets-manager.sh" style "glass" >/dev/null 2>&1 || true
        elif [[ -x "${SCRIPT_DIR}/deskwidgets-manager.sh" ]]; then
            "${SCRIPT_DIR}/deskwidgets-manager.sh" style "glass" >/dev/null 2>&1 || true
        fi

        # 6. Refresh Panel
        xfce4-panel -r 2>/dev/null || true

        if command -v notify-send &>/dev/null; then
            notify-send "macOS Appearance" "Night Mode Active (Deep Obsidian Glass & Vibrant Accents)" -i weather-clear-night-symbolic 2>/dev/null || true
        fi
        echo "✔ macOS Sequoia Night Mode active."
        ;;
    *)
        echo "Usage: $0 [light|dark|toggle]" >&2
        exit 1
        ;;
esac
