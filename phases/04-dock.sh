#!/usr/bin/env bash
# ==============================================================================
# Phase 4: Plank Dock Configuration (macOS Sequoia Theme + 10 Preview Launchers)
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

PLANK_THEME_DEST="${HOME}/.local/share/plank/themes/Sequoia"
PLANK_LAUNCHERS_DIR="${HOME}/.config/plank/dock1/launchers"
DCONF_PATH="/net/launchpad/plank/docks/dock1"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 4
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 4: Stopping Plank & Restoring Bottom Panel..."

    if command -v pkill &>/dev/null; then
        pkill -x plank 2>/dev/null || true
    fi

    rm -f "${HOME}/.config/autostart/plank.desktop"
    rm -rf "${PLANK_THEME_DEST}"
    rm -rf "${PLANK_LAUNCHERS_DIR}"

    # Replay backup if available
    local latest_backup
    latest_backup="$(ls -td "${BACKUP_ROOT}"/*/phase4 2>/dev/null | head -n1 || true)"
    if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
        log_info "Replaying recorded settings from ${latest_backup}..."
        bash "${latest_backup}/restore-xfconf.sh" || log_warn "Partial restore warning."
    fi

    log_success "Phase 4 successfully reverted."
}

if [[ "${1:-}" == "--undo" ]]; then
    undo_phase
    exit 0
fi

log_info "Phase 4: Starting Plank Dock Configuration (10 Launchers & Sequoia Theme)"

# ------------------------------------------------------------------------------
# 1. Back Up Existing Configurations First
# ------------------------------------------------------------------------------
init_phase_backup 4

# ------------------------------------------------------------------------------
# 2. Dependency Checks (plank, dconf-cli)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=("plank" "dconf-cli")
check_required_packages "${REQUIRED_PKGS[@]}"

# ------------------------------------------------------------------------------
# 3. Deploy Custom Sequoia Dock Theme
# ------------------------------------------------------------------------------
mkdir -p "${PLANK_THEME_DEST}"
safe_copy "${CONFIG_DIR}/plank/theme/Sequoia/dock.theme" "${PLANK_THEME_DEST}/dock.theme"

# ------------------------------------------------------------------------------
# 4. Deploy Unified 10-Item Dock Launchers
# ------------------------------------------------------------------------------
mkdir -p "${PLANK_LAUNCHERS_DIR}"
backup_item "${PLANK_LAUNCHERS_DIR}"

# Remove existing stale launchers to ensure clean 10-icon order
rm -f "${PLANK_LAUNCHERS_DIR}/"*.dockitem

# Copy 10 unified dock launchers
for item in "${CONFIG_DIR}/plank/launchers/"*.dockitem; do
    if [[ -f "${item}" ]]; then
        safe_copy "${item}" "${PLANK_LAUNCHERS_DIR}/$(basename "${item}")"
    fi
done

# ------------------------------------------------------------------------------
# 5. Configure Plank via dconf
# ------------------------------------------------------------------------------
log_info "Configuring Plank dock geometry (48px icon, zoom 118%, dodge-window)..."

if command -v dconf &>/dev/null; then
    # Backup existing dconf tree
    mkdir -p "${CURRENT_PHASE_DIR}"
    dconf dump "${DCONF_PATH}/" > "${CURRENT_PHASE_DIR}/plank-dconf-backup.txt" 2>/dev/null || true

    dconf write "${DCONF_PATH}/theme" "'Sequoia'"
    dconf write "${DCONF_PATH}/icon-size" "48"
    dconf write "${DCONF_PATH}/zoom-enabled" "true"
    dconf write "${DCONF_PATH}/zoom-percent" "118"
    dconf write "${DCONF_PATH}/hide-mode" "'dodge-window'"
    dconf write "${DCONF_PATH}/position" "'bottom'"
    dconf write "${DCONF_PATH}/alignment" "'center'"
    dconf write "${DCONF_PATH}/show-dock-item" "false"
    dconf write "${DCONF_PATH}/pinned-only" "false"
    log_success "Plank preferences configured via dconf."
fi

# ------------------------------------------------------------------------------
# 6. Hide Any Existing Stock Bottom Panel (panel-2)
# ------------------------------------------------------------------------------
if command -v xfconf-query &>/dev/null; then
    # If panel-2 is currently positioned at the bottom, set autohide or remove bottom conflict
    PANEL2_POS="$(xfconf-query -c xfce4-panel -p /panels/panel-2/position 2>/dev/null || true)"
    if [[ "${PANEL2_POS}" =~ p=[1-3] || "${PANEL2_POS}" =~ p=8 ]]; then
        log_info "Hiding legacy bottom XFCE panel-2 to yield bottom edge to Plank..."
        set_xfconf_prop "xfce4-panel" "/panels/panel-2/autohide-behavior" "uint" "2" # Intelligently autohide
    fi
fi

# ------------------------------------------------------------------------------
# 7. Safety Test & Register Delayed Autostart
# ------------------------------------------------------------------------------
TEST_PASSED=0
if command -v plank &>/dev/null; then
    TEST_PASSED=1
    log_success "Plank binary verified."
fi

if [[ "${TEST_PASSED}" -eq 1 ]]; then
    install_delayed_autostart "plank" "plank" "macOS Sequoia Floating Dock"
fi

# Reload in active X11 session if present
if [[ -n "${DISPLAY:-}" ]] && command -v plank &>/dev/null; then
    pkill -x plank 2>/dev/null || true
    sleep 0.5
    plank &>/dev/null & disown || log_warn "Plank launch deferred."
fi

log_success "Phase 4 Complete: Plank dock configured with 10 unified icons."
log_info "Undo this phase anytime with: ./phases/04-dock.sh --undo (or ./uninstall.sh -p 4)"
