#!/usr/bin/env bash
# ==============================================================================
# Phase 4: Dock Configuration (Plank with macOS Sequoia theme)
# macOS Sequoia Transformation for Linux Mint XFCE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "Phase 4: Starting Plank Dock Configuration"

# 1. Dependency Checks
REQUIRED_PKGS=("plank" "dconf-cli")
check_required_packages "${REQUIRED_PKGS[@]}"

# 2. Install Sequoia Dock Theme
PLANK_THEME_DEST="${HOME}/.local/share/plank/themes/Sequoia"
mkdir -p "${PLANK_THEME_DEST}"
safe_copy "${CONFIG_DIR}/plank/theme/Sequoia/dock.theme" "${PLANK_THEME_DEST}/dock.theme"

# 3. Configure Dock Launchers
PLANK_LAUNCHERS_DIR="${HOME}/.config/plank/dock1/launchers"
mkdir -p "${PLANK_LAUNCHERS_DIR}"

for launcher in "${CONFIG_DIR}/plank/launchers/"*.dockitem; do
    if [[ -f "${launcher}" ]]; then
        safe_copy "${launcher}" "${PLANK_LAUNCHERS_DIR}/$(basename "${launcher}")"
    fi
done

# 4. Configure Plank Settings via dconf
log_info "Configuring Plank dock settings via dconf..."
DCONF_PATH="/net/launchpad/plank/docks/dock1"

if command -v dconf &>/dev/null; then
    init_backup
    dconf dump "${DCONF_PATH}/" > "${SESSION_BACKUP_DIR}/plank-dconf-backup.txt" 2>/dev/null || true
    echo "dconf load ${DCONF_PATH}/ < \"${SESSION_BACKUP_DIR}/plank-dconf-backup.txt\"" >> "${SESSION_BACKUP_DIR}/restore-xfconf.sh"

    dconf write "${DCONF_PATH}/theme" "'Sequoia'"
    dconf write "${DCONF_PATH}/icon-size" "44"
    dconf write "${DCONF_PATH}/zoom-enabled" "true"
    dconf write "${DCONF_PATH}/zoom-percent" "120"
    dconf write "${DCONF_PATH}/hide-mode" "'dodge-window'"
    dconf write "${DCONF_PATH}/position" "'bottom'"
    dconf write "${DCONF_PATH}/alignment" "'center'"
    dconf write "${DCONF_PATH}/show-dock-item" "false"
    dconf write "${DCONF_PATH}/pinned-only" "false"
    log_success "Plank settings applied to dconf"
fi

# 5. Enable Plank Autostart
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"
safe_copy "${CONFIG_DIR}/autostart/plank.desktop" "${AUTOSTART_DIR}/plank.desktop"

# 6. Restart Plank if running inside X11 session
if [[ -n "${DISPLAY:-}" ]]; then
    log_info "Restarting Plank in current session..."
    killall plank 2>/dev/null || true
    plank &>/dev/null & disown || log_warn "Plank failed to start in background."
fi

log_success "Phase 4 Complete: Plank dock configured and styled."
