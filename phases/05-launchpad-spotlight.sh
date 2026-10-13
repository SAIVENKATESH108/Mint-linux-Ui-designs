#!/usr/bin/env bash
# ==============================================================================
# Phase 5: Launchpad & Spotlight Configuration (Rofi + xfdashboard)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 5: Starting Launchpad, Spotlight & Mission Control Configuration"

# 1. Dependency Checks
REQUIRED_PKGS=("rofi" "xfdashboard")
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Install Rofi Themes
ROFI_CONFIG_DIR="${HOME}/.config/rofi"
mkdir -p "${ROFI_CONFIG_DIR}"
safe_copy "${CONFIG_DIR}/rofi/spotlight.rasi" "${ROFI_CONFIG_DIR}/spotlight.rasi"
safe_copy "${CONFIG_DIR}/rofi/launchpad.rasi" "${ROFI_CONFIG_DIR}/launchpad.rasi"

# 3. Install Helper Executable Wrappers
USER_BIN_DIR="${HOME}/.local/bin"
mkdir -p "${USER_BIN_DIR}"
safe_copy "${REPO_ROOT}/scripts/spotlight.sh" "${USER_BIN_DIR}/spotlight.sh"
safe_copy "${REPO_ROOT}/scripts/launchpad.sh" "${USER_BIN_DIR}/launchpad.sh"
safe_copy "${REPO_ROOT}/scripts/mission-control.sh" "${USER_BIN_DIR}/mission-control.sh"
chmod +x "${USER_BIN_DIR}/spotlight.sh" "${USER_BIN_DIR}/launchpad.sh" "${USER_BIN_DIR}/mission-control.sh"

# 4. Install xfdashboard Theme
XFDASHBOARD_THEME_DIR="${HOME}/.local/share/xfdashboard/themes/Sequoia"
mkdir -p "${XFDASHBOARD_THEME_DIR}"
safe_copy "${CONFIG_DIR}/xfdashboard/xfdashboard.css" "${XFDASHBOARD_THEME_DIR}/xfdashboard.css"

# 5. Configure Keyboard Shortcuts in XFCE
log_info "Configuring keyboard shortcuts for Spotlight (Super+Space) and Launchpad (F4/Super+A)..."
KB_CHANNEL="xfce4-keyboard-shortcuts"

# Spotlight: Super+Space
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>space" "string" "${USER_BIN_DIR}/spotlight.sh"

# Launchpad: F4 and Super+A
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F4" "string" "${USER_BIN_DIR}/launchpad.sh"
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>a" "string" "${USER_BIN_DIR}/launchpad.sh"

# Mission Control: F3 and Super+Up
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F3" "string" "${USER_BIN_DIR}/mission-control.sh"
set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>Up" "string" "${USER_BIN_DIR}/mission-control.sh"

log_success "Phase 5 Complete: Spotlight, Launchpad, and Mission Control ready."
