#!/usr/bin/env bash
# ==============================================================================
# Sequoia Permanent System Enforcer
# Consolidates all configuration, wipes stale/glitched CSS fragments,
# applies macOS traffic lights across applications, zero-gap struts,
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
log_info " Applying clean state & locking persistence across reboots"
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
log_success "GTK 3.0 stylesheets cleanly consolidated."

# ------------------------------------------------------------------------------
# 2. Deploy Binaries to ~/.local/bin/
# ------------------------------------------------------------------------------
log_info "Step 2: Installing session binaries into ~/.local/bin/..."
mkdir -p "${HOME}/.local/bin"

for b in "sequoia-supervisor.sh" "start-plank.sh" "conky-manager.sh" \
         "weather-cache.sh" "sequoia-ctl" "app-window-theming.sh" "lite-mode.sh"; do
    if [[ -f "${SCRIPT_DIR}/${b}" ]]; then
        safe_copy "${SCRIPT_DIR}/${b}" "${HOME}/.local/bin/${b}"
        chmod +x "${HOME}/.local/bin/${b}"
    fi
done
log_success "Binaries deployed and marked executable."

# ------------------------------------------------------------------------------
# 3. Permanent Consolidated Autostart (Survives Reboot)
# ------------------------------------------------------------------------------
log_info "Step 3: Configuring reboot-persistent autostart supervisor..."
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"
MIGRATED_DIR="${AUTOSTART_DIR}/.sequoia-migrated"
mkdir -p "${MIGRATED_DIR}"

# Disable & archive individual legacy autostart entries to stop launch races
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
# 4. Enforce macOS Window Decorations & Zero Topbar Gap
# ------------------------------------------------------------------------------
log_info "Step 4: Enforcing macOS traffic lights & zero topbar gap..."
bash "${SCRIPT_DIR}/app-window-theming.sh"

# ------------------------------------------------------------------------------
# 5. Enforce Top Bar Panel Geometry & Struts
# ------------------------------------------------------------------------------
log_info "Step 5: Enforcing panel-1 struts and geometry..."
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "28"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/icon-size" "uint" "16"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/length" "uint" "100"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position-locked" "bool" "true"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/autohide-behavior" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/background-style" "uint" "0"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/enable-struts" "bool" "true"

    # Ensure panel-2 is not present
    P2_CHECK="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -c '2' || echo 0)"
    if [[ "${P2_CHECK}" -gt 0 ]]; then
        log_info "Purging residual panel-2..."
        xfconf-query -c xfce4-panel -p /panels/panel-2 -r -R 2>/dev/null || true
        set_xfconf_prop "xfce4-panel" "/panels" "int" "1"
    fi
fi

# ------------------------------------------------------------------------------
# 6. Ensure Compositor & Session Services
# ------------------------------------------------------------------------------
log_info "Step 6: Starting supervisor services in active session..."
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfwm4" "/general/use_compositing" "bool" "false"
fi

if [[ -n "${DISPLAY:-}" ]]; then
    # Start supervisor immediately
    bash "${HOME}/.local/bin/sequoia-supervisor.sh" || true
    
    # Reload panel safely to pick up clean scoped CSS and struts
    log_info "Reloading top panel with clean scoped styling..."
    guarded_panel_reload || true
fi

log_success "=========================================================="
log_success " Permanent system enforcement complete!"
log_success " Clean CSS active, macOS traffic lights applied, 0 top gap enforced."
log_success " All services will cleanly autostart upon reboot."
log_success "=========================================================="
