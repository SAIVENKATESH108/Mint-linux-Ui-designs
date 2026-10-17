"""
Sequoia UI - Shared GTK3/PyGObject UI Toolkit for macOS Sequoia Desktop on Linux Mint XFCE.
Provides:
  - BaseOverlayWindow: Focus-safe, animated, self-dismissing overlay window with telemetry.
  - SequoiaApplication: Single-instance Gtk.Application helper with instant toggle.
  - CSSValidator & load_css: Validates CSS rules against GTK 3.24 syntax with line/col reporting.
  - DesignTokens: Loads user/preset design tokens (@define-color, radius, spacing).
  - IconCache: Lazy loading LRU icon cache.
  - Animation: Smooth 120-180ms opacity fade helpers.
  - WorkerPool: Worker-thread helper with cancellation and 5s timeout.
  - Telemetry: Measures first paint, geometry, RSS memory, and exact dismissal reason.
"""

from .tokens import get_design_tokens, DesignTokens
from .css import validate_gtk3_css, load_css, MINIMAL_FALLBACK_CSS
from .telemetry import record_telemetry, get_process_rss_mb
from .icons import IconCache
from .animation import animate_window_fade_in, animate_window_fade_out
from .threads import WorkerPool, CancellationToken
from .window import BaseOverlayWindow
from .app import SequoiaApplication

__all__ = [
    "get_design_tokens",
    "DesignTokens",
    "validate_gtk3_css",
    "load_css",
    "MINIMAL_FALLBACK_CSS",
    "record_telemetry",
    "get_process_rss_mb",
    "IconCache",
    "animate_window_fade_in",
    "animate_window_fade_out",
    "WorkerPool",
    "CancellationToken",
    "BaseOverlayWindow",
    "SequoiaApplication",
]
