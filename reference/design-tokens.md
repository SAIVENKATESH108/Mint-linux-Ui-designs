# macOS Sequoia Design Tokens Specification

Derived from Apple macOS Sequoia guidelines and the Stitch project reference screens (`projects/12494559196641412690`).
Optimized for **Linux Mint 22.3 XFCE (X11)** on target legacy hardware (Intel Core i3-3220, 12GB RAM, NVIDIA GT 610, 1280x1024).

---

## 1. Color Palette

### 1.1 Brand & System Accents
| Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| `accent-primary` | `#0A84FF` / `#007AFF` | `#0A84FF` / `#3E90FF` | Selection, active links, primary buttons |
| `accent-emerald` (Mint) | `#10B981` / `#059669` | `#34D399` / `#4AE183` | Mint leaf logo, success indicators, battery |
| `traffic-close` | `#FF5F56` (Border: `#E0443E`) | `#FF5F56` (Border: `#E0443E`) | Window Close button |
| `traffic-minimize` | `#FFBD2E` (Border: `#DEA123`) | `#FFBD2E` (Border: `#DEA123`) | Window Minimize button |
| `traffic-maximize` | `#27C93F` (Border: `#1AAB29`) | `#27C93F` (Border: `#1AAB29`) | Window Maximize button |

### 1.2 Surface Colors & Glass Translucency
| Token | Light Mode (Glass Edition) | Dark Mode (Smoked Edition) |
|---|---|---|
| `menu-bar-bg` | `rgba(255, 255, 255, 0.45)` | `rgba(18, 20, 31, 0.72)` |
| `menu-bar-border` | `rgba(255, 255, 255, 0.45)` | `rgba(255, 255, 255, 0.08)` |
| `window-bg` | `rgba(255, 255, 255, 0.65)` | `rgba(17, 20, 30, 0.82)` |
| `window-border` | `rgba(255, 255, 255, 0.55)` | `rgba(255, 255, 255, 0.10)` |
| `dock-bg` | `rgba(255, 255, 255, 0.40)` | `rgba(15, 17, 26, 0.75)` |
| `dock-border` | `rgba(255, 255, 255, 0.45)` | `rgba(255, 255, 255, 0.12)` |
| `card-bg` (Widgets) | `rgba(255, 255, 255, 0.52)` | `rgba(22, 25, 38, 0.72)` |
| `card-border` | `rgba(255, 255, 255, 0.40)` | `rgba(255, 255, 255, 0.08)` |
| `control-center-bg` | `rgba(255, 255, 255, 0.75)` | `rgba(22, 25, 38, 0.82)` |
| `control-center-border` | `rgba(255, 255, 255, 0.50)` | `rgba(255, 255, 255, 0.16)` |
| `popover-item-bg` | `rgba(0, 0, 0, 0.05)` | `rgba(255, 255, 255, 0.06)` |

### 1.3 Typography Colors
| Token | Light Mode | Dark Mode |
|---|---|---|
| `text-primary` | `#0F172A` (Slate 900) / `#1E293B` (Slate 800) | `#F8FAFC` (Slate 50) / `#E2E8F0` (Slate 200) |
| `text-secondary` | `#475569` (Slate 600) / `#64748B` (Slate 500) | `#94A3B8` (Slate 400) / `#64748B` (Slate 500) |
| `text-muted` | `#94A3B8` (Slate 400) | `#475569` (Slate 600) |
| `text-accent` | `#0A84FF` | `#3E90FF` |

---

## 2. Blur & Compositing Specifications

### 2.1 Ideal Target Specifications (Modern GPU / Reference UI)
| Surface | Backdrop Filter Blur | Saturation | Inset Highlights | Drop Shadow |
|---|---|---|---|---|
| **Top Menu Bar** | `blur(28px)` | `saturate(190%)` | `0 1px 1px rgba(255,255,255,0.2)` | `0 16px 38px rgba(0,0,0,0.08)` |
| **Window Body** | `blur(40px - 44px)` | `saturate(190% - 210%)` | `0 0 0 1px rgba(255,255,255,0.08)` | `0 28px 70px rgba(0,0,0,0.60)` |
| **Plank Dock** | `blur(35px - 38px)` | `saturate(200%)` | `0 1px 1px rgba(255,255,255,0.15)` | `0 22px 50px rgba(0,0,0,0.55)` |
| **Widget Cards** | `blur(24px - 28px)` | `saturate(180%)` | `0 1px 1px rgba(255,255,255,0.05)` | `0 12px 30px rgba(0,0,0,0.35)` |
| **Control Center** | `blur(48px)` | `saturate(190%)` | `0 0 0 1px rgba(255,255,255,0.08)` | `0 28px 60px rgba(0,0,0,0.60)` |

### 2.2 Target Hardware Optimization (GT 610 / nouveau X11)
> [!IMPORTANT]
> Real-time OpenGL 40px dual-kawase blur across fullscreen causes severe GPU pipeline stall on the NVIDIA GT 610. The compositor provides two profiles:

- **Picom Lite Profile (Default for Old PC)**:
  - Backend: `xrender` (or minimal `glx` with no blur shaders).
  - Blur: `blur-background = false;`.
  - Shadows: Subtle radius 8, opacity 0.35.
  - Appearance: Translucency simulated via solid alpha tinting + crisp 1px borders.
- **Picom Full Profile (For VM with 3D Accel / Capable GPU)**:
  - Backend: `glx`.
  - Blur: `dual_kawase`, strength 4.
  - Shadows: Radius 16, opacity 0.45.

---

## 3. Border Radii

| Element | Radius | CSS / Config Value |
|---|---|---|
| **Traffic Light Dots** | 100% circle (12px × 12px) | `border-radius: 9999px;` |
| **Menu Buttons / Applet Pills** | 6px | `border-radius: 6px;` |
| **Context Menus / Dropdowns** | 8px - 10px | `border-radius: 8px;` |
| **Window Frame (xfwm4)** | 10px - 12px | `border-radius: 12px;` |
| **Left Sidebar (Desktops)** | 16px | `border-radius: 16px;` |
| **Desktop Widget Cards** | 16px | `border-radius: 16px;` |
| **Control Center Modal** | 20px | `border-radius: 20px;` |
| **Plank Dock** | 22px (`TopRoundness=22`) | `border-radius: 22px;` |
| **Launchpad Grid App Icons** | 18px (72px × 72px icon) | `border-radius: 18px;` |
| **Spotlight Window** | 14px | `border-radius: 14px;` |

---

## 4. Spacing & Geometry

| Element | Dimension / Spacing | Reference Source |
|---|---|---|
| **Menu Bar Height** | `28px` (display density 1280x1024 / 1920x1080) | Stitch Header |
| **Menu Bar Font Size** | `13px` medium | Stitch Header |
| **Left Sidebar Width** | `74px` (collapsed/dark) to `92px` (standard) | Stitch Left Sidebar |
| **Left Sidebar Desktop Item** | `w: 48px - 56px`, `h: 36px - 40px` | Stitch Virtual Desktops |
| **Plank Dock Height & Icon** | Icon size: `44px - 48px`, zoom: `120%` | Stitch Glass Dock |
| **Plank Bottom Margin** | `14px` from bottom screen edge | Stitch Glass Dock |
| **Right Widget Grid Width** | `456px` | Stitch Widget Aside |
| **Widget Grid Top Margin** | `112px` (leaves gap under top bar & notifications) | Stitch Widget Aside |
| **Widget Grid Gaps** | `16px` | Stitch Grid Gap |
| **Control Center Dropdown** | `w: 330px`, `top: 34px`, `right: 14px` | Stitch Control Center |
| **Spotlight Modal** | `w: 600px`, centered | Stitch Spotlight |
| **Launchpad Grid** | 7 columns × 4-5 rows, 72px icons | Stitch Launchpad |

---

## 5. Typography

- **Primary UI Font**: `Inter` (Fallback: `-apple-system`, `BlinkMacSystemFont`, `Ubuntu`, `Segoe UI`)
- **Display / Headers**: `Geist` or `Inter SemiBold`
- **Monospace / Code**: `JetBrains Mono` or `Ubuntu Mono`

### Type Scale
- **Display Clock**: 28px - 32px Bold
- **Window Headers**: 13px SemiBold
- **Menu Bar Items**: 13px Medium
- **Body & App Labels**: 11px - 12px Regular/Medium
- **Micro Labels / Badges**: 9px - 10px Bold (Uppercase tracking)
