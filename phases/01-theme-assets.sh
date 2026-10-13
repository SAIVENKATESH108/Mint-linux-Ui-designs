#!/usr/bin/env bash
# ==============================================================================
# Phase 1: Prerequisites & Theme Assets (WhiteSur GTK / Icons / Cursors)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 1: Starting Theme & Assets Installation"

# 1. Dependency checks for theme compilation and rendering
REQUIRED_PKGS=(
    "sassc"
    "libglib2.0-bin"
    "gtk2-engines-murrine"
    "gtk2-engines-pixbuf"
    "optipng"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Extract and Install Vendored WhiteSur GTK Theme
THEME_DEST="${HOME}/.themes"
mkdir -p "${THEME_DEST}"

BUILD_TMP="$(mktemp -d -t whitesur-build-XXXXXX)"
trap 'rm -rf "${BUILD_TMP}"' EXIT

if [[ ! -d "${THEME_DEST}/WhiteSur-Dark" ]]; then
    log_info "Extracting and installing vendored WhiteSur GTK theme..."
    tar -zxf "${VENDOR_DIR}/archives/WhiteSur-gtk-theme.tar.gz" -C "${BUILD_TMP}"
    
    # Run vendored installer targeting local user themes
    (
        cd "${BUILD_TMP}/WhiteSur-gtk-theme-master"
        ./install.sh -d "${THEME_DEST}" -c Dark -t default -N glassy -o normal --normal
    )
    log_success "WhiteSur GTK theme installed into ${THEME_DEST}"
else
    log_success "WhiteSur GTK theme already installed in ${THEME_DEST}"
fi

# 3. Extract and Install Vendored WhiteSur Icon Theme
ICON_DEST="${HOME}/.icons"
mkdir -p "${ICON_DEST}"

if [[ ! -d "${ICON_DEST}/WhiteSur-dark" && ! -d "${ICON_DEST}/WhiteSur" ]]; then
    log_info "Extracting and installing vendored WhiteSur icon theme..."
    tar -zxf "${VENDOR_DIR}/archives/WhiteSur-icon-theme.tar.gz" -C "${BUILD_TMP}"
    
    (
        cd "${BUILD_TMP}/WhiteSur-icon-theme-master"
        ./install.sh -d "${ICON_DEST}" -t default -a
    )
    log_success "WhiteSur Icon theme installed into ${ICON_DEST}"
else
    log_success "WhiteSur Icon theme already installed in ${ICON_DEST}"
fi

# 4. Install Custom Assets (Apple Logo for Panel Launcher)
APPLE_ICON_SRC="${REPO_ROOT}/assets/icons/apple-logo.svg"
APPLE_ICON_DEST="${HOME}/.local/share/icons/apple-logo.svg"
safe_copy "${APPLE_ICON_SRC}" "${APPLE_ICON_DEST}"

# 5. Apply GTK, Icon, and Window Manager Themes via xfconf
log_info "Applying theme settings via xfconf..."

# GTK application theme
set_xfconf_prop "xsettings" "/Net/ThemeName" "string" "WhiteSur-Dark"

# Icon theme
if [[ -d "${ICON_DEST}/WhiteSur-dark" ]]; then
    set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "WhiteSur-dark"
else
    set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "WhiteSur"
fi

# Cursor theme (WhiteSur-cursors or fallback)
if [[ -d "${ICON_DEST}/WhiteSur-cursors" || -d "${HOME}/.icons/WhiteSur-cursors" ]]; then
    set_xfconf_prop "xsettings" "/Gtk/CursorThemeName" "string" "WhiteSur-cursors"
fi

# Window Manager (xfwm4) theme
set_xfconf_prop "xfwm4" "/general/theme" "string" "WhiteSur-Dark"

# Default Sequoia font
set_xfconf_prop "xsettings" "/Gtk/FontName" "string" "Inter 10"

log_success "Phase 1 Complete: WhiteSur GTK & Icon themes applied successfully."
