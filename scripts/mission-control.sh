#!/usr/bin/env bash
# ==============================================================================
# macOS Sequoia Mission Control Wrapper (xfdashboard with Rofi Window Fallback)
# Trigger: Super+Up or F3
# ==============================================================================

set -euo pipefail

# Try xfdashboard if available and working
if command -v xfdashboard &>/dev/null; then
    THEME_DIR="${HOME}/.local/share/xfdashboard/themes/Sequoia"
    if [[ -d "${THEME_DIR}" ]]; then
        xfdashboard -t "${THEME_DIR}" 2>/dev/null && exit 0
    else
        xfdashboard 2>/dev/null && exit 0
    fi
fi

# Fallback: Rofi window overview (fast, 0% GPU load on GT 610)
if command -v rofi &>/dev/null; then
    exec rofi -show window -theme-str 'window { width: 700px; border-radius: 14px; }'
fi

echo "Neither xfdashboard nor rofi is available for Mission Control." >&2
exit 1
