#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Desktop Transformation Library
# Common utilities for backups, idempotency, xfconf modification, and logging
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

# Determine repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
REFERENCE_DIR="${REPO_ROOT}/reference"
VENDOR_DIR="${REPO_ROOT}/vendor"

# Global backup tracking
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="${HOME}/.mint-sequoia-backup"
SESSION_BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
BACKUP_INITIALIZED=0

init_backup() {
    if [[ "${BACKUP_INITIALIZED}" -eq 0 ]]; then
        mkdir -p "${SESSION_BACKUP_DIR}"
        echo "## Backup Session initialized: ${TIMESTAMP}" > "${SESSION_BACKUP_DIR}/manifest.log"
        echo "#!/usr/bin/env bash" > "${SESSION_BACKUP_DIR}/restore-xfconf.sh"
        chmod +x "${SESSION_BACKUP_DIR}/restore-xfconf.sh"
        BACKUP_INITIALIZED=1
        log_info "Backup directory initialized at: ${SESSION_BACKUP_DIR}"
    fi
}

# Ensure execution safety
verify_environment() {
    if [[ "${EUID}" -eq 0 ]]; then
        log_error "Do NOT run this script as root/sudo! Desktop settings belong to user: ${USER}."
        exit 1
    fi

    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "This script is designed for Linux Mint XFCE, not ${OSTYPE}."
        exit 1
    fi
}

# Backup a file or directory before modifying
backup_item() {
    local target="$1"
    if [[ -e "${target}" || -L "${target}" ]]; then
        init_backup
        local rel_path
        # Normalize relative path under HOME
        if [[ "${target}" == "${HOME}/"* ]]; then
            rel_path="${target#"${HOME}/"}"
        else
            rel_path="$(echo "${target}" | sed 's|^/||')"
        fi
        local dest="${SESSION_BACKUP_DIR}/${rel_path}"
        mkdir -p "$(dirname "${dest}")"
        cp -a "${target}" "${dest}"
        echo "BACKUP:${target}->${dest}" >> "${SESSION_BACKUP_DIR}/manifest.log"
    fi
}

# Idempotent file copy with backup
safe_copy() {
    local src="$1"
    local dest="$2"

    if [[ ! -f "${src}" ]]; then
        log_error "Source file not found: ${src}"
        return 1
    fi

    # Check if destination already has identical content
    if [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
        log_success "Already up-to-date: ${dest}"
        return 0
    fi

    backup_item "${dest}"
    mkdir -p "$(dirname "${dest}")"
    cp -f "${src}" "${dest}"
    log_success "Installed: ${dest}"
}

# Idempotent directory sync with backup
safe_sync_dir() {
    local src="$1"
    local dest="$2"

    if [[ ! -d "${src}" ]]; then
        log_error "Source directory not found: ${src}"
        return 1
    fi

    backup_item "${dest}"
    mkdir -p "${dest}"
    cp -a "${src}/." "${dest}/"
    log_success "Synced directory: ${dest}"
}

# Idempotent xfconf property modification with rollback script recording
set_xfconf_prop() {
    local channel="$1"
    local property="$2"
    local type="$3"
    local new_val="$4"

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

    init_backup
    # Record previous value in restore script
    if [[ -n "${current_val}" ]]; then
        echo "xfconf-query -c \"${channel}\" -p \"${property}\" -s \"${current_val}\"" >> "${SESSION_BACKUP_DIR}/restore-xfconf.sh"
    else
        echo "xfconf-query -c \"${channel}\" -p \"${property}\" -r -R 2>/dev/null || true" >> "${SESSION_BACKUP_DIR}/restore-xfconf.sh"
    fi

    # Apply new value
    xfconf-query -c "${channel}" -p "${property}" --create -t "${type}" -s "${new_val}"
    log_success "xfconf [${channel}] ${property} updated: '${current_val}' -> '${new_val}'"
}

# Check if packages are installed and prompt if missing
check_required_packages() {
    local missing=()
    for pkg in "$@"; do
        if ! dpkg -s "${pkg}" &>/dev/null; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing required packages: ${missing[*]}"
        log_info "To install them, run:"
        echo "  sudo apt update && sudo apt install -y ${missing[*]}"
        read -p "Would you like to install them now with sudo? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt update && sudo apt install -y "${missing[@]}"
        else
            log_error "Required packages missing. Please install them and re-run."
            exit 1
        fi
    fi
}
