# Project: macOS-style Linux Mint XFCE Desktop

## Environment
- Development happens on the laptop (Windows). The target is a DIFFERENT machine: Linux Mint 22.3 XFCE (X11), old hardware (Intel Core i3-3220, 12GB RAM, NVIDIA GT 610, 1280x1024). See `./reference/system-info.txt`.
- Do NOT apply anything to the laptop's own desktop. Never run `apt`, `sudo`, or `xfconf-query` on this machine.
- Your job is to write scripts and config files in this repo. Testing is done in a Mint XFCE VM, then deployed to the old PC through git.

## Rules
1. Every script must be idempotent (safe to run twice) and back up existing configs to `~/.mint-sequoia-backup/<timestamp>/` before changing them.
2. One script per phase in `./phases/`, plus a matching undo step in `uninstall.sh`.
3. Use only X11-compatible tools. Performance matters more than effects, so provide a lite mode.
4. Pull colors, radii, and spacing from `./reference/`. Do not invent new ones.
5. Keep configs as files in `./config/` and symlink or copy them into place with the script.
6. Scripts must print clear errors and stop on failure (`set -euo pipefail`).
7. After each phase, give me: how to test it in the VM, what to expect, and how to undo it.
8. Commit each phase to git with a clear message.

## Preview workflow
- Phase 0: build HTML mockups in ./preview/ for each component and get my approval before writing XFCE configs.
- Every phase must include: a reload command (added to scripts/reload.sh), a screenshot step (scripts/snap.sh), and a list of differences versus the reference image.
- Say clearly which differences are XFCE limitations and which are fixable.

## Target hardware (from reference/system-info.txt)
- Linux Mint 22.3 (Ubuntu 24.04 base), XFCE 4.18, X11.
- Desktop PC, no battery. i3-3220 (2C/4T), 12 GB RAM, GeForce GT 610 on nouveau (weak GPU).
- Screen: 1280x1024 (5:4). Design and test at this resolution as well as 1920x1080.
- Picom is not installed.

## Performance rules
- Default profile is "lite": rounded corners + shadows + fade, NO blur, translucent flat colors for glass.
- "Glass" profile (optional): Picom blur (kawase, low strength) only for panel, dock, and widgets. Must be switchable with ./lite-mode.sh.
- No battery or Bluetooth elements unless detected at install time.
- Conky: max 3 windows, update_interval >= 3.
- Do not compile or install forks of Picom.

## Toolchain
WhiteSur GTK + icons (vendored), xfwm4 + Picom, xfce4-panel styled via CSS, Plank dock, Conky widgets, Rofi (Launchpad/Spotlight), xfdashboard for overview.
