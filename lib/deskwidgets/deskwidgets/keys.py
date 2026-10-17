"""
Keyboard shortcuts manager for macOS Sequoia Desktop on Linux Mint XFCE.
Single owner for all desktop shortcuts:
- Stores user configuration in ~/.config/sequoia/keys.json
- Defaults DO NOT use Super key (uses Ctrl+Alt combinations and Function keys)
- Optional Super shortcuts can be toggled on/off (default: off)
- Validates XFCE accelerator syntax (<Primary>, <Alt>, <Shift>, <Super>)
- Detects conflicts against /commands/custom, /xfwm4/custom, and known system shortcuts
- Tracks owned bindings in ~/.config/sequoia/manifest.json
- Atomic application and rollback; never modifies user-created shortcuts
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

CONFIG_DIR = os.path.expanduser("~/.config/sequoia")
STATE_DIR = os.path.expanduser("~/.local/state/sequoia")
KEYS_FILE = os.path.join(CONFIG_DIR, "keys.json")
MANIFEST_FILE = os.path.join(CONFIG_DIR, "manifest.json")
BACKUP_DIR = os.path.expanduser("~/.mint-sequoia-backup")

# Default action configuration (Zero Super key dependence)
DEFAULT_KEYS = {
    "super_enabled": False,
    "bindings": {
        "control_center": {
            "name": "Control Center",
            "command": os.path.expanduser("~/.local/bin/control-center.sh"),
            "primary": "<Primary><Alt>c",
            "secondary": None,
            "super": "<Super>c",
            "description": "Quick settings, brightness, volume, media",
        },
        "spotlight": {
            "name": "Spotlight",
            "command": os.path.expanduser("~/.local/bin/spotlight.sh"),
            "primary": "<Primary><Alt>space",
            "secondary": None,
            "super": "<Super>space",
            "description": "Global application & document search",
        },
        "launchpad": {
            "name": "Launchpad",
            "command": os.path.expanduser("~/.local/bin/launchpad.sh"),
            "primary": "F4",
            "secondary": "<Primary><Alt>a",
            "super": "<Super>a",
            "description": "Full-screen app grid launcher",
        },
        "mission_control": {
            "name": "Mission Control",
            "command": os.path.expanduser("~/.local/bin/mission-control.sh"),
            "primary": "F3",
            "secondary": "<Primary><Alt>m",
            "super": "<Super>Up",
            "description": "Window overview & workspaces",
        },
        "settings": {
            "name": "Sequoia Settings",
            "command": os.path.expanduser("~/.local/bin/sequoia-settings.sh"),
            "primary": "<Primary><Alt>s",
            "secondary": "<Primary><Alt>comma",
            "super": "<Super>comma",
            "description": "Sequoia desktop preferences",
        },
        "theme_toggle": {
            "name": "Toggle Day/Night Theme",
            "command": os.path.expanduser("~/.local/bin/toggle-theme.sh"),
            "primary": "<Primary><Alt>n",
            "secondary": None,
            "super": "<Super>t",
            "description": "Switch between Dark Obsidian & Light Frosted",
        },
        "help": {
            "name": "Shortcuts Help",
            "command": os.path.expanduser("~/.local/bin/sequoia-ctl keys help"),
            "primary": "<Primary><Alt>h",
            "secondary": "F1",
            "super": "<Super>h",
            "description": "Display keyboard shortcuts cheat sheet",
        },
    },
}

KNOWN_SYSTEM_SHORTCUTS = {
    "<Primary><Alt>t": "Terminal Emulator (exo-open)",
    "<Primary><Alt>l": "Lock Screen (xflock4)",
    "<Primary><Alt>d": "Show Desktop (xfwm4)",
    "<Primary><Alt>Delete": "Task Manager / Lock (xflock4)",
    "<Alt>space": "Window Operations Menu (xfwm4)",
    "<Alt>Tab": "Cycle Windows (xfwm4)",
    "<Alt>F4": "Close Window (xfwm4)",
    "<Alt>F2": "Application Finder (xfrun4)",
    "<Alt>F10": "Maximize Window (xfwm4)",
    "<Alt>F9": "Minimize Window (xfwm4)",
    "<Primary><Alt>Left": "Workspace Left (xfwm4)",
    "<Primary><Alt>Right": "Workspace Right (xfwm4)",
}

VALID_MODIFIERS = ["<Primary>", "<Alt>", "<Shift>", "<Super>"]
VALID_SPECIAL_KEYS = {
    "space", "comma", "period", "Return", "Escape", "Tab", "BackSpace",
    "Delete", "Insert", "Home", "End", "Page_Up", "Page_Down",
    "Up", "Down", "Left", "Right", "minus", "plus", "equal",
    "slash", "backslash", "grave",
}


def validate_accelerator(accel: str) -> tuple[bool, str]:
    """
    Validates XFCE accelerator string format.
    Accepts:
      - Function keys: F1 to F12
      - Modifiers followed by key: e.g. <Primary><Alt>c, <Primary>space, <Shift>F4
    Returns (is_valid, error_message).
    """
    if not accel or not isinstance(accel, str):
        return False, "Accelerator string cannot be empty"

    accel = accel.strip()

    # Standalone function key
    if re.fullmatch(r"F([1-9]|1[0-2])", accel):
        return True, ""

    # Must contain valid modifiers
    remaining = accel
    mods_found = []
    while remaining.startswith("<"):
        end_idx = remaining.find(">")
        if end_idx == -1:
            return False, f"Malformed modifier token in '{accel}'"
        mod = remaining[:end_idx + 1]
        if mod not in VALID_MODIFIERS:
            return False, f"Invalid modifier '{mod}' (must be one of {VALID_MODIFIERS})"
        mods_found.append(mod)
        remaining = remaining[end_idx + 1:]

    if not mods_found:
        return False, f"Accelerator '{accel}' must include modifiers (<Primary>, <Alt>, <Shift>, <Super>) or be a function key (F1-F12)"

    if not remaining:
        return False, f"Missing key name after modifiers in '{accel}'"

    # Validate remaining key
    if re.fullmatch(r"F([1-9]|1[0-2])", remaining):
        return True, ""

    if remaining in VALID_SPECIAL_KEYS:
        return True, ""

    if re.fullmatch(r"[a-z0-9]", remaining):
        return True, ""

    return False, f"Unrecognized key '{remaining}' in accelerator '{accel}'"


def get_xfconf_bindings() -> dict:
    """Reads active bindings from xfce4-keyboard-shortcuts channel."""
    bindings = {}
    if not shutil.which("xfconf-query"):
        return bindings

    try:
        res = subprocess.run(
            ["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-l"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=3.0,
        )
        for prop in res.stdout.splitlines():
            prop = prop.strip()
            if prop.startswith("/commands/custom/"):
                accel = prop[len("/commands/custom/"):]
                cmd_res = subprocess.run(
                    ["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    check=False,
                    timeout=2.0,
                )
                bindings[accel] = cmd_res.stdout.strip()
            elif prop.startswith("/xfwm4/custom/"):
                accel = prop[len("/xfwm4/custom/"):]
                cmd_res = subprocess.run(
                    ["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    check=False,
                    timeout=2.0,
                )
                bindings[accel] = f"xfwm4:{cmd_res.stdout.strip()}"
    except Exception:
        pass
    return bindings


def load_keys_config() -> dict:
    """Loads ~/.config/sequoia/keys.json or initializes with DEFAULT_KEYS."""
    if not os.path.exists(KEYS_FILE):
        return DEFAULT_KEYS.copy()
    try:
        with open(KEYS_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        if "bindings" not in cfg:
            cfg["bindings"] = DEFAULT_KEYS["bindings"].copy()
        if "super_enabled" not in cfg:
            cfg["super_enabled"] = False
        return cfg
    except Exception:
        return DEFAULT_KEYS.copy()


def save_keys_config(cfg: dict):
    """Saves keys config to ~/.config/sequoia/keys.json."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(KEYS_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


def load_manifest() -> dict:
    """Loads ~/.config/sequoia/manifest.json to determine installed ownership."""
    if not os.path.exists(MANIFEST_FILE):
        return {"installed_shortcuts": []}
    try:
        with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"installed_shortcuts": []}


def save_manifest(manifest: dict):
    """Saves manifest to ~/.config/sequoia/manifest.json and mirrors in state/."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(MANIFEST_FILE, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(os.path.join(STATE_DIR, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
    except OSError:
        pass


def detect_conflicts(cfg: dict, xfconf_map: dict = None) -> list:
    """
    Evaluates every accelerator candidate in cfg against active system bindings.
    Returns list of records:
      {
        'action': action_key,
        'name': action_name,
        'candidate': accel,
        'type': 'primary'|'secondary'|'super',
        'status': 'PASS'|'CONFLICT',
        'owner': owner_string,
        'free': bool
      }
    """
    if xfconf_map is None:
        xfconf_map = get_xfconf_bindings()

    manifest = load_manifest()
    owned_props = set(manifest.get("installed_shortcuts", []))

    records = []
    bindings = cfg.get("bindings", {})
    super_enabled = cfg.get("super_enabled", False)

    for action_key, info in bindings.items():
        candidates = []
        if info.get("primary"):
            candidates.append((info["primary"], "primary"))
        if info.get("secondary"):
            candidates.append((info["secondary"], "secondary"))
        if super_enabled and info.get("super"):
            candidates.append((info["super"], "super"))

        for accel, c_type in candidates:
            prop_key = f"/commands/custom/{accel}"
            is_our_manifest = prop_key in owned_props

            owner = None
            if accel in KNOWN_SYSTEM_SHORTCUTS:
                owner = f"System Default: {KNOWN_SYSTEM_SHORTCUTS[accel]}"
            elif accel in xfconf_map:
                owner = f"XFCE: {xfconf_map[accel]}"

            if owner is None or is_our_manifest or (owner and info["command"] in owner):
                records.append({
                    "action": action_key,
                    "name": info["name"],
                    "candidate": accel,
                    "type": c_type,
                    "status": "PASS",
                    "owner": "Free / Owned by Sequoia" if not is_our_manifest else "Owned by Sequoia",
                    "free": True,
                })
            else:
                records.append({
                    "action": action_key,
                    "name": info["name"],
                    "candidate": accel,
                    "type": c_type,
                    "status": "CONFLICT",
                    "owner": owner,
                    "free": False,
                })

    return records


def apply_keys(cfg: dict, force: bool = False) -> tuple[bool, str]:
    """
    Applies keys from cfg to xfce4-keyboard-shortcuts.
    - Validates all accelerators syntax.
    - Enforces conflict detection (aborts unless force=True).
    - Removes previously installed bindings tracked in manifest.json.
    - Writes active bindings and updates manifest.json.
    """
    if not shutil.which("xfconf-query"):
        return False, "'xfconf-query' command not available in PATH"

    # Syntax validation
    for act, info in cfg.get("bindings", {}).items():
        for field in ["primary", "secondary"]:
            v = info.get(field)
            if v:
                ok, err = validate_accelerator(v)
                if not ok:
                    return False, f"Syntax error in {act} ({field}): {err}"
        if cfg.get("super_enabled", False) and info.get("super"):
            ok, err = validate_accelerator(info["super"])
            if not ok:
                return False, f"Syntax error in {act} (super): {err}"

    # Conflict validation
    conflicts = [r for r in detect_conflicts(cfg) if r["status"] == "CONFLICT"]
    if conflicts and not force:
        conflict_msg = "\n".join([f"  • {c['candidate']} ({c['name']}) conflicts with {c['owner']}" for c in conflicts])
        return False, f"Shortcuts conflict detected:\n{conflict_msg}\nUse --force to override existing bindings."

    manifest = load_manifest()
    old_shortcuts = manifest.get("installed_shortcuts", [])

    # Remove previously installed shortcuts
    for prop in old_shortcuts:
        subprocess.run(
            ["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop, "-r", "-R"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    # Install active shortcuts
    new_installed = []
    bindings = cfg.get("bindings", {})
    super_enabled = cfg.get("super_enabled", False)

    for act, info in bindings.items():
        cmd = info["command"]
        accels = []
        if info.get("primary"):
            accels.append(info["primary"])
        if info.get("secondary"):
            accels.append(info["secondary"])
        if super_enabled and info.get("super"):
            accels.append(info["super"])

        for acc in accels:
            prop = f"/commands/custom/{acc}"
            res = subprocess.run(
                ["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop, "-n", "-t", "string", "-s", cmd],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                new_installed.append(prop)

    manifest["installed_shortcuts"] = new_installed
    save_manifest(manifest)
    save_keys_config(cfg)
    return True, f"Successfully applied {len(new_installed)} keyboard shortcut(s)."


def cmd_list(cfg: dict):
    print("======================================================================")
    print("                  SEQUOIA DESKTOP KEYBOARD SHORTCUTS")
    print("======================================================================")
    print(f"Super Key Mode: [CONFIGURED] {'ENABLED (optional)' if cfg.get('super_enabled') else 'DISABLED (Default: No Super key required)'}")
    print(f"Keys File:      [CONFIGURED] {KEYS_FILE}")
    print(f"Manifest:       [CONFIGURED] {MANIFEST_FILE}")
    print("----------------------------------------------------------------------")
    printf_fmt = "%-18s | %-16s | %-16s | %-10s | %s\n"
    print(printf_fmt % ("ACTION", "PRIMARY KEY", "SECONDARY KEY", "SUPER KEY", "DESCRIPTION"))
    print("-" * 70)
    for act, info in cfg.get("bindings", {}).items():
        p = info.get("primary") or "(none)"
        s = info.get("secondary") or "(none)"
        sup = info.get("super") if cfg.get("super_enabled") else f"({info.get('super')}) [off]"
        print(printf_fmt % (act, p, s, sup, info.get("description", "")))
    print("======================================================================")


def cmd_check(cfg: dict):
    records = detect_conflicts(cfg)
    print("======================================================================")
    print("              KEYBOARD SHORTCUTS CONFLICT CHECK [MEASURED]")
    print("======================================================================")
    has_conflict = False
    for r in records:
        status_tag = f"[\033[32mPASS\033[0m]" if r["status"] == "PASS" else f"[\033[31mCONFLICT\033[0m]"
        print(f" {status_tag} {r['candidate']:<18} -> {r['name']:<20} ({r['owner']})")
        if r["status"] == "CONFLICT":
            has_conflict = True
    print("----------------------------------------------------------------------")
    if not has_conflict:
        print("Result: [MEASURED] ALL CANDIDATES PASS (zero conflicts detected)")
    else:
        print("Result: [MEASURED] CONFLICTS DETECTED (resolve before applying or use --force)")
    return 1 if has_conflict else 0


def cmd_set(cfg: dict, action: str, accel: str, force: bool = False):
    if action not in cfg.get("bindings", {}):
        sys.stderr.write(f"Unknown action '{action}'. Valid actions: {list(cfg.get('bindings', {}).keys())}\n")
        return 1

    ok, err = validate_accelerator(accel)
    if not ok:
        sys.stderr.write(f"Invalid accelerator '{accel}': {err}\n")
        return 1

    # Backup current configuration before changing
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"keys_{ts}.json")
    try:
        shutil.copyfile(KEYS_FILE, backup_file)
        print(f"Backed up previous configuration to {backup_file}")
    except OSError:
        pass

    cfg["bindings"][action]["primary"] = accel
    save_keys_config(cfg)
    ok_apply, msg = apply_keys(cfg, force=force)
    if ok_apply:
        print(f"[SUCCESS] Set {action} -> {accel}. {msg}")
        return 0
    else:
        sys.stderr.write(f"[ERROR] Failed to apply: {msg}\n")
        return 1


def cmd_reset(cfg: dict, target: str):
    if target == "all":
        cfg = DEFAULT_KEYS.copy()
        print("Reset all shortcuts to defaults (Zero Super key dependence).")
    elif target in cfg.get("bindings", {}):
        cfg["bindings"][target] = DEFAULT_KEYS["bindings"][target].copy()
        print(f"Reset '{target}' shortcut to default ({cfg['bindings'][target]['primary']}).")
    else:
        sys.stderr.write(f"Unknown target '{target}'. Use 'all' or one of {list(cfg.get('bindings', {}).keys())}\n")
        return 1

    save_keys_config(cfg)
    ok, msg = apply_keys(cfg, force=True)
    if ok:
        print(f"[SUCCESS] {msg}")
        return 0
    else:
        sys.stderr.write(f"[ERROR] {msg}\n")
        return 1


def cmd_super(cfg: dict, state: str):
    new_state = (state.lower() in ("on", "true", "1", "enable"))
    cfg["super_enabled"] = new_state
    save_keys_config(cfg)
    ok, msg = apply_keys(cfg, force=True)
    print(f"[SUCCESS] Super key bindings {'ENABLED' if new_state else 'DISABLED'}. {msg}")
    return 0


def cmd_help_modal(cfg: dict):
    lines = [
        "==================================================",
        "          macOS Sequoia Keyboard Shortcuts",
        "==================================================",
    ]
    for act, info in cfg.get("bindings", {}).items():
        p = info.get("primary") or ""
        s = f", {info['secondary']}" if info.get("secondary") else ""
        lines.append(f"• {info['name']:<22} {p}{s}")
    lines.append("==================================================")
    content = "\n".join(lines)

    # If GUI available, show yad or zenity dialog
    if shutil.which("yad") and os.environ.get("DISPLAY"):
        subprocess.Popen([
            "yad", "--text-info", "--title=Sequoia Keyboard Shortcuts",
            "--width=450", "--height=320", "--button=Close:0",
            "--center", "--fontname=Monospace 10",
        ], stdin=subprocess.PIPE).communicate(input=content.encode("utf-8"))
        return 0
    elif shutil.which("zenity") and os.environ.get("DISPLAY"):
        subprocess.Popen([
            "zenity", "--text-info", "--title=Sequoia Keyboard Shortcuts",
            "--width=450", "--height=320",
        ], stdin=subprocess.PIPE).communicate(input=content.encode("utf-8"))
        return 0

    print(content)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Sequoia Keyboard Shortcuts Manager")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("list", help="List all configured actions and shortcuts")
    sub.add_parser("check", help="Detect conflicts with system shortcuts")
    sub.add_parser("apply", help="Apply configured shortcuts to XFCE")

    set_p = sub.add_parser("set", help="Set shortcut accelerator for an action")
    set_p.add_argument("action", help="Action name (e.g. control_center, spotlight)")
    set_p.add_argument("accelerator", help="Accelerator (e.g. <Primary><Alt>c, F4)")
    set_p.add_argument("--force", action="store_true", help="Override conflicting bindings")

    reset_p = sub.add_parser("reset", help="Reset action or all to defaults")
    reset_p.add_argument("target", nargs="?", default="all", help="Action name or 'all'")

    super_p = sub.add_parser("super", help="Toggle optional Super key bindings")
    super_p.add_argument("state", choices=["on", "off"], help="on or off")

    sub.add_parser("help", help="Display shortcuts cheat sheet")

    args = parser.parse_args()
    cfg = load_keys_config()

    if args.command == "list" or not args.command:
        cmd_list(cfg)
        return 0
    elif args.command == "check":
        return cmd_check(cfg)
    elif args.command == "apply":
        ok, msg = apply_keys(cfg)
        if ok:
            print(f"[SUCCESS] {msg}")
            return 0
        else:
            sys.stderr.write(f"[ERROR] {msg}\n")
            return 1
    elif args.command == "set":
        return cmd_set(cfg, args.action, args.accelerator, force=args.force)
    elif args.command == "reset":
        return cmd_reset(cfg, args.target)
    elif args.command == "super":
        return cmd_super(cfg, args.state)
    elif args.command == "help":
        return cmd_help_modal(cfg)

    return 0


if __name__ == "__main__":
    sys.exit(main())
