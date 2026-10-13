#!/usr/bin/env bash
# ==============================================================================
# Conky Manager for macOS Sequoia Desktop Widgets (3 Windows)
# Controls: start, stop, restart, status
# Target Hardware: Intel Core i3-3220, NVIDIA GT 610 nouveau
# ==============================================================================

set -euo pipefail

CONKY_DIR="${HOME}/.config/conky"
ACTION="${1:-start}"

stop_conky() {
    echo "==> Stopping all Conky widget instances..."
    if pgrep -x conky >/dev/null 2>&1; then
        pkill -x conky >/dev/null 2>&1 || true
        for _ in {1..8}; do
            if ! pgrep -x conky >/dev/null 2>&1; then
                break
            fi
            sleep 0.25
        done
        if pgrep -x conky >/dev/null 2>&1; then
            pkill -9 -x conky >/dev/null 2>&1 || true
            sleep 0.2
        fi
    fi
    echo "✔ Conky stopped."
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
