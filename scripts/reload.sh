#!/usr/bin/env bash
# ==============================================================================
# Hot Reload Script for Linux Mint XFCE Desktop
# Allows instant refreshing of UI components without logging out
# ==============================================================================

set -euo pipefail

TARGET="${1:-all}"

reload_gtk() {
    echo "==> Reloading GTK Theme & CSS..."
    if command -v xfconf-query &>/dev/null; then
        CURRENT_THEME="$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo "WhiteSur-Dark")"
        xfconf-query -c xsettings -p /Net/ThemeName -s "Mint-Y" 2>/dev/null || true
        sleep 0.1
        xfconf-query -c xsettings -p /Net/ThemeName -s "${CURRENT_THEME}" 2>/dev/null || true
    fi
    echo "  ✔ GTK theme reloaded."
}

reload_xfwm4() {
    echo "==> Reloading xfwm4 window manager..."
    if command -v xfwm4 &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        xfwm4 --replace 2>/dev/null &
    fi
    echo "  ✔ xfwm4 reloaded."
}

reload_panel() {
    echo "==> Reloading xfce4-panel..."
    if command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r 2>/dev/null || true
    fi
    echo "  ✔ xfce4-panel reloaded."
}

reload_plank() {
    echo "==> Reloading Plank dock..."
    if [[ -x "${HOME}/.local/bin/start-plank.sh" ]]; then
        bash "${HOME}/.local/bin/start-plank.sh"
    elif command -v plank &>/dev/null; then
        pkill -x plank 2>/dev/null || true
        sleep 1
        plank &>/dev/null & disown
    fi
    echo "  ✔ Plank dock restarted."
}

reload_conky() {
    echo "==> Reloading Conky widgets..."
    if [[ -x "${HOME}/.local/bin/conky-manager.sh" ]]; then
        bash "${HOME}/.local/bin/conky-manager.sh" restart
    else
        pkill -x conky 2>/dev/null || true
    fi
    echo "  ✔ Conky restarted."
}

reload_picom() {
    echo "==> Reloading Picom compositor..."
    if command -v picom &>/dev/null; then
        pkill -x picom 2>/dev/null || true
        sleep 0.3
        if [[ -f "${HOME}/.config/picom/picom.conf" ]]; then
            picom --config "${HOME}/.config/picom/picom.conf" -b 2>/dev/null || true
        fi
    fi
    echo "  ✔ Picom reloaded."
}

case "${TARGET}" in
    gtk)
        reload_gtk
        ;;
    wm|xfwm4)
        reload_xfwm4
        ;;
    panel)
        reload_panel
        ;;
    plank)
        reload_plank
        ;;
    conky)
        reload_conky
        ;;
    picom)
        reload_picom
        ;;
    all)
        reload_gtk
        reload_xfwm4
        reload_panel
        reload_plank
        reload_conky
        reload_picom
        echo "🎉 All XFCE desktop components reloaded successfully!"
        ;;
    *)
        echo "Usage: $0 [all|gtk|wm|panel|plank|conky|picom]"
        exit 1
        ;;
esac
