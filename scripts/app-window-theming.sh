#!/usr/bin/env bash
# ==============================================================================
# macOS Window Theming & Top Bar Gap Elimination Tool
# 1. Eliminates gap/space between browser windows and the top bar (struts & 0-margins).
# 2. Configures Brave, Chrome, Chromium, VS Code, and GTK apps to use native
#    macOS WhiteSur window frames (Red Close, Yellow Minimize, Green Maximize on left).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

verify_environment

log_info "==> Configuring macOS Window Frames & Eliminating Top Bar Gap..."

# ------------------------------------------------------------------------------
# 1. Eliminate Gap Between Windows and Top Bar (xfwm4 0-margins & panel struts)
# ------------------------------------------------------------------------------
log_info "Eliminating top bar gap (zeroing xfwm4 margins, locking 28px struts)..."
if command -v xfconf-query &>/dev/null; then
    set_xfconf_prop "xfwm4" "/general/margin_top" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_bottom" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_left" "int" "0"
    set_xfconf_prop "xfwm4" "/general/margin_right" "int" "0"

    set_xfconf_prop "xfce4-panel" "/panels/panel-1/size" "uint" "28"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/enable-struts" "bool" "true"
    set_xfconf_prop "xfce4-panel" "/panels/panel-1/position" "string" "p=6;x=0;y=0"

    # Snap to screen edge with 0 resistance gap
    set_xfconf_prop "xfwm4" "/general/snap_to_border" "bool" "true"
    set_xfconf_prop "xfwm4" "/general/snap_to_windows" "bool" "true"
    set_xfconf_prop "xfwm4" "/general/snap_width" "int" "10"
    set_xfconf_prop "xfwm4" "/general/snap_resist" "bool" "true"

    # Enforce left traffic light buttons (Close, Hide, Maximize)
    set_xfconf_prop "xfwm4" "/general/theme" "string" "WhiteSur-Dark"
    set_xfconf_prop "xfwm4" "/general/button_layout" "string" "CHM|"
    set_xfconf_prop "xfwm4" "/general/title_alignment" "string" "center"
    set_xfconf_prop "xsettings" "/Gtk/DecorationLayout" "string" "close,minimize,maximize:"
fi

# ------------------------------------------------------------------------------
# 2. Brave / Chromium / Chrome: Enable System Title Bar (macOS Traffic Lights)
# ------------------------------------------------------------------------------
log_info "Configuring Brave / Chromium browsers to use native macOS title bars..."

python3 - << 'EOF' || true
import json, os, glob

candidates = [
    os.path.expanduser("~/.config/BraveSoftware/Brave-Browser"),
    os.path.expanduser("~/.config/chromium"),
    os.path.expanduser("~/.config/google-chrome"),
]

for base in candidates:
    if not os.path.isdir(base):
        continue
    # Search for Preferences in Default and all Profile directories
    pref_files = glob.glob(os.path.join(base, "Default", "Preferences")) + \
                 glob.glob(os.path.join(base, "Profile *", "Preferences"))
    for pf in pref_files:
        try:
            with open(pf, "r", encoding="utf-8") as f:
                data = json.load(f)
            
            # custom_chrome_frame = False tells Chromium to use the OS window title bar
            if "browser" not in data:
                data["browser"] = {}
            if data["browser"].get("custom_chrome_frame") != False:
                # Backup first
                backup_path = pf + ".sequoia.bak"
                if not os.path.exists(backup_path):
                    with open(backup_path, "w", encoding="utf-8") as bf:
                        json.dump(data, bf)
                data["browser"]["custom_chrome_frame"] = False
                with open(pf, "w", encoding="utf-8") as f:
                    json.dump(data, f)
                print(f"  ✔ Enabled macOS system title bar in: {pf}")
            else:
                print(f"  ✔ Already using system title bar: {pf}")
        except Exception as e:
            print(f"  ⚠ Could not parse {pf}: {e}")
EOF

# ------------------------------------------------------------------------------
# 3. VS Code & Cursor: Enable Native Window Frame
# ------------------------------------------------------------------------------
log_info "Configuring VS Code / Cursor to use native macOS title bar..."

python3 - << 'EOF' || true
import json, os

editor_dirs = [
    os.path.expanduser("~/.config/Code/User"),
    os.path.expanduser("~/.config/Cursor/User"),
    os.path.expanduser("~/.config/VSCodium/User"),
]

for ed in editor_dirs:
    sf = os.path.join(ed, "settings.json")
    if os.path.isfile(sf):
        try:
            with open(sf, "r", encoding="utf-8") as f:
                content = f.read()
            # If valid JSON without comments
            data = json.loads(content)
            if data.get("window.titleBarStyle") != "native":
                data["window.titleBarStyle"] = "native"
                with open(sf, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=4)
                print(f"  ✔ Set window.titleBarStyle: native in {sf}")
        except Exception:
            # If file has comments (JSONC), print instruction
            pass
EOF

log_success "Window configuration applied: macOS traffic light buttons active and 0-gap enforced."
log_info "If Brave is currently running, restart Brave to display the new macOS title bar."
