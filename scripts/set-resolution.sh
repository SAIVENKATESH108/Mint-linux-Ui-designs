#!/usr/bin/env bash
# ==============================================================================
# Resolution Setter for Linux Mint XFCE (Target PC: HDMI-1 @ 1280x1024)
# Applies target resolution with a 15-second safety auto-revert timeout
# ==============================================================================

set -euo pipefail

OUTPUT="HDMI-1"
TARGET_MODE="1280x1024"
TARGET_RATE="60.02"
TIMEOUT=15

# Verify xrandr is available
if ! command -v xrandr &>/dev/null; then
    echo "✖ Error: xrandr command not found." >&2
    exit 1
fi

# Detect currently active mode on HDMI-1
CURRENT_MODE="$(xrandr | awk -v out="${OUTPUT}" '$1 == out {flag=1; next} flag && /^[ ]+[0-9]+x[0-9]+/ {if ($0 ~ /\*/) {print $1; exit}} flag && /^[a-zA-Z]/ {exit}')"

if [[ -z "${CURRENT_MODE}" ]]; then
    # Fallback mode detection
    CURRENT_MODE="$(xrandr --current | grep -E '\*' | head -n 1 | awk '{print $1}')"
fi

echo "==> Display Output: ${OUTPUT}"
echo "    Current Active Mode: ${CURRENT_MODE}"
echo "    Applying Target Mode: ${TARGET_MODE} @ ${TARGET_RATE}Hz..."

# Apply new mode
if ! xrandr --output "${OUTPUT}" --mode "${TARGET_MODE}" --rate "${TARGET_RATE}" 2>/dev/null; then
    # Try standard 60Hz rate if 60.02Hz fails
    xrandr --output "${OUTPUT}" --mode "${TARGET_MODE}" --rate 60.00
fi

echo "✔ Resolution switched to ${TARGET_MODE} on ${OUTPUT}."
echo "--------------------------------------------------------"
echo "Testing display stability. Auto-reverting in ${TIMEOUT} seconds..."
echo "Press 'Y' to KEEP this resolution, or 'N' (or wait) to REVERT."
echo "--------------------------------------------------------"

KEEP="n"
if read -t "${TIMEOUT}" -r -p "Keep this resolution? [y/N]: " USER_INPUT; then
    if [[ "${USER_INPUT}" =~ ^[Yy]$ ]]; then
        KEEP="y"
    fi
fi

echo ""
if [[ "${KEEP}" == "y" ]]; then
    echo "✔ Settings kept: ${TARGET_MODE} is now active."
    exit 0
else
    echo "⚠ Reverting to previous mode: ${CURRENT_MODE}..."
    xrandr --output "${OUTPUT}" --mode "${CURRENT_MODE}"
    echo "✔ Reverted to ${CURRENT_MODE}."
    exit 1
fi
