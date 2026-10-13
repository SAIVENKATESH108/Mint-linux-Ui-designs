#!/usr/bin/env bash
# ==============================================================================
# Phase 5: Left Workspace Sidebar (76px Floating Panel, 4 Desktops, 3 Launchers)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

GTK_CONFIG_DIR="${HOME}/.config/gtk-3.0"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 5
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 5: Removing Left Sidebar (panel-2)..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would revert left sidebar (panel-2) and restore xfconf settings"
        return 0
    fi

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase5 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded xfconf settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf replay warning."
    else
        log_info "Removing panel-2 configuration..."
        if command -v xfconf-query &>/dev/null; then
            xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
            set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
        fi
    fi

    if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r 2>/dev/null || true
    fi

    log_success "Phase 5 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 5: Configuring Left Workspace Sidebar (76px width, 4 Desktops)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 5

# ------------------------------------------------------------------------------
# 2. Dependency Checks
# ------------------------------------------------------------------------------
REQUIRED_PKGS=(
    "xfce4-panel"
    "xfce4-timer-plugin"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Ensure 4 Workspaces Configured in xfwm4
# ------------------------------------------------------------------------------
log_info "Configuring 4 virtual desktop spaces (Desk 1..4)..."
set_xfconf_prop "xfwm4" "/general/workspace_count" "int" "4"

# Set friendly names for the 4 spaces
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would set workspace names: Desk 1, Desk 2, Desk 3, Desk 4"
elif command -v xfconf-query &>/dev/null; then
    xfconf-query -c xfwm4 -p /general/workspace_names --create -t string -s "Desk 1" -t string -s "Desk 2" -t string -s "Desk 3" -t string -s "Desk 4" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Deploy Updated GTK 3.0 CSS (Panel-2 Sidebar Styling)
# ------------------------------------------------------------------------------
run mkdir -p "${GTK_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/gtk-3.0/gtk.css" "${GTK_CONFIG_DIR}/gtk.css"

# ------------------------------------------------------------------------------
# 5. Configure panel-2 Geometry via xfconf
# ------------------------------------------------------------------------------
log_info "Configuring panel-2 as a 76px vertical sidebar on left edge..."

# Add panel-2 to panels array if not already present
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would ensure panel-2 is in xfce4-panel panels array"
elif command -v xfconf-query &>/dev/null; then
    CURRENT_PANELS="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || echo "1")"
    if [[ "${CURRENT_PANELS}" != *"2"* ]]; then
        xfconf-query -c xfce4-panel -p /panels --create -t int -s 1 -t int -s 2 2>/dev/null || true
    fi
fi

# Geometry: vertical left edge (p=9 is floating vertical, x=10, y=38)
set_xfconf_prop "xfce4-panel" "/panels/panel-2/position" "string" "p=9;x=10;y=38"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/size" "uint" "76"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/icon-size" "uint" "24"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/length" "uint" "58"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/position-locked" "bool" "true"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/autohide-behavior" "uint" "0" # Visible by default
set_xfconf_prop "xfce4-panel" "/panels/panel-2/background-style" "uint" "0"

# ------------------------------------------------------------------------------
# 6. Safety Check & Panel Reload
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would reload xfce4-panel to activate left sidebar"
elif [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
    log_info "Reloading xfce4-panel to activate left sidebar..."
    xfce4-panel -r 2>/dev/null || log_warn "Panel reload deferred."
fi

log_success "Phase 5 Complete: Left Sidebar configured (76px width, 4 desktop pager)."
log_info "Undo this phase anytime with: ./phases/05-left-sidebar.sh --undo (or ./uninstall.sh -p 5)"
