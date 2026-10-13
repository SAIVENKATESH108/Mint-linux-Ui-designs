#!/usr/bin/env bash
# ==============================================================================
# Safe Plank Dock Launcher
# Prevents DBus registration races by ensuring previous instances are stopped
# Target: Linux Mint 22.3 (XFCE 4.18, X11)
# ==============================================================================

set -euo pipefail

LOG_DIR="${HOME}/.cache/mint-sequoia"
LOG_FILE="${LOG_DIR}/plank.log"
mkdir -p "${LOG_DIR}"

# 1. Kill any existing plank instance and wait for it to exit
if pgrep -x plank >/dev/null 2>&1; then
    killall plank 2>/dev/null || pkill -x plank 2>/dev/null || true
    # Wait until pgrep -x plank is empty (max 5 seconds)
    for _ in {1..10}; do
        if ! pgrep -x plank >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done

    # Force kill if still lingering
    if pgrep -x plank >/dev/null 2>&1; then
        pkill -9 -x plank 2>/dev/null || true
        sleep 0.5
    fi
fi

# 2. Start plank and log output
echo "=== Starting Plank at $(date) ===" >> "${LOG_FILE}"
( plank >> "${LOG_FILE}" 2>&1 & )

# 3. Verify plank launched and stayed alive
sleep 1.5
if pgrep -x plank >/dev/null 2>&1; then
    echo "✔ Plank dock started successfully (PID: $(pgrep -x plank | head -n1))."
    exit 0
else
    echo "✖ ERROR: Plank failed to start. Last log entries from ${LOG_FILE}:" >&2
    tail -n 15 "${LOG_FILE}" >&2 || true
    exit 1
fi
