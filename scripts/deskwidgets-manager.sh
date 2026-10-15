#!/usr/bin/env bash
# ==============================================================================
# Sequoia DeskWidgets Manager for Linux Mint XFCE (1280x1024 Target)
# Powered by DeskWidgets (Cairo + Conky + Python engine)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WIDGETS_SRC="${REPO_DIR}/lib/deskwidgets"

CONFIG_DIR="${HOME}/.config/deskwidgets"
LAYOUT_FILE="${CONFIG_DIR}/layout.json"
SETTINGS_FILE="${CONFIG_DIR}/settings.json"
FONT_DIR="${HOME}/.local/share/fonts"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/deskwidgets"
LOG_FILE="${HOME}/.cache/deskwidgets/service.log"
BIN_RUNNER="${HOME}/.local/bin/deskwidgets"

mkdir -p "${CONFIG_DIR}" "${FONT_DIR}" "${HOME}/.cache/deskwidgets" "${RUN_DIR}"

# 1. Install DeskWidgets package to ~/.local and install fonts
install_deskwidgets() {
    # Copy Material Design Icons font
    local src_font="${WIDGETS_SRC}/fonts/MaterialDesignIcons.ttf"
    local dest_font="${FONT_DIR}/MaterialDesignIcons.ttf"
    if [[ -f "${src_font}" ]] && [[ ! -f "${dest_font}" ]]; then
        cp -f "${src_font}" "${dest_font}"
        fc-cache -f "${FONT_DIR}" 2>/dev/null || true
    fi

    # Always ensure latest engine and binary are synchronized to ~/.local
    if [[ -f "${WIDGETS_SRC}/install.sh" ]]; then
        sh "${WIDGETS_SRC}/install.sh" --prefix "${HOME}/.local" >/dev/null 2>&1 || true
    fi
}

# 2. Get current system appearance mode (dark vs light)
get_current_theme_mode() {
    local theme
    theme="$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || echo "WhiteSur-Dark")"
    if [[ "${theme}" =~ [Dd]ark ]]; then
        echo "glass"
    else
        echo "light"
    fi
}

# 3. Setup 1280x1024 Calibrated Layout & Settings matching DeskWidgets Showcase
setup_config() {
    local target_style
    target_style="${1:-$(get_current_theme_mode)}"

    # Generate global settings
    cat > "${SETTINGS_FILE}" << EOF
{
  "language": "en",
  "scale": 0.95,
  "gap": 14,
  "margin_top": 36,
  "margin_bottom": 72,
  "margin_side": 16,
  "font": "Ubuntu Sans",
  "default_style": "${target_style}",
  "default_accent": "blue",
  "autostart": true,
  "hotkey": false,
  "grid_overlay": false
}
EOF

    # Provision calibrated 1280x1024 macOS widget stack with modern colorful accents
    cat > "${LAYOUT_FILE}" << EOF
{
  "version": 3,
  "instances": [
    {
      "id": "clock-1",
      "type": "clock",
      "size": "small",
      "style": "${target_style}",
      "accent": "purple",
      "options": {},
      "col": 5,
      "row": 0
    },
    {
      "id": "calendar-1",
      "type": "calendar",
      "size": "small",
      "style": "color",
      "accent": "red",
      "options": {},
      "col": 6,
      "row": 0
    },
    {
      "id": "weather-1",
      "type": "weather",
      "size": "medium",
      "style": "${target_style}",
      "accent": "auto",
      "options": {},
      "col": 5,
      "row": 1
    },
    {
      "id": "system-1",
      "type": "system",
      "size": "medium",
      "style": "${target_style}",
      "accent": "auto",
      "options": {},
      "col": 5,
      "row": 2
    },
    {
      "id": "media-1",
      "type": "media",
      "size": "medium",
      "style": "color",
      "accent": "pink",
      "options": {},
      "col": 5,
      "row": 3
    }
  ]
}
EOF
}

# 4. Stop All Widgets (DeskWidgets and Old Conky)
stop_widgets() {
    echo "Stopping DeskWidgets service and widget instances..."
    pkill -f "deskwidgets run" 2>/dev/null || true
    # Stop legacy conky cards permanently
    pkill -f "calendar-system.conkyrc" 2>/dev/null || true
    pkill -f "clock-weather.conkyrc" 2>/dev/null || true
    pkill -f "media-notes.conkyrc" 2>/dev/null || true
    
    # Kill any conky instances spawned by DeskWidgets
    for pid in $(pgrep conky 2>/dev/null || true); do
        if grep -q "deskwidgets" "/proc/${pid}/cmdline" 2>/dev/null; then
            kill -9 "${pid}" 2>/dev/null || true
        fi
    done
    rm -f "${RUN_DIR}/dragging" "${RUN_DIR}/grid.json" 2>/dev/null || true
    sleep 0.3
}

# 5. Start DeskWidgets
start_widgets() {
    install_deskwidgets
    local current_mode
    current_mode="$(get_current_theme_mode)"
    setup_config "${current_mode}"

    echo "==> Starting DeskWidgets macOS Suite (${current_mode} colorful mode)..."
    stop_widgets

    local runner="${BIN_RUNNER}"
    if [[ ! -x "${runner}" ]]; then
        runner="${WIDGETS_SRC}/bin/deskwidgets"
    fi

    nohup python3 "${runner}" run > "${LOG_FILE}" 2>&1 &
    local new_pid=$!
    echo "${new_pid}" > "${HOME}/.cache/deskwidgets/service.pid"
    echo "✔ DeskWidgets service active (PID: ${new_pid})."
}

# 6. Change Style (glass, light, graphite, colour, sakura, manga, neon)
set_style() {
    local new_style="${1:-glass}"
    echo "Applying DeskWidgets style: ${new_style}..."
    setup_config "${new_style}"
    stop_widgets
    start_widgets
}

status_widgets() {
    local pid
    pid="$(pgrep -f "deskwidgets run" | head -n1 || true)"
    local count
    count="$(pgrep -fc "deskwidget:" 2>/dev/null || echo 0)"
    if [[ -n "${pid}" ]]; then
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
    style)
        set_style "${2:-glass}"
        ;;
    gallery)
        install_deskwidgets
        "${BIN_RUNNER}" gallery &
        ;;
    reset-layout)
        rm -f "${LAYOUT_FILE}" "${SETTINGS_FILE}"
        setup_config
        stop_widgets
        start_widgets
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|style <name>|gallery|reset-layout}"
        exit 1
        ;;
esac
