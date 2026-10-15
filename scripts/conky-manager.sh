#!/usr/bin/env bash
# ==============================================================================
# Conky Manager for macOS Sequoia Desktop Widgets (3 Windows)
# Controls: start, stop, restart, status
# Target Hardware: Intel Core i3-3220, NVIDIA GT 610 nouveau
# ==============================================================================

set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

CONKY_DIR="${HOME}/.config/conky"
ACTION="${1:-start}"

stop_conky() {
    echo "==> Stopping legacy 3-card Conky widget instances..."
    for p in /proc/[0-9]*; do
        local pid="${p##*/}"
        if [[ -f "/proc/${pid}/cmdline" ]]; then
            local cmd
            cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
            if [[ "${cmd}" == *"conky"* && ("${cmd}" == *"clock-weather.conkyrc"* || "${cmd}" == *"calendar-system.conkyrc"* || "${cmd}" == *"media-notes.conkyrc"*) ]]; then
                kill -TERM "${pid}" 2>/dev/null || true
            fi
        fi
    done
    sleep 0.2
    echo "✔ Legacy Conky stopped."
}

start_conky() {
    stop_conky
    echo "==> Starting 3 macOS Sequoia Conky widget windows..."

    local configs=(
        "clock-weather.conkyrc"
        "calendar-system.conkyrc"
        "media-notes.conkyrc"
    )

    for cfg in "${configs[@]}"; do
        local path="${CONKY_DIR}/${cfg}"
        if [[ -f "${path}" ]]; then
            conky -c "${path}" -d >/dev/null 2>&1 || {
                echo "⚠ Warning: Failed to launch ${cfg}" >&2
            }
        else
            echo "⚠ Configuration not found: ${path}" >&2
        fi
    done

    echo "✔ 3 Conky widget windows launched."
}

status_conky() {
    local count
    count="$(pgrep -c -x conky || echo 0)"
    echo "Active Conky instances: ${count} / 3 windows"
}

case "${ACTION}" in
    start)
        start_conky
        ;;
    stop)
        stop_conky
        ;;
    restart)
        start_conky
        ;;
    status)
        status_conky
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|status]" >&2
        exit 1
        ;;
esac
