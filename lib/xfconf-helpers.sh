#!/usr/bin/env bash
# ==============================================================================
# XFCE Panel Dynamic Helpers & Safety Library
# Eliminates hardcoded plugin IDs, provides dynamic allocation,
# manages array types with --force-array, and enforces process-aware panel guards.
# ==============================================================================

set -euo pipefail

CHANNEL_PANEL="xfce4-panel"

# ------------------------------------------------------------------------------
# 1. Clean Array Operations (Strips xfconf header lines)
# ------------------------------------------------------------------------------
read_xfconf_int_array() {
    local channel="$1"
    local prop="$2"

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    # Filter strictly for numeric digits to strip "Value is an array with N items:"
    xfconf-query -c "${channel}" -p "${prop}" 2>/dev/null | grep -E '^[0-9]+$' || true
}

set_xfconf_int_array() {
    local channel="$1"
    local prop="$2"
    shift 2
    local ids=("$@")

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_dry "Would set int array [${channel}] ${prop} = (${ids[*]})"
        return 0
    fi

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    local args=()
    for id in "${ids[@]}"; do
        args+=("-t" "int" "-s" "${id}")
    done

    xfconf-query -c "${channel}" -p "${prop}" -r -R 2>/dev/null || true
    if [[ ${#args[@]} -gt 0 ]]; then
        xfconf-query -c "${channel}" -p "${prop}" --create --force-array "${args[@]}" 2>/dev/null || true
    fi
}

set_xfconf_string_array() {
    local channel="$1"
    local prop="$2"
    shift 2
    local items=("$@")

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_dry "Would set string array [${channel}] ${prop} = (${items[*]})"
        return 0
    fi

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    local args=()
    for item in "${items[@]}"; do
        args+=("-t" "string" "-s" "${item}")
    done

    xfconf-query -c "${channel}" -p "${prop}" -r -R 2>/dev/null || true
    if [[ ${#args[@]} -gt 0 ]]; then
        xfconf-query -c "${channel}" -p "${prop}" --create --force-array "${args[@]}" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 2. Dynamic Plugin Discovery by Type
# Returns space-separated list of plugin IDs belonging to panel_id of given type
# ------------------------------------------------------------------------------
find_panel_plugins_by_type() {
    local panel_id="${1:-1}"
    local target_type="$2"

    if ! command -v xfconf-query &>/dev/null; then
        return 0
    fi

    local plugin_ids
    plugin_ids="$(read_xfconf_int_array "${CHANNEL_PANEL}" "/panels/panel-${panel_id}/plugin-ids")"
    
    local matched=()
    for pid in ${plugin_ids}; do
        local ptype
        ptype="$(xfconf-query -c "${CHANNEL_PANEL}" -p "/plugins/plugin-${pid}" 2>/dev/null || true)"
        if [[ "${ptype}" == "${target_type}" ]]; then
            matched+=("${pid}")
        fi
    done

    echo "${matched[*]:-}"
}

# ------------------------------------------------------------------------------
# 3. Dynamic Plugin ID Allocation
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
# 4. Top Panel Health Assertion
# Returns 0 if panel-1 is present and configured, 1 otherwise
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
# 5. Snapshot Panel State to File
# ------------------------------------------------------------------------------
snapshot_panel_state() {
    local snapshot_path="$1"
    mkdir -p "$(dirname "${snapshot_path}")"

    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c "${CHANNEL_PANEL}" -lv > "${snapshot_path}" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 6. Restore Panel State from Snapshot
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
# 7. Process-Aware Guarded Panel Reload
# Strictly verifies running PROCESS. Uses -r ONLY when running; starts if missing.
# Verifies process and panel-1 survival, restoring on error and failing if dead.
# ------------------------------------------------------------------------------
guarded_panel_reload() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_dry "Would execute guarded panel reload (verify process -> reload/start -> verify survival)"
        return 0
    fi

    local snapshot_dir="${HOME}/.cache/sequoia"
    local snapshot_file="${snapshot_dir}/panel-pre-reload-snapshot.txt"
    mkdir -p "${snapshot_dir}"

    snapshot_panel_state "${snapshot_file}"

    # Step 1: Pre-reload process check
    local is_running=0
    if pgrep -x xfce4-panel >/dev/null 2>&1; then
        is_running=1
    fi

    if [[ "${is_running}" -eq 0 ]]; then
        log_warn "xfce4-panel process is NOT running. Starting background instance..."
        ( xfce4-panel & ) >/dev/null 2>&1
        local waited=0
        while (( waited < 25 )); do
            if pgrep -x xfce4-panel >/dev/null 2>&1; then
                is_running=1
                break
            fi
            sleep 0.2
            waited=$(( waited + 1 ))
        done

        if [[ "${is_running}" -eq 0 ]]; then
            log_error "Failed to launch xfce4-panel process within 5 seconds."
            exit 1
        fi
        log_success "xfce4-panel process started (PID: $(pgrep -x xfce4-panel | tr '\n' ' '))"
    else
        log_info "Reloading existing xfce4-panel process (PID: $(pgrep -x xfce4-panel | tr '\n' ' ')) via xfce4-panel -r..."
        xfce4-panel -r >/dev/null 2>&1 || true
    fi

    # Step 2: Post-reload health polling (Process + panel-1 in xfconf)
    local healthy=0
    local waited=0
    while (( waited < 25 )); do
        if pgrep -x xfce4-panel >/dev/null 2>&1 && assert_top_panel_exists; then
            healthy=1
            break
        fi
        sleep 0.2
        waited=$(( waited + 1 ))
    done

    # Step 3: Emergency recovery if process died or panel-1 vanished
    if [[ "${healthy}" -eq 0 ]]; then
        log_error "Top panel failed to stay alive after reload! Restoring snapshot and restarting..."
        restore_panel_state "${snapshot_file}"
        pkill -9 -x xfce4-panel >/dev/null 2>&1 || true
        sleep 0.5
        ( xfce4-panel & ) >/dev/null 2>&1

        waited=0
        while (( waited < 25 )); do
            if pgrep -x xfce4-panel >/dev/null 2>&1 && assert_top_panel_exists; then
                healthy=1
                break
            fi
            sleep 0.2
            waited=$(( waited + 1 ))
        done
    fi

    # Step 4: Final assertion - NEVER report intact without active process!
    if [[ "${healthy}" -eq 1 ]] && pgrep -x xfce4-panel >/dev/null 2>&1; then
        local pids
        pids="$(pgrep -x xfce4-panel | tr '\n' ' ')"
        log_success "Top panel process verified RUNNING (PID: ${pids}) with panel-1 active."
        return 0
    else
        log_error "CRITICAL: xfce4-panel process is NOT running or panel-1 is missing."
        exit 1
    fi
}
