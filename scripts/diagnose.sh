#!/usr/bin/env bash
# ==============================================================================
# Hardware & Environment Diagnostic Tool
# Dumps versions, xrandr, glxinfo, picom diagnostics, and queries window classes
# ==============================================================================

set -euo pipefail

REPORT_FILE="diagnostics-report.txt"
exec > >(tee "${REPORT_FILE}") 2>&1

echo "=========================================================="
echo " 🩺 Linux Mint XFCE - macOS Sequoia Diagnostics Tool"
echo " Date: $(date)"
echo " Report file: ${REPORT_FILE}"
echo "=========================================================="

echo ""
echo "--- 1. System & Desktop Environment ---"
if [[ -f /etc/os-release ]]; then
    grep -E '^(PRETTY_NAME|VERSION)=' /etc/os-release || true
fi
uname -srm
if command -v xfce4-session &>/dev/null; then
    xfce4-session --version | head -n1 || true
fi
if command -v xfwm4 &>/dev/null; then
    xfwm4 --version | head -n1 || true
fi

echo ""
echo "--- 2. Display & Resolution (xrandr) ---"
if command -v xrandr &>/dev/null; then
    xrandr --current | head -n 15 || true
else
    echo "xrandr not available."
fi

echo ""
echo "--- 3. OpenGL & GPU Capabilities (glxinfo) ---"
if command -v glxinfo &>/dev/null; then
    glxinfo -B || true
else
    echo "glxinfo not available (install mesa-utils)."
fi

echo ""
echo "--- 4. Picom Compositor Capabilities ---"
if command -v picom &>/dev/null; then
    picom --version || true
    echo "Picom Diagnostics:"
    picom --diagnostics 2>/dev/null | head -n 35 || true
else
    echo "picom not installed."
fi

echo ""
echo "--- 5. Window Class Identification (xprop WM_CLASS) ---"
echo "To verify UNVERIFIED window classes for Picom rules, run:"
echo "    xprop WM_CLASS"
echo "and click on the target window."
echo ""

if [[ -n "${DISPLAY:-}" ]] && command -v xprop &>/dev/null; then
    read -p "Would you like to click a window now to inspect WM_CLASS? [y/N]: " -n 1 -r REPLY
    echo
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        echo "==> Click on any window (xfce4-panel, Plank, Conky, etc.)..."
        xprop WM_CLASS || true
    fi
fi

echo ""
echo "=========================================================="
echo " Diagnostic report saved to: ${REPORT_FILE}"
echo " Paste this report into chat for analysis."
echo "=========================================================="
