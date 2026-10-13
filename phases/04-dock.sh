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
LOCAL_BIN="${HOME}/.local/bin"
DCONF_PATH="/net/launchpad/plank/docks/dock1"

# ------------------------------------------------------------------------------
# Undo Functionality for Phase 4
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 4: Stopping Plank & Restoring Bottom Panel..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would stop Plank and remove dock config files"
        return 0
    fi

    if command -v pkill &>/dev/null; then
        pkill -x plank 2>/dev/null || true
    fi

    rm -f "${HOME}/.config/autostart/plank.desktop"
    rm -f "${HOME}/.local/bin/start-plank.sh"
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
# 3. Deploy Custom Sequoia Dock Theme (Strictly Validated against system template)
# ------------------------------------------------------------------------------
run mkdir -p "${PLANK_THEME_DEST}"

DEFAULT_THEME="/usr/share/plank/themes/Default/dock.theme"
if [[ -f "${DEFAULT_THEME}" ]]; then
    log_info "Generating Sequoia dock.theme strictly from system Default template (${DEFAULT_THEME})..."
    KNOWN_KEYS="$(grep -E '^[A-Za-z0-9]+=' "${DEFAULT_THEME}" | cut -d'=' -f1 || true)"

    # Verify that all keys in our Sequoia theme exist in the system template
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
        [[ "${key}" =~ ^#.* || -z "${key}" || "${key}" =~ ^\[ ]] && continue
        key="$(echo "${key}" | tr -d ' ')"
        if ! grep -qw "${key}" <<< "${KNOWN_KEYS}"; then
            log_error "Plank theme key '${key}' does not exist in /usr/share/plank/themes/Default/dock.theme! Failing phase as required."
            exit 1
        fi
    done < "${CONFIG_DIR}/plank/theme/Sequoia/dock.theme"

    # Copy Default as base and substitute verified values
    safe_copy "${DEFAULT_THEME}" "${PLANK_THEME_DEST}/dock.theme"
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
        [[ "${key}" =~ ^#.* || -z "${key}" || "${key}" =~ ^\[ ]] && continue
        key="$(echo "${key}" | tr -d ' ')"
        val="$(echo "${val}" | tr -d '\r')"
        sed -i "s|^${key}=.*|${key}=${val}|" "${PLANK_THEME_DEST}/dock.theme"
    done < "${CONFIG_DIR}/plank/theme/Sequoia/dock.theme"
    log_success "Sequoia dock theme generated and verified against system Default."
else
    safe_copy "${CONFIG_DIR}/plank/theme/Sequoia/dock.theme" "${PLANK_THEME_DEST}/dock.theme"
fi

# ------------------------------------------------------------------------------
# 4. Deploy Unified 10-Item Dock Launchers (With Installed Equivalents & Trash Last)
# ------------------------------------------------------------------------------
run mkdir -p "${PLANK_LAUNCHERS_DIR}"
backup_item "${PLANK_LAUNCHERS_DIR}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would clean stale launchers and deploy 10 ordered dockitems with Trash last"
else
    rm -f "${PLANK_LAUNCHERS_DIR}/"*.dockitem

    find_best_desktop() {
        for cand in "$@"; do
            if [[ -f "${cand}" ]]; then
                echo "${cand}"
                return 0
            fi
        done
        return 1
    }

    deploy_dockitem() {
        local prefix="$1"
        local name="$2"
        local desktop_path="$3"
        local candidates_desc="$4"

        if [[ -n "${desktop_path}" && -f "${desktop_path}" ]]; then
            cat << EOF > "${PLANK_LAUNCHERS_DIR}/${prefix}-${name}.dockitem"
[PlankDockItemPreferences]
Launcher=file://${desktop_path}
EOF
            log_success "Dock slot [${prefix} ${name}]: ${desktop_path}"
        else
            log_warn "Dock slot [${prefix} ${name}]: SKIPPED. None of candidate paths installed: ${candidates_desc}"
        fi
    }

    # 01. Files
    D_FILES="$(find_best_desktop "/usr/share/applications/thunar.desktop" "/usr/share/applications/nemo.desktop" "/usr/share/applications/org.gnome.Nautilus.desktop" || true)"
    deploy_dockitem "01" "files" "${D_FILES}" "thunar, nemo, nautilus"

    # 02. Browser
    D_BROWSER="$(find_best_desktop "/usr/share/applications/firefox.desktop" "/usr/share/applications/brave-browser.desktop" "/usr/share/applications/google-chrome.desktop" || true)"
    deploy_dockitem "02" "browser" "${D_BROWSER}" "firefox, brave-browser, chrome"

    # 03. Terminal
    D_TERM="$(find_best_desktop "/usr/share/applications/xfce4-terminal.desktop" "/usr/share/applications/gnome-terminal.desktop" "/usr/share/applications/xterm.desktop" || true)"
    deploy_dockitem "03" "terminal" "${D_TERM}" "xfce4-terminal, gnome-terminal, xterm"

    # 04. Text Editor
    D_EDIT="$(find_best_desktop "/usr/share/applications/xed.desktop" "/usr/share/applications/mousepad.desktop" "/usr/share/applications/gedit.desktop" || true)"
    deploy_dockitem "04" "editor" "${D_EDIT}" "xed, mousepad, gedit"

    # 05. Music
    D_MUSIC="$(find_best_desktop "/usr/share/applications/rhythmbox.desktop" "/usr/share/applications/hypnotix.desktop" "/usr/share/applications/org.gnome.Music.desktop" "/usr/share/applications/celluloid.desktop" || true)"
    deploy_dockitem "05" "music" "${D_MUSIC}" "rhythmbox, hypnotix, gnome-music, celluloid"

    # 06. Photos
    D_PHOTOS="$(find_best_desktop "/usr/share/applications/pix.desktop" "/usr/share/applications/xviewer.desktop" "/usr/share/applications/ristretto.desktop" "/usr/share/applications/org.gnome.eog.desktop" || true)"
    deploy_dockitem "06" "photos" "${D_PHOTOS}" "pix, xviewer, ristretto, eog"

    # 07. Calendar
    D_CAL="$(find_best_desktop "/usr/share/applications/org.gnome.Calendar.desktop" "/usr/share/applications/orage.desktop" "/usr/share/applications/xfce4-datetime-plugin.desktop" "/usr/share/applications/thunderbird.desktop" || true)"
    deploy_dockitem "07" "calendar" "${D_CAL}" "gnome-calendar, orage, xfce4-datetime, thunderbird"

    # 08. Settings
    D_SETTINGS="$(find_best_desktop "/usr/share/applications/xfce4-settings-manager.desktop" "/usr/share/applications/gnome-control-center.desktop" || true)"
    deploy_dockitem "08" "settings" "${D_SETTINGS}" "xfce4-settings-manager, gnome-control-center"

    # 09. Software Manager
    D_SOFTWARE="$(find_best_desktop "/usr/share/applications/mintinstall.desktop" "/usr/share/applications/gnome-software.desktop" || true)"
    deploy_dockitem "09" "software" "${D_SOFTWARE}" "mintinstall, gnome-software"

    # 10. Trash (Always Last!)
    cat << EOF > "${PLANK_LAUNCHERS_DIR}/10-trash.dockitem"
[PlankDockItemPreferences]
Launcher=docklet://trash
EOF
    log_success "Dock slot [10 trash]: docklet://trash (Ordered last)"
fi

# ------------------------------------------------------------------------------
# 5. Configure Plank via dconf & Verify
# ------------------------------------------------------------------------------
log_info "Configuring Plank dock geometry (48px icon, zoom 118%, offset 4, dodge-window)..."

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would configure Plank preferences via dconf (theme: Sequoia, icon-size: 48, offset: 4, zoom: 118%, hide-mode: dodge-window)"
elif command -v dconf &>/dev/null; then
    mkdir -p "${CURRENT_PHASE_DIR}"
    dconf dump "${DCONF_PATH}/" > "${CURRENT_PHASE_DIR}/plank-dconf-backup.txt" 2>/dev/null || true

    dconf write "${DCONF_PATH}/theme" "'Sequoia'"
    dconf write "${DCONF_PATH}/icon-size" "48"
    dconf write "${DCONF_PATH}/offset" "4"
    dconf write "${DCONF_PATH}/zoom-enabled" "true"
    dconf write "${DCONF_PATH}/zoom-percent" "118"
    dconf write "${DCONF_PATH}/hide-mode" "'dodge-window'"
    dconf write "${DCONF_PATH}/position" "'bottom'"
    dconf write "${DCONF_PATH}/alignment" "'center'"
    dconf write "${DCONF_PATH}/show-dock-item" "false"
    dconf write "${DCONF_PATH}/pinned-only" "false"

    # Verify dconf configuration
    ACTUAL_THEME="$(dconf read "${DCONF_PATH}/theme" 2>/dev/null || true)"
    ACTUAL_OFFSET="$(dconf read "${DCONF_PATH}/offset" 2>/dev/null || true)"
    if [[ "${ACTUAL_THEME}" == "'Sequoia'" ]]; then
        log_success "Plank preferences verified via dconf (theme: ${ACTUAL_THEME}, offset: ${ACTUAL_OFFSET})."
    else
        log_warn "dconf verification: expected 'Sequoia', got '${ACTUAL_THEME}'"
    fi
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
# 7. Deploy Safe Plank Launcher Utility
# ------------------------------------------------------------------------------
run mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/start-plank.sh" "${LOCAL_BIN}/start-plank.sh"
run chmod +x "${LOCAL_BIN}/start-plank.sh"

# ------------------------------------------------------------------------------
# 8. Safety Test & Register Delayed Autostart
# ------------------------------------------------------------------------------
TEST_PASSED=0
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would verify plank binary"
    TEST_PASSED=1
elif command -v plank &>/dev/null; then
    TEST_PASSED=1
    log_success "Plank binary verified."
fi

if [[ "${TEST_PASSED}" -eq 1 ]]; then
    install_delayed_autostart "plank" "${LOCAL_BIN}/start-plank.sh" "macOS Sequoia Floating Dock"
fi

# Reload in active X11 session if present
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would start Plank dock via start-plank.sh"
elif [[ -n "${DISPLAY:-}" ]] && command -v plank &>/dev/null; then
    bash "${LOCAL_BIN}/start-plank.sh" || log_warn "Plank launch deferred."
fi

log_success "Phase 4 Complete: Plank dock configured with 10 unified icons."
log_info "Undo this phase anytime with: ./phases/04-dock.sh --undo (or ./uninstall.sh -p 4)"
