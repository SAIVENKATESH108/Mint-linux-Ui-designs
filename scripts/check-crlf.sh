#!/usr/bin/env bash
# ==============================================================================
# CRLF Line Ending Validation Script
# Scans all script and configuration files to ensure 100% LF endings
# Exits with 1 if any CRLF line endings are detected
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0
CHECKED=0

echo "==> Scanning repository for CRLF line endings..."

# Find all text files in repo excluding git directory and vendor archives
while IFS= read -r -d '' file; do
    CHECKED=$((CHECKED + 1))
    if file "${file}" | grep -q "CRLF"; then
        echo "✖ CRLF detected: ${file}" >&2
        ERRORS=$((ERRORS + 1))
    elif grep -q $'\r' "${file}" 2>/dev/null; then
        echo "✖ Carriage return (^M) detected: ${file}" >&2
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "${REPO_ROOT}" -type f \
    \( -name "*.sh" -o -name "*.conf" -o -name "*.conkyrc" -o -name "*.rasi" \
       -o -name "*.css" -o -name "*.json" -o -name "*.theme" -o -name "*.dockitem" \
       -o -name "*.desktop" -o -name "*.in" \) \
    -not -path "*/.git/*" \
    -not -path "*/vendor/archives/*" \
    -print0)

echo "Checked ${CHECKED} files."

if [[ "${ERRORS}" -gt 0 ]]; then
    echo "✖ FAILED: Found ${ERRORS} file(s) with CRLF line endings!" >&2
    echo "Run: dos2unix <file> or git checkout-index to fix." >&2
    exit 1
else
    echo "✔ PASSED: All ${CHECKED} files have clean Unix (LF) line endings."
    exit 0
fi
