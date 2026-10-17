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
# Undo Functionality for Phase 4 (Plank Only - Never touches panels)
# ------------------------------------------------------------------------------
undo_phase() {
    log_info "==> Reverting Phase 4: Stopping Plank & Restoring Dock Settings..."

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would stop Plank and remove dock config files and themes"
        return 0
    fi

    if command -v pkill &>/dev/null; then
        pkill -x plank 2>/dev/null || true
    fi

    rm -f "${HOME}/.config/autostart/plank.desktop"
    rm -f "${HOME}/.local/bin/start-plank.sh"
    rm -rf "${PLANK_THEME_DEST}"
    rm -rf "${PLANK_LAUNCHERS_DIR}"

    # Reset dconf to Default theme if dconf available
    if command -v dconf &>/dev/null; then
        dconf write "${DCONF_PATH}/theme" "'Default'" 2>/dev/null || true
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

# Self-healing: if panel-2 was accidentally autohidden by previous run, heal it back
if command -v xfconf-query &>/dev/null; then
    P2_AUTOHIDE="$(xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior 2>/dev/null || true)"
    if [[ "${P2_AUTOHIDE}" == "2" ]]; then
        log_info "Self-healing: restoring panel-2 autohide-behavior to 0..."
        set_xfconf_prop "xfce4-panel" "/panels/panel-2/autohide-behavior" "uint" "0"
    fi
fi

# ------------------------------------------------------------------------------
# 2. Dependency Checks (plank, dconf-cli)
# ------------------------------------------------------------------------------
REQUIRED_PKGS=("plank" "dconf-cli")
check_required_packages "${REQUIRED_PKGS[@]}"

# Stop any running Plank instance so it does not overwrite files/dconf on exit
if [[ "${DRY_RUN}" -eq 0 ]] && command -v pkill &>/dev/null; then
    pkill -x plank 2>/dev/null || true
    sleep 0.5
fi

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
# 4. Multi-Directory Search & Deploy 10 Unified Dock Launchers
# ------------------------------------------------------------------------------
run mkdir -p "${PLANK_LAUNCHERS_DIR}"
backup_item "${PLANK_LAUNCHERS_DIR}"

# Multi-directory search helper matching .desktop IDs
find_desktop_file() {
    local desktop_ids=("$@")
    local search_dirs=(
        "/usr/share/applications"
        "${HOME}/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "${HOME}/.local/share/flatpak/exports/share/applications"
    )

    for id in "${desktop_ids[@]}"; do
        for sdir in "${search_dirs[@]}"; do
            local candidate="${sdir}/${id}"
            if [[ -f "${candidate}" ]]; then
                echo "${candidate}"
                return 0
            fi
        done
    done
    return 1
}

# Fallback helper to search by Categories in desktop files
find_desktop_by_category() {
    local category="$1"
    local search_dirs=(
        "/usr/share/applications"
        "${HOME}/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "${HOME}/.local/share/flatpak/exports/share/applications"
    )

    for sdir in "${search_dirs[@]}"; do
        [[ -d "${sdir}" ]] || continue
        while IFS= read -r df; do
            [[ -f "${df}" ]] || continue
            if grep -Eq "^Categories=.*${category}" "${df}" 2>/dev/null; then
                if ! grep -Eq '^NoDisplay=true' "${df}" 2>/dev/null; then
                    echo "${df}"
                    return 0
                fi
            fi
        done < <(find "${sdir}" -maxdepth 1 -name "*.desktop" 2>/dev/null)
    done
    return 1
}

DEPLOYED_ITEMS=()

deploy_dockitem() {
    local prefix="$1"
    local name="$2"
    shift 2
    local candidates=("$@")

    local resolved
    resolved="$(find_desktop_file "${candidates[@]}" || true)"

    # Fallback to category search if specific candidate files were not found
    if [[ -z "${resolved}" && "${name}" == "editor" ]]; then
        resolved="$(find_desktop_by_category "TextEditor" || true)"
        if [[ -n "${resolved}" ]]; then
            log_info "Dock slot [${prefix} ${name}]: matched via Categories=TextEditor fallback: ${resolved}"
        fi
    fi

    local item_filename="${prefix}-${name}.dockitem"

    if [[ -n "${resolved}" && -f "${resolved}" ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            log_dry "Would create ${item_filename} -> ${resolved}"
        else
            cat << EOF > "${PLANK_LAUNCHERS_DIR}/${item_filename}"
[PlankDockItemPreferences]
Launcher=file://${resolved}
EOF
        fi
        DEPLOYED_ITEMS+=("${item_filename}")
        log_success "Dock slot [${prefix} ${name}]: picked ${resolved}"
    else
        log_warn "Dock slot [${prefix} ${name}]: SKIPPED (no candidate installed)."
        local search_dirs=(
            "/usr/share/applications"
            "${HOME}/.local/share/applications"
            "/var/lib/flatpak/exports/share/applications"
            "${HOME}/.local/share/flatpak/exports/share/applications"
        )
        log_warn "  Checked candidate paths:"
        for id in "${candidates[@]}"; do
            for sdir in "${search_dirs[@]}"; do
                log_warn "    - ${sdir}/${id} (missing)"
            done
        done
    fi
}

if [[ "${DRY_RUN}" -eq 0 ]]; then
    rm -f "${PLANK_LAUNCHERS_DIR}/"*.dockitem
fi

# 00. Launchpad (macOS-style first dock item)
deploy_dockitem "00" "launchpad" \
    "launchpad.desktop"

# 01. Files: Thunar / Nemo / Nautilus
deploy_dockitem "01" "files" \
    "thunar.desktop" \
    "nemo.desktop" \
    "org.gnome.Nautilus.desktop"

# 02. Browser: Firefox / Brave / Chrome / Chromium
deploy_dockitem "02" "browser" \
    "firefox.desktop" \
    "brave-browser.desktop" \
    "google-chrome.desktop" \
    "chromium.desktop" \
    "chromium-browser.desktop"

# 03. Terminal: XFCE Terminal / GNOME Terminal / xterm
deploy_dockitem "03" "terminal" \
    "xfce4-terminal.desktop" \
    "gnome-terminal.desktop" \
    "org.gnome.Terminal.desktop" \
    "xterm.desktop"

# 04. Text Editor: Xed (org.x.editor.desktop / xed.desktop), Mousepad, Gedit, or Category=TextEditor
deploy_dockitem "04" "editor" \
    "org.x.editor.desktop" \
    "xed.desktop" \
    "org.xfce.mousepad.desktop" \
    "mousepad.desktop" \
    "gedit.desktop" \
    "org.gnome.gedit.desktop"

# 05. Music: Rhythmbox / Celluloid / GNOME Music (Explicitly NOT Hypnotix)
deploy_dockitem "05" "music" \
    "org.gnome.Rhythmbox3.desktop" \
    "rhythmbox.desktop" \
    "io.github.celluloid_player.Celluloid.desktop" \
    "celluloid.desktop" \
    "org.gnome.Music.desktop"

# 06. Photos: Pix / Ristretto / Xviewer / Eye of GNOME
deploy_dockitem "06" "photos" \
    "pix.desktop" \
    "ristretto.desktop" \
    "xviewer.desktop" \
    "org.gnome.eog.desktop"

# 07. Calendar: GNOME Calendar / Orage / Datetime plugin / Thunderbird
deploy_dockitem "07" "calendar" \
    "org.gnome.Calendar.desktop" \
    "orage.desktop" \
    "xfce4-datetime-plugin.desktop" \
    "thunderbird.desktop"

# 08. Settings: XFCE Settings Manager / GNOME Control Center
deploy_dockitem "08" "settings" \
    "xfce-settings-manager.desktop" \
    "xfce4-settings-manager.desktop" \
    "gnome-control-center.desktop"

# 09. Software Manager: Mintinstall / GNOME Software
deploy_dockitem "09" "software" \
    "mintinstall.desktop" \
    "gnome-software.desktop"

# 10. Trash Docklet (Always Last!)
TRASH_ITEM="10-trash.dockitem"
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would create ${TRASH_ITEM} -> docklet://trash"
else
    cat << EOF > "${PLANK_LAUNCHERS_DIR}/${TRASH_ITEM}"
[PlankDockItemPreferences]
Launcher=docklet://trash
EOF
fi
DEPLOYED_ITEMS+=("${TRASH_ITEM}")
log_success "Dock slot [10 trash]: docklet://trash (Trash locked at far right)"

# ------------------------------------------------------------------------------
# 5. Configure Plank via dconf (Sync dock-items array directly)
# ------------------------------------------------------------------------------
log_info "Configuring Plank dock geometry (48px icon, zoom 118%, offset 4, dodge-window)..."

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would configure Plank preferences via dconf with dock-items: (${DEPLOYED_ITEMS[*]})"
elif command -v dconf &>/dev/null; then
    mkdir -p "${CURRENT_PHASE_DIR}"
    dconf dump "${DCONF_PATH}/" > "${CURRENT_PHASE_DIR}/plank-dconf-backup.txt" 2>/dev/null || true

    # Format GVariant string array: "['01-files.dockitem', '02-browser.dockitem', ...]"
    DCONF_ARRAY_ELEMS=()
    for it in "${DEPLOYED_ITEMS[@]}"; do
        DCONF_ARRAY_ELEMS+=("'${it}'")
    done
    joined=""
    for elem in "${DCONF_ARRAY_ELEMS[@]}"; do
        if [[ -z "${joined}" ]]; then
            joined="${elem}"
        else
            joined="${joined}, ${elem}"
        fi
    done
    DCONF_ITEMS_VAL="[${joined}]"

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
    dconf write "${DCONF_PATH}/dock-items" "${DCONF_ITEMS_VAL}"

    # Verify dconf configuration
    ACTUAL_THEME="$(dconf read "${DCONF_PATH}/theme" 2>/dev/null || true)"
    ACTUAL_ITEMS="$(dconf read "${DCONF_PATH}/dock-items" 2>/dev/null || true)"
    log_success "Plank preferences verified via dconf (theme: ${ACTUAL_THEME}, pinned items: ${#DEPLOYED_ITEMS[@]})."
fi

# ------------------------------------------------------------------------------
# 6. Deploy Safe Plank Launcher Utility
# ------------------------------------------------------------------------------
run mkdir -p "${LOCAL_BIN}"
safe_copy "${SCRIPTS_DIR}/start-plank.sh" "${LOCAL_BIN}/start-plank.sh"
run chmod +x "${LOCAL_BIN}/start-plank.sh"

# ------------------------------------------------------------------------------
# 7. Safety Test & Register Delayed Autostart
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

# Restart Plank in active X11 session if present
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_dry "Would start Plank dock via start-plank.sh"
elif [[ -n "${DISPLAY:-}" ]] && command -v plank &>/dev/null; then
    log_info "Starting Plank dock process..."
    bash "${LOCAL_BIN}/start-plank.sh" || log_warn "Plank launch deferred."
    sleep 2

    # Post-start verification of pinned items count
    if [[ -d "${PLANK_LAUNCHERS_DIR}" ]]; then
        ACTUAL_FILE_COUNT="$(find "${PLANK_LAUNCHERS_DIR}" -maxdepth 1 -name '*.dockitem' | wc -l | tr -d ' ')"
        log_info "Active dock launchers on disk: ${ACTUAL_FILE_COUNT} files."
        if (( ACTUAL_FILE_COUNT < ${#DEPLOYED_ITEMS[@]} )); then
            log_warn "Discrepancy: Deployed ${#DEPLOYED_ITEMS[@]} items, but only ${ACTUAL_FILE_COUNT} remain on disk."
        fi
    fi
fi

log_success "Phase 4 Complete: Plank dock configured with ${#DEPLOYED_ITEMS[@]} unified icons."
log_info "Inspect dock state anytime with: ./scripts/plank-state.sh"
log_info "Undo this phase anytime with: ./phases/04-dock.sh --undo (or ./uninstall.sh -p 4)"
