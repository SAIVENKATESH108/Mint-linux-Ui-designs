#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Transformation Master Installer
# Target: Linux Mint 22.3, XFCE 4.18, X11, 1280x1024 @ 60 Hz, scale 1x
# Hardware: Intel Core i3-3220, 12 GB RAM, NVIDIA GT 610 (nouveau), Picom 10.2
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

verify_environment

PROFILE_MODE="lite"
TARGET_PHASE="all"
DRY_RUN=0
OFFLINE_MODE=0

show_help() {
    cat << EOF
macOS Sequoia Desktop Transformation Suite (Linux Mint 22.3 XFCE)
Usage: $0 [OPTIONS]

Options:
  --dry-run              Simulate execution without modifying files or xfconf
  --phase, -p <1-8>      Run only a specific phase
  --all                  Run all 8 phases (default)
  --offline              Skip external network downloads, use only local/vendor assets
  --profile <lite|glass> Choose compositor profile (default: lite - no GPU blur)
  -h, --help             Show this help message

Phases:
  1. Theme & Icons (WhiteSur GTK, icons, Inter font, left window buttons)
  2. Compositor (Picom 10.2 GLX backend, lite default, xfwm4 uncomposited)
  3. Top Menu Bar (xfce4-panel 28px, macOS clock, no battery/BT)
  4. Dock (Plank Sequoia theme, 10 unified icons, bottom panel hidden)
  5. Left Sidebar (76px vertical panel, 4-desktop pager, 3 launchers)
  6. Desktop Widgets (3 Conky windows, cached wttr.in weather, update >= 3.5s)
  7. Application Launchers (Rofi Spotlight: Super+Space, Launchpad: Super+A)
  8. System Extras (Mission Control, Control Center, macOS hotkeys)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            export DRY_RUN
            shift
            ;;
        --offline)
            OFFLINE_MODE=1
            export OFFLINE_MODE
            shift
            ;;
        --profile)
            PROFILE_MODE="${2,,}"
            export PROFILE_MODE
            shift 2
            ;;
        --lite)
            PROFILE_MODE="lite"
            export PROFILE_MODE
            shift
            ;;
        --glass|--full)
            PROFILE_MODE="glass"
            export PROFILE_MODE
            shift
            ;;
        --phase|-p)
            TARGET_PHASE="$2"
            shift 2
            ;;
        --all)
            TARGET_PHASE="all"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

export PROFILE_MODE DRY_RUN OFFLINE_MODE

log_info "=========================================================="
log_info " macOS Sequoia Transformation Suite for Linux Mint XFCE"
log_info " Target: HDMI-1 1280x1024 @ 60Hz | Core i3-3220 / GT 610"
log_info " Profile: [${PROFILE_MODE}] | Target: Phase [${TARGET_PHASE}]"
if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_warn " DRY-RUN MODE ACTIVE: No files or xfconf settings will change."
fi
if [[ "${OFFLINE_MODE}" -eq 1 ]]; then
    log_warn " OFFLINE MODE ACTIVE: Skipping apt/git network requests."
fi
log_info "=========================================================="

run_phase() {
    local phase_num="$1"
    local script_name=""
    case "${phase_num}" in
        1) script_name="01-theme.sh" ;;
        2) script_name="02-compositor.sh" ;;
        3) script_name="03-top-bar.sh" ;;
        4) script_name="04-dock.sh" ;;
        5) script_name="05-left-sidebar.sh" ;;
        6) script_name="06-widgets.sh" ;;
        7) script_name="07-launcher.sh" ;;
        8) script_name="08-extras.sh" ;;
        *) log_error "Invalid phase: ${phase_num}"; exit 1 ;;
    esac

    local full_path="${SCRIPT_DIR}/phases/${script_name}"
    if [[ ! -f "${full_path}" ]]; then
        log_error "Phase script not found: ${full_path}"
        exit 1
    fi

    log_info "Executing Phase ${phase_num}: ${script_name} (${PROFILE_MODE} profile)..."
    bash "${full_path}"
}

if [[ "${TARGET_PHASE}" == "all" ]]; then
    for p in {1..8}; do
        run_phase "${p}"
    done
    log_success "🎉 All 8 phases completed successfully!"
    log_info "Run ./scripts/verify.sh to validate deployment integrity."
    log_info "To revert, run ./uninstall.sh --all (or individual phases via ./uninstall.sh --phase N)."
else
    run_phase "${TARGET_PHASE}"
    log_success "Phase ${TARGET_PHASE} completed successfully!"
    log_info "Run ./scripts/verify.sh to validate."
fi
