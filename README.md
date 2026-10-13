# macOS Sequoia Style Linux Mint XFCE Desktop

Automated, idempotent, defensive, and reversible desktop transformation suite that turns a Linux Mint 22.3 XFCE desktop into an authentic macOS Sequoia workspace. Specifically calibrated for legacy hardware (Intel Core i3-3220, NVIDIA GeForce GT 610, HDMI-1 1280×1024 @ 60.02 Hz) running X11.

---

## 🖥️ Target System & Architecture

- **Operating System**: Linux Mint 22.3 (Zena) / Ubuntu 24.04 LTS (Noble)
- **Desktop Environment**: XFCE 4.18 (X11 Display Server)
- **Target Hardware**: Intel Core i3-3220 (2C/4T @ 3.3GHz), 12 GB RAM, NVIDIA GT 610 (Fermi GF119, nouveau driver, OpenGL 4.3 Mesa 25.2.8)
- **Chassis**: Desktop PC (No battery, No Bluetooth)
- **Display**: HDMI-1, 1280×1024 @ 60.02 Hz (5:4 aspect ratio, 1x scale). PRIMARY and required target.
- **Default Profile**: **LITE Mode** (Picom 10.2 GLX backend, rounded corners 12px, soft shadows, fade, **0% blur** to prevent GPU fillrate stalls).

---

## 🚀 The 8 Phases

| Phase | Component | Script | Key Features | Undo Command |
|---|---|---|---|---|
| **01** | Theme & Icons | `phases/01-theme.sh` | WhiteSur GTK (Dark & Light), WhiteSur icons, Inter font, left traffic-lights (`CHM\|`), `toggle-theme.sh` | `./phases/01-theme.sh --undo` |
| **02** | Compositor | `phases/02-compositor.sh` | Picom 10.2 (glx backend), lite profile default, glass profile optional, xfwm4 uncomposited, `lite-mode.sh` | `./phases/02-compositor.sh --undo` |
| **03** | Top Menu Bar | `phases/03-top-bar.sh` | `xfce4-panel` (28px height), macOS clock format (`%a %e %b  %l:%M %P`), Apple logo, GTK CSS styling | `./phases/03-top-bar.sh --undo` |
| **04** | Dock | `phases/04-dock.sh` | Plank with custom Sequoia theme, 10 unified icons, dodge-window autohide, bottom panel hidden | `./phases/04-dock.sh --undo` |
| **05** | Left Sidebar | `phases/05-left-sidebar.sh` | 76px vertical floating panel (`panel-2`), 4-desktop pager (`Desk 1..4`), 3 quick launchers, power button | `./phases/05-left-sidebar.sh --undo` |
| **06** | Desktop Widgets | `phases/06-widgets.sh` | 3 Conky windows (Clock+Weather, Calendar+Sensors, Media+Storage), update interval 3.5s, cached wttr.in weather | `./phases/06-widgets.sh --undo` |
| **07** | Launchers | `phases/07-launcher.sh` | Rofi Spotlight (`Super+Space`), 7×5 Launchpad app grid (`Super+A` / `F4`), Sequoia themes | `./phases/07-launcher.sh --undo` |
| **08** | Extras & Hotkeys | `phases/08-extras.sh` | Mission Control (`Super+Up` / `F3`), interactive Control Center menu (`Super+C`), macOS window shortcuts | `./phases/08-extras.sh --undo` |

---

## 🛠️ Installation & Execution Guide

### 1. Dry Run (Test Before Modifying)
To inspect every change without modifying files or xfconf:
```bash
./install.sh --dry-run
```

### 2. Full Installation (All 8 Phases)
```bash
# Default Lite Profile (Recommended for NVIDIA GT 610):
./install.sh --all

# Or explicitly select profile:
./install.sh --all --profile lite
```

### 3. Step-by-Step Execution
Run phases individually in order:
```bash
./install.sh --phase 1
./install.sh --phase 2
./install.sh --phase 3
./install.sh --phase 4
./install.sh --phase 5
./install.sh --phase 6
./install.sh --phase 7
./install.sh --phase 8
```

### 4. Offline Installation
If deploying without an active internet connection:
```bash
./install.sh --all --offline
```

---

## 🔍 Verification & Diagnostics

### Run the Integrity Audit
After running phases, audit every package, config, running process, and xfconf setting:
```bash
./scripts/verify.sh
```
Prints a clear `[PASS]` / `[FAIL]` report that you can paste back into chat.

### Hardware & Window Class Diagnostics
To dump system info or inspect window classes with `xprop`:
```bash
./scripts/diagnose.sh
```

---

## 🔄 Hot Reload & Screenshot Tools

- **Reload All Components**: `./scripts/reload.sh` (reloads GTK, panel, dock, widgets, picom, and xfwm4)
- **Capture Desktop Screenshot**: `./scripts/snap.sh [label]` (saves to `preview/vm-[label].png`)
- **Toggle Light / Dark Mode**: `~/.local/bin/toggle-theme.sh [light|dark|toggle]`
- **Toggle Lite / Glass Mode**: `~/.local/bin/lite-mode.sh [lite|glass|toggle]`

---

## ↩️ Rollback & Emergency Recovery

### Granular Rollback
Revert an individual phase:
```bash
./uninstall.sh --phase 2
```

### Full Transformation Reversal
Revert all 8 phases back to stock Linux Mint XFCE:
```bash
./uninstall.sh --all
```

### 🚨 Emergency Recovery from TTY (Ctrl+Alt+F3)
If the graphical desktop freezes, crashes, or fails to render:
1. Press `Ctrl + Alt + F3` to access a text console and log in.
2. Run:
   ```bash
   cd ~/linux-mint-design
   bash restore-default-desktop.sh
   ```
3. This script immediately:
   - Kills `picom`, `plank`, `conky`, `rofi`, and `xfdashboard`
   - Disables all autostarts
   - Re-enables native `xfwm4` compositing
   - Restores stock Mint-Y theme and traditional right window buttons (`O|HMC`)
   - Resets the panel to default
4. Press `Ctrl + Alt + F7` (or `sudo systemctl restart lightdm`) to return to your working desktop.
