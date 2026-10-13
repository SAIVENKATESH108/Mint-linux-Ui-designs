#!/usr/bin/env bash
# ==============================================================================
# Phase 3: Top Menu Bar Configuration (xfce4-panel styled via CSS)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 3: Starting Top Menu Bar Configuration"

# 1. Dependency Checks
REQUIRED_PKGS=(
    "xfce4-panel"
    "xfce4-whiskermenu-plugin"
    "xfce4-pulseaudio-plugin"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Back up and Install GTK3 CSS Styling
GTK_CONFIG_DIR="${HOME}/.config/gtk-3.0"
mkdir -p "${GTK_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/gtk-3.0/gtk.css" "${GTK_CONFIG_DIR}/gtk.css"

# 3. Configure Top Panel Geometry via xfconf
log_info "Configuring panel-1 as macOS Sequoia top menu bar..."

# Ensure only panel-1 is active (retiring panel-2 if it was a bottom dock)
# First back up panel channel xml
PANEL_XML="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
backup_item "${PANEL_XML}"

# Set single panel array
set_xfconf_prop "xfce4-panel" "/panels" "int" "1"

# Geometry: 26px height, 16px icon size, 100% width, locked, top edge (p=6 is top edge in XFCE)
set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "26"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/icon-size" "uint" "16"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/length" "uint" "100"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/position-locked" "bool" "true"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "0"
set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"

# 4. Configure Whisker Menu as Apple Menu Button
log_info "Configuring Whisker Menu button to show Apple icon..."
APPLE_ICON_PATH="${HOME}/.local/share/icons/apple-logo.svg"

# Search all plugins for whiskermenu
if command -v xfconf-query &>/dev/null; then
    PLUGINS="$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null || true)"
    for p in ${PLUGINS}; do
        NAME="$(xfconf-query -c xfce4-panel -p "${p}" 2>/dev/null || true)"
        if [[ "${NAME}" == "whiskermenu" ]]; then
            log_info "Found Whisker Menu at ${p}"
            set_xfconf_prop "xfce4-panel" "${p}/button-icon" "string" "${APPLE_ICON_PATH}"
            set_xfconf_prop "xfce4-panel" "${p}/button-title" "string" ""
            set_xfconf_prop "xfce4-panel" "${p}/show-button-title" "bool" "false"
            set_xfconf_prop "xfce4-panel" "${p}/show-button-icon" "bool" "true"
        elif [[ "${NAME}" == "clock" || "${NAME}" == "datetime" ]]; then
            log_info "Found Clock plugin at ${p}, setting macOS date/time format..."
            set_xfconf_prop "xfce4-panel" "${p}/digital-format" "string" "%a %d %b  %l:%M %p"
            set_xfconf_prop "xfce4-panel" "${p}/digital-time-format" "string" "%a %d %b  %l:%M %p"
            set_xfconf_prop "xfce4-panel" "${p}/mode" "uint" "2"
        fi
    done
fi

# 5. Reload Panel if running inside X11 session
if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
    log_info "Reloading xfce4-panel to apply new styles and layout..."
    xfce4-panel -r || log_warn "Could not reload xfce4-panel automatically."
fi

log_success "Phase 3 Complete: Top Menu Bar configured and styled."
