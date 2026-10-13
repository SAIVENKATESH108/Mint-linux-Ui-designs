#!/usr/bin/env bash
# ==============================================================================
# macOS Sequoia Launchpad Application Grid Wrapper (Rofi 7x5 Grid)
# Trigger: Super+A or F4
# ==============================================================================

set -euo pipefail

THEME_FILE="${HOME}/.config/rofi/launchpad.rasi"

if [[ ! -f "${THEME_FILE}" ]]; then
    THEME_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/rofi/launchpad.rasi"
fi

exec rofi -show drun -theme "${THEME_FILE}"
