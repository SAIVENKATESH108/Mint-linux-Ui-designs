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
    # If it is a shell script (.sh), ensure it has the executable bit in git and filesystem
    if [[ "${file}" == *.sh ]]; then
        # Check git index mode if tracked
        if command -v git &>/dev/null; then
            git_mode="$(git ls-files -s "${file}" 2>/dev/null | awk '{print $1}' || true)"
            if [[ -n "${git_mode}" && "${git_mode}" != "100755" ]]; then
                echo "✖ Missing executable bit in git index (mode ${git_mode}): ${file}" >&2
                echo "  Run: git update-index --chmod=+x \"${file}\"" >&2
                ERRORS=$((ERRORS + 1))
            fi
        fi
        # Check filesystem execute bit on POSIX environments
        if [[ "$(uname -s)" != *"MINGW"* && "$(uname -s)" != *"CYGWIN"* && "$(uname -s)" != *"MSYS"* && ! -x "${file}" ]]; then
            echo "✖ Missing execute permission on filesystem: ${file}" >&2
            echo "  Run: chmod +x \"${file}\"" >&2
            ERRORS=$((ERRORS + 1))
        fi
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
    echo "✖ FAILED: Found ${ERRORS} error(s) (CRLF line endings or missing execute bits)!" >&2
    exit 1
else
    echo "✔ PASSED: All ${CHECKED} files have clean Unix (LF) line endings and correct permissions."
    exit 0
fi
