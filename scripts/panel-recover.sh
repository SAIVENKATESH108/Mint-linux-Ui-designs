#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - Panel Recovery Helper
# Restores xfce4-panel process and settings if top panel disappears or fails.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "==> XFCE Panel Recovery Diagnostic & Repair Utility..."

# 1. Inspect running process
PANEL_PIDS="$(pgrep -x xfce4-panel || true)"
if [[ -z "${PANEL_PIDS}" ]]; then
    log_warn "xfce4-panel process is NOT running. Starting background instance..."
    ( xfce4-panel & ) >/dev/null 2>&1
    sleep 1
    PANEL_PIDS="$(pgrep -x xfce4-panel || true)"
    if [[ -n "${PANEL_PIDS}" ]]; then
        log_success "xfce4-panel successfully started (PID: ${PANEL_PIDS})."
    else
        log_error "Failed to start xfce4-panel process."
    fi
else
    log_success "xfce4-panel is active (PID: ${PANEL_PIDS})."
fi

# 2. Check xfconf configuration health
TOP_PANEL_OK=0
if assert_top_panel_exists; then
    TOP_PANEL_OK=1
fi

PLUGIN_COUNT=0
if command -v xfconf-query &>/dev/null; then
    ACTIVE_IDS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    PLUGIN_COUNT=${#ACTIVE_IDS[@]}
fi

if [[ "${TOP_PANEL_OK}" -eq 0 || "${PLUGIN_COUNT}" -eq 0 ]]; then
    log_warn "Panel-1 configuration corrupted (panel missing or 0 plugins detected)."
    log_info "Attempting restoration from snapshot / backups..."

    SNAPSHOT_FILE="${HOME}/.cache/sequoia/panel-pre-reload-snapshot.txt"
    RESTORE_SOURCE=""

    if [[ -f "${SNAPSHOT_FILE}" ]]; then
        RESTORE_SOURCE="${SNAPSHOT_FILE}"
    else
        LATEST_BACKUP="$(ls -td "${HOME}/.mint-sequoia-backup"/*/phase3 2>/dev/null | head -n1 || true)"
        if [[ -n "${LATEST_BACKUP}" && -f "${LATEST_BACKUP}/xfconf-xfce4-panel.txt" ]]; then
            RESTORE_SOURCE="${LATEST_BACKUP}/xfconf-xfce4-panel.txt"
        fi
    fi

    if [[ -n "${RESTORE_SOURCE}" ]]; then
        log_info "Restoring settings from: ${RESTORE_SOURCE}"
        restore_panel_state "${RESTORE_SOURCE}"
        pkill -9 -x xfce4-panel >/dev/null 2>&1 || true
        sleep 0.5
        ( xfce4-panel & ) >/dev/null 2>&1
        sleep 1
        log_success "Restoration complete."
    else
        log_warn "No snapshot file found to restore from."
    fi
fi

# 3. Print Final Diagnostic State
echo ""
echo "=========================================================="
log_info "Final Panel State Summary:"
echo "=========================================================="
if pgrep -x xfce4-panel >/dev/null 2>&1; then
    printf "  Process:    ${C_GREEN}RUNNING (PID %s)${C_RESET}\n" "$(pgrep -x xfce4-panel | tr '\n' ' ')"
else
    printf "  Process:    ${C_RED}NOT RUNNING${C_RESET}\n"
fi

if command -v xfconf-query &>/dev/null; then
    PANELS="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || echo "None")"
    printf "  Panels:     %s\n" "${PANELS//$'\n'/ }"

    FINAL_PLUGINS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    printf "  Panel-1 IDs (%d items): %s\n" "${#FINAL_PLUGINS[@]}" "${FINAL_PLUGINS[*]:-None}"

    echo ""
    log_info "Panel-1 Plugin Details:"
    for pid in "${FINAL_PLUGINS[@]}"; do
        ptype="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || echo "unknown")"
        printf "    - plugin-%s: %s\n" "${pid}" "${ptype}"
    done
fi
echo "=========================================================="
