#!/usr/bin/env bash
# ==============================================================================
# Linux Mint XFCE - Picom Compositor Profile Switcher (Lite vs Glass)
# Lite: Rounded corners + shadows + fade, NO blur (Optimal for NVIDIA GT 610)
# Glass: Dual-Kawase blur on panel, dock, widgets (Requires OpenGL 4.3 Mesa)
# ==============================================================================

set -euo pipefail

PICOM_CONFIG_DIR="${HOME}/.config/picom"
TARGET="${1:-toggle}"

if [[ ! -d "${PICOM_CONFIG_DIR}" ]]; then
    echo "✖ Error: Picom configuration directory not found at ${PICOM_CONFIG_DIR}." >&2
    exit 1
fi

CURRENT_IS_LITE=1
if [[ -f "${PICOM_CONFIG_DIR}/picom.conf" ]] && grep -q "dual_kawase" "${PICOM_CONFIG_DIR}/picom.conf"; then
    CURRENT_IS_LITE=0
fi

if [[ "${TARGET}" == "toggle" ]]; then
    if [[ "${CURRENT_IS_LITE}" -eq 1 ]]; then
        TARGET="glass"
    else
        TARGET="lite"
    fi
fi

case "${TARGET,,}" in
    lite)
        echo "==> Switching to Picom LITE Profile (No GPU blur, smooth 60 FPS)..."
        cp -f "${PICOM_CONFIG_DIR}/picom-lite.conf" "${PICOM_CONFIG_DIR}/picom.conf"
        ;;
    glass)
        echo "==> Switching to Picom GLASS Profile (Dual-Kawase blur on panel/dock/widgets)..."
        cp -f "${PICOM_CONFIG_DIR}/picom-glass.conf" "${PICOM_CONFIG_DIR}/picom.conf"
        ;;
    *)
        echo "Usage: $0 [lite|glass|toggle]" >&2
        exit 1
        ;;
esac

# Restart picom if running
if pgrep -x picom >/dev/null; then
    pkill -x picom || true
    sleep 0.5
    picom --config "${PICOM_CONFIG_DIR}/picom.conf" -b 2>/dev/null || {
        echo "⚠ Failed to restart picom in background. Check with: picom --config ${PICOM_CONFIG_DIR}/picom.conf" >&2
    }
fi

echo "✔ Compositor profile is now: ${TARGET}"
