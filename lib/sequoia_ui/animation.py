"""
Animation Helper for Sequoia UI.
Provides smooth 120-180ms opacity fades.
Disabled when animations are disabled in configuration or safe-mode is active.
"""

import json
import os
from typing import Callable, Optional

USER_CONFIG = os.path.expanduser("~/.config/sequoia/user.json")


def animations_enabled() -> bool:
    """Checks whether UI animations are enabled in user configuration."""
    if os.path.isfile(USER_CONFIG):
        try:
            with open(USER_CONFIG, "r", encoding="utf-8") as f:
                data = json.load(f)
            # Safe-mode or explicit animation disabled
            if data.get("safe_mode", False) or data.get("animations", True) is False:
                return False
        except Exception:
            pass
    return True


def animate_window_fade_in(window, duration_ms: int = 150, on_done: Optional[Callable] = None):
    """Fades in window opacity from 0.0 to 1.0 over duration_ms."""
    if not animations_enabled():
        window.set_opacity(1.0)
        if on_done:
            on_done()
        return

    try:
        from gi.repository import GLib
    except ImportError:
        window.set_opacity(1.0)
        if on_done:
            on_done()
        return

    fps = 60
    interval_ms = int(1000 / fps)
    steps = max(1, int(duration_ms / interval_ms))
    step = 0

    window.set_opacity(0.0)

    def _tick():
        nonlocal step
        step += 1
        progress = min(1.0, step / steps)
        # Smooth ease-out quad
        ease = 1.0 - (1.0 - progress) * (1.0 - progress)
        window.set_opacity(ease)
        if progress >= 1.0:
            if on_done:
                on_done()
            return False
        return True

    GLib.timeout_add(interval_ms, _tick)


def animate_window_fade_out(window, duration_ms: int = 120, on_done: Optional[Callable] = None):
    """Fades out window opacity from 1.0 to 0.0 over duration_ms."""
    if not animations_enabled():
        window.set_opacity(0.0)
        if on_done:
            on_done()
        return

    try:
        from gi.repository import GLib
    except ImportError:
        window.set_opacity(0.0)
        if on_done:
            on_done()
        return

    fps = 60
    interval_ms = int(1000 / fps)
    steps = max(1, int(duration_ms / interval_ms))
    step = 0

    def _tick():
        nonlocal step
        step += 1
        progress = min(1.0, step / steps)
        ease = (1.0 - progress) * (1.0 - progress)
        window.set_opacity(ease)
        if progress >= 1.0:
            if on_done:
                on_done()
            return False
        return True

    GLib.timeout_add(interval_ms, _tick)
