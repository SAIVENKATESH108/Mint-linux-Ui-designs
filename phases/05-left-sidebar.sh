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

    rm -f "${GTK_CONFIG_DIR}/sequoia/sidebar.css"
    if [[ ! -f "${GTK_CONFIG_DIR}/sequoia/panel-top.css" ]]; then
        rm -f "${GTK_CONFIG_DIR}/sequoia/tokens.css"
        rm -f "${GTK_CONFIG_DIR}/gtk.css"
    fi

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase5 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded xfconf settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf replay warning."
    else
        log_info "Removing panel-2 configuration and plugins..."
        if command -v xfconf-query &>/dev/null; then
            local p2_plugins
            p2_plugins="$(xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids 2>/dev/null | tr '\n' ' ' || true)"
            for pid in ${p2_plugins}; do
                xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" -r -R 2>/dev/null || true
            done
            xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
            set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
        fi
    fi

    guarded_panel_reload

    log_success "Phase 5 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

WITH_SIDEBAR="${WITH_SIDEBAR:-0}"
FALLBACK_PLANK_DOCK="${FALLBACK_PLANK_DOCK:-0}"

for arg in "$@"; do
    case "${arg}" in
        --with-sidebar) WITH_SIDEBAR=1 ;;
        --fallback-plank-dock) FALLBACK_PLANK_DOCK=1 ;;
    esac
done

if [[ "${WITH_SIDEBAR}" -eq 0 ]]; then
    log_warn "Phase 5 (Left Workspace Sidebar) is OPT-IN and skipped by default."
    log_info "Position codes (p=...) in XFCE must be calibrated via GUI (drag panel to left edge)."
    log_info "To run this phase explicitly, use: ./phases/05-left-sidebar.sh --with-sidebar"
    exit 0
fi

log_info "Phase 5: Configuring Left Workspace Sidebar (76px width, 4 Desktops, Opt-In)"

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
# 4. Deploy Modular GTK 3.0 CSS Stylesheets (Tokens & Sidebar Fragment)
# ------------------------------------------------------------------------------
run mkdir -p "${GTK_CONFIG_DIR}/sequoia"
safe_copy "${CONFIG_DIR}/gtk-3.0/sequoia/tokens.css" "${GTK_CONFIG_DIR}/sequoia/tokens.css"
safe_copy "${CONFIG_DIR}/gtk-3.0/sequoia/sidebar.css" "${GTK_CONFIG_DIR}/sequoia/sidebar.css"
safe_copy "${CONFIG_DIR}/gtk-3.0/gtk.css" "${GTK_CONFIG_DIR}/gtk.css"

# ------------------------------------------------------------------------------
# 5. Configure panel-2 Geometry via xfconf (Mode 1: True Vertical)
# ------------------------------------------------------------------------------
log_info "Configuring panel-2 as a 76px true vertical sidebar..."

# Add panel-2 to panels array if not already present
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would ensure panel-2 is in xfce4-panel panels array"
elif command -v xfconf-query &>/dev/null; then
    CURRENT_PANELS="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || echo "1")"
    if [[ "${CURRENT_PANELS}" != *"2"* ]]; then
        xfconf-query -c xfce4-panel -p /panels --create -t int -s 1 -t int -s 2 2>/dev/null || true
    fi
fi

# Critical: mode = 1 is VERTICAL in XFCE 4.18 panel (mode 0 is horizontal)
set_xfconf_prop "xfce4-panel" "/panels/panel-2/mode" "uint" "1"
# In vertical mode, size is width (76px) and length is height percentage (58%)
set_xfconf_prop "xfce4-panel" "/panels/panel-2/size" "uint" "76"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/icon-size" "uint" "24"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/length" "uint" "58"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/length-adjust" "bool" "false"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/position-locked" "bool" "true"
set_xfconf_prop "xfce4-panel" "/panels/panel-2/autohide-behavior" "uint" "0" # Visible by default
set_xfconf_prop "xfce4-panel" "/panels/panel-2/background-style" "uint" "0"

# Note on position: do NOT hardcode unverified p=1 codes.
# Preserve existing position if configured in GUI; otherwise notify user.
if command -v xfconf-query &>/dev/null; then
    EXISTING_POS="$(xfconf-query -c xfce4-panel -p /panels/panel-2/position 2>/dev/null || true)"
    if [[ -n "${EXISTING_POS}" ]]; then
        log_info "Preserving calibrated panel-2 position: ${EXISTING_POS}"
    else
        log_warn "No position set for panel-2. In Panel Preferences, position it on the left,"
        log_warn "then read back via: xfconf-query -c xfce4-panel -p /panels/panel-2/position"
    fi
fi

# ------------------------------------------------------------------------------
# 6. Configure Dynamically Allocated Plugins for Panel-2
# ------------------------------------------------------------------------------
log_info "Configuring sidebar plugins (4-row pager, spacer, shortcuts)..."

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would dynamically allocate 4 plugin IDs for panel-2 [pager, separator, showdesktop, actions]"
elif command -v xfconf-query &>/dev/null; then
    P_BASE="$(allocate_next_plugin_id)"
    P_PAGER="${P_BASE}"
    P_SEP="$((P_BASE + 1))"
    P_SHOWDESK="$((P_BASE + 2))"
    P_ACTIONS="$((P_BASE + 3))"

    log_info "Dynamically allocated plugin IDs: ${P_PAGER} (pager), ${P_SEP} (separator), ${P_SHOWDESK} (showdesktop), ${P_ACTIONS} (actions)"

    # Plugin: Pager with 4 vertical rows
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_PAGER}" "string" "pager"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_PAGER}/rows" "uint" "4"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_PAGER}/miniature-view" "bool" "true"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_PAGER}/numbering" "bool" "true"

    # Plugin: Expanding transparent separator
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_SEP}" "string" "separator"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_SEP}/style" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_SEP}/expand" "bool" "true"

    # Plugin: Show Desktop
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_SHOWDESK}" "string" "showdesktop"

    # Plugin: Power / Session action button at bottom (Strict GPtrArray string array)
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_ACTIONS}" "string" "actions"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-${P_ACTIONS}/appearance" "uint" "0"
    set_xfconf_string_array "xfce4-panel" "/plugins/plugin-${P_ACTIONS}/items" "+lock-screen" "+logout"

    # Assign dynamically allocated plugins to panel-2
    set_xfconf_int_array "xfce4-panel" "/panels/panel-2/plugin-ids" "${P_PAGER}" "${P_SEP}" "${P_SHOWDESK}" "${P_ACTIONS}"
fi

# ------------------------------------------------------------------------------
# 7. Verification: Confirm Vertical Orientation & Visible Window Before Reload
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would verify panel-2 mode is vertical (mode=1) and plugins exist"
    log_dry "Would perform guarded panel reload"
else
    # 1. Verify orientation is vertical
    PANEL_MODE="$(xfconf-query -c xfce4-panel -p /panels/panel-2/mode 2>/dev/null || echo "0")"
    if [[ "${PANEL_MODE}" != "1" ]]; then
        log_error "Verification FAILED: panel-2 mode is '${PANEL_MODE}' (expected '1' for Vertical). Aborting reload."
        exit 1
    fi

    # 2. Verify plugins exist
    PANEL_PLUGINS="$(read_xfconf_int_array "xfce4-panel" "/panels/panel-2/plugin-ids")"
    if [[ -z "${PANEL_PLUGINS}" ]]; then
        log_error "Verification FAILED: panel-2 plugin-ids is empty. Aborting reload."
        exit 1
    fi

    log_success "Verified: panel-2 is VERTICAL (mode=1) with active plugins: ${PANEL_PLUGINS//$'\n'/ }"
    guarded_panel_reload

    # 3. Check for dock/panel window presence if DISPLAY is active
    if [[ -n "${DISPLAY:-}" ]] && command -v wmctrl &>/dev/null; then
        if ! wmctrl -l -G 2>/dev/null | grep -i 'panel' | grep -qE '[[:space:]]76[[:space:]]'; then
            log_warn "Visual verification: 76px window not confirmed via wmctrl."
            log_info "Fallback available: You can run with --fallback-plank-dock to use a secondary left Plank dock."
        fi
    fi
fi

log_success "Phase 5 Complete: Left Sidebar configured (76px width, 4 desktop pager)."
log_info "Undo this phase anytime with: ./phases/05-left-sidebar.sh --undo (or ./uninstall.sh -p 5)"
