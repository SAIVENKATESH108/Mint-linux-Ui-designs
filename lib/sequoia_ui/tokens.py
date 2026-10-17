"""
Design Tokens Loader for macOS Sequoia Desktop.
Pulls colors, radii, and spacing from user configuration (~/.config/sequoia/user.json)
and active presets. Formats GTK 3.24 compatible CSS using @define-color.
"""

import json
import os
from typing import Dict, Any

USER_CONFIG = os.path.expanduser("~/.config/sequoia/user.json")
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PRESETS_DIR = os.path.join(REPO_ROOT, "themes", "presets")


class DesignTokens:
    def __init__(self, data: Dict[str, Any] = None):
        self.data = data or {}
        self.profile = self.data.get("profile", "lite")
        self.is_dark = self._detect_dark()
        self.accent = self.data.get("accent", "#007AFF")
        self.corner_radius = 16
        self.base_font = "Inter, -apple-system, BlinkMacSystemFont, 'SF Pro Text', Cantarell, Sans"

    def _detect_dark(self) -> bool:
        mode = self.data.get("theme", "dark").lower()
        if mode in ("light", "vibrant-light"):
            return False
        return True

    @property
    def bg_color(self) -> str:
        if self.is_dark:
            # Lite profile uses flat translucent; glass adds picom blur
            return "rgba(28, 28, 30, 0.88)" if self.profile == "lite" else "rgba(22, 22, 24, 0.72)"
        else:
            return "rgba(242, 242, 247, 0.90)" if self.profile == "lite" else "rgba(255, 255, 255, 0.75)"

    @property
    def card_bg(self) -> str:
        if self.is_dark:
            return "rgba(255, 255, 255, 0.08)"
        else:
            return "rgba(0, 0, 0, 0.05)"

    @property
    def fg_color(self) -> str:
        return "#FFFFFF" if self.is_dark else "#1C1C1E"

    @property
    def fg_secondary(self) -> str:
        return "rgba(255, 255, 255, 0.60)" if self.is_dark else "rgba(60, 60, 67, 0.60)"

    @property
    def border_color(self) -> str:
        if self.is_dark:
            return "rgba(255, 255, 255, 0.14)"
        else:
            return "rgba(0, 0, 0, 0.10)"

    @property
    def separator_color(self) -> str:
        if self.is_dark:
            return "rgba(255, 255, 255, 0.10)"
        else:
            return "rgba(0, 0, 0, 0.08)"

    def to_gtk_css_defines(self) -> str:
        """
        Generates standard GTK 3.24 @define-color directives.
        GTK3 does not support CSS custom properties (--var), so @define-color is mandatory.
        """
        lines = [
            f"@define-color sequoia_accent {self.accent};",
            f"@define-color sequoia_bg {self.bg_color};",
            f"@define-color sequoia_card_bg {self.card_bg};",
            f"@define-color sequoia_fg {self.fg_color};",
            f"@define-color sequoia_fg_secondary {self.fg_secondary};",
            f"@define-color sequoia_border {self.border_color};",
            f"@define-color sequoia_separator {self.separator_color};",
        ]
        return "\n".join(lines)


def get_design_tokens() -> DesignTokens:
    cfg = {}
    if os.path.isfile(USER_CONFIG):
        try:
            with open(USER_CONFIG, "r", encoding="utf-8") as f:
                cfg = json.load(f)
        except Exception:
            pass
    if not cfg:
        preset_file = os.path.join(PRESETS_DIR, "default.json")
        if os.path.isfile(preset_file):
            try:
                with open(preset_file, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
            except Exception:
                pass
    return DesignTokens(cfg)
