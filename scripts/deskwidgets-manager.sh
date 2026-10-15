#!/usr/bin/env bash
# ==============================================================================
# Sequoia DeskWidgets Manager for Linux Mint XFCE (1280x1024 Target)
# Powered by DeskWidgets (Cairo + Conky + Python engine)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WIDGETS_DIR="${REPO_DIR}/lib/deskwidgets"
BIN_RUNNER="${WIDGETS_DIR}/bin/deskwidgets"

CONFIG_DIR="${HOME}/.config/deskwidgets"
LAYOUT_FILE="${CONFIG_DIR}/layout.json"
SETTINGS_FILE="${CONFIG_DIR}/settings.json"
FONT_DIR="${HOME}/.local/share/fonts"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/deskwidgets"
LOG_FILE="${HOME}/.cache/deskwidgets/service.log"

mkdir -p "${CONFIG_DIR}" "${FONT_DIR}" "${HOME}/.cache/deskwidgets" "${RUN_DIR}"

# 1. Install & Cache MaterialDesignIcons Font
install_fonts() {
    local src_font="${WIDGETS_DIR}/fonts/MaterialDesignIcons.ttf"
    local dest_font="${FONT_DIR}/MaterialDesignIcons.ttf"
    if [[ -f "${src_font}" ]] && [[ ! -f "${dest_font}" ]]; then
        cp -f "${src_font}" "${dest_font}"
        fc-cache -f "${FONT_DIR}" 2>/dev/null || true
    fi
}

# 2. Setup 1280x1024 Calibrated Layout & Settings
setup_config() {
    # Generate settings optimized for 1280x1024 resolution and GT 610 hardware
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        cat > "${SETTINGS_FILE}" << 'EOF'
{
  "language": "en",
  "scale": 0.95,
  "gap": 14,
  "margin_top": 36,
  "margin_bottom": 72,
  "margin_side": 16,
  "font": "Ubuntu Sans",
  "default_style": "glass",
  "default_accent": "blue",
  "autostart": true,
  "hotkey": false,
  "grid_overlay": false
}
EOF
    fi

    # Generate layout on the right-hand columns of the 1280x1024 screen
    if [[ ! -f "${LAYOUT_FILE}" ]]; then
        cat > "${LAYOUT_FILE}" << 'EOF'
{
  "version": 3,
  "instances": [
    {
      "id": "clock-1",
      "type": "clock",
      "size": "small",
      "style": "glass",
      "accent": "blue",
      "options": {},
      "col": 5,
      "row": 0
    },
    {
      "id": "calendar-1",
      "type": "calendar",
      "size": "small",
      "style": "glass",
      "accent": "blue",
      "options": {},
      "col": 6,
      "row": 0
    },
    {
      "id": "weather-1",
      "type": "weather",
      "size": "medium",
      "style": "glass",
      "accent": "blue",
      "options": {},
      "col": 5,
      "row": 1
    },
    {
      "id": "system-1",
      "type": "system",
      "size": "medium",
      "style": "glass",
      "accent": "blue",
      "options": {},
      "col": 5,
      "row": 2
    },
    {
      "id": "media-1",
      "type": "media",
      "size": "medium",
      "style": "glass",
      "accent": "blue",
      "options": {},
      "col": 5,
      "row": 3
    }
  ]
}
EOF
    fi
}

# 3. Process Management
is_running() {
    pgrep -f "deskwidgets run" >/dev/null 2>&1
}

stop_widgets() {
    echo "Stopping DeskWidgets service and widgets..."
    pkill -f "deskwidgets run" 2>/dev/null || true
    # Kill any conky instances spawned by deskwidgets
    for pid in $(pgrep conky 2>/dev/null || true); do
        if grep -q "deskwidgets" "/proc/${pid}/cmdline" 2>/dev/null; then
            kill -15 "${pid}" 2>/dev/null || true
        fi
    done
    # Also stop legacy static conky widgets if still running
    pkill -f "calendar-system.conkyrc" 2>/dev/null || true
    pkill -f "clock-weather.conkyrc" 2>/dev/null || true
    pkill -f "media-notes.conkyrc" 2>/dev/null || true
    sleep 0.5
}

start_widgets() {
    install_fonts
    setup_config

    echo "==> Launching desktop widgets..."
    pkill -f "deskwidgets run" 2>/dev/null || true
    pkill -f "calendar-system.conkyrc" 2>/dev/null || true
    pkill -f "clock-weather.conkyrc" 2>/dev/null || true
    pkill -f "media-notes.conkyrc" 2>/dev/null || true
    sleep 0.3

    local started_cairo=0
    if [[ -x "${BIN_RUNNER}" ]] && command -v python3 &>/dev/null; then
        echo "Attempting to start DeskWidgets Cairo vector suite..."
        nohup python3 "${BIN_RUNNER}" run > "${LOG_FILE}" 2>&1 &
        local new_pid=$!
        echo "${new_pid}" > "${HOME}/.cache/deskwidgets/service.pid"

        # Check if deskwidgets successfully spawned conky windows within 2 seconds
        for _ in {1..5}; do
            sleep 0.4
            if kill -0 "${new_pid}" 2>/dev/null && pgrep -f "conky -c.*widget.conf" >/dev/null 2>&1; then
                started_cairo=1
                break
            fi
        done
    fi

    if [[ "${started_cairo}" -eq 1 ]]; then
        echo "✔ DeskWidgets Cairo suite successfully active."
    else
        echo "ℹ Activating high-reliability native macOS Sequoia Conky cards..."
        pkill -f "deskwidgets run" 2>/dev/null || true
        if [[ -x "${SCRIPT_DIR}/conky-manager.sh" ]]; then
            "${SCRIPT_DIR}/conky-manager.sh" start
        elif [[ -x "${HOME}/.local/bin/conky-manager.sh" ]]; then
            "${HOME}/.local/bin/conky-manager.sh" start
        fi
        echo "✔ macOS Sequoia Conky cards active."
    fi
}

open_gallery() {
    install_fonts
    setup_config
    python3 "${BIN_RUNNER}" gallery &
}

status_widgets() {
    if is_running; then
        local pid
        pid=$(pgrep -f "deskwidgets run" | head -n1)
        local count
        count=$(pgrep -fc "deskwidget:" || true)
        echo "[RUNNING] DeskWidgets service active (PID: ${pid}, active widget windows: ${count})"
    else
        echo "[STOPPED] DeskWidgets service is not running."
    fi
}

cmd="${1:-status}"
case "${cmd}" in
    start)
        start_widgets
        ;;
    stop)
        stop_widgets
        ;;
    restart|reload)
        stop_widgets
        start_widgets
        ;;
    status)
        status_widgets
        ;;
    gallery)
        open_gallery
        ;;
    reset-layout)
        rm -f "${LAYOUT_FILE}" "${SETTINGS_FILE}"
        setup_config
        echo "Reset layout to default macOS 1280x1024 stack."
        if is_running; then
            stop_widgets
            start_widgets
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|gallery|reset-layout}"
        exit 1
        ;;
esac
