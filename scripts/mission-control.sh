#!/usr/bin/env bash
# macOS Mission Control Launcher
exec xfdashboard -t "${HOME}/.local/share/xfdashboard/themes/Sequoia" 2>/dev/null || exec xfdashboard
