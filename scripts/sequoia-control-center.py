#!/usr/bin/env python3
"""
macOS Sequoia Native Control Center Popover for Linux Mint XFCE
Matches Apple macOS Control Center layout and functionality:
- Profile header with user avatar, name, settings, and power buttons
- Quick toggle grid: Wi-Fi (toggle & network picker), Network Shares (thunar network:///)
- Right utility grid: Do Not Disturb card + Day/Night Appearance mode switcher + Display settings
- Live interactive Display Brightness slider (xrandr / brightnessctl)
- Live interactive Sound Volume slider (pactl / PulseAudio) + Mixer launcher
- Live Now Playing media card (native D-Bus MPRIS with fallback to playerctl)
- Full Day/Night mode styling coordination (Dark Obsidian Glass vs Light Frosted Crystal)
- Auto-dismiss on click outside (focus-out), 30s inactivity, or Escape key
- Process terminates cleanly within 2 seconds of close/hide
- Scoped PID management and watchdog compatibility (~/.cache/sequoia/control-center.pid)
- Internal feature gate checking ~/.config/sequoia/features.json (bypassed with --trial)
"""

import json
import os
import pwd
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import Gtk, Gdk, GLib, GdkPixbuf, Pango, Gio
except ImportError as e:
    sys.stderr.write(f"GTK3/PyGObject not available: {e}\n")
    sys.exit(1)


_current_app = None
PID_FILE = os.path.expanduser("~/.cache/sequoia/control-center.pid")
FEATURES_FILE = os.path.expanduser("~/.config/sequoia/features.json")


def is_feature_enabled() -> bool:
    """Checks if control_center is enabled in ~/.config/sequoia/features.json."""
    if not os.path.exists(FEATURES_FILE):
        return False
    try:
        with open(FEATURES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return bool(data.get("control_center", False))
    except Exception:
        return False


def write_pid_file():
    """Writes current PID to ~/.cache/sequoia/control-center.pid."""
    try:
        os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
        with open(PID_FILE, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass


def remove_pid_file():
    """Removes PID file if it matches current process PID."""
    try:
        if os.path.exists(PID_FILE):
            with open(PID_FILE, "r", encoding="utf-8") as f:
                content = f.read().strip()
            if content == str(os.getpid()):
                os.remove(PID_FILE)
    except OSError:
        pass


def dismiss_popover():
    global _current_app
    if _current_app:
        _current_app.hide_window()


def cleanup_and_exit(*_args):
    global _current_app
    if _current_app:
        _current_app.quit_app()
    else:
        remove_pid_file()
        sys.exit(0)


# -----------------------------------------------------------------------------
# System Helpers (Worker Threads & 5s Timeouts)
# -----------------------------------------------------------------------------

def run_cmd(args, timeout=5.0):
    """Executes external command with hard timeout; returns stdout stripped."""
    try:
        res = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=timeout,
        )
        return res.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return ""
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
    status = run_cmd(["nmcli", "-t", "-f", "WIFI", "g"], timeout=3.0)
    enabled = (status.lower() == "enabled")
    ssid = "Not Connected"
    if enabled:
        out = run_cmd(["nmcli", "-t", "-f", "NAME,TYPE", "c", "show", "--active"], timeout=3.0)
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and "wireless" in parts[1].lower():
                ssid = parts[0]
                break
        if ssid == "Not Connected":
            ssid_out = run_cmd(["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"], timeout=3.0)
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
    run_cmd(["nmcli", "radio", "wifi", new_state], timeout=4.0)


def get_wifi_network_list():
    out = run_cmd(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"], timeout=5.0)
    networks = []
    seen = set()
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 4:
            in_use = (parts[0].strip() == "*")
            ssid = parts[1].strip()
            signal = parts[2].strip()
            sec = parts[3].strip()
            if ssid and ssid not in seen:
                seen.add(ssid)
                networks.append({"ssid": ssid, "signal": signal, "sec": sec, "active": in_use})
    return networks


def connect_to_wifi(ssid):
    if not ssid:
        return

    def _do_connect():
        try:
            res = subprocess.run(
                ["nmcli", "dev", "wifi", "connect", ssid],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5.0,
            )
            if res.returncode != 0 and ("Secrets were required" in res.stderr or "password" in res.stderr.lower()):
                zenity = shutil.which("zenity")
                if zenity:
                    pw_res = subprocess.run(
                        [zenity, "--password", f"--title=Wi-Fi Password: {ssid}"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        text=True,
                        timeout=5.0,
                    )
                    password = pw_res.stdout.strip()
                    if password:
                        subprocess.run(
                            ["nmcli", "dev", "wifi", "connect", ssid, "password", password],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=5.0,
                        )
            elif res.returncode == 0:
                if shutil.which("notify-send"):
                    subprocess.run(
                        ["notify-send", "Wi-Fi Connected", f"Connected to {ssid}", "-i", "network-wireless-symbolic"],
                        timeout=3.0,
                    )
        except Exception:
            pass

    threading.Thread(target=_do_connect, daemon=True).start()


def open_wifi_settings():
    for cmd in [["nm-connection-editor"], ["xfce4-terminal", "-e", "nmtui"], ["gnome-control-center", "wifi"]]:
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd)
            dismiss_popover()
            return


def get_dnd_state():
    out = run_cmd(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb"], timeout=3.0)
    return out.lower() == "true"


def toggle_dnd():
    run_cmd(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb", "-T"], timeout=3.0)


def get_current_theme_mode():
    out = run_cmd(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName"], timeout=3.0)
    return "dark" if "dark" in out.lower() else "light"


def toggle_system_theme():
    script_candidates = [
        os.path.expanduser("~/.local/bin/toggle-theme.sh"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "toggle-theme.sh"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "toggle-theme.sh"),
    ]
    for s in script_candidates:
        if os.path.isfile(s):
            subprocess.run(["bash", s, "toggle"], timeout=5.0)
            return


def get_sound_volume():
    out = run_cmd(["pactl", "get-sink-volume", "@DEFAULT_SINK@"], timeout=2.0)
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
            dismiss_popover()
            return


def get_primary_display():
    out = run_cmd(["xrandr", "--query"], timeout=3.0)
    for line in out.splitlines():
        if " connected" in line:
            return line.split()[0]
    return "HDMI-1"


def get_display_brightness():
    disp = get_primary_display()
    out = run_cmd(["xrandr", "--verbose"], timeout=3.0)
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
            dismiss_popover()
            return


# -----------------------------------------------------------------------------
# MPRIS via D-Bus with Fallback
# -----------------------------------------------------------------------------

def get_media_info():
    """Queries media player information via D-Bus MPRIS; falls back to playerctl."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        res = bus.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "ListNames",
            None,
            GLib.VariantType("(as)"),
            Gio.DBusCallFlags.NONE,
            500,
            None,
        )
        names = res.get_child_value(0).unpack()
        mpris_names = [n for n in names if n.startswith("org.mpris.MediaPlayer2.")]
        if mpris_names:
            proxy = Gio.DBusProxy.new_sync(
                bus,
                Gio.DBusProxyFlags.NONE,
                None,
                mpris_names[0],
                "/org/mpris/MediaPlayer2",
                "org.mpris.MediaPlayer2.Player",
                None,
            )
            status_var = proxy.get_cached_property("PlaybackStatus")
            status = status_var.unpack() if status_var else "Stopped"
            meta_var = proxy.get_cached_property("Metadata")
            meta = meta_var.unpack() if meta_var else {}
            title = meta.get("xesam:title", "Unknown Title")
            artist_val = meta.get("xesam:artist", ["Unknown Artist"])
            artist = artist_val[0] if isinstance(artist_val, (list, tuple)) and artist_val else str(artist_val)
            art = meta.get("mpris:artUrl", "")
            return str(title), str(artist), str(status), str(art)
    except Exception:
        pass

    # Fallback to playerctl
    out = run_cmd(["playerctl", "metadata", "--format", "{{title}}|{{artist}}|{{status}}|{{mpris:artUrl}}"], timeout=2.0)
    if not out or "|" not in out:
        return "No media playing", "Music", "Stopped", ""
    parts = out.split("|")
    title = parts[0] if len(parts) > 0 and parts[0] else "Unknown Title"
    artist = parts[1] if len(parts) > 1 and parts[1] else "Unknown Artist"
    status = parts[2] if len(parts) > 2 and parts[2] else "Stopped"
    art = parts[3] if len(parts) > 3 else ""
    return title, artist, status, art


def media_play_pause():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        res = bus.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "ListNames",
            None,
            GLib.VariantType("(as)"),
            Gio.DBusCallFlags.NONE,
            500,
            None,
        )
        names = [n for n in res.get_child_value(0).unpack() if n.startswith("org.mpris.MediaPlayer2.")]
        if names:
            proxy = Gio.DBusProxy.new_sync(
                bus, Gio.DBusProxyFlags.NONE, None, names[0],
                "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", None
            )
            proxy.call_sync("PlayPause", None, Gio.DBusCallFlags.NONE, 500, None)
            return
    except Exception:
        pass
    run_cmd(["playerctl", "play-pause"], timeout=2.0)


def media_next():
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        res = bus.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "ListNames",
            None,
            GLib.VariantType("(as)"),
            Gio.DBusCallFlags.NONE,
            500,
            None,
        )
        names = [n for n in res.get_child_value(0).unpack() if n.startswith("org.mpris.MediaPlayer2.")]
        if names:
            proxy = Gio.DBusProxy.new_sync(
                bus, Gio.DBusProxyFlags.NONE, None, names[0],
                "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", None
            )
            proxy.call_sync("Next", None, Gio.DBusCallFlags.NONE, 500, None)
            return
    except Exception:
        pass
    run_cmd(["playerctl", "next"], timeout=2.0)


# -----------------------------------------------------------------------------
# Dynamic CSS (Dark & Light Mode with Smooth Transitions)
# -----------------------------------------------------------------------------

SAFE_FALLBACK_CSS = """
* {
    color: #ffffff;
}

window.control-center-window {
    background-color: transparent;
}

.main-card {
    background-color: rgba(28, 28, 30, 0.96);
    border: 1px solid rgba(255, 255, 255, 0.20);
    border-radius: 18px;
    padding: 10px;
}

.card {
    background-color: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.10);
    border-radius: 12px;
    padding: 8px;
}

.card-button {
    background-color: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.10);
    border-radius: 12px;
    padding: 6px;
}

.circle-icon-btn {
    border-radius: 50%;
    min-width: 28px;
    min-height: 28px;
    background-color: rgba(255, 255, 255, 0.15);
    color: #ffffff;
    border: none;
}

.title-text {
    font-size: 11px;
    font-weight: bold;
    color: #ffffff;
}

.subtitle-text {
    font-size: 10px;
    color: rgba(255, 255, 255, 0.70);
}
"""


def load_css_safely(provider, css_string):
    """
    Loads CSS data into a Gtk.CssProvider safely:
    - Traps parsing-error signals and GLib.GError exceptions.
    - Falls back to SAFE_FALLBACK_CSS if loading fails.
    """
    error_occurred = [False]

    def _on_parsing_error(prov, section, err):
        error_occurred[0] = True
        try:
            start_line = section.get_start_line() + 1
            start_col = section.get_start_position() + 1
        except Exception:
            start_line = "?"
            start_col = "?"
        sys.stderr.write(f"[CSS ERROR] Parsing error at line {start_line}, column {start_col}: {err.message}\n")
        sys.stderr.flush()

    handler_id = None
    try:
        handler_id = provider.connect("parsing-error", _on_parsing_error)
    except Exception:
        pass

    try:
        provider.load_from_data(css_string.encode("utf-8"))
        if error_occurred[0]:
            provider.load_from_data(SAFE_FALLBACK_CSS.encode("utf-8"))
            return False
        return True
    except GLib.GError:
        try:
            provider.load_from_data(SAFE_FALLBACK_CSS.encode("utf-8"))
        except Exception:
            pass
        return False
    finally:
        if handler_id is not None:
            try:
                provider.disconnect(handler_id)
            except Exception:
                pass


def build_css(theme_mode):
    is_dark = (theme_mode == "dark")
    bg_window = "rgba(24, 25, 28, 0.92)" if is_dark else "rgba(245, 245, 248, 0.94)"
    border_window = "rgba(255, 255, 255, 0.14)" if is_dark else "rgba(0, 0, 0, 0.10)"
    bg_card = "rgba(255, 255, 255, 0.08)" if is_dark else "rgba(0, 0, 0, 0.05)"
    bg_card_hover = "rgba(255, 255, 255, 0.14)" if is_dark else "rgba(0, 0, 0, 0.09)"
    btn_hover = "rgba(255, 255, 255, 0.22)" if is_dark else "rgba(0, 0, 0, 0.14)"
    border_card = "rgba(255, 255, 255, 0.07)" if is_dark else "rgba(0, 0, 0, 0.06)"
    text_main = "#ffffff" if is_dark else "#1e293b"
    text_sub = "rgba(255, 255, 255, 0.65)" if is_dark else "rgba(30, 41, 59, 0.65)"
    scale_trough = "rgba(255, 255, 255, 0.18)" if is_dark else "rgba(0, 0, 0, 0.12)"
    scale_fill = "#ffffff" if is_dark else "#007aff"
    scale_slider = "#ffffff"

    return f"""
* {{
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Ubuntu", "Inter", sans-serif;
    color: {text_main};
}}

window.control-center-window {{
    background-color: transparent;
}}

.main-card {{
    background-color: {bg_window};
    border: 1px solid {border_window};
    border-radius: 22px;
    padding: 10px;
}}

.card {{
    background-color: {bg_card};
    border: 1px solid {border_card};
    border-radius: 14px;
    padding: 8px 10px;
    transition: background-color 150ms ease-in-out;
}}

.card-button {{
    background-color: {bg_card};
    border: 1px solid {border_card};
    border-radius: 14px;
    padding: 6px 8px;
    transition: background-color 150ms ease-in-out;
}}

.card-button:hover {{
    background-color: {bg_card_hover};
}}

.circle-icon-btn {{
    border-radius: 50%;
    min-width: 28px;
    min-height: 28px;
    padding: 0;
    background-color: {bg_card_hover};
    color: {text_main};
    border: none;
    transition: background-color 150ms ease-in-out, color 150ms ease-in-out;
}}

.circle-icon-btn:hover {{
    background-color: {btn_hover};
}}

.circle-icon-btn.active {{
    background-color: #0a84ff;
    color: #ffffff;
}}

.circle-icon-btn.active-purple {{
    background-color: #bf5af2;
    color: #ffffff;
}}

.circle-icon-btn.active-amber {{
    background-color: #ff9f0a;
    color: #ffffff;
}}

.title-text {{
    font-size: 11px;
    font-weight: 600;
    color: {text_main};
}}

.subtitle-text {{
    font-size: 10px;
    color: {text_sub};
}}

.header-name {{
    font-size: 12px;
    font-weight: 700;
    color: {text_main};
}}

scale trough {{
    background-color: {scale_trough};
    border-radius: 14px;
    min-height: 22px;
    border: none;
    transition: background-color 180ms ease-in-out;
}}

scale highlight {{
    background-color: {scale_fill};
    border-radius: 14px;
    min-height: 22px;
}}

scale slider {{
    background-color: {scale_slider};
    border-radius: 50%;
    min-width: 20px;
    min-height: 20px;
    margin: -1px;
    border: 1px solid rgba(0, 0, 0, 0.15);
    box-shadow: 0 2px 5px rgba(0, 0, 0, 0.25);
}}

.media-btn {{
    background-color: transparent;
    border: none;
    padding: 4px;
    min-width: 24px;
    transition: color 150ms ease-in-out;
}}

.media-btn:hover {{
    color: #0a84ff;
}}

.wifi-list-card {{
    background-color: {bg_card};
    border: 1px solid {border_card};
    border-radius: 14px;
    padding: 8px 10px;
    margin-top: 2px;
}}

.wifi-item-btn {{
    background-color: transparent;
    border: none;
    border-radius: 8px;
    padding: 6px 8px;
    transition: background-color 150ms ease-in-out;
}}

.wifi-item-btn:hover {{
    background-color: {bg_card_hover};
}}

.wifi-item-btn.active {{
    background-color: rgba(10, 132, 255, 0.22);
}}
"""


class SequoiaControlCenter(Gtk.Window):
    def __init__(self, app=None):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.app = app
        if app is not None:
            self.set_application(app)
        self.set_title("Control Center")
        self.set_role("popover")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_app_paintable(True)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        self.get_style_context().add_class("control-center-window")

        # Load dynamic CSS
        self.current_theme = get_current_theme_mode()
        self.css_provider = Gtk.CssProvider()
        self.apply_theme_css()
        Gtk.StyleContext.add_provider_for_screen(
            screen, self.css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self._poll_timer_id = None
        self._inactivity_timer_id = None

        self.build_ui()

        # Connect window events
        self.connect("delete-event", self.on_delete_event)
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("map-event", self.on_map_event)
        self.connect("unmap-event", self.on_unmap_event)

        # Inactivity resets on user input
        self.add_events(Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.connect("motion-notify-event", lambda *_: self.reset_inactivity())
        self.connect("button-press-event", lambda *_: self.reset_inactivity())

        self.position_window()

    def apply_theme_css(self):
        css_data = build_css(self.current_theme)
        load_css_safely(self.css_provider, css_data)

    def position_window(self):
        screen = self.get_screen()
        screen_w = screen.get_width()
        win_w = 356
        self.set_size_request(win_w, -1)
        pos_x = max(0, screen_w - win_w - 12)
        pos_y = 34
        self.move(pos_x, pos_y)

    def on_map_event(self, *_):
        self._map_time = time.time()
        self.position_window()
        self.start_polling()
        self.reset_inactivity()
        self.present()
        self.grab_focus()
        self._record_status(mapped=True, reason="open")

    def on_unmap_event(self, *_):
        self.stop_polling()
        self.stop_inactivity()

    def on_delete_event(self, _widget, _event):
        self.hide_to_dismiss(reason="window-close")
        return True

    def on_focus_out(self, _widget, _event):
        elapsed = time.time() - getattr(self, "_map_time", 0)
        if elapsed < 0.35:
            # Ignore transient focus loss in first 350ms during map/grab setup
            return False
        self.hide_to_dismiss(reason="focus-out")
        return False

    def on_key_press(self, _widget, event):
        self.reset_inactivity()
        if event.keyval == Gdk.KEY_Escape:
            self.hide_to_dismiss(reason="Escape")
            return True
        return False

    def hide_to_dismiss(self, reason="idle"):
        self._record_status(mapped=False, reason=reason)
        if self.app:
            self.app.hide_window()
        else:
            self.hide()

    def _record_status(self, mapped: bool, reason: str):
        try:
            status_file = os.path.expanduser("~/.cache/sequoia/control-center-status.json")
            os.makedirs(os.path.dirname(status_file), exist_ok=True)
            screen = self.get_screen()
            screen_w = screen.get_width()
            pos_x, pos_y = self.get_position()
            size_w, size_h = self.get_size()
            open_dur = 0.0
            if hasattr(self, "_map_time"):
                open_dur = round(time.time() - self._map_time, 2)
            data = {
                "pid": os.getpid(),
                "mapped": mapped,
                "reason": reason,
                "time_open_sec": open_dur,
                "x": pos_x,
                "y": pos_y,
                "w": size_w,
                "h": size_h,
                "top_bar_gap": pos_y - 28,
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
            with open(status_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def reset_inactivity(self):
        """Resets the 30-second inactivity auto-close timer."""
        self.stop_inactivity()
        self._inactivity_timer_id = GLib.timeout_add_seconds(30, self._on_inactivity_timeout)

    def stop_inactivity(self):
        if self._inactivity_timer_id is not None:
            GLib.source_remove(self._inactivity_timer_id)
            self._inactivity_timer_id = None

    def _on_inactivity_timeout(self):
        self._inactivity_timer_id = None
        self.hide_to_dismiss(reason="inactivity")
        return False

    def start_polling(self):
        """Starts dynamic state updates; zero polling while hidden."""
        if self._poll_timer_id is None:
            self.update_dynamic_state()
            self._poll_timer_id = GLib.timeout_add(1500, self._poll_callback)

    def stop_polling(self):
        """Stops all background polling timers."""
        if self._poll_timer_id is not None:
            GLib.source_remove(self._poll_timer_id)
            self._poll_timer_id = None

    def _poll_callback(self):
        if not self.get_visible():
            self._poll_timer_id = None
            return False
        self.update_dynamic_state()
        return True

    def build_ui(self):
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        main_box.get_style_context().add_class("main-card")
        self.add(main_box)

        # ---------------------------------------------------------------------
        # 1. Profile / Header Card
        # ---------------------------------------------------------------------
        header_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header_card.get_style_context().add_class("card")

        avatar = Gtk.Image.new_from_icon_name("avatar-default-symbolic", Gtk.IconSize.DND)
        avatar.set_pixel_size(26)
        header_card.pack_start(avatar, False, False, 0)

        user_name = get_current_user_info()
        name_btn = Gtk.Button(label=user_name)
        name_btn.get_style_context().add_class("card-button")
        name_btn.connect("clicked", lambda *_: (subprocess.Popen(["xfce4-settings-manager"]), self.hide_to_dismiss()))
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

        close_btn = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
        close_btn.get_style_context().add_class("circle-icon-btn")
        close_btn.set_tooltip_text("Close (Esc)")
        close_btn.connect("clicked", lambda *_: self.hide_to_dismiss())
        header_card.pack_start(close_btn, False, False, 0)

        main_box.pack_start(header_card, False, False, 0)

        # ---------------------------------------------------------------------
        # 2. Quick Toggles Grid (Left: Wi-Fi, Network Shares / Right: DND, Theme, Display)
        # ---------------------------------------------------------------------
        toggles_grid = Gtk.Grid()
        toggles_grid.set_column_spacing(8)
        toggles_grid.set_row_spacing(8)
        toggles_grid.set_column_homogeneous(True)

        # Left Column: Network Toggles Card
        net_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        net_card.get_style_context().add_class("card")

        # Wi-Fi Row
        wifi_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.wifi_btn = Gtk.Button.new_from_icon_name("network-wireless-symbolic", Gtk.IconSize.BUTTON)
        self.wifi_btn.get_style_context().add_class("circle-icon-btn")
        self.wifi_btn.set_tooltip_text("Toggle Wi-Fi")
        self.wifi_btn.connect("clicked", self.on_toggle_wifi)
        wifi_row.pack_start(self.wifi_btn, False, False, 0)

        wifi_click = Gtk.EventBox()
        wifi_click.set_tooltip_text("Available Networks")
        wifi_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        w_t = Gtk.Label(label="Wi-Fi")
        w_t.get_style_context().add_class("title-text")
        w_t.set_xalign(0)
        self.wifi_sub = Gtk.Label(label="...")
        self.wifi_sub.get_style_context().add_class("subtitle-text")
        self.wifi_sub.set_xalign(0)
        self.wifi_sub.set_ellipsize(Pango.EllipsizeMode.END)
        self.wifi_sub.set_max_width_chars(12)
        wifi_text_box.pack_start(w_t, False, False, 0)
        wifi_text_box.pack_start(self.wifi_sub, False, False, 0)
        wifi_click.add(wifi_text_box)
        wifi_click.connect("button-press-event", lambda *_: self.on_toggle_wifi_details())
        wifi_row.pack_start(wifi_click, True, True, 0)

        wifi_chev = Gtk.Image.new_from_icon_name("pan-end-symbolic", Gtk.IconSize.BUTTON)
        wifi_chev.set_pixel_size(10)
        wifi_row.pack_end(wifi_chev, False, False, 0)
        net_card.pack_start(wifi_row, False, False, 0)

        # Network Shares Row (Renamed AirDrop replacement, Desktop-friendly)
        shares_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.shares_btn = Gtk.Button.new_from_icon_name("network-workgroup-symbolic", Gtk.IconSize.BUTTON)
        self.shares_btn.get_style_context().add_class("circle-icon-btn")
        self.shares_btn.get_style_context().add_class("active")
        self.shares_btn.connect("clicked", lambda *_: (subprocess.Popen(["thunar", "network:///"]), self.hide_to_dismiss()))
        shares_row.pack_start(self.shares_btn, False, False, 0)

        shares_click = Gtk.EventBox()
        shares_text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        s_t = Gtk.Label(label="Network Shares")
        s_t.get_style_context().add_class("title-text")
        s_t.set_xalign(0)
        self.shares_sub = Gtk.Label(label="Local Network")
        self.shares_sub.get_style_context().add_class("subtitle-text")
        self.shares_sub.set_xalign(0)
        shares_text_box.pack_start(s_t, False, False, 0)
        shares_text_box.pack_start(self.shares_sub, False, False, 0)
        shares_click.add(shares_text_box)
        shares_click.connect("button-press-event", lambda *_: (subprocess.Popen(["thunar", "network:///"]), self.hide_to_dismiss()))
        shares_row.pack_start(shares_click, True, True, 0)
        net_card.pack_start(shares_row, False, False, 0)

        toggles_grid.attach(net_card, 0, 0, 1, 2)

        # Right Column: Do Not Disturb Card (Top)
        dnd_card = Gtk.EventBox()
        dnd_card.get_style_context().add_class("card-button")
        dnd_inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.dnd_btn = Gtk.Button.new_from_icon_name("weather-clear-night-symbolic", Gtk.IconSize.BUTTON)
        self.dnd_btn.get_style_context().add_class("circle-icon-btn")
        self.dnd_btn.get_style_context().add_class("active-purple")
        self.dnd_btn.connect("clicked", self.on_toggle_dnd)
        dnd_inner.pack_start(self.dnd_btn, False, False, 0)

        dnd_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        d_t = Gtk.Label(label="Don't Disturb")
        d_t.get_style_context().add_class("title-text")
        d_t.set_xalign(0)
        d_t.set_ellipsize(Pango.EllipsizeMode.END)
        self.dnd_sub = Gtk.Label(label="Off")
        self.dnd_sub.get_style_context().add_class("subtitle-text")
        self.dnd_sub.set_xalign(0)
        dnd_text.pack_start(d_t, False, False, 0)
        dnd_text.pack_start(self.dnd_sub, False, False, 0)
        dnd_inner.pack_start(dnd_text, True, True, 0)
        dnd_card.add(dnd_inner)
        dnd_card.connect("button-press-event", lambda *_: self.on_toggle_dnd())
        toggles_grid.attach(dnd_card, 1, 0, 1, 1)

        # Right Column: Bottom Split Row (Appearance Day/Night + Display Settings)
        util_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        # Appearance (Day/Night Theme Mode Switcher)
        theme_card = Gtk.EventBox()
        theme_card.get_style_context().add_class("card-button")
        theme_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        theme_inner.set_halign(Gtk.Align.CENTER)
        self.theme_icon_btn = Gtk.Button.new_from_icon_name("weather-clear-symbolic", Gtk.IconSize.BUTTON)
        self.theme_icon_btn.get_style_context().add_class("circle-icon-btn")
        self.theme_icon_btn.get_style_context().add_class("active-amber")
        self.theme_icon_btn.connect("clicked", self.on_toggle_theme)
        theme_inner.pack_start(self.theme_icon_btn, False, False, 0)

        self.theme_lbl = Gtk.Label(label="Appearance")
        self.theme_lbl.get_style_context().add_class("subtitle-text")
        theme_inner.pack_start(self.theme_lbl, False, False, 0)
        theme_card.add(theme_inner)
        theme_card.connect("button-press-event", lambda *_: self.on_toggle_theme())
        util_box.pack_start(theme_card, True, True, 0)

        # Display Settings
        disp_box = Gtk.EventBox()
        disp_box.get_style_context().add_class("card-button")
        disp_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        disp_inner.set_halign(Gtk.Align.CENTER)
        disp_icon = Gtk.Image.new_from_icon_name("video-display-symbolic", Gtk.IconSize.BUTTON)
        disp_icon.set_pixel_size(24)
        disp_inner.pack_start(disp_icon, False, False, 2)
        disp_lbl = Gtk.Label(label="Display")
        disp_lbl.get_style_context().add_class("subtitle-text")
        disp_inner.pack_start(disp_lbl, False, False, 0)
        disp_box.add(disp_inner)
        disp_box.connect("button-press-event", lambda *_: open_display_settings())
        util_box.pack_start(disp_box, True, True, 0)

        toggles_grid.attach(util_box, 1, 1, 1, 1)
        main_box.pack_start(toggles_grid, False, False, 0)

        # Wi-Fi Networks Revealer Drawer (macOS inline expansion)
        self.wifi_revealer = Gtk.Revealer()
        self.wifi_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.wifi_revealer.set_transition_duration(200)

        wifi_drawer_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        wifi_drawer_box.get_style_context().add_class("wifi-list-card")

        drawer_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        dh_lbl = Gtk.Label(label="Wi-Fi Networks")
        dh_lbl.get_style_context().add_class("title-text")
        dh_lbl.set_xalign(0)
        drawer_header.pack_start(dh_lbl, True, True, 0)

        self.wifi_ref_btn = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)
        self.wifi_ref_btn.get_style_context().add_class("circle-icon-btn")
        self.wifi_ref_btn.set_tooltip_text("Refresh Networks")
        self.wifi_ref_btn.connect("clicked", self.refresh_wifi_networks)
        drawer_header.pack_start(self.wifi_ref_btn, False, False, 0)
        wifi_drawer_box.pack_start(drawer_header, False, False, 2)

        self.wifi_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        wifi_drawer_box.pack_start(self.wifi_list_box, True, True, 0)

        self.wifi_revealer.add(wifi_drawer_box)
        main_box.pack_start(self.wifi_revealer, False, False, 0)

        # ---------------------------------------------------------------------
        # 3. Display Brightness Slider Card
        # ---------------------------------------------------------------------
        disp_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        disp_card.get_style_context().add_class("card")

        sun_icon = Gtk.Image.new_from_icon_name("display-brightness-symbolic", Gtk.IconSize.BUTTON)
        disp_card.pack_start(sun_icon, False, False, 0)

        cur_bright = get_display_brightness()
        self.bright_adj = Gtk.Adjustment(float(cur_bright), 10.0, 100.0, 5.0, 10.0, 0.0)
        self.bright_slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.bright_adj)
        self.bright_slider.set_draw_value(False)
        self.bright_slider.connect("value-changed", self.on_brightness_changed)
        disp_card.pack_start(self.bright_slider, True, True, 0)

        main_box.pack_start(disp_card, False, False, 0)

        # ---------------------------------------------------------------------
        # 4. Sound Volume Slider Card
        # ---------------------------------------------------------------------
        vol_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vol_card.get_style_context().add_class("card")

        spk_icon = Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.BUTTON)
        vol_card.pack_start(spk_icon, False, False, 0)

        cur_vol = get_sound_volume()
        self.vol_adj = Gtk.Adjustment(float(cur_vol), 0.0, 100.0, 5.0, 10.0, 0.0)
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
        media_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        media_card.get_style_context().add_class("card")

        self.cover_img = Gtk.Image.new_from_icon_name("audio-x-generic-symbolic", Gtk.IconSize.DND)
        self.cover_img.set_pixel_size(34)
        media_card.pack_start(self.cover_img, False, False, 0)

        media_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        self.media_title = Gtk.Label(label="No media playing")
        self.media_title.get_style_context().add_class("title-text")
        self.media_title.set_xalign(0)
        self.media_title.set_ellipsize(Pango.EllipsizeMode.END)
        self.media_title.set_max_width_chars(16)

        self.media_artist = Gtk.Label(label="Music")
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

    def update_dynamic_state(self):
        # Wi-Fi
        wifi_enabled, wifi_ssid = get_wifi_state()
        self.wifi_sub.set_text(wifi_ssid)
        if wifi_enabled:
            self.wifi_btn.get_style_context().add_class("active")
        else:
            self.wifi_btn.get_style_context().remove_class("active")

        # DND
        dnd_on = get_dnd_state()
        self.dnd_sub.set_text("On" if dnd_on else "Off")

        # Theme Appearance & Reactive Styling
        mode = get_current_theme_mode()
        if mode != self.current_theme:
            self.current_theme = mode
            self.apply_theme_css()

        if mode == "dark":
            self.theme_lbl.set_text("Dark Mode")
            self.theme_icon_btn.set_image(Gtk.Image.new_from_icon_name("weather-clear-night-symbolic", Gtk.IconSize.BUTTON))
        else:
            self.theme_lbl.set_text("Day Mode")
            self.theme_icon_btn.set_image(Gtk.Image.new_from_icon_name("weather-clear-symbolic", Gtk.IconSize.BUTTON))

        # Media (MPRIS via D-Bus)
        title, artist, status, _art = get_media_info()
        self.media_title.set_text(title)
        self.media_artist.set_text(artist)
        if status.lower() == "playing":
            self.play_btn.set_image(Gtk.Image.new_from_icon_name("media-playback-pause-symbolic", Gtk.IconSize.BUTTON))
        else:
            self.play_btn.set_image(Gtk.Image.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON))

        return True

    def on_toggle_wifi(self, *_):
        self.reset_inactivity()
        toggle_wifi()
        enabled, _ = get_wifi_state()
        if not enabled:
            self.wifi_revealer.set_reveal_child(False)
        GLib.timeout_add(300, self.update_dynamic_state)

    def on_toggle_wifi_details(self, *_):
        self.reset_inactivity()
        is_revealed = self.wifi_revealer.get_reveal_child()
        if not is_revealed:
            self.wifi_revealer.set_reveal_child(True)
            self.refresh_wifi_networks()
        else:
            self.wifi_revealer.set_reveal_child(False)

    def refresh_wifi_networks(self, *_):
        self.reset_inactivity()
        for child in self.wifi_list_box.get_children():
            self.wifi_list_box.remove(child)

        spinner = Gtk.Label(label="Scanning networks...")
        spinner.get_style_context().add_class("subtitle-text")
        spinner.set_halign(Gtk.Align.START)
        self.wifi_list_box.pack_start(spinner, False, False, 4)
        self.wifi_list_box.show_all()

        def _fetch():
            nets = get_wifi_network_list()
            GLib.idle_add(self._populate_wifi_networks, nets)

        threading.Thread(target=_fetch, daemon=True).start()

    def _populate_wifi_networks(self, networks):
        for child in self.wifi_list_box.get_children():
            self.wifi_list_box.remove(child)

        if not networks:
            lbl = Gtk.Label(label="No Wi-Fi networks found.")
            lbl.get_style_context().add_class("subtitle-text")
            lbl.set_halign(Gtk.Align.START)
            self.wifi_list_box.pack_start(lbl, False, False, 4)
        else:
            for net in networks[:6]:
                ssid = net["ssid"]
                active = net["active"]
                sec = net["sec"]
                sig = net["signal"]

                btn = Gtk.Button()
                btn.get_style_context().add_class("wifi-item-btn")
                if active:
                    btn.get_style_context().add_class("active")

                hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
                icon_name = "network-wireless-signal-excellent-symbolic"
                try:
                    sig_val = int(sig)
                    if sig_val < 35:
                        icon_name = "network-wireless-signal-weak-symbolic"
                    elif sig_val < 70:
                        icon_name = "network-wireless-signal-ok-symbolic"
                except Exception:
                    pass

                icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON)
                hbox.pack_start(icon, False, False, 0)

                name_lbl = Gtk.Label(label=ssid)
                name_lbl.get_style_context().add_class("title-text")
                name_lbl.set_xalign(0)
                name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
                hbox.pack_start(name_lbl, True, True, 0)

                if sec and sec != "--":
                    lock = Gtk.Image.new_from_icon_name("changes-prevent-symbolic", Gtk.IconSize.BUTTON)
                    lock.set_pixel_size(12)
                    hbox.pack_start(lock, False, False, 0)

                if active:
                    check = Gtk.Label(label="✔")
                    check.get_style_context().add_class("title-text")
                    hbox.pack_start(check, False, False, 0)

                btn.add(hbox)
                btn.connect("clicked", lambda _, s=ssid: (connect_to_wifi(s), GLib.timeout_add(1500, self.refresh_wifi_networks)))
                self.wifi_list_box.pack_start(btn, False, False, 1)

        bottom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        adv_btn = Gtk.Button(label="Network Settings...")
        adv_btn.get_style_context().add_class("media-btn")
        adv_btn.connect("clicked", lambda *_: open_wifi_settings())
        bottom_box.pack_start(adv_btn, False, False, 0)
        self.wifi_list_box.pack_start(bottom_box, False, False, 4)
        self.wifi_list_box.show_all()

    def on_toggle_dnd(self, *_):
        self.reset_inactivity()
        toggle_dnd()
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_toggle_theme(self, *_):
        self.reset_inactivity()
        toggle_system_theme()
        GLib.timeout_add(300, self.update_dynamic_state)

    def on_brightness_changed(self, scale):
        self.reset_inactivity()
        val = scale.get_value()
        set_display_brightness(val)

    def on_volume_changed(self, scale):
        self.reset_inactivity()
        val = scale.get_value()
        set_sound_volume(val)

    def on_media_play_pause(self, *_):
        self.reset_inactivity()
        media_play_pause()
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_media_next(self, *_):
        self.reset_inactivity()
        media_next()
        GLib.timeout_add(200, self.update_dynamic_state)

    def on_open_settings(self, *_):
        subprocess.Popen(["xfce4-settings-manager"])
        self.hide_to_dismiss()

    def on_open_power(self, *_):
        subprocess.Popen(["xfce4-session-logout"])
        self.hide_to_dismiss()


class ControlCenterApp(Gtk.Application):
    def __init__(self, trial_mode=False):
        super().__init__(
            application_id="org.sequoia.ControlCenter",
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self.win = None
        self._held = False
        self._exit_timer_id = None
        self.trial_mode = trial_mode
        global _current_app
        _current_app = self

    def do_startup(self):
        Gtk.Application.do_startup(self)
        GLib.set_prgname("org.sequoia.ControlCenter")
        GLib.set_application_name("Control Center")
        write_pid_file()
        self.hold()
        self._held = True

    def do_activate(self):
        self.toggle_window()

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        exit_code = 0

        # Check internal feature gate
        if "--trial" in args:
            self.trial_mode = True

        if not self.trial_mode and not is_feature_enabled() and "--status" not in args and "--quit" not in args:
            msg = "Control Center is disabled in ~/.config/sequoia/features.json (enable with: sequoia-ctl feature enable control-center)\n"
            sys.stderr.write(msg)
            sys.stderr.flush()
            self.quit_app()
            return 0

        if "--quit" in args:
            self.quit_app()
        elif "--hide" in args:
            self.hide_window()
        elif "--show" in args:
            self.show_window()
        elif "--status" in args:
            vis = self.win is not None and self.win.get_visible()
            status_str = "visible\n" if vis else "hidden\n"
            try:
                command_line.print_literal(status_str)
            except Exception:
                pass
            sys.stdout.write(status_str)
            sys.stdout.flush()
            exit_code = 0 if vis else 1
        else:
            self.toggle_window()

        try:
            command_line.set_exit_status(exit_code)
        except Exception:
            pass
        return exit_code

    def get_or_create_window(self):
        if self.win is None:
            self.win = SequoiaControlCenter(self)
            self.add_window(self.win)
        return self.win

    def toggle_window(self):
        win = self.get_or_create_window()
        if win.get_visible():
            self.hide_window()
        else:
            self.show_window()

    def show_window(self):
        # Cancel any pending exit timer
        if self._exit_timer_id is not None:
            GLib.source_remove(self._exit_timer_id)
            self._exit_timer_id = None

        win = self.get_or_create_window()
        win.position_window()
        win.show_all()
        win.present()
        win.start_polling()
        win.reset_inactivity()

    def hide_window(self):
        if self.win and self.win.get_visible():
            self.win.stop_polling()
            self.win.stop_inactivity()
            self.win.hide()

        # Start 2-second countdown to exit process cleanly after close/hide
        if self._exit_timer_id is None:
            self._exit_timer_id = GLib.timeout_add(2000, self._on_idle_exit)

    def _on_idle_exit(self):
        self._exit_timer_id = None
        self.quit_app()
        return False

    def quit_app(self):
        if self._exit_timer_id is not None:
            GLib.source_remove(self._exit_timer_id)
            self._exit_timer_id = None
        if self.win:
            self.win.stop_polling()
            self.win.stop_inactivity()
            self.win.destroy()
            self.win = None
        if self._held:
            self.release()
            self._held = False
        remove_pid_file()
        self.quit()


def main():
    def _sig_handler(*_):
        global _current_app
        if _current_app:
            _current_app.quit_app()
        else:
            remove_pid_file()
            sys.exit(0)

    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    trial = ("--trial" in sys.argv)
    query_cmd = ("--status" in sys.argv or "--quit" in sys.argv)

    # Check feature gate early before Gtk.Application initialisation
    if not trial and not query_cmd and not is_feature_enabled():
        sys.stderr.write(
            "Control Center is disabled in ~/.config/sequoia/features.json "
            "(enable with: sequoia-ctl feature enable control-center)\n"
        )
        sys.stderr.flush()
        return 0

    try:
        app = ControlCenterApp(trial_mode=trial)
        return app.run(sys.argv)
    except Exception as e:
        sys.stderr.write(f"Control Center Exception: {e}\n")
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.stderr.flush()
        remove_pid_file()
        return 1


if __name__ == "__main__":
    sys.exit(main())
