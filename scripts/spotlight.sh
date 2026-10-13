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

exec rofi -show combi -combi-modes "drun,run,filebrowser" -theme "${THEME_FILE}"
