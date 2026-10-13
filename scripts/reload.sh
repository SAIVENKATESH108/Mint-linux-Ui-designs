#!/usr/bin/env bash
# ==============================================================================
# Hot Reload Script for Linux Mint XFCE Desktop Testing (Level 2 Preview)
# Allows instant refreshing of UI components without logging out
# ==============================================================================

set -euo pipefail

TARGET="${1:-all}"

reload_gtk() {
    echo "==> Reloading GTK Theme & CSS..."
    CURRENT_THEME="$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo "Mint-Y-Dark")"
    xfconf-query -c xsettings -p /Net/ThemeName -s "Mint-Y" 2>/dev/null || true
    sleep 0.1
    xfconf-query -c xsettings -p /Net/ThemeName -s "${CURRENT_THEME}" 2>/dev/null || true
    echo "  ✔ GTK theme reloaded."
}

reload_panel() {
    echo "==> Reloading xfce4-panel..."
    xfce4-panel -r 2>/dev/null || true
    echo "  ✔ xfce4-panel reloaded."
}

reload_plank() {
    echo "==> Reloading Plank dock..."
    killall plank 2>/dev/null || true
    sleep 0.2
    plank &>/dev/null & disown
    echo "  ✔ Plank dock restarted."
}

reload_conky() {
    echo "==> Reloading Conky widgets..."
    killall conky 2>/dev/null || true
    sleep 0.2
    if [[ -f "${HOME}/.config/conky/sequoia-glance.conkyrc" ]]; then
        conky -c "${HOME}/.config/conky/sequoia-glance.conkyrc" -d &>/dev/null || true
    fi
    echo "  ✔ Conky restarted."
}

reload_picom() {
    echo "==> Reloading Picom compositor..."
    killall picom 2>/dev/null || true
    sleep 0.2
    if [[ -f "${HOME}/.config/picom/picom.conf" ]]; then
        picom --config "${HOME}/.config/picom/picom.conf" -b 2>/dev/null || true
    fi
    echo "  ✔ Picom reloaded."
}

case "${TARGET}" in
    gtk)
        reload_gtk
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
        reload_panel
        reload_plank
        reload_conky
        reload_picom
        echo "🎉 All XFCE desktop components reloaded successfully!"
        ;;
    *)
        echo "Usage: $0 [all|gtk|panel|plank|conky|picom]"
        exit 1
        ;;
esac
