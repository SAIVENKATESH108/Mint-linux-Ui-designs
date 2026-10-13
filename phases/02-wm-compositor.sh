#!/usr/bin/env bash
# ==============================================================================
# Phase 2: Window Manager & Compositor Configuration (xfwm4 + Picom)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 2: Starting Window Manager & Compositor Configuration"

# Check mode flag: --lite (default for GT 610) or --full
MODE="lite"
for arg in "$@"; do
    case "${arg}" in
        --full)
            MODE="full"
            ;;
        --lite)
            MODE="lite"
            ;;
    esac
done

log_info "Compositor profile selected: [${MODE}]"

# 1. Dependency Check
REQUIRED_PKGS=("picom")
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Configure xfwm4 (Window Manager)
log_info "Configuring xfwm4 for macOS Sequoia window styling..."

# Window buttons layout: Close, Hide, Maximize on left | title centered
set_xfconf_prop "xfwm4" "/general/button_layout" "string" "CHM|"
set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "center"
set_xfconf_prop "xfwm4" "/general/title_font" "string" "Inter Bold 11"
set_xfconf_prop "xfwm4" "/general/double_click_action" "string" "maximize"
set_xfconf_prop "xfwm4" "/general/click_to_focus" "bool" "true"

# Disable xfwm4 built-in compositing to prevent conflict with Picom
set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "false"

# 3. Install Picom Configuration
PICOM_CONFIG_DIR="${HOME}/.config/picom"
mkdir -p "${PICOM_CONFIG_DIR}"

if [[ "${MODE}" == "full" ]]; then
    safe_copy "${CONFIG_DIR}/picom/picom-full.conf" "${PICOM_CONFIG_DIR}/picom.conf"
else
    safe_copy "${CONFIG_DIR}/picom/picom-lite.conf" "${PICOM_CONFIG_DIR}/picom.conf"
fi

# 4. Enable Picom Autostart
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"
safe_copy "${CONFIG_DIR}/autostart/picom.desktop" "${AUTOSTART_DIR}/picom.desktop"

# 5. Restart or start Picom if running inside X11 session
if [[ -n "${DISPLAY:-}" ]]; then
    log_info "Reloading Picom in current session..."
    killall picom 2>/dev/null || true
    picom --config "${PICOM_CONFIG_DIR}/picom.conf" -b || log_warn "Picom failed to launch in background."
fi

log_success "Phase 2 Complete: xfwm4 & Picom (${MODE} mode) configured successfully."
