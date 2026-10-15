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
LOG_FILE="${HOME}/.cache/sequoia/deskwidgets.log"
BIN_RUNNER="${HOME}/.local/bin/deskwidgets"

mkdir -p "${CONFIG_DIR}" "${FONT_DIR}" "${HOME}/.cache/deskwidgets" "${HOME}/.cache/sequoia" "${RUN_DIR}"

# 1. Install DeskWidgets package to ~/.local and install fonts
install_deskwidgets() {
    # Copy Material Design Icons font
    local src_font="${WIDGETS_SRC}/fonts/MaterialDesignIcons.ttf"
    local dest_font="${FONT_DIR}/MaterialDesignIcons.ttf"
    if [[ -f "${src_font}" ]] && [[ ! -f "${dest_font}" ]]; then
        cp -f "${src_font}" "${dest_font}"
        fc-cache -f "${FONT_DIR}" 2>/dev/null || true
    fi

    # Ensure files are synchronized via sequoia-ctl deploy
    local inst_paths="${HOME}/.local/share/deskwidgets/deskwidgets/paths.py"
    local repo_paths="${WIDGETS_SRC}/deskwidgets/paths.py"
    if [[ ! -f "${inst_paths}" ]] || ! cmp -s "${repo_paths}" "${inst_paths}"; then
        if [[ -x "${REPO_DIR}/scripts/sequoia-ctl" ]]; then
            "${REPO_DIR}/scripts/sequoia-ctl" deploy >/dev/null 2>&1 || true
        fi
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

    # Generate global settings (anchored from 28px bar with 16px margins and 16px gaps)
    cat > "${SETTINGS_FILE}" << EOF
{
  "language": "en",
  "scale": 1.0,
  "gap": 16,
  "margin_top": 44,
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

    # Provision calibrated 1280x1024 macOS widget stack (columns 4 and 5 right-anchored)
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
      "col": 4,
      "row": 0
    },
    {
      "id": "calendar-1",
      "type": "calendar",
      "size": "small",
      "style": "color",
      "accent": "red",
      "options": {},
      "col": 5,
      "row": 0
    },
    {
      "id": "weather-1",
      "type": "weather",
      "size": "medium",
      "style": "${target_style}",
      "accent": "auto",
      "options": {},
      "col": 4,
      "row": 1
    },
    {
      "id": "system-1",
      "type": "system",
      "size": "medium",
      "style": "${target_style}",
      "accent": "auto",
      "options": {},
      "col": 4,
      "row": 2
    },
    {
      "id": "media-1",
      "type": "media",
      "size": "medium",
      "style": "color",
      "accent": "pink",
      "options": {},
      "col": 4,
      "row": 3
    }
  ]
}
EOF
}

# 4. Stop All Widgets (DeskWidgets and Conky)
stop_widgets() {
    echo "Stopping DeskWidgets service and widget instances..."
    local pid_file="${HOME}/.cache/deskwidgets/service.pid"
    if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            local is_dw=0
            if [[ -f "/proc/${pid}/cmdline" ]]; then
                local pcmd
                pcmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
                if [[ "${pcmd}" == *"deskwidgets"* ]]; then
                    is_dw=1
                fi
            fi

            if [[ "${is_dw}" -eq 1 ]]; then
                echo "Stopping DeskWidgets daemon (PID: ${pid})..."
                kill -TERM "${pid}" 2>/dev/null || true
                for _ in {1..15}; do
                    if ! kill -0 "${pid}" 2>/dev/null; then
                        break
                    fi
                    sleep 0.1
                done
            else
                echo "Notice: PID ${pid} is an unrelated process. Removing stale PID file."
            fi
        fi
        rm -f "${pid_file}"
    fi

    # Terminate any remaining conky processes that strictly belong to deskwidgets
    for p in /proc/[0-9]*; do
        local pid="${p##*/}"
        if [[ -f "/proc/${pid}/cmdline" ]]; then
            local cmd
            cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
            if [[ "${cmd}" == *"conky"* && "${cmd}" == *"widget.conf"* ]]; then
                kill -TERM "${pid}" 2>/dev/null || true
            elif [[ "${cmd}" == *"deskwidgets run"* ]]; then
                kill -TERM "${pid}" 2>/dev/null || true
            fi
        fi
    done

    # Clean legacy 3-card conky files if any
    for p in /proc/[0-9]*; do
        local pid="${p##*/}"
        if [[ -f "/proc/${pid}/cmdline" ]]; then
            local cmd
            cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
            if [[ "${cmd}" == *"conky"* && ("${cmd}" == *"calendar-system.conkyrc"* || "${cmd}" == *"clock-weather.conkyrc"* || "${cmd}" == *"media-notes.conkyrc"*) ]]; then
                kill -TERM "${pid}" 2>/dev/null || true
            fi
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

    echo "==> Starting DeskWidgets macOS Suite (${current_mode} mode)..."
    stop_widgets

    local runner="${BIN_RUNNER}"
    if [[ ! -x "${runner}" ]]; then
        runner="${WIDGETS_SRC}/bin/deskwidgets"
    fi

    mkdir -p "$(dirname "${LOG_FILE}")"
    nohup python3 "${runner}" run > "${LOG_FILE}" 2>&1 &
    local new_pid=$!
    echo "${new_pid}" > "${HOME}/.cache/deskwidgets/service.pid"

    # Liveness check: verify process didn't crash on startup
    sleep 0.5
    if kill -0 "${new_pid}" 2>/dev/null; then
        echo "✔ DeskWidgets service active (PID: ${new_pid})."
    else
        echo "✘ ERROR: DeskWidgets service process ${new_pid} failed to start. Last log lines from ${LOG_FILE}:"
        tail -n 15 "${LOG_FILE}" 2>/dev/null || true
        return 1
    fi
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
    local runner="${BIN_RUNNER}"
    if [[ ! -x "${runner}" ]]; then
        runner="${WIDGETS_SRC}/bin/deskwidgets"
    fi
    python3 "${runner}" status
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
