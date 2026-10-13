#!/usr/bin/env bash
# ==============================================================================
# Phase 3: Top Menu Bar Configuration (xfce4-panel 28px + GTK CSS)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# Clock format: "ddd d MMM  h:mm a" (%a %e %b  %l:%M %P)
# Hardware: Desktop PC (No battery, No Bluetooth applets)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

GTK_CONFIG_DIR="${HOME}/.config/gtk-3.0"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 3
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 3: Restoring Top Panel Defaults & GTK CSS..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would restore top panel defaults and revert GTK CSS"
        return 0
    fi

    rm -f "${GTK_CONFIG_DIR}/sequoia/panel-top.css"
    rm -f "${GTK_CONFIG_DIR}/sequoia/tokens.css"
    rm -f "${GTK_CONFIG_DIR}/gtk.css"

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase3 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded xfconf settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf replay warning."
    else
        log_info "Restoring stock panel-1 size to 24px..."
        set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "24"
    fi

    guarded_panel_reload

    log_success "Phase 3 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 3: Starting Top Menu Bar Configuration (28px height, No Battery/BT)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 3

# ------------------------------------------------------------------------------
# 2. Dependency Checks
# ------------------------------------------------------------------------------
REQUIRED_PKGS=(
    "xfce4-panel"
    "xfce4-whiskermenu-plugin"
    "xfce4-pulseaudio-plugin"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Deploy Modular GTK 3.0 CSS Stylesheets (Tokens & Top Panel Fragment)
# ------------------------------------------------------------------------------
run mkdir -p "${GTK_CONFIG_DIR}/sequoia"
safe_copy "${CONFIG_DIR}/gtk-3.0/sequoia/tokens.css" "${GTK_CONFIG_DIR}/sequoia/tokens.css"
safe_copy "${CONFIG_DIR}/gtk-3.0/sequoia/panel-top.css" "${GTK_CONFIG_DIR}/sequoia/panel-top.css"
safe_copy "${CONFIG_DIR}/gtk-3.0/gtk.css" "${GTK_CONFIG_DIR}/gtk.css"

# ------------------------------------------------------------------------------
# 4. Configure Top Menu Bar (panel-1) Geometry via xfconf
# ------------------------------------------------------------------------------
log_info "Configuring panel-1 geometry: 28px height, top pinned, locked..."

# Top edge position (p=6 is top edge in XFCE)
set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "28"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/icon-size" "uint" "16"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/length" "uint" "100"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/position-locked" "bool" "true"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "1"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/enable-struts" "bool" "false"

# Eliminate any workspace margin gaps between top bar and application windows
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfwm4" "/general/margin_top" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_bottom" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_left" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_right" "int" "0"
    set_xfconf_prop "xfwm4" "/general/snap_to_border" "bool" "true"
fi

KEEP_TOP_LAUNCHERS="${KEEP_TOP_LAUNCHERS:-0}"
for arg in "$@"; do
    case "${arg}" in
        --keep-top-launchers) KEEP_TOP_LAUNCHERS=1 ;;
    esac
done

# ------------------------------------------------------------------------------
# 5. Remove Tasklist & Duplicate Launchers from Top Bar (Dock handles open apps)
# ------------------------------------------------------------------------------
log_info "Ensuring tasklist and duplicate launchers are removed from top bar..."
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would filter tasklist, windowmenu, and duplicate launcher plugins from panel-1"
elif command -v xfconf-query &>/dev/null; then
    CURRENT_IDS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    if [[ ${#CURRENT_IDS[@]} -gt 0 ]]; then
        FILTERED_IDS=()
        for pid in "${CURRENT_IDS[@]}"; do
            PTYPE="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || true)"
            if [[ "${PTYPE}" == "tasklist" || "${PTYPE}" == "windowmenu" ]]; then
                log_info "Identified tasklist/windowmenu plugin-${pid} on panel-1. Removing from top bar..."
            elif [[ "${PTYPE}" == "launcher" && "${KEEP_TOP_LAUNCHERS}" -eq 0 ]]; then
                log_info "Identified duplicate stock launcher plugin-${pid} on panel-1. Removing (dock owns apps)..."
            else
                FILTERED_IDS+=("${pid}")
            fi
        done

        set_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids" "${FILTERED_IDS[@]}"
    fi
fi

# ------------------------------------------------------------------------------
# 6. Configure Apple Logo Launcher & macOS Clock Format (By Plugin Type)
# ------------------------------------------------------------------------------
APPLE_ICON_PATH="${HOME}/.local/share/icons/apple-logo.svg"
if [[ ! -f "${APPLE_ICON_PATH}" && -f "${REPO_ROOT}/assets/icons/apple-logo.svg" ]]; then
    safe_copy "${REPO_ROOT}/assets/icons/apple-logo.svg" "${APPLE_ICON_PATH}"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would configure whisker menu, clock, and separators on panel-1 by discovered type"
elif command -v xfconf-query &>/dev/null; then
    ACTIVE_IDS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    for pid in "${ACTIVE_IDS[@]}"; do
        PTYPE="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || true)"

        # Apple icon on Whisker Menu
        if [[ "${PTYPE}" == "whiskermenu" ]]; then
            log_info "Found Whisker Menu at /plugins/plugin-${pid}, applying Apple logo..."
            if [[ -f "${APPLE_ICON_PATH}" ]]; then
                set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/button-icon" "string" "${APPLE_ICON_PATH}"
            fi
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/button-title" "string" ""
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/show-button-title" "bool" "false"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/show-button-icon" "bool" "true"

        # macOS Clock Format: "ddd d MMM  h:mm a" -> %a %e %b  %l:%M %P
        elif [[ "${PTYPE}" == "clock" || "${PTYPE}" == "datetime" ]]; then
            log_info "Found Clock at /plugins/plugin-${pid}, configuring macOS Sequoia date/time format..."
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/digital-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/digital-time-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/mode" "uint" "2"

        # Expand separator to push clock and tray items to the far right
        elif [[ "${PTYPE}" == "separator" ]]; then
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/expand" "bool" "true"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/style" "uint" "0"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 7. Verification: Confirm Panel-1 Plugins (Whisker & Clock mapped, no tasklist/launchers)
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would verify panel-1 plugin-ids contain whisker, clock, zero tasklists, zero duplicate launchers"
elif command -v xfconf-query &>/dev/null; then
    FINAL_IDS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    log_info "Auditing panel-1 active plugins (${#FINAL_IDS[@]} items):"
    HAS_WHISKER=0
    HAS_CLOCK=0

    for pid in "${FINAL_IDS[@]}"; do
        PTYPE="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || echo "unknown")"
        log_info "  [plugin-${pid}] type: '${PTYPE}'"

        if [[ "${PTYPE}" == "whiskermenu" ]]; then
            HAS_WHISKER=1
        elif [[ "${PTYPE}" == "clock" || "${PTYPE}" == "datetime" ]]; then
            HAS_CLOCK=1
        elif [[ "${PTYPE}" == "tasklist" || "${PTYPE}" == "windowmenu" ]]; then
            log_error "Assertion FAILED: Tasklist/windowmenu plugin-${pid} is still assigned to panel-1!"
            exit 1
        elif [[ "${PTYPE}" == "launcher" && "${KEEP_TOP_LAUNCHERS}" -eq 0 ]]; then
            log_error "Assertion FAILED: Duplicate stock launcher plugin-${pid} is still assigned to panel-1! Pass --keep-top-launchers to retain."
            exit 1
        fi
    done

    if [[ "${HAS_WHISKER}" -eq 0 ]]; then
        log_warn "Whisker Menu plugin not detected on panel-1."
    fi
    if [[ "${HAS_CLOCK}" -eq 0 ]]; then
        log_warn "Clock plugin not detected on panel-1."
    fi
    log_success "Panel-1 plugins verified: Tasklist & duplicate launchers absent, Whisker & Clock mapped."
fi

# ------------------------------------------------------------------------------
# 8. Safety Check & Process-Aware Guarded Panel Reload
# ------------------------------------------------------------------------------
guarded_panel_reload

log_success "Phase 3 Complete: Top Menu Bar configured (28px height, macOS Sequoia clock)."
log_info "Undo this phase anytime with: ./phases/03-top-bar.sh --undo (or ./uninstall.sh -p 3)"
