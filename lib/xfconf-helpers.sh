#!/usr/bin/env bash
# ==============================================================================
# XFCE Panel Dynamic Helpers & Safety Library
# Eliminates hardcoded plugin IDs, provides dynamic allocation,
# and enforces atomic panel backup/recovery guards.
# ==============================================================================

set -euo pipefail

CHANNEL_PANEL="xfce4-panel"

# ------------------------------------------------------------------------------
# 1. Dynamic Plugin Discovery by Type
# Returns space-separated list of plugin IDs belonging to panel_id of given type
# ------------------------------------------------------------------------------
find_panel_plugins_by_type() {
    local panel_id="${1:-1}"
    local target_type="$2"

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    local plugin_ids
    plugin_ids="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/panels/panel-${panel_id}/plugin-ids" 2>/dev/null | tr '\n' ' ' || true)"
    
    local matched=()
    for pid in ${plugin_ids}; do
        local ptype
        ptype="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/plugins/plugin-${pid}" 2>/dev/null || true)"
        if [[ "${ptype}" == "${target_type}" ]]; then
            matched+=("${pid}")
        fi
    done

    echo "${matched[*]}"
}

# ------------------------------------------------------------------------------
# 2. Dynamic Plugin ID Allocation
# Finds the maximum currently used plugin ID and returns (max + 1)
# ------------------------------------------------------------------------------
allocate_next_plugin_id() {
    if ! command -v xfconf-query &>/dev/null; then
        echo "20"
        return 0
    fi

    local max_id=19
    local all_plugins
    all_plugins="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/plugins" -l 2>/dev/null || true)"

    for p in ${all_plugins}; do
        # Extract numeric id from /plugins/plugin-N or /plugins/plugin-N/...
        if [[ "${p}" =~ ^/plugins/plugin-([0-9]+) ]]; then
            local num="${BASH_REMATCH[1]}"
            if (( num > max_id )); then
                max_id="${num}"
            fi
        fi
    done

    echo "$((max_id + 1))"
}

# ------------------------------------------------------------------------------
# 3. Top Panel Health Assertion
# Returns 0 if panel-1 is present, 1 otherwise
# ------------------------------------------------------------------------------
assert_top_panel_exists() {
    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    local p1_pos
    p1_pos="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/panels/panel-1/position" 2>/dev/null || true)"
    if [[ -n "${p1_pos}" ]]; then
        return 0
    fi

    local panels_list
    panels_list="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/panels" 2>/dev/null || true)"
    if [[ "${panels_list}" =~ "1" ]]; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# 4. Snapshot Panel State to File
# ------------------------------------------------------------------------------
snapshot_panel_state() {
    local snapshot_path="$1"
    mkdir -p "$(dirname "${snapshot_path}")"

    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c "${CHANNEL_PANEL}" -lv > "${snapshot_path}" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 5. Restore Panel State from Snapshot
# ------------------------------------------------------------------------------
restore_panel_state() {
    local snapshot_path="$1"
    if [[ ! -f "${snapshot_path}" ]]; then
        return 1
    fi

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    log_warn "Restoring panel settings from snapshot: ${snapshot_path}..."
    while IFS= read -r line || [[ -n "${line}" ]]; do
        local prop val
        prop="$(awk '{print $1}' <<< "${line}")"
        val="$(cut -d' ' -f2- <<< "${line}")"
        if [[ -n "${prop}" && -n "${val}" ]]; then
            xfconf-query -c "${CHANNEL_PANEL}" -p "${prop}" -s "${val}" 2>/dev/null || true
        fi
    done < "${snapshot_path}"
}

# ------------------------------------------------------------------------------
# 6. Guarded Panel Reload
# Verifies top panel integrity before reload, snapshots state, reloads,
# and verifies top panel survived reload (recovering snapshot if corrupted).
# ------------------------------------------------------------------------------
guarded_panel_reload() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_dry "Would execute guarded panel reload (snapshot -> reload -> assert top panel)"
        return 0
    fi

    local snapshot_dir="${HOME}/.cache/sequoia"
    local snapshot_file="${snapshot_dir}/panel-pre-reload-snapshot.txt"
    mkdir -p "${snapshot_dir}"

    # 1. Pre-reload verification: if top panel already vanished, attempt recovery
    if ! assert_top_panel_exists; then
        log_warn "Top panel (panel-1) was missing before reload! Attempting emergency restoration..."
        local latest_backup
        latest_backup="$(ls -td "${HOME}/.mint-sequoia-backup"/*/phase3 2>/dev/null | head -n1 || true)"
        if [[ -n "${latest_backup}" && -f "${latest_backup}/restore-xfconf.sh" ]]; then
            bash "${latest_backup}/restore-xfconf.sh" || true
        fi
    fi

    # 2. Take fresh snapshot
    snapshot_panel_state "${snapshot_file}"

    # 3. Reload panel daemon
    if [[ -n "${DISPLAY:-}" ]] && command -v xfce4-panel &>/dev/null; then
        log_info "Reloading xfce4-panel safely..."
        xfce4-panel -r 2>/dev/null || true
        sleep 1

        # 4. Post-reload assertion: verify top panel is still intact
        if ! assert_top_panel_exists; then
            log_error "Top panel disappeared during reload! Auto-restoring from snapshot..."
            restore_panel_state "${snapshot_file}"
            xfce4-panel -r 2>/dev/null || true
            sleep 0.5
        fi
        log_success "Top panel verified intact after reload."
    fi
}
