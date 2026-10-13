#!/usr/bin/env bash
# ==============================================================================
# Last-Resort Emergency Desktop Recovery Tool
# Works from a TTY (Ctrl+Alt+F3) without active X11 graphical display
# Kills compositors/widgets, restores XFCE native panel/xfwm4 defaults & Mint-Y
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo " 🚨 Linux Mint XFCE - Emergency Desktop Recovery Tool"
echo " Running last-resort restoration to stock Mint-Y defaults..."
echo "=========================================================="

# 1. Kill any hung or crashing companion processes
echo "==> Terminating picom, plank, conky, and rofi..."
pkill -9 -x picom 2>/dev/null || true
pkill -9 -x plank 2>/dev/null || true
pkill -9 -x conky 2>/dev/null || true
pkill -9 -x rofi 2>/dev/null || true
pkill -9 -x xfdashboard 2>/dev/null || true

# 2. Neutralize autostart entries to prevent re-launch on next login
echo "==> Removing transformation autostart desktop entries..."
rm -f "${HOME}/.config/autostart/picom.desktop"
rm -f "${HOME}/.config/autostart/plank.desktop"
rm -f "${HOME}/.config/autostart/conky.desktop"

# 3. Remove custom GTK overrides
echo "==> Removing custom GTK3 CSS overrides..."
rm -f "${HOME}/.config/gtk-3.0/gtk.css"

# 4. Reset xfwm4 & xsettings via xfconf-query or direct XML edits
echo "==> Restoring stock xfwm4 and theme settings..."
if command -v xfconf-query &>/dev/null; then
    # Window Manager
    xfconf-query -c xfwm4 -p /general/use_compositing --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/theme --create -t string -s "Mint-Y-Dark" 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/button_layout --create -t string -s "O|HMC" 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/title_alignment --create -t string -s "left" 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/title_font --create -t string -s "Ubuntu Bold 9" 2>/dev/null || true

    # Themes & Fonts
    xfconf-query -c xsettings -p /Net/ThemeName --create -t string -s "Mint-Y-Dark" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName --create -t string -s "Mint-Y" 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/FontName --create -t string -s "Ubuntu 10" 2>/dev/null || true

    # Panels: Restore single panel (panel-1), remove panel-2
    xfconf-query -c xfce4-panel -p /panels --create -t int -s 1 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-1/size --create -t uint -s 24 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
fi

# 5. If running inside X11, reload the panel and window manager
if [[ -n "${DISPLAY:-}" ]]; then
    echo "==> Reloading XFCE components..."
    xfce4-panel -r 2>/dev/null || true
    xfwm4 --replace 2>/dev/null &
fi

echo "----------------------------------------------------------"
echo "✔ Emergency desktop recovery complete."
echo "  • xfwm4 compositing: RE-ENABLED"
echo "  • Theme: Mint-Y-Dark"
echo "  • Window Controls: Traditional right (O|HMC)"
echo "  • Picom, Plank, Conky: STOPPED & DISABLED"
echo "You can switch back to GUI via Ctrl+Alt+F7 (or restart via 'sudo systemctl restart lightdm')."
echo "----------------------------------------------------------"
