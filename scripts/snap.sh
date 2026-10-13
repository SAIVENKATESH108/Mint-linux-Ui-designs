#!/usr/bin/env bash
# ==============================================================================
# Screenshot Capture Tool for Level 3 Visual Comparison
# Saves VM desktop screenshots to preview/ for automated comparison against reference
# ==============================================================================

set -euo pipefail

LABEL="${1:-latest}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW_DIR="${REPO_ROOT}/preview"
OUTPUT_FILE="${PREVIEW_DIR}/vm-${LABEL}.png"

mkdir -p "${PREVIEW_DIR}"

echo "==> Capturing VM Desktop Screenshot: ${OUTPUT_FILE}..."

if command -v xfce4-screenshooter &>/dev/null; then
    xfce4-screenshooter -f -s "${OUTPUT_FILE}"
elif command -v scrot &>/dev/null; then
    scrot -z "${OUTPUT_FILE}"
elif command -v import &>/dev/null; then
    import -window root "${OUTPUT_FILE}"
else
    echo "✖ Error: No screenshot tool found (install xfce4-screenshooter or scrot)."
    exit 1
fi

echo "  ✔ Screenshot captured: ${OUTPUT_FILE}"
echo "==> Level 3 Comparison:"
echo "    Compare ${OUTPUT_FILE} against the reference image in reference/ to audit differences."
