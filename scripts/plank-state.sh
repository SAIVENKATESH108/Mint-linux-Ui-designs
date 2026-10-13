#!/usr/bin/env bash
# ==============================================================================
# Plank Dock Diagnostic & State Inspector
# Audits launcher files, verifies target .desktop existence, and dumps dconf settings.
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"

PLANK_LAUNCHERS_DIR="${HOME}/.config/plank/dock1/launchers"
DCONF_PATH="/net/launchpad/plank/docks/dock1"

echo "=========================================================="
printf "${C_BLUE}${C_BOLD}%s${C_RESET}\n" " Plank Dock State Diagnostic Audit"
echo "=========================================================="

# 1. Process Status
if pgrep -x plank >/dev/null 2>&1; then
    printf "  Process:    ${C_GREEN}RUNNING (PID %s)${C_RESET}\n" "$(pgrep -x plank | tr '\n' ' ')"
else
    printf "  Process:    ${C_RED}NOT RUNNING${C_RESET}\n"
fi

# 2. Disk Launchers Audit
echo ""
printf "${C_BOLD}Active Launcher Files in %s:${C_RESET}\n" "${PLANK_LAUNCHERS_DIR}"
TOTAL_ITEMS=0
VALID_ITEMS=0

if [[ -d "${PLANK_LAUNCHERS_DIR}" ]]; then
    for f in "${PLANK_LAUNCHERS_DIR}"/*.dockitem; do
        [[ -f "${f}" ]] || continue
        TOTAL_ITEMS=$(( TOTAL_ITEMS + 1 ))
        item_name="$(basename "${f}")"
        launcher_target="$(grep -E '^Launcher=' "${f}" 2>/dev/null | cut -d'=' -f2- || true)"

        if [[ "${launcher_target}" =~ ^docklet:// ]]; then
            printf "  ${C_GREEN}[OK]${C_RESET}      %-24s -> %s (Internal docklet)\n" "${item_name}" "${launcher_target}"
            VALID_ITEMS=$(( VALID_ITEMS + 1 ))
        else
            clean_path="$(echo "${launcher_target}" | sed 's#^file://##')"
            if [[ -f "${clean_path}" ]]; then
                printf "  ${C_GREEN}[OK]${C_RESET}      %-24s -> %s\n" "${item_name}" "${clean_path}"
                VALID_ITEMS=$(( VALID_ITEMS + 1 ))
            else
                printf "  ${C_RED}[MISSING]${C_RESET} %-24s -> %s\n" "${item_name}" "${clean_path}"
            fi
        fi
    done
    printf "  Total Files: %d (%d valid targets, %d broken)\n" "${TOTAL_ITEMS}" "${VALID_ITEMS}" "$(( TOTAL_ITEMS - VALID_ITEMS ))"
else
    printf "  ${C_YELLOW}Directory missing: %s${C_RESET}\n" "${PLANK_LAUNCHERS_DIR}"
fi

# 3. Dconf Settings Dump
echo ""
printf "${C_BOLD}Plank Dconf Settings (%s):${C_RESET}\n" "${DCONF_PATH}"
if command -v dconf &>/dev/null; then
    dconf dump "${DCONF_PATH}/" || echo "No dconf dump available."
    
    DCONF_ITEMS="$(dconf read "${DCONF_PATH}/dock-items" 2>/dev/null || echo "None")"
    echo ""
    printf "  dconf dock-items: %s\n" "${DCONF_ITEMS}"
fi

echo "=========================================================="
