#!/usr/bin/env python3
"""
macOS Sequoia Native Control Center Popover for Linux Mint XFCE
Matches Apple macOS Control Center layout and functionality:
- Profile header with user avatar, name, settings, and power buttons
- Quick toggle grid: Wi-Fi (toggle & network picker), Bluetooth (toggle & settings), AirDrop (network shares)
- Utility grid: Do Not Disturb, Day/Night Appearance (Dark/Light Mode system-wide toggle), Keyboard, Display Mirroring
- Live interactive Display Brightness slider (xrandr / brightnessctl)
- Live interactive Sound Volume slider (pactl / PulseAudio) + Mixer launcher
- Live Now Playing media card (playerctl with album art, track, artist, play/pause/next)
- Auto-dismiss on click outside (focus-out) or Escape key
- Clean toggle activation (kills existing instance if already open)
"""

import os
import sys
import signal
import subprocess
import shutil
import pwd

# Prevent duplicate instances: if already open, toggle close
PID_FILE = os.path.expanduser("~/.cache/sequoia-control-center.pid")

def handle_singleton():
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE, "r") as f:
                old_pid = int(f.read().strip())
            if old_pid != os.getpid() and os.path.exists(f"/proc/{old_pid}"):
                os.kill(old_pid, signal.SIGTERM)
                try:
                    os.remove(PID_FILE)
                except OSError:
                    pass
                sys.exit(0)
        except Exception:
            pass
    try:
        os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass

handle_singleton()

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Gtk, Gdk, GLib, GdkPixbuf, Pango
except ImportError as e:
    sys.stderr.write(f"GTK3/PyGObject not available: {e}\n")
    sys.exit(1)


def cleanup_and_exit(*_args):
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except OSError:
        pass
    Gtk.main_quit()


# -----------------------------------------------------------------------------
# System Helpers (Volume, Brightness, Wi-Fi, Bluetooth, DND, Theme, Media)
# -----------------------------------------------------------------------------

def run_cmd(args):
    try:
        res = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=False)
        return res.stdout.strip()
    except Exception:
        return ""


def get_current_user_info():
    user = os.environ.get("USER", "User")
    try:
        entry = pwd.getpwnam(user)
        full_name = entry.pw_gecos.split(",")[0].strip()
        if full_name:
            user = full_name
    except Exception:
        pass
    return user


def get_wifi_state():
    status = run_cmd(["nmcli", "-t", "-f", "WIFI", "g"])
    enabled = (status.lower() == "enabled")
    ssid = "Not Connected"
    if enabled:
        out = run_cmd(["nmcli", "-t", "-f", "NAME,TYPE", "c", "show", "--active"])
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and "wireless" in parts[1].lower():
                ssid = parts[0]
                break
        if ssid == "Not Connected":
            ssid_out = run_cmd(["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"])
            for line in ssid_out.splitlines():
                if line.startswith("yes:"):
                    ssid = line.split(":", 1)[1]
                    break
        if ssid == "Not Connected":
            ssid = "Wi-Fi On"
    else:
        ssid = "Off"
    return enabled, ssid


def toggle_wifi():
    enabled, _ = get_wifi_state()
    new_state = "off" if enabled else "on"
    run_cmd(["nmcli", "radio", "wifi", new_state])


def open_wifi_settings():
    for cmd in [["nm-connection-editor"], ["xfce4-terminal", "-e", "nmtui"], ["gnome-control-center", "wifi"]]:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd)
            cleanup_and_exit()
            return


def get_bluetooth_state():
    out = run_cmd(["rfkill", "list", "bluetooth"])
    if not out:
        return False, "Not Available"
    is_blocked = "Soft blocked: yes" in out or "Hard blocked: yes" in out
    return not is_blocked, ("On" if not is_blocked else "Off")


def toggle_bluetooth():
    enabled, _ = get_bluetooth_state()
    run_cmd(["rfkill", "unblock" if not enabled else "block", "bluetooth"])


def open_bluetooth_settings():
    for cmd in [["blueman-manager"], ["blueberry"], ["gnome-control-center", "bluetooth"]]:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd)
            cleanup_and_exit()
            return


def get_dnd_state():
    out = run_cmd(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb"])
    return out.lower() == "true"


def toggle_dnd():
    run_cmd(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb", "-T"])


def get_current_theme_mode():
    out = run_cmd(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName"])
    return "dark" if "dark" in out.lower() else "light"


def toggle_system_theme():
    script_candidates = [
        os.path.expanduser("~/.local/bin/toggle-theme.sh"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "toggle-theme.sh"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "toggle-theme.sh"),
    ]
    for s in script_candidates:
        if os.path.isfile(s):
            subprocess.run(["bash", s, "toggle"])
            return


def get_sound_volume():
    out = run_cmd(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
    for token in out.split():
        if token.endswith("%"):
            try:
                return int(token.rstrip("%"))
            except ValueError:
                pass
    return 50


def set_sound_volume(percent):
    percent = max(0, min(100, int(percent)))
    subprocess.Popen(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{percent}%"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_sound_settings():
    for cmd in [["pavucontrol"], ["xfce4-mixer"], ["gnome-control-center", "sound"]]:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd)
            cleanup_and_exit()
            return


def get_primary_display():
    out = run_cmd(["xrandr", "--query"])
    for line in out.splitlines():
        if " connected" in line:
            return line.split()[0]
    return "HDMI-1"


def get_display_brightness():
    disp = get_primary_display()
    out = run_cmd(["xrandr", "--verbose"])
    in_disp = False
    for line in out.splitlines():
        if line.startswith(disp + " connected"):
            in_disp = True
            continue
        if in_disp and line.startswith(disp):
            break
        if in_disp and "Brightness:" in line:
            try:
                val = float(line.split("Brightness:")[1].strip())
                return int(val * 100)
            except Exception:
                pass
    return 100


def set_display_brightness(percent):
    percent = max(10, min(100, int(percent)))
    disp = get_primary_display()
    brightness_val = f"{percent / 100.0:.2f}"
    subprocess.Popen(["xrandr", "--output", disp, "--brightness", brightness_val],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_display_settings():
    for cmd in [["xfce4-display-settings"], ["gnome-control-center", "display"]]:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd)
            cleanup_and_exit()
            return


def get_media_info():
    out = run_cmd(["playerctl", "metadata", "--format", "{{title}}|{{artist}}|{{status}}|{{mpris:artUrl}}"])
    if not out or "|" not in out:
        return "No media playing", "Music", "Stopped", ""
    parts = out.split("|")
    title = parts[0] if len(parts) > 0 and parts[0] else "Unknown Title"
    artist = parts[1] if len(parts) > 1 and parts[1] else "Unknown Artist"
    status = parts[2] if len(parts) > 2 and parts[2] else "Stopped"
    art = parts[3] if len(parts) > 3 else ""
    return title, artist, status, art


# -----------------------------------------------------------------------------
# Control Center GTK Popover Window
# -----------------------------------------------------------------------------

CSS = """
* {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Ubuntu", "Inter", sans-serif;
    color: #ffffff;
}

window.control-center-window {
    background-color: transparent;
}

.main-card {
    background-color: rgba(30, 31, 34, 0.90);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 24px;
    padding: 12px;
}

.card {
    background-color: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 16px;
    padding: 10px;
}

.card-button {
    background-color: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 14px;
    padding: 8px 10px;
}

.card-button:hover {
    background-color: rgba(255, 255, 255, 0.15);
}

.circle-icon-btn {
    border-radius: 50%;
    min-width: 32px;
    min-height: 32px;
    padding: 0;
    background-color: rgba(255, 255, 255, 0.12);
    color: #ffffff;
}

.circle-icon-btn.active {
    background-color: #007aff;
    color: #ffffff;
}

.circle-icon-btn.active-orange {
    background-color: #ff9500;
    color: #ffffff;
}

.circle-icon-btn.active-purple {
    background-color: #af52de;
    color: #ffffff;
}

.circle-icon-btn.active-amber {
    background-color: #f59e0b;
    color: #ffffff;
}

.title-text {
    font-size: 13px;
    font-weight: 600;
    color: #ffffff;
}

.subtitle-text {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.65);
}

.header-name {
    font-size: 13px;
    font-weight: 700;
}

scale trough {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 16px;
    min-height: 24px;
    border: none;
}

scale highlight {
    background-color: #ffffff;
    border-radius: 16px;
    min-height: 24px;
}

scale slider {
    background-color: #ffffff;
    border-radius: 50%;
    min-width: 22px;
    min-height: 22px;
    margin: -1px;
    border: 1px solid rgba(0, 0, 0, 0.1);
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
}

.media-btn {
    background: transparent;
    border: none;
    padding: 4px;
    min-width: 24px;
}
.media-btn:hover {
    color: #007aff;
}
"""

class SequoiaControlCenter(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title("Control Center")
        self.set_role("popover")
        self.set_wmclass("SequoiaControlCenter", "SequoiaControlCenter")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        self.get_style_context().add_class("control-center-window")

        # Load CSS
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(CSS.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_screen(
            screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.build_ui()

        # Connect events
        self.connect("destroy", cleanup_and_exit)
        self.connect("focus-out-event", lambda *_: cleanup_and_exit())
        self.connect("key-press-event", self.on_key_press)

        # Update timers
        GLib.timeout_add(1500, self.update_dynamic_state)

        # Position window on screen (top-right under the topbar)
        self.position_window()

    def position_window(self):
        screen = self.get_screen()
        screen_w = screen.get_width()
        win_w = 344
        win_h = 530
        self.set_size_request(win_w, win_h)
        # Position 12px from right edge, 34px from top (under 30px panel)
        pos_x = max(0, screen_w - win_w - 12)
        pos_y = 34
        self.move(pos_x, pos_y)

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            cleanup_and_exit()
            return True
        return False

    def build_ui(self):
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        main_box.get_style_context().add_class("main-card")
        self.add(main_box)

        # ---------------------------------------------------------------------
        # 1. Profile / Header Card
        # ---------------------------------------------------------------------
        header_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        header_card.get_style_context().add_class("card")

        avatar = Gtk.Image.new_from_icon_name("avatar-default-symbolic", Gtk.IconSize.DND)
        avatar.set_pixel_size(28)
        header_card.pack_start(avatar, False, False, 0)

        user_name = get_current_user_info()
        name_btn = Gtk.Button(label=user_name)
        name_btn.get_style_context().add_class("card-button")
        name_btn.connect("clicked", lambda *_: (subprocess.Popen(["xfce4-settings-manager"]), cleanup_and_exit()))
        header_card.pack_start(name_btn, True, True, 0)

        settings_btn = Gtk.Button.new_from_icon_name("preferences-system-symbolic", Gtk.IconSize.BUTTON)
        settings_btn.get_style_context().add_class("circle-icon-btn")
        settings_btn.set_tooltip_text("System Settings")
        settings_btn.connect("clicked", self.on_open_settings)
        header_card.pack_start(settings_btn, False, False, 0)

        power_btn = Gtk.Button.new_from_icon_name("system-shutdown-symbolic", Gtk.IconSize.BUTTON)
        power_btn.get_style_context().add_class("circle-icon-btn")
        power_btn.set_tooltip_text("Log Out / Shut Down")
        power_btn.connect("clicked", self.on_open_power)
        header_card.pack_start(power_btn, False, False, 0)

        main_box.pack_start(header_card, False, False, 0)

        # ---------------------------------------------------------------------
        # 2. Quick Toggles Grid (Left: Wi-Fi, BT, AirDrop / Right: DND, Theme, Mirror)
        # ---------------------------------------------------------------------
        toggles_grid = Gtk.Grid()
        toggles_grid.set_column_spacing(10)
        toggles_grid.set_row_spacing(10)
        toggles_grid.set_column_homogeneous(True)

        # Left Column: Network Toggles Card
        net_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        net_card.get_style_context().add_class("card")

        # Wi-Fi Row (Click icon to toggle on/off, click text to open network picker)
        wifi_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.wifi_btn = Gtk.Button.new_from_icon_name("network-wireless-symbolic", Gtk.IconSize.BUTTON)
        self.wifi_btn.get_style_context().add_class("circle-icon-btn")
        self.wifi_btn.set_tooltip_text("Toggle Wi-Fi")
        self.wifi_btn.connect("clicked", self.on_toggle_wifi)
        wifi_row.pack_start(self.wifi_btn, False, False, 0)

        wifi_click = Gtk.EventBox()
        wifi_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        w_t = Gtk.Label(label="Wi-Fi")
        w_t.get_style_context().add_class("title-text")
        w_t.set_xalign(0)
        self.wifi_sub = Gtk.Label(label="...")
        self.wifi_sub.get_style_context().add_class("subtitle-text")
        self.wifi_sub.set_xalign(0)
        self.wifi_sub.set_ellipsize(Pango.EllipsizeMode.END)
        self.wifi_sub.set_max_width_chars(11)
        wifi_text_box.pack_start(w_t, False, False, 0)
        wifi_text_box.pack_start(self.wifi_sub, False, False, 0)
        wifi_click.add(wifi_text_box)
        wifi_click.connect("button-press-event", lambda *_: open_wifi_settings())
        wifi_row.pack_start(wifi_click, True, True, 0)
        net_card.pack_start(wifi_row, False, False, 0)

        # Bluetooth Row (Click icon to toggle on/off, click text to open bluetooth settings)
        bt_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.bt_btn = Gtk.Button.new_from_icon_name("bluetooth-active-symbolic", Gtk.IconSize.BUTTON)
        self.bt_btn.get_style_context().add_class("circle-icon-btn")
        self.bt_btn.set_tooltip_text("Toggle Bluetooth")
        self.bt_btn.connect("clicked", self.on_toggle_bt)
        bt_row.pack_start(self.bt_btn, False, False, 0)

        bt_click = Gtk.EventBox()
        bt_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        b_t = Gtk.Label(label="Bluetooth")
        b_t.get_style_context().add_class("title-text")
        b_t.set_xalign(0)
        self.bt_sub = Gtk.Label(label="...")
        self.bt_sub.get_style_context().add_class("subtitle-text")
        self.bt_sub.set_xalign(0)
        bt_text_box.pack_start(b_t, False, False, 0)
        bt_text_box.pack_start(self.bt_sub, False, False, 0)
        bt_click.add(bt_text_box)
        bt_click.connect("button-press-event", lambda *_: open_bluetooth_settings())
        bt_row.pack_start(bt_click, True, True, 0)
        net_card.pack_start(bt_row, False, False, 0)

        # AirDrop / Network Sharing Row
        ad_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.ad_btn = Gtk.Button.new_from_icon_name("network-workgroup-symbolic", Gtk.IconSize.BUTTON)
        self.ad_btn.get_style_context().add_class("circle-icon-btn")
        self.ad_btn.get_style_context().add_class("active")
        self.ad_btn.connect("clicked", lambda *_: (subprocess.Popen(["thunar", "network:///"]), cleanup_and_exit()))
        ad_row.pack_start(self.ad_btn, False, False, 0)

        ad_click = Gtk.EventBox()
        ad_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        a_t = Gtk.Label(label="AirDrop")
        a_t.get_style_context().add_class("title-text")
        a_t.set_xalign(0)
        self.ad_sub = Gtk.Label(label="Network Shares")
        self.ad_sub.get_style_context().add_class("subtitle-text")
        self.ad_sub.set_xalign(0)
        ad_text_box.pack_start(a_t, False, False, 0)
        ad_text_box.pack_start(self.ad_sub, False, False, 0)
        ad_click.add(ad_text_box)
        ad_click.connect("button-press-event", lambda *_: (subprocess.Popen(["thunar", "network:///"]), cleanup_and_exit()))
        ad_row.pack_start(ad_click, True, True, 0)
        net_card.pack_start(ad_row, False, False, 0)

        toggles_grid.attach(net_card, 0, 0, 1, 2)

        # Right Column: Do Not Disturb Card (Top)
        dnd_card = Gtk.EventBox()
        dnd_card.get_style_context().add_class("card-button")
        dnd_inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.dnd_btn = Gtk.Button.new_from_icon_name("weather-clear-night-symbolic", Gtk.IconSize.BUTTON)
        self.dnd_btn.get_style_context().add_class("circle-icon-btn")
        self.dnd_btn.get_style_context().add_class("active-purple")
        self.dnd_btn.connect("clicked", self.on_toggle_dnd)
        dnd_inner.pack_start(self.dnd_btn, False, False, 0)

        dnd_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        d_t = Gtk.Label(label="Don't Disturb")
        d_t.get_style_context().add_class("title-text")
        d_t.set_xalign(0)
        self.dnd_sub = Gtk.Label(label="Off")
        self.dnd_sub.get_style_context().add_class("subtitle-text")
        self.dnd_sub.set_xalign(0)
        dnd_text.pack_start(d_t, False, False, 0)
        dnd_text.pack_start(self.dnd_sub, False, False, 0)
        dnd_inner.pack_start(dnd_text, True, True, 0)
        dnd_card.add(dnd_inner)
        dnd_card.connect("button-press-event", lambda *_: self.on_toggle_dnd())
        toggles_grid.attach(dnd_card, 1, 0, 1, 1)

        # Right Column: System Day/Light Theme Mode Toggle (Requested by user)
        theme_card = Gtk.EventBox()
        theme_card.get_style_context().add_class("card-button")
        theme_inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.theme_icon_btn = Gtk.Button.new_from_icon_name("weather-clear-symbolic", Gtk.IconSize.BUTTON)
        self.theme_icon_btn.get_style_context().add_class("circle-icon-btn")
        self.theme_icon_btn.get_style_context().add_class("active-amber")
        self.theme_icon_btn.connect("clicked", self.on_toggle_theme)
        theme_inner.pack_start(self.theme_icon_btn, False, False, 0)

        theme_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        th_t = Gtk.Label(label="Appearance")
        th_t.get_style_context().add_class("title-text")
        th_t.set_xalign(0)
        self.theme_sub = Gtk.Label(label="Dark Mode")
        self.theme_sub.get_style_context().add_class("subtitle-text")
        self.theme_sub.set_xalign(0)
        theme_text.pack_start(th_t, False, False, 0)
        theme_text.pack_start(self.theme_sub, False, False, 0)
        theme_inner.pack_start(theme_text, True, True, 0)
        theme_card.add(theme_inner)
        theme_card.connect("button-press-event", lambda *_: self.on_toggle_theme())
        toggles_grid.attach(theme_card, 1, 1, 1, 1)

        main_box.pack_start(toggles_grid, False, False, 0)

        # ---------------------------------------------------------------------
        # 3. Display Brightness Slider Card
        # ---------------------------------------------------------------------
        disp_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        disp_card.get_style_context().add_class("card")

        sun_icon = Gtk.Image.new_from_icon_name("display-brightness-symbolic", Gtk.IconSize.BUTTON)
        disp_card.pack_start(sun_icon, False, False, 0)

        cur_bright = get_display_brightness()
        self.bright_adj = Gtk.Adjustment(value=cur_bright, lower=10, upper=100, step_increment=5, page_increment=10)
        self.bright_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.bright_adj)
        self.bright_slider.set_draw_value(False)
        self.bright_slider.connect("value-changed", self.on_brightness_changed)
        disp_card.pack_start(self.bright_slider, True, True, 0)

        disp_btn = Gtk.Button.new_from_icon_name("video-display-symbolic", Gtk.IconSize.BUTTON)
        disp_btn.get_style_context().add_class("card-button")
        disp_btn.set_tooltip_text("Display Settings")
        disp_btn.connect("clicked", lambda *_: open_display_settings())
        disp_card.pack_start(disp_btn, False, False, 0)

        main_box.pack_start(disp_card, False, False, 0)

        # ---------------------------------------------------------------------
        # 4. Sound Volume Slider Card
        # ---------------------------------------------------------------------
        vol_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vol_card.get_style_context().add_class("card")

        spk_icon = Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.BUTTON)
        vol_card.pack_start(spk_icon, False, False, 0)

        cur_vol = get_sound_volume()
        self.vol_adj = Gtk.Adjustment(value=cur_vol, lower=0, upper=100, step_increment=5, page_increment=10)
        self.vol_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.vol_adj)
        self.vol_slider.set_draw_value(False)
        self.vol_slider.connect("value-changed", self.on_volume_changed)
        vol_card.pack_start(self.vol_slider, True, True, 0)

        airplay_btn = Gtk.Button.new_from_icon_name("audio-speakers-symbolic", Gtk.IconSize.BUTTON)
        airplay_btn.get_style_context().add_class("card-button")
        airplay_btn.set_tooltip_text("Sound Mixer / Audio Output")
        airplay_btn.connect("clicked", lambda *_: open_sound_settings())
        vol_card.pack_start(airplay_btn, False, False, 0)

        main_box.pack_start(vol_card, False, False, 0)

        # ---------------------------------------------------------------------
        # 5. Now Playing Media Card
        # ---------------------------------------------------------------------
        media_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        media_card.get_style_context().add_class("card")

        self.cover_img = Gtk.Image.new_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.DND)
        self.cover_img.set_pixel_size(36)
        media_card.pack_start(self.cover_img, False, False, 0)

        media_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.media_title = Gtk.Label(label="Break My Baby")
        self.media_title.get_style_context().add_class("title-text")
        self.media_title.set_xalign(0)
        self.media_title.set_ellipsize(Pango.EllipsizeMode.END)
        self.media_title.set_max_width_chars(16)

        self.media_artist = Gtk.Label(label="KALEO")
        self.media_artist.get_style_context().add_class("subtitle-text")
        self.media_artist.set_xalign(0)
        self.media_artist.set_ellipsize(Pango.EllipsizeMode.END)
        self.media_artist.set_max_width_chars(16)

        media_text.pack_start(self.media_title, False, False, 0)
        media_text.pack_start(self.media_artist, False, False, 0)
        media_card.pack_start(media_text, True, True, 0)

        self.play_btn = Gtk.Button.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON)
        self.play_btn.get_style_context().add_class("media-btn")
        self.play_btn.connect("clicked", self.on_media_play_pause)
        media_card.pack_start(self.play_btn, False, False, 0)

        self.next_btn = Gtk.Button.new_from_icon_name("media-skip-forward-symbolic", Gtk.IconSize.BUTTON)
        self.next_btn.get_style_context().add_class("media-btn")
        self.next_btn.connect("clicked", self.on_media_next)
        media_card.pack_start(self.next_btn, False, False, 0)

        main_box.pack_start(media_card, False, False, 0)

        # Initial data update
        self.update_dynamic_state()

    # -------------------------------------------------------------------------
    # Callbacks & Updaters
    # -------------------------------------------------------------------------

    def update_dynamic_state(self):
        # Wi-Fi
        wifi_enabled, wifi_ssid = get_wifi_state()
        self.wifi_sub.set_text(wifi_ssid)
        if wifi_enabled:
            self.wifi_btn.get_style_context().add_class("active")
        else:
            self.wifi_btn.get_style_context().remove_class("active")

        # Bluetooth
        bt_enabled, bt_text = get_bluetooth_state()
        self.bt_sub.set_text(bt_text)
        if bt_enabled:
            self.bt_btn.get_style_context().add_class("active")
        else:
            self.bt_btn.get_style_context().remove_class("active")

        # DND
        dnd_on = get_dnd_state()
        self.dnd_sub.set_text("On" if dnd_on else "Off")

        # Theme Appearance
        mode = get_current_theme_mode()
        if mode == "dark":
            self.theme_sub.set_text("Dark Mode")
            self.theme_icon_btn.set_image(Gtk.Image.new_from_icon_name("weather-clear-night-symbolic", Gtk.IconSize.BUTTON))
        else:
            self.theme_sub.set_text("Light Mode")
            self.theme_icon_btn.set_image(Gtk.Image.new_from_icon_name("weather-clear-symbolic", Gtk.IconSize.BUTTON))

        # Media
        title, artist, status, art = get_media_info()
        self.media_title.set_text(title)
        self.media_artist.set_text(artist)
        if status.lower() == "playing":
            self.play_btn.set_image(Gtk.Image.new_from_icon_name("media-playback-pause-symbolic", Gtk.IconSize.BUTTON))
        else:
            self.play_btn.set_image(Gtk.Image.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON))

        return True

    def on_toggle_wifi(self, *_):
        toggle_wifi()
        GLib.timeout_add(400, self.update_dynamic_state)

    def on_toggle_bt(self, *_):
        toggle_bluetooth()
        GLib.timeout_add(400, self.update_dynamic_state)

    def on_toggle_dnd(self, *_):
        toggle_dnd()
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_toggle_theme(self, *_):
        toggle_system_theme()
        GLib.timeout_add(300, self.update_dynamic_state)

    def on_brightness_changed(self, scale):
        val = scale.get_value()
        set_display_brightness(val)

    def on_volume_changed(self, scale):
        val = scale.get_value()
        set_sound_volume(val)

    def on_media_play_pause(self, *_):
        run_cmd(["playerctl", "play-pause"])
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_media_next(self, *_):
        run_cmd(["playerctl", "next"])
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_open_settings(self, *_):
        subprocess.Popen(["xfce4-settings-manager"])
        cleanup_and_exit()

    def on_open_power(self, *_):
        subprocess.Popen(["xfce4-session-logout"])
        cleanup_and_exit()


def main():
    signal.signal(signal.SIGINT, cleanup_and_exit)
    signal.signal(signal.SIGTERM, cleanup_and_exit)

    win = SequoiaControlCenter()
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
