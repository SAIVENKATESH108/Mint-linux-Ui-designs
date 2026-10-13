#!/usr/bin/env bash
# ==============================================================================
# Phase 1: Theme & Visual Assets (WhiteSur GTK, Icons, Inter Font, Window Controls)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

THEME_DEST="${HOME}/.themes"
ICON_DEST="${HOME}/.icons"
LOCAL_BIN="${HOME}/.local/bin"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 1
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 1: Restoring Default Linux Mint XFCE Theme & Window Controls..."

    # Replay precise xfconf backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase1 2>/dev/null | head -n1 || true)"
    if [[ -z "${latest_backup}" ]]; then
        latest_backup="$(ls -td "${BACKUP_ROOT}"/* 2>/dev/null | head -n1 || true)"
    fi

    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded xfconf settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial xfconf replay warning."
    else
        log_info "Restoring stock Mint-Y defaults via xfconf..."
        set_xfconf_prop "xsettings" "/Net/ThemeName" "string" "Mint-Y-Dark"
        set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "Mint-Y"
        set_xfconf_prop "xsettings" "/Gtk/CursorThemeName" "string" "DMZ-White"
        set_xfconf_prop "xsettings" "/Gtk/FontName" "string" "Ubuntu 10"
        set_xfconf_prop "xfwm4" "/general/theme" "string" "Mint-Y-Dark"
        set_xfconf_prop "xfwm4" "/general/title_font" "string" "Ubuntu Bold 9"
        set_xfconf_prop "xfwm4" "/general/button_layout" "string" "O|HMC"
        set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "left"
    fi

    rm -f "${LOCAL_BIN}/toggle-theme.sh"
    log_success "Phase 1 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 1: Starting Theme & Assets Installation (Mint 22.3 / XFCE 4.18)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 1

# ------------------------------------------------------------------------------
# 2. Dependency Checks (sassc, glib, engines, fonts)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=(
    "sassc"
    "libglib2.0-bin"
    "gtk2-engines-murrine"
    "gtk2-engines-pixbuf"
    "optipng"
    "fonts-inter"
)
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Extract and Install WhiteSur GTK Theme (Vendor First, Git Clone Fallback)
# ------------------------------------------------------------------------------
mkdir -p "${THEME_DEST}"
BUILD_TMP="$(mktemp -d -t whitesur-build-XXXXXX)"
trap 'rm -rf "${BUILD_TMP}"' EXIT

GTK_TARBALL="${VENDOR_DIR}/archives/WhiteSur-gtk-theme.tar.gz"

if [[ -f "${GTK_TARBALL}" ]]; then
    if [[ ! -d "${THEME_DEST}/WhiteSur-Dark" || ! -d "${THEME_DEST}/WhiteSur-Light" ]]; then
        log_info "Extracting and compiling vendored WhiteSur GTK themes (Dark & Light)..."
        tar -zxf "${GTK_TARBALL}" -C "${BUILD_TMP}"
        (
            cd "${BUILD_TMP}/WhiteSur-gtk-theme-master"
            ./install.sh -d "${THEME_DEST}" -c Light Dark -t default -N glassy -o normal --normal
        )
        log_success "WhiteSur GTK theme variants installed into ${THEME_DEST}"
    else
        log_success "WhiteSur GTK theme already present in ${THEME_DEST}"
    fi
elif [[ "${OFFLINE_MODE}" -eq 0 ]] && command -v git &>/dev/null; then
    log_info "Vendored GTK tarball missing. Attempting online git fallback..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git "${BUILD_TMP}/WhiteSur-gtk-theme"
    (
        cd "${BUILD_TMP}/WhiteSur-gtk-theme"
        ./install.sh -d "${THEME_DEST}" -c Light Dark -t default -N glassy -o normal --normal
    )
    log_success "WhiteSur GTK theme cloned and installed."
else
    log_warn "WhiteSur GTK source not available. Proceeding with existing themes if present."
fi

# ------------------------------------------------------------------------------
# 4. Extract and Install WhiteSur Icon Theme (Vendor First, Git Clone Fallback)
# ------------------------------------------------------------------------------
mkdir -p "${ICON_DEST}"
ICON_TARBALL="${VENDOR_DIR}/archives/WhiteSur-icon-theme.tar.gz"

if [[ -f "${ICON_TARBALL}" ]]; then
    if [[ ! -d "${ICON_DEST}/WhiteSur-dark" && ! -d "${ICON_DEST}/WhiteSur" ]]; then
        log_info "Extracting and installing vendored WhiteSur icon themes..."
        tar -zxf "${ICON_TARBALL}" -C "${BUILD_TMP}"
        (
            cd "${BUILD_TMP}/WhiteSur-icon-theme-master"
            ./install.sh -d "${ICON_DEST}" -t default -a
        )
        log_success "WhiteSur Icon theme installed into ${ICON_DEST}"
    else
        log_success "WhiteSur Icon theme already present in ${ICON_DEST}"
    fi
elif [[ "${OFFLINE_MODE}" -eq 0 ]] && command -v git &>/dev/null; then
    log_info "Vendored Icon tarball missing. Attempting online git fallback..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "${BUILD_TMP}/WhiteSur-icon-theme"
    (
        cd "${BUILD_TMP}/WhiteSur-icon-theme"
        ./install.sh -d "${ICON_DEST}" -t default -a
    )
    log_success "WhiteSur Icon theme cloned and installed."
else
    log_warn "WhiteSur Icon source not available. Proceeding with existing icons if present."
fi

# ------------------------------------------------------------------------------
# 5. Install Custom Assets (Apple Logo SVG)
# ------------------------------------------------------------------------------
APPLE_ICON_SRC="${REPO_ROOT}/assets/icons/apple-logo.svg"
APPLE_ICON_DEST="${HOME}/.local/share/icons/apple-logo.svg"
if [[ -f "${APPLE_ICON_SRC}" ]]; then
    safe_copy "${APPLE_ICON_SRC}" "${APPLE_ICON_DEST}"
fi

# ------------------------------------------------------------------------------
# 6. Install Light/Dark Theme Switcher Script
# ------------------------------------------------------------------------------
mkdir -p "${LOCAL_BIN}"
TOGGLE_SRC="${REPO_ROOT}/scripts/toggle-theme.sh"
TOGGLE_DEST="${LOCAL_BIN}/toggle-theme.sh"
if [[ -f "${TOGGLE_SRC}" ]]; then
    safe_copy "${TOGGLE_SRC}" "${TOGGLE_DEST}"
    chmod +x "${TOGGLE_DEST}"
    log_success "Theme toggle utility installed: ${TOGGLE_DEST}"
fi

# ------------------------------------------------------------------------------
# 7. Apply XFCE Settings via xfconf
# ------------------------------------------------------------------------------
log_info "Applying macOS Sequoia desktop settings via xfconf..."

# Application GTK Theme (Default: WhiteSur-Dark)
set_xfconf_prop "xsettings" "/Net/ThemeName" "string" "WhiteSur-Dark"

# Icon Theme
if [[ -d "${ICON_DEST}/WhiteSur-dark" ]]; then
    set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "WhiteSur-dark"
elif [[ -d "${ICON_DEST}/WhiteSur" ]]; then
    set_xfconf_prop "xsettings" "/Net/IconThemeName" "string" "WhiteSur"
fi

# Cursor Theme
if [[ -d "${ICON_DEST}/WhiteSur-cursors" || -d "${HOME}/.icons/WhiteSur-cursors" ]]; then
    set_xfconf_prop "xsettings" "/Gtk/CursorThemeName" "string" "WhiteSur-cursors"
fi

# Fonts: Set Inter font per design tokens
set_xfconf_prop "xsettings" "/Gtk/FontName" "string" "Inter 10"
set_xfconf_prop "xsettings" "/Gtk/MonospaceFontName" "string" "JetBrains Mono 10"

# Window Manager (xfwm4): WhiteSur theme, Inter title font
set_xfconf_prop "xfwm4" "/general/theme" "string" "WhiteSur-Dark"
set_xfconf_prop "xfwm4" "/general/title_font" "string" "Inter Medium 10"

# Window Control Buttons on the Left (macOS Sequoia layout)
# 'C' = Close, 'H' = Hide (minimize), 'M' = Maximize, '|' = Title separator
set_xfconf_prop "xfwm4" "/general/button_layout" "string" "CHM|"
set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "center"

log_success "Phase 1 Complete: WhiteSur themes, Inter font, and macOS window buttons applied."
log_info "Test switching modes anytime with: ~/.local/bin/toggle-theme.sh"
log_info "Undo this phase anytime with: ./phases/01-theme.sh --undo (or ./uninstall.sh -p 1)"
