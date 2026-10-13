#!/usr/bin/env bash
# ==============================================================================
# macOS Sequoia Spotlight Search Wrapper (Rofi Combi Mode)
# Trigger: Super+Space
# ==============================================================================

set -euo pipefail

THEME_FILE="${HOME}/.config/rofi/spotlight.rasi"

if [[ ! -f "${THEME_FILE}" ]]; then
    THEME_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/rofi/spotlight.rasi"
fi

if command -v rofi &>/dev/null && [[ -f "${THEME_FILE}" ]]; then
    exec rofi -show combi -combi-modes "drun,run,filebrowser" -theme "${THEME_FILE}"
elif command -v xfce4-appfinder &>/dev/null; then
    exec xfce4-appfinder
else
    xfce4-popup-whiskermenu || true
fi
