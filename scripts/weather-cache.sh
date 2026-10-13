#!/usr/bin/env bash
# ==============================================================================
# Weather Cache Helper for Conky Widgets
# Fetches weather from wttr.in and caches result to /tmp/wttr_cache.txt
# Refreshes at most once every 1800 seconds (30 mins) to prevent network spam
# ==============================================================================

set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
CACHE_FILE="${CACHE_DIR}/wttr_cache.txt"
CACHE_TTL=1800 # 30 minutes
CITY="${1:-}"

# Check if cache is fresh
if [[ -f "${CACHE_FILE}" ]]; then
    LAST_MOD="$(stat -c %Y "${CACHE_FILE}" 2>/dev/null || stat -f %m "${CACHE_FILE}" 2>/dev/null || echo 0)"
    NOW="$(date +%s)"
    AGE=$(( NOW - LAST_MOD ))

    if [[ "${AGE}" -lt "${CACHE_TTL}" ]]; then
        cat "${CACHE_FILE}"
        exit 0
    fi
fi

# Fetch new weather reading if online
FETCHED=""
if command -v curl &>/dev/null; then
    FETCHED="$(curl -s --connect-timeout 3 --max-time 5 "wttr.in/${CITY}?format=%C+%t" 2>/dev/null || true)"
fi

if [[ -n "${FETCHED}" && ! "${FETCHED}" =~ "Unknown" && ! "${FETCHED}" =~ "html" ]]; then
    echo "${FETCHED}" > "${CACHE_FILE}"
    echo "${FETCHED}"
else
    # Fallback to existing cache or default placeholder
    if [[ -f "${CACHE_FILE}" && -s "${CACHE_FILE}" ]]; then
        cat "${CACHE_FILE}"
    else
        echo "Clear +21°C" > "${CACHE_FILE}"
        echo "Clear +21°C"
    fi
fi
