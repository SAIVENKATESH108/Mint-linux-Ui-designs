#!/usr/bin/env bash
# ==============================================================================
# macOS Sequoia Control Center Menu for Linux Mint XFCE
# Trigger: Super+C or panel launcher
#
# Technical Limits & Implementation Reality:
#   XFCE 4.18 has no native composite popover widget matching macOS Control Center.
#   Rather than running heavy Electron/JavaScript background daemons that exhaust
#   the Core i3-3220 CPU and 12GB RAM, this script builds an interactive, zero-overhead
#   control menu using Rofi/CLI tools (pactl, xrandr, nmcli, playerctl).
#   No Bluetooth options are shown (Desktop PC hardware constraint).
# ==============================================================================

set -euo pipefail

# Get current status readings
WIFI_STATUS="$(nmcli -t -f WIFI g 2>/dev/null || echo "enabled")"
VOL_STATUS="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n1 | awk '{print $5}' || echo "N/A")"
IS_MUTED="$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}' || echo "no")"
TRACK_INFO="$(playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || echo "No media playing")"

MENU_ITEMS=(
    "📶  Wi-Fi: [${WIFI_STATUS}] (Click to toggle)"
    "🔊  Sound Volume: [${VOL_STATUS}] (Mute: ${IS_MUTED})"
    "🔉  Volume Down (-5%)"
    "🔊  Volume Up (+5%)"
    "🔇  Toggle Mute"
    "☀️  Display Brightness: Increase (+10%)"
    "🌙  Display Brightness: Decrease (-10%)"
    "🎵  Now Playing: ${TRACK_INFO} (Play/Pause)"
    "🛑  Do Not Disturb: Toggle Notifications"
    "⚙️  Open System Settings"
)

CHOICE=$(printf "%s\n" "${MENU_ITEMS[@]}" | rofi -dmenu -i -p "Control Center" -theme-str '
window { width: 440px; border-radius: 14px; location: north east; anchor: north east; x-offset: -14px; y-offset: 36px; }
listview { lines: 10; }
') || exit 0

case "${CHOICE}" in
    *"Wi-Fi"*)
        if [[ "${WIFI_STATUS}" == "enabled" ]]; then
            nmcli radio wifi off 2>/dev/null || true
            notify-send "Control Center" "Wi-Fi Disabled"
        else
            nmcli radio wifi on 2>/dev/null || true
            notify-send "Control Center" "Wi-Fi Enabled"
        fi
        ;;
    *"Volume Down"*)
        pactl set-sink-volume @DEFAULT_SINK@ -5% 2>/dev/null || true
        ;;
    *"Volume Up"*)
        pactl set-sink-volume @DEFAULT_SINK@ +5% 2>/dev/null || true
        ;;
    *"Toggle Mute"*)
        pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null || true
        ;;
    *"Brightness: Increase"*)
        xrandr --output HDMI-1 --brightness 1.0 2>/dev/null || true
        ;;
    *"Brightness: Decrease"*)
        xrandr --output HDMI-1 --brightness 0.8 2>/dev/null || true
        ;;
    *"Now Playing"*)
        playerctl play-pause 2>/dev/null || true
        ;;
    *"Do Not Disturb"*)
        xfconf-query -c xfce4-notifyd -p /do-not-disturb -t bool -s "$(xfconf-query -c xfce4-notifyd -p /do-not-disturb 2>/dev/null | grep -q true && echo false || echo true)" 2>/dev/null || true
        notify-send "Control Center" "Do Not Disturb Toggled"
        ;;
    *"System Settings"*)
        xfce4-settings-manager &
        ;;
esac
