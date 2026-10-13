#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Desktop Transformation Library
# Common utilities for backups, idempotency, xfconf modification, and logging
# Target: Linux Mint 22.3 (Ubuntu 24.04 noble base), XFCE 4.18, X11
# ==============================================================================

set -euo pipefail

# ANSI color codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_CYAN="\033[1;36m"

log_info() {
    printf "${C_BLUE}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$1"
}

log_success() {
    printf "${C_GREEN}  ✔${C_RESET} %s\n" "$1"
}

log_warn() {
    printf "${C_YELLOW}  ⚠ Warning:${C_RESET} %s\n" "$1"
}

log_error() {
    printf "${C_RED}  ✖ Error:${C_RESET} %s\n" "$1" >&2
}

log_dry() {
    printf "${C_CYAN}  [DRY-RUN]${C_RESET} %s\n" "$1"
}

# Determine repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
REFERENCE_DIR="${REPO_ROOT}/reference"
VENDOR_DIR="${REPO_ROOT}/vendor"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# Environment Flags (propagated from install.sh or sub-shells)
DRY_RUN="${DRY_RUN:-0}"
OFFLINE_MODE="${OFFLINE_MODE:-0}"
PROFILE_MODE="${PROFILE_MODE:-lite}"

# Global backup tracking
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="${HOME}/.mint-sequoia-backup"
SESSION_BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
CURRENT_PHASE_NUM="0"
CURRENT_PHASE_DIR="${SESSION_BACKUP_DIR}"
BACKUP_INITIALIZED=0

# Universal side-effect wrapper: only prints in dry-run mode
run() {
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log_dry "Would execute: $*"
        return 0
    else
        "$@"
    fi
}

init_phase_backup() {
    local phase_num="${1:-0}"
    CURRENT_PHASE_NUM="${phase_num}"
    CURRENT_PHASE_DIR="${SESSION_BACKUP_DIR}/phase${phase_num}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would initialize backup directory at: ${CURRENT_PHASE_DIR}"
        log_dry "Would dump active xfconf channels for Phase ${phase_num}"
        return 0
    fi

    mkdir -p "${CURRENT_PHASE_DIR}"
    echo "## Backup Session initialized: ${TIMESTAMP} for Phase ${phase_num}" > "${CURRENT_PHASE_DIR}/manifest.log"
    echo "#!/usr/bin/env bash" > "${CURRENT_PHASE_DIR}/restore-xfconf.sh"
    echo "# Auto-generated rollback script for Phase ${phase_num}" >> "${CURRENT_PHASE_DIR}/restore-xfconf.sh"
    chmod +x "${CURRENT_PHASE_DIR}/restore-xfconf.sh"
    BACKUP_INITIALIZED=1
    log_info "Backup initialized for Phase ${phase_num} at: ${CURRENT_PHASE_DIR}"

    # Dump active xfconf channels if xfconf-query is present
    if command -v xfconf-query &>/dev/null; then
        mkdir -p "${CURRENT_PHASE_DIR}/xfconf-dumps"
        for channel in xsettings xfwm4 xfce4-panel xfce4-desktop xfce4-keyboard-shortcuts xfce4-session; do
            xfconf-query -c "${channel}" -lv > "${CURRENT_PHASE_DIR}/xfconf-dumps/${channel}.txt" 2>/dev/null || true
        done
    fi

    # Backup critical config directories if they exist
    for dir_to_check in "${HOME}/.config/xfce4" "${HOME}/.config/gtk-3.0" "${HOME}/.config/autostart"; do
        if [[ -d "${dir_to_check}" ]]; then
            backup_item "${dir_to_check}"
        fi
    done
}

init_backup() {
    init_phase_backup "${CURRENT_PHASE_NUM}"
}

verify_environment() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_error "Do NOT run this script as root/sudo! Desktop settings belong to user: ${USER}."
        exit 1
    fi

    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "This script is designed for Linux Mint XFCE (Linux X11), not ${OSTYPE}."
        exit 1
    fi
}

backup_item() {
    local target="$1"
    if [[ -e "${target}" || -L "${target}" ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            log_dry "Would back up: ${target} -> ${CURRENT_PHASE_DIR}/"
            return 0
        fi

        local rel_path
        if [[ "${target}" == "${HOME}/"* ]]; then
            rel_path="${target#"${HOME}/"}"
        else
            rel_path="$(echo "${target}" | sed 's|^/||')"
        fi
        local dest="${CURRENT_PHASE_DIR}/${rel_path}"
        mkdir -p "$(dirname "${dest}")"
        cp -a "${target}" "${dest}"
        echo "BACKUP:${target}->${dest}" >> "${CURRENT_PHASE_DIR}/manifest.log"
    fi
}

safe_copy() {
    local src="$1"
    local dest="$2"

    if [[ ! -f "${src}" ]]; then
        log_error "Source file not found: ${src}"
        return 1
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would copy: ${src} -> ${dest}"
        return 0
    fi

    if [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
        log_success "Already up-to-date: ${dest}"
        return 0
    fi

    backup_item "${dest}"
    mkdir -p "$(dirname "${dest}")"
    cp -f "${src}" "${dest}"
    log_success "Installed: ${dest}"
}

safe_sync_dir() {
    local src="$1"
    local dest="$2"

    if [[ ! -d "${src}" ]]; then
        log_error "Source directory not found: ${src}"
        return 1
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would sync directory: ${src} -> ${dest}"
        return 0
    fi

    backup_item "${dest}"
    mkdir -p "${dest}"
    cp -a "${src}/." "${dest}/"
    log_success "Synced directory: ${dest}"
}

set_xfconf_prop() {
    local channel="$1"
    local property="$2"
    local type="$3"
    local new_val="$4"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would set xfconf [${channel}] ${property} (${type}) = '${new_val}'"
        return 0
    fi

    if ! command -v xfconf-query &>/dev/null; then
        log_warn "xfconf-query not found. Skipping xfconf setting: ${channel}:${property}"
        return 0
    fi

    local current_val
    current_val="$(xfconf-query -c "${channel}" -p "${property}" 2>/dev/null || true)"

    if [[ "${current_val}" == "${new_val}" ]]; then
        log_success "xfconf [${channel}] ${property} is already set to '${new_val}'"
        return 0
    fi

    if [[ -n "${current_val}" ]]; then
        echo "xfconf-query -c \"${channel}\" -p \"${property}\" -s \"${current_val}\"" >> "${CURRENT_PHASE_DIR}/restore-xfconf.sh"
    else
        echo "xfconf-query -c \"${channel}\" -p \"${property}\" -r -R 2>/dev/null || true" >> "${CURRENT_PHASE_DIR}/restore-xfconf.sh"
    fi

    xfconf-query -c "${channel}" -p "${property}" --create -t "${type}" -s "${new_val}"
    log_success "xfconf [${channel}] ${property} updated: '${current_val}' -> '${new_val}'"
}

run_sudo_cmd() {
    local cmd_str="$*"
    log_warn "Privileged action requested:"
    printf "      ${C_BOLD}%s${C_RESET}\n" "${cmd_str}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would execute privileged command: ${cmd_str}"
        return 0
    fi

    if [[ "${OFFLINE_MODE}" -eq 1 && "${cmd_str}" =~ apt ]]; then
        log_warn "Offline mode active: skipping apt network command."
        return 0
    fi

    read -p "Do you want to run this command now? [y/N]: " -n 1 -r REPLY
    echo
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        eval "${cmd_str}"
        log_success "Command completed."
    else
        log_warn "Command skipped by user."
        return 1
    fi
}

check_required_packages() {
    local missing=()
    for pkg in "$@"; do
        if ! dpkg -s "${pkg}" &>/dev/null; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
            log_dry "Missing package(s) detected: ${missing[*]}. Would prompt: sudo apt update && sudo apt install -y ${missing[*]}"
            return 0
        fi

        log_warn "Missing required package(s): ${missing[*]}"
        local install_cmd="sudo apt update && sudo apt install -y ${missing[*]}"
        run_sudo_cmd "${install_cmd}" || {
            log_warn "Packages not installed. Scripts will attempt fallback or fail gracefully."
        }
    fi
}

install_delayed_autostart() {
    local name="$1"
    local exec_cmd="$2"
    local comment="$3"
    local autostart_dir="${HOME}/.config/autostart"
    local dest_file="${autostart_dir}/${name}.desktop"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log_dry "Would register autostart (5s delay): ${dest_file} -> 'sleep 5 && ${exec_cmd}'"
        return 0
    fi

    mkdir -p "${autostart_dir}"
    backup_item "${dest_file}"

    cat > "${dest_file}" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Comment=${comment}
Exec=sh -c "sleep 5 && ${exec_cmd}"
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
EOF
    chmod +x "${dest_file}"
    log_success "Autostart registered (5s delay): ${dest_file}"
}
