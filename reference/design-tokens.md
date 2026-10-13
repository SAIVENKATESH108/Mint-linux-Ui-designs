# macOS Sequoia Design Tokens Specification

Derived directly from [`preview/tokens.css`](../preview/tokens.css) and calibrated for **Linux Mint 22.3 XFCE (X11)** on target desktop hardware:
- **CPU**: Intel Core i3-3220 (2C/4T @ 3.3GHz)
- **RAM**: 12 GB
- **GPU**: NVIDIA GeForce GT 610 (Fermi GF119, nouveau driver, OpenGL 4.3 Mesa)
- **Display**: HDMI-1, 1280×1024 @ 60.02 Hz, scale 1x (5:4 aspect ratio). PRIMARY and only required target.
- **Chassis**: Desktop PC (No battery, No Bluetooth)

---

## 1. Unified Token Matrix (Lite vs Glass, Light vs Dark)

| Token Name | Light (Lite - Default) | Light (Glass) | Dark (Lite - Default) | Dark (Glass) | XFCE Target File / Key |
|---|---|---|---|---|---|
| **Menu Bar Background** | `rgba(245, 245, 247, 0.90)` | `rgba(255, 255, 255, 0.45)` | `rgba(24, 26, 36, 0.94)` | `rgba(18, 20, 31, 0.72)` | `gtk.css` (`.xfce4-panel.background`) |
| **Menu Bar Border** | `rgba(0, 0, 0, 0.12)` | `rgba(255, 255, 255, 0.45)` | `rgba(255, 255, 255, 0.10)` | `rgba(255, 255, 255, 0.08)` | `gtk.css` (`border-bottom`) |
| **Menu Bar Height** | `28px` | `28px` | `28px` | `28px` | `xfce4-panel.xml` (`/panels/panel-1/size`) |
| **Sidebar Width** | `76px` | `76px` | `76px` | `76px` | `xfce4-panel.xml` (`/panels/panel-2/size`) |
| **Sidebar Background** | `rgba(245, 245, 247, 0.90)` | `rgba(255, 255, 255, 0.45)` | `rgba(24, 26, 36, 0.94)` | `rgba(18, 20, 31, 0.72)` | `gtk.css` (`#panel-2`) |
| **Window Background** | `rgba(255, 255, 255, 0.96)` | `rgba(255, 255, 255, 0.65)` | `rgba(20, 22, 32, 0.96)` | `rgba(17, 20, 30, 0.82)` | `gtk.css` (`window.background`) |
| **Window Border** | `rgba(0, 0, 0, 0.15)` | `rgba(255, 255, 255, 0.55)` | `rgba(255, 255, 255, 0.12)` | `rgba(255, 255, 255, 0.10)` | `gtk.css` (`window decoration`) |
| **Window Radius** | `12px` | `12px` | `12px` | `12px` | `xfwm4/themerc` |
| **Dock Background** | `rgba(240, 240, 245, 0.90)` | `rgba(255, 255, 255, 0.40)` | `rgba(20, 22, 32, 0.92)` | `rgba(15, 17, 26, 0.75)` | `dock.theme` (`FillStart`, `FillEnd`) |
| **Dock Border** | `rgba(0, 0, 0, 0.12)` | `rgba(255, 255, 255, 0.45)` | `rgba(255, 255, 255, 0.12)` | `rgba(255, 255, 255, 0.12)` | `dock.theme` (`LineColor`) |
| **Dock Radius** | `22px` | `22px` | `22px` | `22px` | `dock.theme` (`TopRoundness`, `BottomRoundness`) |
| **Dock Icon Size** | `48px` | `48px` | `48px` | `48px` | `dconf` (`/net/launchpad/plank/docks/dock1/icon-size`) |
| **Dock Zoom Scale** | `118%` | `118%` | `118%` | `118%` | `dconf` (`zoom-enabled=true`, `zoom-percent=118`) |
| **Conky Card Background** | `rgba(255, 255, 255, 0.92)` | `rgba(255, 255, 255, 0.52)` | `rgba(28, 31, 46, 0.92)` | `rgba(22, 25, 38, 0.72)` | `*.conkyrc` (`own_window_colour`) |
| **Conky Card Radius** | `16px` | `16px` | `16px` | `16px` | `*.conkyrc` (Cairo rounded rectangle) |
| **Conky Update Rate** | `3.5s` | `3.0s` | `3.5s` | `3.0s` | `*.conkyrc` (`update_interval = 3.5`) |
| **Text Primary** | `#1e293b` | `#1e293b` | `#f8fafc` | `#f8fafc` | `gtk.css`, `*.conkyrc` (`default_color`) |
| **Text Secondary** | `#64748b` | `#64748b` | `#94a3b8` | `#94a3b8` | `gtk.css`, `*.conkyrc` (`color2`) |
| **Accent Blue** | `#0a84ff` | `#0a84ff` | `#0a84ff` | `#0a84ff` | `gtk.css` (`@define-color theme_selected_bg_color`), `dock.theme` |
| **Accent Mint (Logo)** | `#10b981` | `#10b981` | `#10b981` | `#10b981` | `assets/icons/apple-logo.svg` |
| **Traffic Close** | `#ff5f56` | `#ff5f56` | `#ff5f56` | `#ff5f56` | `xfwm4/close-active.xpm` |
| **Traffic Minimize** | `#ffbd2e` | `#ffbd2e` | `#ffbd2e` | `#ffbd2e` | `xfwm4/hide-active.xpm` |
| **Traffic Maximize** | `#27c93f` | `#27c93f` | `#27c93f` | `#27c93f` | `xfwm4/maximize-active.xpm` |

---

## 2. Planned Picom Compositor Configurations

The target machine uses a GeForce GT 610 with Mesa 25.2.8 nouveau driver. OpenGL 4.3 works, but shader-based blur stalls the GPU pipeline.

### Profile A: `picom-lite.conf` (Default for Target PC)
```ini
# Performance-focused profile: NO GPU blur, smooth vsync, subtle drop shadows
backend = "xrender";            # or "glx" with zero blur shaders
vsync = true;
use-damage = true;
mark-wmwin-focused = true;
mark-ovld-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
detect-transient = true;

# Subtle macOS drop shadows (low radius, low overhead)
shadow = true;
shadow-radius = 8;
shadow-opacity = 0.30;
shadow-offset-x = -8;
shadow-offset-y = -8;
shadow-exclude = [
  "name = 'Notification'",
  "class_g = 'Conky'",
  "class_g = 'Plank'",
  "class_g = 'xfce4-panel'",
  "_GTK_FRAME_EXTENTS@:c"
];

# Fading
fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
fade-delta = 10;

# Blur: DISABLED completely in Lite mode
blur-background = false;

# Window Types
wintypes:
{
  tooltip = { fade = true; shadow = true; opacity = 0.95; focus = true; };
  dock = { shadow = false; clip-shadow-above = true; };
  dropdown_menu = { opacity = 0.98; shadow = true; };
  popup_menu = { opacity = 0.98; shadow = true; };
};
```

### Profile B: `picom-glass.conf` (Optional for VM with 3D Accel / Capable GPU)
```ini
# Visual-fidelity profile: dual-kawase blur, rounded corners, deeper shadows
backend = "glx";
glx-no-stencil = true;
glx-copy-from-front = false;
vsync = true;
use-damage = true;

corner-radius = 12;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'xfce4-panel'"
];

shadow = true;
shadow-radius = 16;
shadow-opacity = 0.45;
shadow-offset-x = -16;
shadow-offset-y = -16;

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;

# Dual-kawase blur restricted to panel, dock, and popup surfaces
blur-method = "dual_kawase";
blur-strength = 4;
blur-background = true;
blur-background-exclude = [
  "window_type = 'desktop'",
  "class_g = 'slop'",
  "class_g = 'Conky'",
  "_GTK_FRAME_EXTENTS@:c"
];
```

---

## 3. Element Structure & Hardware Adaptations

1. **Top Menu Bar (28px)**:
   - Panel 1 in `xfce4-panel.xml`.
   - Hardware: Removed battery and Bluetooth icons. Added CPU Temperature readout (34°C) and uptime.
2. **Left Workspace Sidebar (76px)**:
   - Panel 2 in `xfce4-panel.xml` pinned to the left edge with autohide.
   - Contains 4 desktop workspaces (`Desk 1..4`), Terminal, VS Code, Software Manager, and Power menu.
3. **Plank Dock (Bottom, 48px icons, 22px radius)**:
   - Exactly 10 unified icons: Files, Firefox, Terminal, Text Editor, Music, Photos, Calendar, Settings, Software Manager, separator, Trash.
4. **Desktop Widgets (Conky, 3 Windows)**:
   - Grouped into 3 standalone Conky configs (`window 1: Clock/Weather`, `window 2: Calendar Oct 2026/Hardware`, `window 3: Media/Notes/Storage`).
   - `update_interval = 3.5s` to protect the Core i3-3220 from CPU wakeups.
5. **Resolution Handling (Primary Target: 1280×1024)**:
   - Fixed target: HDMI-1 at 1280×1024 (5:4 aspect ratio, 60.02 Hz).
   - Widget grid width is fixed at 320px (2 columns) and window sizes are calibrated so that sidebar (76px), active application window (left: 104px, width: ~600px), and right widget grid (right: 14px, width: 320px) never collide or overlap. 1920×1080 is purely optional and not targeted.
