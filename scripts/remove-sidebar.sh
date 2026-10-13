#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - Remove Panel-2 Sidebar Utility
# Safely unregisters panel-2, removes all associated plugins (including stale plugin-23),
# resets panel count to 1, and triggers a guarded panel reload.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "==> Removing Panel-2 Sidebar and Cleaning Stale Plugins..."

if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log_dry "Would remove panel-2 and associated plugins"
    exit 0
fi

if ! command -v xfconf-query &>/dev/null; then
    log_error "xfconf-query not found."
    exit 1
fi

# 1. Take safety snapshot
SNAPSHOT_FILE="${HOME}/.cache/sequoia/panel-pre-remove-sidebar.txt"
snapshot_panel_state "${SNAPSHOT_FILE}"

# 2. Collect any plugins assigned to panel-2
P2_PLUGINS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-2/plugin-ids"))

# Also include stale plugin IDs 20..23 if they linger
for pid in 20 21 22 23 "${P2_PLUGINS[@]}"; do
    if xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" &>/dev/null; then
        log_info "Purging plugin-${pid} properties from xfce4-panel channel..."
        xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" -r -R 2>/dev/null || true
    fi
done

# 3. Remove panel-2 properties
log_info "Removing /panels/panel-2 property tree..."
xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true

# 4. Reset panels list to panel-1 only
set_xfconf_int_array "xfce4-panel" "/panels" 1

# 5. Clean up sidebar GTK CSS fragment
rm -f "${HOME}/.config/gtk-3.0/sequoia/sidebar.css"

# 6. Execute guarded reload
log_info "Executing guarded panel reload to commit changes..."
guarded_panel_reload

log_success "Panel-2 sidebar completely removed. Stale plugin warnings resolved."
