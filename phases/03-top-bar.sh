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

    if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
        xfce4-panel -r 2>/dev/null || true
    fi

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
# 3. Deploy GTK 3.0 CSS Stylesheet
# ------------------------------------------------------------------------------
run mkdir -p "${GTK_CONFIG_DIR}"
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
set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "0"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"

# ------------------------------------------------------------------------------
# 5. Remove Tasklist (Window Buttons) from Top Menu Bar (Dock handles open apps)
# ------------------------------------------------------------------------------
log_info "Ensuring tasklist (window buttons) is removed from top bar (dock handles windows)..."
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would filter tasklist plugin from panel-1 plugin-ids array"
elif command -v xfconf-query &>/dev/null; then
    CURRENT_IDS=($(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | tr '\n' ' ' || true))
    if [[ ${#CURRENT_IDS[@]} -gt 0 ]]; then
        FILTERED_IDS=()
        TASKLIST_FOUND=0
        for pid in "${CURRENT_IDS[@]}"; do
            PTYPE="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || true)"
            if [[ "${PTYPE}" == "tasklist" || "${PTYPE}" == "windowmenu" ]]; then
                log_info "Identified tasklist plugin-${pid} on panel-1. Removing..."
                TASKLIST_FOUND=1
            else
                FILTERED_IDS+=("${pid}")
            fi
        done

        if [[ "${TASKLIST_FOUND}" -eq 1 && ${#FILTERED_IDS[@]} -gt 0 ]]; then
            XFCONF_ARGS=()
            for fpid in "${FILTERED_IDS[@]}"; do
                XFCONF_ARGS+=("-t" "int" "-s" "${fpid}")
            done
            xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -r -R 2>/dev/null || true
            xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids --create -a "${XFCONF_ARGS[@]}" 2>/dev/null || true
            log_success "Tasklist removed from top bar. Remaining plugins: ${FILTERED_IDS[*]}"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 6. Configure Apple Logo Launcher & macOS Clock Format
# ------------------------------------------------------------------------------
APPLE_ICON_PATH="${HOME}/.local/share/icons/apple-logo.svg"
if [[ ! -f "${APPLE_ICON_PATH}" && -f "${REPO_ROOT}/assets/icons/apple-logo.svg" ]]; then
    safe_copy "${REPO_ROOT}/assets/icons/apple-logo.svg" "${APPLE_ICON_PATH}"
fi

if command -v xfconf-query &>/dev/null; then
    PLUGINS="$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null || true)"
    for p in ${PLUGINS}; do
        NAME="$(xfconf-query -c xfce4-panel -p "${p}" 2>/dev/null || true)"

        # Apple icon on Whisker Menu
        if [[ "${NAME}" == "whiskermenu" ]]; then
            log_info "Found Whisker Menu at ${p}, setting Apple icon..."
            if [[ -f "${APPLE_ICON_PATH}" ]]; then
                set_xfconf_prop "xfce4-panel" "${p}/button-icon" "string" "${APPLE_ICON_PATH}"
            fi
            set_xfconf_prop "xfce4-panel" "${p}/button-title" "string" ""
            set_xfconf_prop "xfce4-panel" "${p}/show-button-title" "bool" "false"
            set_xfconf_prop "xfce4-panel" "${p}/show-button-icon" "bool" "true"

        # macOS Clock Format: "ddd d MMM  h:mm a" -> %a %e %b  %l:%M %P
        elif [[ "${NAME}" == "clock" || "${NAME}" == "datetime" ]]; then
            log_info "Found Clock plugin at ${p}, configuring macOS Sequoia date/time..."
            # Format: e.g. "Mon 12 Oct  10:45 AM"
            set_xfconf_prop "xfce4-panel" "${p}/digital-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "${p}/digital-time-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "${p}/mode" "uint" "2"

        # Expand separator to push clock and tray items to the far right
        elif [[ "${NAME}" == "separator" ]]; then
            set_xfconf_prop "xfce4-panel" "${p}/expand" "bool" "true"
            set_xfconf_prop "xfce4-panel" "${p}/style" "uint" "0"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 6. Safety Check & Panel Reload
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would reload xfce4-panel"
elif [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
    log_info "Reloading xfce4-panel to apply updated geometry and CSS..."
    xfce4-panel -r 2>/dev/null || log_warn "Panel reload deferred."
fi

log_success "Phase 3 Complete: Top Menu Bar configured (28px height, macOS Sequoia clock)."
log_info "Undo this phase anytime with: ./phases/03-top-bar.sh --undo (or ./uninstall.sh -p 3)"
