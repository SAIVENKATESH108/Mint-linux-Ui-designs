#!/usr/bin/env bash
# ==============================================================================
# Sequoia Conflict & Collision Checker
# Audits user configuration files and autostart entries for potential conflicts
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_YELLOW="\033[1;33m"

CONFLICTS=0

echo "=========================================================="
printf "${C_BOLD}%s${C_RESET}\n" " Sequoia Configuration Conflict Audit"
echo "=========================================================="

# 1. Check for duplicate autostart entries
echo "Scanning ~/.config/autostart for duplicate daemons..."
AUTOSTART_DIR="${HOME}/.config/autostart"

if [[ -f "${AUTOSTART_DIR}/sequoia-session.desktop" ]]; then
    for old in "picom.desktop" "plank.desktop" "conky.desktop"; do
        if [[ -f "${AUTOSTART_DIR}/${old}" ]]; then
            printf "  ${C_RED}[CONFLICT]${C_RESET} Legacy autostart entry '%s' co-exists with consolidated supervisor!\n" "${old}"
            CONFLICTS=$(( CONFLICTS + 1 ))
        fi
    done
fi

# 2. Check for GTK 3 custom CSS conflicts
GTK_CSS="${HOME}/.config/gtk-3.0/gtk.css"
if [[ -f "${GTK_CSS}" ]]; then
    if grep -q "sequoia/sidebar.css" "${GTK_CSS}" 2>/dev/null; then
        printf "  ${C_RED}[CONFLICT]${C_RESET} Deleted sidebar.css is still imported in %s\n" "${GTK_CSS}"
        CONFLICTS=$(( CONFLICTS + 1 ))
    fi
fi

# 3. Check compositor conflicts
if command -v xfconf-query &>/dev/null; then
    XFWM_COMP="$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo "false")"
    if [[ "${XFWM_COMP}" == "true" ]] && pgrep -x picom &>/dev/null; then
        printf "  ${C_YELLOW}[WARNING]${C_RESET} Both xfwm4 compositing AND picom are running simultaneously!\n"
        CONFLICTS=$(( CONFLICTS + 1 ))
    fi
fi

echo "=========================================================="
if (( CONFLICTS == 0 )); then
    printf "Result: ${C_GREEN}Zero conflicts detected. System configuration is clean.${C_RESET}\n"
    exit 0
else
    printf "Result: ${C_YELLOW}%d conflict(s) or warnings detected.${C_RESET}\n" "${CONFLICTS}"
    exit 1
fi
