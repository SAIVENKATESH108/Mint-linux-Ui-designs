#!/usr/bin/env bash
# ==============================================================================
# Sequoia Consolidated Session Supervisor
# Single entry point for user-session services: Picom (with watchdog), Plank, Conky.
# Replaces scattered individual autostart files to eliminate launch races.
# Target: Linux Mint 22.3 XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="${RUNTIME_DIR}/sequoia-supervisor-${UID}.lock"

# Single-instance enforcement via file descriptor lock
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
    echo "Sequoia supervisor is already running for user ${UID}."
    exit 0
fi

log() { echo "[$(date '+%H:%M:%S')] [supervisor] $*"; }

# ------------------------------------------------------------------------------
# 1. Migrate & Disable Legacy Scattered Autostart Entries
# ------------------------------------------------------------------------------
MIGRATED_DIR="${HOME}/.config/autostart/.sequoia-migrated"
mkdir -p "${MIGRATED_DIR}"

for old_entry in "picom.desktop" "plank.desktop" "conky.desktop"; do
    target_file="${HOME}/.config/autostart/${old_entry}"
    if [[ -f "${target_file}" ]]; then
        log "Migrating legacy autostart entry: ${old_entry}..."
        mv -f "${target_file}" "${MIGRATED_DIR}/${old_entry}" || true
    fi
done

# ------------------------------------------------------------------------------
# 2. Launch Picom with Crash Watchdog & Fallback
# ------------------------------------------------------------------------------
start_picom() {
    local conf="${HOME}/.config/picom/picom.conf"
    if [[ -f "${conf}" ]] && command -v picom &>/dev/null; then
        pkill -x picom 2>/dev/null || true
        sleep 0.3
        picom --config "${conf}" -b 2>/dev/null || true
        log "Picom compositor started."
    fi
}

start_picom

# Background supervisor watchdog for Picom stability on weak GPU
(
    CRASH_COUNT=0
    LAST_CRASH_TIME=0

    while true; do
        sleep 10
        if ! pgrep -x picom &>/dev/null; then
            NOW=$(date +%s)
            TIME_DIFF=$(( NOW - LAST_CRASH_TIME ))
            LAST_CRASH_TIME="${NOW}"
            CRASH_COUNT=$(( CRASH_COUNT + 1 ))

            if (( TIME_DIFF < 60 && CRASH_COUNT >= 2 )); then
                # Picom crashed repeatedly: activate safe-mode rollback
                echo "[$(date)] Picom repeatedly crashed. Falling back to xfwm4 safe compositing." >> /tmp/picom-crash.log
                if command -v xfconf-query &>/dev/null; then
                    xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
                fi
                if command -v notify-send &>/dev/null; then
                    notify-send "Compositor Safe Mode" "Picom failed; fell back to xfwm4 safe compositing." -u critical || true
                fi
                break
            else
                echo "[$(date)] Picom died. Attempting single restart..." >> /tmp/picom-crash.log
                start_picom
            fi
        fi
    done
) &

# ------------------------------------------------------------------------------
# 3. Launch Plank Dock
# ------------------------------------------------------------------------------
if [[ -x "${SCRIPT_DIR}/start-plank.sh" ]]; then
    log "Starting Plank dock..."
    "${SCRIPT_DIR}/start-plank.sh" || true
elif [[ -x "${HOME}/.local/bin/start-plank.sh" ]]; then
    "${HOME}/.local/bin/start-plank.sh" || true
fi

# ------------------------------------------------------------------------------
# 4. Launch Desktop Conky Widgets
# ------------------------------------------------------------------------------
if [[ -x "${SCRIPT_DIR}/conky-manager.sh" ]]; then
    log "Starting Conky desktop widgets..."
    "${SCRIPT_DIR}/conky-manager.sh" start || true
elif [[ -x "${HOME}/.local/bin/conky-manager.sh" ]]; then
    "${HOME}/.local/bin/conky-manager.sh" start || true
fi

log "Sequoia session initialized successfully."
exit 0
