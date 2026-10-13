# macOS Sequoia Style Linux Mint XFCE Desktop

Automated, idempotent, and reversible desktop transformation suite that turns a Linux Mint 22.3 XFCE system into a macOS Sequoia-style desktop environment. Tailored for legacy x86_64 hardware (Core i3-3220, NVIDIA GeForce GT 610, 1280x1024 resolution) running X11.

---

## 🖥️ Target System & Architecture

- **Base System**: Linux Mint 22.3 (Zena) / Ubuntu 24.04 LTS (Noble)
- **Desktop Environment**: XFCE 4.18 (X11 Display Server)
- **Target Hardware**: Intel Core i3-3220 @ 3.3GHz, 12GB RAM, NVIDIA GT 610 (nouveau driver)
- **Display Resolution**: 1280x1024 @ 60Hz

---

## 🎨 Design Tokens & Reference

All colors, radii, spacing, and typography are canonically declared in [`reference/design-tokens.conf`](reference/design-tokens.conf):
- **Window Controls**: Traffic lights (`#ff5f56`, `#ffbd2e`, `#27c93f`) on the left (`CHM|`).
- **Top Panel**: 26px height, dark frosted translucent background (`rgba(30, 30, 32, 0.85)`), Apple logo launcher.
- **Dock**: Plank 44px icons, 14px corner radius, dodge-window autohide, zoom on hover.
- **Spotlight & Launchpad**: Rofi themes styled with Apple Blue (`#007aff`) accents.
- **Compositor Profiles**:
  - **`lite` mode** (*default*): `xrender` backend, 0 blur, smooth shadows, lightweight for GT 610.
  - **`full` mode**: `glx` backend with dual-kawase blur for capable hardware.

---

## 🚀 Toolchain & Phases

| Phase | Component | Script | Key Features |
|---|---|---|---|
| **Phase 1** | GTK & Icons | `phases/01-theme-assets.sh` | Vendored WhiteSur-Dark GTK theme, WhiteSur icons, Apple logo |
| **Phase 2** | WM & Compositor | `phases/02-wm-compositor.sh` | xfwm4 left traffic lights, Picom compositor (lite / full) |
| **Phase 3** | Top Menu Bar | `phases/03-top-panel.sh` | xfce4-panel 26px top bar styled via GTK3 CSS, macOS clock format |
| **Phase 4** | Dock | `phases/04-plank-dock.sh` | Plank bottom dock with Sequoia theme, zoom effect, pinned apps |
| **Phase 5** | Search & Launchers | `phases/05-launchpad-spotlight.sh` | Rofi Spotlight (`Super+Space`), Launchpad (`F4`), xfdashboard (`F3`) |
| **Phase 6** | Desktop Widgets | `phases/06-conky-widgets.sh` | Conky glance widget (clock, date, CPU/RAM/SSD glance) |

---

## 📦 VM Testing Guide

### 1. Transfer or Clone to VM
```bash
git clone <repository-url> linux-mint-design
cd linux-mint-design
```

### 2. Testing Phase-by-Phase

#### **Phase 1: Theme Assets**
```bash
bash phases/01-theme-assets.sh
```
- **What to Expect**: Window theme switches to WhiteSur-Dark, icons change to macOS style, Apple icon is installed.
- **How to Test**: Open Thunar file manager and XFCE Settings to inspect the dark window chrome and icons.
- **Undo**: `bash uninstall.sh --phase 1`

#### **Phase 2: Window Manager & Compositor**
```bash
# Test with lite mode (recommended for GT 610)
bash phases/02-wm-compositor.sh --lite

# Or test full mode if VM has 3D acceleration enabled
bash phases/02-wm-compositor.sh --full
```
- **What to Expect**: Traffic light dots (Close, Minimize, Maximize) appear on the top-left of every window. Picom launches with tear-free vsync and subtle shadows.
- **Undo**: `bash uninstall.sh --phase 2`

#### **Phase 3: Top Menu Bar**
```bash
bash phases/03-top-panel.sh
```
- **What to Expect**: Panel relocates to the top edge (26px height), styled with translucent dark acrylic styling and Apple menu icon.
- **Undo**: `bash uninstall.sh --phase 3`

#### **Phase 4: Plank Dock**
```bash
bash phases/04-plank-dock.sh
```
- **What to Expect**: macOS-style bottom dock pops up with smooth hover zoom and pinned launchers (Finder/Thunar, Browser, Terminal, Settings).
- **Undo**: `bash uninstall.sh --phase 4`

#### **Phase 5: Spotlight & Launchpad**
```bash
bash phases/05-launchpad-spotlight.sh
```
- **What to Expect**:
  - Press `Super + Space`: Spotlight search modal appears in center screen.
  - Press `F4` or `Super + A`: Fullscreen Launchpad app grid opens.
  - Press `F3`: Mission Control window overview appears.
- **Undo**: `bash uninstall.sh --phase 5`

#### **Phase 6: Desktop Glance Widget**
```bash
bash phases/06-conky-widgets.sh --lite
```
- **What to Expect**: Clean macOS Sequoia date, time, and system resource bars appear on the upper right of the desktop.
- **Undo**: `bash uninstall.sh --phase 6`

---

## ⚡ Master Installer & Complete Rollback

To deploy everything at once:
```bash
# Standard lite run for target PC
bash install.sh --lite

# Full effects mode
bash install.sh --full
```

To completely restore original Mint configuration:
```bash
bash uninstall.sh --all
```
All original configurations are automatically backed up before every change in `~/.mint-sequoia-backup/<timestamp>/`.

---

## 🔒 Safety & Idempotency Guarantee
- Scripts never use `sudo` automatically without explicit confirmation.
- Running any phase twice is safe and produces identical results without duplication.
- No commands affect the development host machine.
