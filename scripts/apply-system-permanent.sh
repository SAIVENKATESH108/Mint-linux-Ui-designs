#!/usr/bin/env bash
# ==============================================================================
# Sequoia Permanent System Enforcer
# Consolidates all configuration, wipes stale/glitched CSS fragments,
# deploys and applies the Sequoia Dock theme (Plank) and Desktop Widgets (Conky),
# enforces macOS traffic lights across applications, zero-gap struts,
# and locks the consolidated supervisor into autostart for 100% reboot persistence.
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
log_info " Applying clean state, dock & widget theming across system"
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
safe_copy "${REPO_ROOT}/config/gtk-3.0/sequoia/panel-top.css" "${GTK_DIR}/sequoia/panel-top.css"
safe_copy "${REPO_ROOT}/config/gtk-3.0/gtk.css" "${GTK_DIR}/gtk.css"
log_success "GTK 3.0 stylesheets cleanly consolidated and strictly scoped."

# ------------------------------------------------------------------------------
# 2. Deploy Picom Compositor Configuration (Prerequisite for Dock & Widgets)
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
# 3. Deploy Sequoia Dock Theme & Apply Plank dconf Settings
# ------------------------------------------------------------------------------
log_info "Step 3: Deploying and activating Sequoia Dock theme..."
PLANK_THEME_DEST="${HOME}/.local/share/plank/themes/Sequoia"
mkdir -p "${PLANK_THEME_DEST}"

safe_copy "${REPO_ROOT}/config/plank/theme/Sequoia/dock.theme" "${PLANK_THEME_DEST}/dock.theme"

if command -v dconf &>/dev/null; then
    DCONF_PATH="/net/launchpad/plank/docks/dock1"
    dconf write "${DCONF_PATH}/theme" "'Sequoia'"
    dconf write "${DCONF_PATH}/icon-size" "48"
    dconf write "${DCONF_PATH}/offset" "0"
    dconf write "${DCONF_PATH}/zoom-enabled" "true"
    dconf write "${DCONF_PATH}/zoom-percent" "118"
    dconf write "${DCONF_PATH}/hide-mode" "'dodge-window'"
    dconf write "${DCONF_PATH}/position" "'bottom'"
    dconf write "${DCONF_PATH}/alignment" "'center'"
    dconf write "${DCONF_PATH}/show-dock-item" "false"
    dconf write "${DCONF_PATH}/pinned-only" "false"
    log_success "Plank dock preferences locked to Sequoia theme via dconf (launchers untouched)."
fi

# ------------------------------------------------------------------------------
# 4. Deploy Conky Desktop Widgets Configuration
# ------------------------------------------------------------------------------
log_info "Step 4: Deploying Conky desktop widget configurations..."
CONKY_CONFIG_DIR="${HOME}/.config/conky"
mkdir -p "${CONKY_CONFIG_DIR}"

safe_copy "${REPO_ROOT}/config/conky/clock-weather.conkyrc" "${CONKY_CONFIG_DIR}/clock-weather.conkyrc"
safe_copy "${REPO_ROOT}/config/conky/calendar-system.conkyrc" "${CONKY_CONFIG_DIR}/calendar-system.conkyrc"
safe_copy "${REPO_ROOT}/config/conky/media-notes.conkyrc" "${CONKY_CONFIG_DIR}/media-notes.conkyrc"
log_success "Conky transparent floating card configurations deployed."

# ------------------------------------------------------------------------------
# 5. Deploy Binaries to ~/.local/bin/
# ------------------------------------------------------------------------------
log_info "Step 5: Installing session binaries into ~/.local/bin/..."
mkdir -p "${HOME}/.local/bin"

for b in "sequoia-supervisor.sh" "start-plank.sh" "conky-manager.sh" \
         "weather-cache.sh" "sequoia-ctl" "app-window-theming.sh" "lite-mode.sh"; do
    if [[ -f "${SCRIPT_DIR}/${b}" ]]; then
        safe_copy "${SCRIPT_DIR}/${b}" "${HOME}/.local/bin/${b}"
        chmod +x "${HOME}/.local/bin/${b}"
    fi
done

# Pre-populate weather cache
if [[ -f "${HOME}/.local/bin/weather-cache.sh" ]]; then
    bash "${HOME}/.local/bin/weather-cache.sh" >/dev/null 2>&1 || true
fi
log_success "Binaries deployed and marked executable."

# ------------------------------------------------------------------------------
# 6. Enforce macOS Window Decorations & Zero Topbar Gap
# ------------------------------------------------------------------------------
log_info "Step 6: Enforcing macOS traffic lights & zero topbar gap..."
bash "${SCRIPT_DIR}/app-window-theming.sh"

# ------------------------------------------------------------------------------
# 7. Enforce Top Bar Panel Geometry & Struts
# ------------------------------------------------------------------------------
log_info "Step 7: Enforcing panel-1 struts and geometry..."
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "28"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/icon-size" "uint" "16"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/length" "uint" "100"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position-locked" "bool" "true"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/enable-struts" "bool" "true"

    # Ensure panel-2 is completely purged
    P2_CHECK="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -c '2' || echo 0)"
    if [[ "${P2_CHECK}" -gt 0 ]]; then
        log_info "Purging residual panel-2..."
        xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
        set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
    fi
fi

# ------------------------------------------------------------------------------
# 8. Permanent Consolidated Autostart (Survives Reboot)
# ------------------------------------------------------------------------------
log_info "Step 8: Configuring reboot-persistent autostart supervisor..."
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
# 9. Live Application & Service Restart (Immediate Visual Refresh)
# ------------------------------------------------------------------------------
log_info "Step 9: Applying themes live to active desktop session..."
if [[ -n "${DISPLAY:-}" ]]; then
    # 9a. Restart Picom
    if command -v picom &>/dev/null && [[ -f "${PICOM_DIR}/picom.conf" ]]; then
        log_info "Starting Picom compositor..."
        pkill -x picom 2>/dev/null || true
        sleep 0.4
        picom --config "${PICOM_DIR}/picom.conf" -b 2>/dev/null || true
    fi

    # 9b. Restart Plank
    if command -v plank &>/dev/null; then
        log_info "Restarting Plank with Sequoia theme..."
        pkill -x plank 2>/dev/null || true
        sleep 0.5
        if [[ -x "${HOME}/.local/bin/start-plank.sh" ]]; then
            nohup "${HOME}/.local/bin/start-plank.sh" >/dev/null 2>&1 &
        else
            nohup plank >/dev/null 2>&1 &
        fi
    fi

    # 9c. Restart Conky
    if command -v conky &>/dev/null; then
        log_info "Restarting Conky widgets with transparent floating layout..."
        if [[ -x "${HOME}/.local/bin/conky-manager.sh" ]]; then
            "${HOME}/.local/bin/conky-manager.sh" restart >/dev/null 2>&1 || true
        fi
    fi

    # 9d. Reload Top Panel
    log_info "Reloading top panel with clean scoped styling..."
    guarded_panel_reload || true
fi

log_success "=========================================================="
log_success " Permanent system enforcement complete!"
log_success " - Dock theme 'Sequoia' deployed & applied via dconf"
log_success " - Conky transparent floating widgets deployed & restarted"
log_success " - Picom compositor active (enables dock/widget transparency)"
log_success " - Scoped GTK CSS active across panel & apps"
log_success " - macOS traffic lights & zero top gap enforced"
log_success " - All services will cleanly autostart upon reboot."
log_success "=========================================================="
