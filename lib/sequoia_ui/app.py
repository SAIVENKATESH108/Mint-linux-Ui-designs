"""
Single-Instance Application Helper for Sequoia UI.
Uses Gtk.Application with D-Bus activation to:
- Enforce single instance across the desktop session
- Toggle or present window on a second launch (via command line or hotkey)
- Support --show, --toggle, --quit, --trial flags
- Clean exit without leftover resident daemons
"""

import os
import sys

try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gio", "2.0")
    from gi.repository import Gtk, Gio, GLib
    HAS_GTK = True
except (ImportError, ValueError):
    HAS_GTK = False
    Gtk = object
    Gio = object


class SequoiaApplication(Gtk.Application if HAS_GTK else object):
    def __init__(self, app_id: str, window_factory_fn):
        if not HAS_GTK:
            raise RuntimeError("GTK 3.0 and Gio 2.0 are required for SequoiaApplication")

        super().__init__(
            application_id=app_id,
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self.window_factory_fn = window_factory_fn
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.window = self.window_factory_fn(self)

    def do_activate(self):
        if not self.window:
            self.window = self.window_factory_fn(self)
        if self.window.get_visible():
            self.window.dismiss(reason="toggle")
        else:
            self.window.show_all()
            self.window.present()

    def do_command_line(self, command_line):
        args = command_line.get_arguments()
        show = "--show" in args
        quit_flag = "--quit" in args
        toggle = "--toggle" in args or (not show and not quit_flag)

        if quit_flag:
            if self.window and self.window.get_visible():
                self.window.dismiss(reason="quit-flag")
            self.quit()
            return 0

        if not self.window:
            self.window = self.window_factory_fn(self)

        if show:
            self.window.show_all()
            self.window.present()
        elif toggle:
            if self.window.get_visible():
                self.window.dismiss(reason="toggle")
            else:
                self.window.show_all()
                self.window.present()

        return 0

    def hide_window(self):
        if self.window:
            self.window.hide()
