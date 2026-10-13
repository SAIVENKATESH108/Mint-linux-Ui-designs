#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - macOS Sequoia Transformation Master Installer
# Runs and coordinates phases 1 through 6
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

verify_environment

MODE="lite"
TARGET_PHASE="all"

show_help() {
    cat << EOF
macOS Sequoia Desktop Transformation for Linux Mint XFCE
Usage: $0 [OPTIONS]

Options:
  --lite           Use lite profile (xrender, low CPU/GPU load - default for legacy hardware)
  --full           Use full visual profile (glx, dual-kawase blur)
  --phase <1-6>    Run only a specific phase
  --all            Run all phases (default)
  -h, --help       Show this help message

Phases:
  1. Prerequisites & Theme Assets (WhiteSur GTK, icons, cursors)
  2. Window Manager & Compositor (xfwm4 left traffic lights + Picom)
  3. Top Menu Bar (xfce4-panel styled via CSS + Apple launcher)
  4. Dock (Plank with Sequoia theme & pinned launchers)
  5. Launchpad & Spotlight (Rofi drun/grid + xfdashboard Mission Control)
  6. Desktop Glance Widgets (Conky system monitor)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lite)
            MODE="lite"
            shift
            ;;
        --full)
            MODE="full"
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

log_info "=========================================================="
log_info " macOS Sequoia Transformation Suite for Linux Mint XFCE"
log_info " Profile: [${MODE}] | Target: Phase [${TARGET_PHASE}]"
log_info "=========================================================="

run_phase() {
    local phase_num="$1"
    local script_name=""
    case "${phase_num}" in
        1) script_name="01-theme-assets.sh" ;;
        2) script_name="02-wm-compositor.sh" ;;
        3) script_name="03-top-panel.sh" ;;
        4) script_name="04-plank-dock.sh" ;;
        5) script_name="05-launchpad-spotlight.sh" ;;
        6) script_name="06-conky-widgets.sh" ;;
        *) log_error "Invalid phase: ${phase_num}"; exit 1 ;;
    esac

    local full_path="${SCRIPT_DIR}/phases/${script_name}"
    log_info "Executing Phase ${phase_num}: ${script_name} (${MODE} mode)..."
    bash "${full_path}" "--${MODE}"
}

if [[ "${TARGET_PHASE}" == "all" ]]; then
    for p in {1..6}; do
        run_phase "${p}"
    done
    log_success "🎉 All 6 phases completed successfully!"
    log_info "You can test the environment or run ./uninstall.sh to revert."
else
    run_phase "${TARGET_PHASE}"
    log_success "Phase ${TARGET_PHASE} completed successfully!"
fi
