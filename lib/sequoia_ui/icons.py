"""
Icon loader with lazy loading and LRU caching for Sequoia UI.
Caches loaded GdkPixbuf instances up to max_size.
Prevents disk bottlenecks during fast scrolling in Launchpad / Spotlight.
"""

from collections import OrderedDict
from typing import Optional


class IconCache:
    def __init__(self, max_size: int = 256):
        self.max_size = max_size
        self._cache: OrderedDict = OrderedDict()

    def get_pixbuf(self, icon_name: str, size: int = 48) -> Optional[object]:
        """Loads and returns a GdkPixbuf.Pixbuf for icon_name at requested size."""
        if not icon_name:
            icon_name = "application-x-executable"

        key = (icon_name, size)
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]

        try:
            import gi
            gi.require_version("Gtk", "3.0")
            gi.require_version("GdkPixbuf", "2.0")
            from gi.repository import Gtk

            theme = Gtk.IconTheme.get_default()
            pixbuf = None
            if theme:
                try:
                    pixbuf = theme.load_icon(icon_name, size, Gtk.IconLookupFlags.GENERIC_FALLBACK)
                except Exception:
                    pass

            if pixbuf is None and theme:
                try:
                    pixbuf = theme.load_icon("application-x-executable", size, Gtk.IconLookupFlags.GENERIC_FALLBACK)
                except Exception:
                    pass

            if pixbuf is not None:
                if len(self._cache) >= self.max_size:
                    self._cache.popitem(last=False)
                self._cache[key] = pixbuf
                return pixbuf
        except Exception:
            pass

        return None

    def clear(self):
        self._cache.clear()
