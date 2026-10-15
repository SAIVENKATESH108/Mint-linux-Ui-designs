#!/usr/bin/env bash
# ==============================================================================
# macOS Sequoia Control Center Menu for Linux Mint XFCE
# Trigger: Super+C or panel launcher
# ==============================================================================

set -euo pipefail

# Try native GTK3 Control Center popover first (macOS style window)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_POPUP="${SCRIPT_DIR}/sequoia-control-center.py"
if [[ ! -f "${PY_POPUP}" ]]; then
    PY_POPUP="${HOME}/.local/bin/sequoia-control-center.py"
fi

if [[ -f "${PY_POPUP}" ]] && command -v python3 &>/dev/null; then
    mkdir -p "${HOME}/.cache"
    # Single-instance Gtk.Application handles toggle via D-Bus IPC without pgrep/pkill
    python3 "${PY_POPUP}" --toggle >> "${HOME}/.cache/control-center.log" 2>&1 &
    exit 0
fi

# Fallback: text-based quick settings menu
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
    "⚙️  Open Sequoia Settings"
)

THEME_FILE="${HOME}/.config/rofi/control-center.rasi"
if [[ ! -f "${THEME_FILE}" ]]; then
    THEME_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/rofi/control-center.rasi"
fi

CHOICE=""
if command -v rofi &>/dev/null && [[ -f "${THEME_FILE}" ]]; then
    CHOICE=$(printf "%s\n" "${MENU_ITEMS[@]}" | rofi -dmenu -i -p "Control Center" -theme "${THEME_FILE}" || true)
elif command -v zenity &>/dev/null; then
    CHOICE=$(zenity --list --title="Control Center" --column="Quick Controls" "${MENU_ITEMS[@]}" --height=380 --width=420 || true)
else
    xfce4-settings-manager &
    exit 0
fi

[[ -z "${CHOICE}" ]] && exit 0

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
    *"Sequoia Settings"*)
        if [[ -x "${HOME}/.local/bin/sequoia-settings.sh" ]]; then
            "${HOME}/.local/bin/sequoia-settings.sh" &
        else
            xfce4-settings-manager &
        fi
        ;;
esac
