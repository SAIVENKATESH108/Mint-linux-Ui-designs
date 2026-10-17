"""
Base Overlay Window for Sequoia UI (Launchpad, Spotlight, Mission Control, Control Center).
Features:
- Undecorated, floating, RGBA visual support
- Focus grab on map, 350ms focus-out suppression to prevent shortcut race conditions
- Escape dismissal, outside click / focus-out dismissal
- Inactivity timeout (30s)
- Automatic persistent telemetry recording (first paint, geometry, gap, RSS, dismissal reason)
- Automatic process exit within 2s of close (never stays resident)
"""

import time
from typing import Optional, Any

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gtk, Gdk, GLib
    HAS_GTK = True
except (ImportError, ValueError):
    HAS_GTK = False
    Gtk = object

from .animation import animate_window_fade_in, animate_window_fade_out
from .telemetry import record_telemetry


class BaseOverlayWindow(Gtk.Window if HAS_GTK else object):
    def __init__(
        self,
        app_name: str = "sequoia-overlay",
        app=None,
        title: str = "Sequoia Overlay",
        width: int = 400,
        height: int = 300,
        telemetry: Optional[Any] = None,
        **kwargs
    ):
        if not HAS_GTK:
            raise RuntimeError("GTK 3.0 is required to instantiate BaseOverlayWindow")

        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.app_name = app_name
        self.app = app
        self.telemetry = telemetry
        self.set_title(title)
        self.set_default_size(width, height)

        # macOS style overlay properties
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)

        # Enable RGBA visuals for smooth translucent backgrounds
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        self._map_time = 0.0
        self._first_paint_time = 0.0
        self._inactivity_timer_id: Optional[int] = None
        self._exit_timer_id: Optional[int] = None

        # Event connections
        self.connect("map-event", self._on_base_map)
        self.connect("unmap-event", self._on_base_unmap)
        self.connect("focus-out-event", self._on_base_focus_out)
        self.connect("key-press-event", self._on_base_key_press)
        self.connect("button-press-event", self._on_base_button_press)
        self.connect("draw", self._on_base_draw)
        self.connect("delete-event", self._on_base_delete)

    def _on_base_map(self, *_):
        self._map_time = time.time()
        self.present()
        self.grab_focus()
        self.reset_inactivity()
        animate_window_fade_in(self, duration_ms=150)
        self._emit_telemetry(mapped=True, reason="open")

    def _on_base_draw(self, _widget, _cr):
        if self._first_paint_time == 0.0 and self._map_time > 0.0:
            self._first_paint_time = time.time()
        return False

    def _on_base_unmap(self, *_):
        self.stop_inactivity()

    def _on_base_delete(self, _widget, _event):
        self.dismiss(reason="window-close")
        return True

    def _on_base_focus_out(self, _widget, _event):
        elapsed = time.time() - self._map_time
        if elapsed < 0.35:
            # Ignore transient focus loss in the first 350ms grace window
            return False
        self.dismiss(reason="focus-out")
        return False

    def _on_base_key_press(self, _widget, event):
        self.reset_inactivity()
        if event.keyval == Gdk.KEY_Escape:
            self.dismiss(reason="Escape")
            return True
        return False

    def _on_base_button_press(self, _widget, _event):
        self.reset_inactivity()
        return False

    def reset_inactivity(self, timeout_sec: int = 30):
        self.stop_inactivity()
        self._inactivity_timer_id = GLib.timeout_add_seconds(timeout_sec, self._on_inactivity_timeout)

    def stop_inactivity(self):
        if self._inactivity_timer_id is not None:
            GLib.source_remove(self._inactivity_timer_id)
            self._inactivity_timer_id = None

    def _on_inactivity_timeout(self):
        self._inactivity_timer_id = None
        self.dismiss(reason="inactivity")
        return False

    def on_dismissed(self, reason: str):
        pass

    def dismiss(self, reason: str = "idle"):
        self.stop_inactivity()
        self._emit_telemetry(mapped=False, reason=reason)
        try:
            self.on_dismissed(reason)
        except Exception:
            pass

        def _after_fade():
            if self.app:
                self.app.hide_window()
            else:
                self.hide()
            # Enforce clean exit within 2s; no resident processes lingering
            self._schedule_clean_exit()

        animate_window_fade_out(self, duration_ms=120, on_done=_after_fade)

    def _schedule_clean_exit(self):
        if self._exit_timer_id is not None:
            GLib.source_remove(self._exit_timer_id)
        # Clean exit within 2 seconds
        self._exit_timer_id = GLib.timeout_add_seconds(2, self._force_exit)

    def _force_exit(self):
        if self.app:
            self.app.quit()
        else:
            Gtk.main_quit()
        return False

    def _emit_telemetry(self, mapped: bool, reason: str):
        try:
            pos = self.get_position()
            size = self.get_size()
            if self.telemetry:
                self.telemetry.set_geometry(pos, size)
                if mapped:
                    self.telemetry.record_paint()
            record_telemetry(
                app_name=self.app_name,
                mapped=mapped,
                reason=reason,
                map_time=self._map_time,
                paint_time=self._first_paint_time,
                pos=pos,
                size=size,
            )
        except Exception:
            pass
