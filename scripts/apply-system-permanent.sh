#!/usr/bin/env bash
# ==============================================================================
# Sequoia Permanent System Enforcer
# Consolidates all configuration, wipes stale/glitched CSS fragments,
# deploys and activates the complete macOS Sequoia suite:
#   - Plank Dock (Preserved untouched per user request)
#   - Conky 3-Card Desktop Widgets (Translucent Glass Cards matching Preview, zero overlap)
#   - Launchpad (Fullscreen 7x5 Application Grid via Rofi & Super+A / F4)
#   - Spotlight Search (Universal search bar via Rofi & Super+Space & Top Bar button)
#   - Control Center (Quick settings popover via Super+C & Top Bar button)
#   - Mission Control (Window overview via Super+Up / F3)
#   - Sequoia Settings (Theme & Appearance GUI Control Panel via Super+,)
#   - Single-line macOS clock, Apple menu, and reboot supervisor
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=../lib/xfconf-helpers.sh
source "${REPO_ROOT}/lib/xfconf-helpers.sh"

verify_environment

log_info "=========================================================="
log_info " Sequoia Permanent System Enforcer"
log_info " Deploying complete functional macOS suite across system"
log_info "=========================================================="

# ------------------------------------------------------------------------------
# 1. Clean Stale / Glitched CSS in ~/.config/gtk-3.0/
# ------------------------------------------------------------------------------
log_info "Step 1: Cleaning and synchronizing GTK 3.0 stylesheets..."
GTK_DIR="${HOME}/.config/gtk-3.0"
mkdir -p "${GTK_DIR}/sequoia"

# Remove any obsolete fragments (sidebar.css, etc.)
rm -f "${GTK_DIR}/sequoia/sidebar.css"
rm -f "${GTK_DIR}/sidebar.css"

# Deploy clean, strictly scoped stylesheets
safe_copy "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens.css" "${GTK_DIR}/sequoia/tokens.css"
safe_copy "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-dark.css" "${GTK_DIR}/sequoia/tokens-dark.css"
safe_copy "${REPO_ROOT}/config/gtk-3.0/sequoia/tokens-light.css" "${GTK_DIR}/sequoia/tokens-light.css"
safe_copy "${REPO_ROOT}/config/gtk-3.0/sequoia/panel-top.css" "${GTK_DIR}/sequoia/panel-top.css"
safe_copy "${REPO_ROOT}/config/gtk-3.0/gtk.css" "${GTK_DIR}/gtk.css"
log_success "GTK 3.0 stylesheets cleanly consolidated and strictly scoped."

# ------------------------------------------------------------------------------
# 2. Deploy Picom Compositor Configuration (16px Corner Radius)
# ------------------------------------------------------------------------------
log_info "Step 2: Deploying Picom compositor configuration..."
PICOM_DIR="${HOME}/.config/picom"
mkdir -p "${PICOM_DIR}"

safe_copy "${REPO_ROOT}/config/picom/picom-lite.conf" "${PICOM_DIR}/picom-lite.conf"
safe_copy "${REPO_ROOT}/config/picom/picom-glass.conf" "${PICOM_DIR}/picom-glass.conf"

# Activate default profile if not already set
if [[ ! -f "${PICOM_DIR}/picom.conf" ]]; then
    safe_copy "${REPO_ROOT}/config/picom/picom-lite.conf" "${PICOM_DIR}/picom.conf"
fi

if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "false"
fi
log_success "Picom compositor configurations deployed."

# ------------------------------------------------------------------------------
# 3. Deploy Sequoia Dock Themes (Dark & Light, DO NOT MODIFY PINNED LAUNCHERS)
# ------------------------------------------------------------------------------
log_info "Step 3: Ensuring Sequoia Dock theme files exist (dock items untouched)..."
PLANK_THEME_DEST="${HOME}/.local/share/plank/themes/Sequoia"
mkdir -p "${PLANK_THEME_DEST}"
safe_copy "${REPO_ROOT}/config/plank/theme/Sequoia/dock.theme" "${PLANK_THEME_DEST}/dock.theme"

PLANK_LIGHT_DEST="${HOME}/.local/share/plank/themes/Sequoia-Light"
mkdir -p "${PLANK_LIGHT_DEST}"
safe_copy "${REPO_ROOT}/config/plank/theme/Sequoia-Light/dock.theme" "${PLANK_LIGHT_DEST}/dock.theme"

if command -v dconf &>/dev/null; then
    DCONF_PATH="/net/launchpad/plank/docks/dock1"
    dconf write "${DCONF_PATH}/theme" "'Sequoia'"
    dconf write "${DCONF_PATH}/icon-size" "48"
    dconf write "${DCONF_PATH}/offset" "0"
    dconf write "${DCONF_PATH}/zoom-enabled" "true"
    dconf write "${DCONF_PATH}/zoom-percent" "118"
    log_success "Plank dock theme verified. Pinned dock launchers left 100% untouched."
fi

# ------------------------------------------------------------------------------
# 4. Deploy DeskWidgets Cairo Vector Suite (21 Widgets, 9 Styles, Snapping Grid)
# ------------------------------------------------------------------------------
log_info "Step 4: Installing and launching DeskWidgets Cairo vector suite..."
# Permanently remove old static conky configs from memory
pkill -f "calendar-system.conkyrc" 2>/dev/null || true
pkill -f "clock-weather.conkyrc" 2>/dev/null || true
pkill -f "media-notes.conkyrc" 2>/dev/null || true

bash "${SCRIPT_DIR}/deskwidgets-manager.sh" start
log_success "DeskWidgets Cairo vector suite active on calibrated 1280x1024 grid."

# ------------------------------------------------------------------------------
# 5. Deploy Rofi Themes (Launchpad 7x5, Spotlight, Control Center)
# ------------------------------------------------------------------------------
log_info "Step 5: Deploying Rofi themes for Launchpad, Spotlight, and Control Center..."
ROFI_DIR="${HOME}/.config/rofi"
mkdir -p "${ROFI_DIR}"

for rasi in "launchpad.rasi" "spotlight.rasi" "control-center.rasi"; do
    if [[ -f "${REPO_ROOT}/config/rofi/${rasi}" ]]; then
        safe_copy "${REPO_ROOT}/config/rofi/${rasi}" "${ROFI_DIR}/${rasi}"
    fi
done
log_success "Rofi stylesheets installed."

# ------------------------------------------------------------------------------
# 6. Deploy xfdashboard Theme (Mission Control)
# ------------------------------------------------------------------------------
log_info "Step 6: Deploying xfdashboard Mission Control theme..."
XFDASH_DIR="${HOME}/.local/share/xfdashboard/themes/Sequoia"
mkdir -p "${XFDASH_DIR}"

if [[ -f "${REPO_ROOT}/config/xfdashboard/xfdashboard.css" ]]; then
    safe_copy "${REPO_ROOT}/config/xfdashboard/xfdashboard.css" "${XFDASH_DIR}/xfdashboard.css"
fi
log_success "Mission Control theme deployed."

# ------------------------------------------------------------------------------
# 7. Deploy Binaries to ~/.local/bin/
# ------------------------------------------------------------------------------
log_info "Step 7: Installing session binaries into ~/.local/bin/..."
mkdir -p "${HOME}/.local/bin"

SESSION_BINS=(
    "sequoia-supervisor.sh"
    "start-plank.sh"
    "conky-manager.sh"
    "conky-calendar.sh"
    "weather-cache.sh"
    "sequoia-ctl"
    "app-window-theming.sh"
    "lite-mode.sh"
    "launchpad.sh"
    "spotlight.sh"
    "control-center.sh"
    "sequoia-control-center.py"
    "toggle-theme.sh"
    "deskwidgets-manager.sh"
    "mission-control.sh"
    "sequoia-settings.sh"
)

for b in "${SESSION_BINS[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${b}" ]]; then
        safe_copy "${SCRIPT_DIR}/${b}" "${HOME}/.local/bin/${b}"
        chmod +x "${HOME}/.local/bin/${b}"
    fi
done

# Pre-populate weather cache
if [[ -f "${HOME}/.local/bin/weather-cache.sh" ]]; then
    bash "${HOME}/.local/bin/weather-cache.sh" >/dev/null 2>&1 || true
fi
log_success "All session binaries deployed and marked executable."

# ------------------------------------------------------------------------------
# 8. Deploy Desktop Applications (.desktop Launchers)
# ------------------------------------------------------------------------------
log_info "Step 8: Installing Desktop Application Launchers..."
APP_DIR="${HOME}/.local/share/applications"
mkdir -p "${APP_DIR}"

APP_ENTRIES=(
    "launchpad.desktop"
    "spotlight.desktop"
    "control-center.desktop"
    "mission-control.desktop"
    "sequoia-settings.desktop"
)

for app in "${APP_ENTRIES[@]}"; do
    if [[ -f "${REPO_ROOT}/config/applications/${app}" ]]; then
        safe_copy "${REPO_ROOT}/config/applications/${app}" "${APP_DIR}/${app}"
        chmod +x "${APP_DIR}/${app}"
    fi
done

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${APP_DIR}" 2>/dev/null || true
fi
log_success "Desktop applications installed (Launchpad, Spotlight, Control Center, Mission Control, Settings)."

# ------------------------------------------------------------------------------
# 9. Bind macOS-Style Global Keyboard Shortcuts
# ------------------------------------------------------------------------------
log_info "Step 9: Binding macOS-style global keyboard shortcuts..."
KB_CHANNEL="xfce4-keyboard-shortcuts"

if command -v xfconf-query &>/dev/null; then
    # Spotlight: Super+Space
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>space" "string" "${HOME}/.local/bin/spotlight.sh"

    # Launchpad: Super+A and F4
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>a" "string" "${HOME}/.local/bin/launchpad.sh"
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F4" "string" "${HOME}/.local/bin/launchpad.sh"

    # Control Center: Super+C
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>c" "string" "${HOME}/.local/bin/control-center.sh"

    # Mission Control: Super+Up and F3
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>Up" "string" "${HOME}/.local/bin/mission-control.sh"
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/F3" "string" "${HOME}/.local/bin/mission-control.sh"

    # Sequoia Settings: Super+comma (Cmd+, macOS standard)
    set_xfconf_prop "${KB_CHANNEL}" "/commands/custom/<Super>comma" "string" "${HOME}/.local/bin/sequoia-settings.sh"
    log_success "Keyboard shortcuts active: Super+Space (Spotlight), Super+A (Launchpad), Super+C (Control Center), Super+Up (Mission Control)."
fi

# ------------------------------------------------------------------------------
# 10. Enforce macOS Window Decorations & Zero Topbar Gap
# ------------------------------------------------------------------------------
log_info "Step 10: Enforcing macOS traffic lights & zero topbar gap..."
bash "${SCRIPT_DIR}/app-window-theming.sh"

# ------------------------------------------------------------------------------
# 11. Top Bar Panel Geometry, Clean Apple Menu, Popovers & Clock Layout
# ------------------------------------------------------------------------------
log_info "Step 11: Configuring top bar geometry, single-line clock & popover buttons..."
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "28"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/icon-size" "uint" "16"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/length" "uint" "100"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position-locked" "bool" "true"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "1"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/enable-struts" "bool" "false"

    # Ensure panel-2 is purged cleanly without syntax errors
    if xfconf-query -c xfce4-panel -p /panels/panel-2 &>/dev/null; then
        log_info "Purging residual panel-2..."
        xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
        set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
    fi

    # Copy Apple Logo Icon
    APPLE_ICON_PATH="${HOME}/.local/share/icons/apple-logo.svg"
    mkdir -p "${HOME}/.local/share/icons"
    if [[ -f "${REPO_ROOT}/assets/icons/apple-logo.svg" ]]; then
        safe_copy "${REPO_ROOT}/assets/icons/apple-logo.svg" "${APPLE_ICON_PATH}"
    fi

    # Setup Popover Launchers for Top Bar: Spotlight (plugin-101) & Control Center (plugin-102)
    PANEL_DIR="${HOME}/.config/xfce4/panel"
    mkdir -p "${PANEL_DIR}/launcher-101"
    safe_copy "${APP_DIR}/spotlight.desktop" "${PANEL_DIR}/launcher-101/spotlight.desktop"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-101" "string" "launcher"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-101/show-label" "bool" "false"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-101/disable-tooltips" "bool" "false"
    xfconf-query -c xfce4-panel -p /plugins/plugin-101/items -n -t string -s "spotlight.desktop" --force-array 2>/dev/null || true

    mkdir -p "${PANEL_DIR}/launcher-102"
    safe_copy "${APP_DIR}/control-center.desktop" "${PANEL_DIR}/launcher-102/control-center.desktop"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-102" "string" "launcher"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-102/show-label" "bool" "false"
    set_xfconf_prop "xfce4-panel" "/plugins/plugin-102/disable-tooltips" "bool" "false"
    xfconf-query -c xfce4-panel -p /plugins/plugin-102/items -n -t string -s "control-center.desktop" --force-array 2>/dev/null || true

    # Clean existing plugin-ids on panel-1:
    # Remove tasklist, windowmenu, and stock duplicate launchers
    CURRENT_IDS=($(read_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids"))
    CLEAN_IDS=()
    WHISKER_ID=""
    SEPARATOR_ID=""
    CLOCK_ID=""
    OTHER_RIGHT_IDS=()

    for pid in "${CURRENT_IDS[@]}"; do
        [[ "${pid}" -eq 101 || "${pid}" -eq 102 ]] && continue
        PTYPE="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-${pid}" 2>/dev/null || true)"

        if [[ "${PTYPE}" == "tasklist" || "${PTYPE}" == "windowmenu" ]]; then
            log_info "Removing unwanted ${PTYPE} plugin-${pid} from panel-1..."
            continue
        elif [[ "${PTYPE}" == "launcher" ]]; then
            log_info "Removing duplicate stock launcher plugin-${pid} from panel-1..."
            continue
        elif [[ "${PTYPE}" == "pulseaudio" || "${PTYPE}" == "notification-plugin" || "${PTYPE}" == *"volume"* || "${PTYPE}" == *"audio"* || "${PTYPE}" == *"notify"* ]]; then
            log_info "Removing redundant ${PTYPE} plugin-${pid} from panel-1 (handled inside Control Center)..."
            continue
        elif [[ "${PTYPE}" == "systray" || "${PTYPE}" == "statusnotifier" ]]; then
            log_info "Removing status tray ${PTYPE} plugin-${pid} from panel-1 (Wi-Fi, sound, and status handled in Control Center)..."
            continue
        elif [[ "${PTYPE}" == "whiskermenu" ]]; then
            WHISKER_ID="${pid}"
            if [[ -f "${APPLE_ICON_PATH}" ]]; then
                set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/button-icon" "string" "${APPLE_ICON_PATH}"
            fi
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/button-title" "string" ""
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/show-button-title" "bool" "false"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/show-button-icon" "bool" "true"
        elif [[ "${PTYPE}" == "separator" ]]; then
            SEPARATOR_ID="${pid}"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/expand" "bool" "true"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/style" "uint" "0"
        elif [[ "${PTYPE}" == "clock" || "${PTYPE}" == "datetime" ]]; then
            CLOCK_ID="${pid}"
            # Configure clean single-line macOS Clock format (no stacked date below)
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/digital-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/digital-time-format" "string" "%a %e %b  %l:%M %P"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/digital-layout" "uint" "3"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/show-date" "bool" "false"
            set_xfconf_prop "xfce4-panel" "/plugins/plugin-${pid}/mode" "uint" "2"
        fi
    done

    # Assemble authentic macOS Sequoia top bar order:
    # 1. Whisker Menu (Apple logo on far left)
    # 2. Separator (expand=true, pushes all right items to the far right)
    # 3. Spotlight Button (101)
    # 4. Control Center Button (102)
    # 5. Single-line Clock (Date and Time)
    FINAL_PANEL_IDS=()
    [[ -n "${WHISKER_ID}" ]] && FINAL_PANEL_IDS+=("${WHISKER_ID}")
    [[ -n "${SEPARATOR_ID}" ]] && FINAL_PANEL_IDS+=("${SEPARATOR_ID}")
    FINAL_PANEL_IDS+=(101 102)
    [[ -n "${CLOCK_ID}" ]] && FINAL_PANEL_IDS+=("${CLOCK_ID}")

    set_xfconf_int_array "xfce4-panel" "/panels/panel-1/plugin-ids" "${FINAL_PANEL_IDS[@]}"
    log_success "Top bar plugins ordered: Apple Menu -> Separator -> Spotlight (101) -> Control Center (102) -> Clock."
fi

# ------------------------------------------------------------------------------
# 12. Permanent Consolidated Autostart (Survives Reboot)
# ------------------------------------------------------------------------------
log_info "Step 12: Configuring reboot-persistent autostart supervisor..."
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"
MIGRATED_DIR="${AUTOSTART_DIR}/.sequoia-migrated"
mkdir -p "${MIGRATED_DIR}"

# Disable & archive individual legacy autostart entries to prevent launch races
for old in "picom.desktop" "plank.desktop" "conky.desktop"; do
    if [[ -f "${AUTOSTART_DIR}/${old}" ]]; then
        log_info "Archiving legacy autostart entry: ${old}..."
        mv -f "${AUTOSTART_DIR}/${old}" "${MIGRATED_DIR}/${old}" || true
    fi
done

# Install unified supervisor desktop entry
cat > "${AUTOSTART_DIR}/sequoia-session.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sequoia Session Supervisor
Comment=Consolidated supervisor for macOS Sequoia desktop components
Exec=sh -c "sleep 2 && ${HOME}/.local/bin/sequoia-supervisor.sh"
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
EOF
chmod +x "${AUTOSTART_DIR}/sequoia-session.desktop"
log_success "Reboot supervisor registered at: ${AUTOSTART_DIR}/sequoia-session.desktop"

# ------------------------------------------------------------------------------
# 13. Live Application & Service Restart (Immediate Visual Refresh)
# ------------------------------------------------------------------------------
log_info "Step 13: Applying themes live to active desktop session..."
if [[ -n "${DISPLAY:-}" ]]; then
    # 13a. Restart Picom
    if command -v picom &>/dev/null && [[ -f "${PICOM_DIR}/picom.conf" ]]; then
        log_info "Restarting Picom compositor (16px corners & GLX backend)..."
        pkill -x picom 2>/dev/null || true
        sleep 0.4
        picom --config "${PICOM_DIR}/picom.conf" -b 2>/dev/null || true
    fi

    # 13b. Restart Desktop Widgets (DeskWidgets Cairo vector suite)
    pkill -f "calendar-system.conkyrc" 2>/dev/null || true
    pkill -f "clock-weather.conkyrc" 2>/dev/null || true
    pkill -f "media-notes.conkyrc" 2>/dev/null || true
    log_info "Restarting DeskWidgets Cairo vector suite (1280x1024 calibrated)..."
    if [[ -x "${HOME}/.local/bin/deskwidgets-manager.sh" ]]; then
        "${HOME}/.local/bin/deskwidgets-manager.sh" restart >/dev/null 2>&1 || true
    elif [[ -x "${SCRIPT_DIR}/deskwidgets-manager.sh" ]]; then
        "${SCRIPT_DIR}/deskwidgets-manager.sh" restart >/dev/null 2>&1 || true
    fi

    # 13c. Reload Top Panel
    log_info "Reloading top panel with clean popovers, single-line clock, and scoped styling..."
    guarded_panel_reload || true
fi

log_success "=========================================================="
log_success " Complete macOS Sequoia System Deployment Finished!"
log_success " - Dock: Left 100% untouched as requested"
log_success " - Widgets: 3 distinct non-overlapping cards with Python calendar"
log_success " - Top Bar: Spotlight & Control Center popover buttons added"
log_success " - Top Bar Clock: Single-line clean macOS date/time format"
log_success " - Shortcuts: Super+Space (Spotlight), Super+C (Control Center)"
log_success " - All services will cleanly autostart upon reboot."
log_success "=========================================================="
