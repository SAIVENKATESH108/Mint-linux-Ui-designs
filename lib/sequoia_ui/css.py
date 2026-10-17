"""
CSS Validator and Loader for GTK 3.24.
GTK 3.24 supports a subset of CSS:
- FORBIDDEN: filter, backdrop-filter, gap, row-gap, column-gap, display, transform, z-index, will-change.
- FORBIDDEN: CSS custom properties (--var: ... or var(--var)).
- REQUIRED: @define-color for color tokens.
This module validates stylesheets, logs line and column of violations, and provides a safe fallback.
"""

import logging
import re
from typing import List, Tuple

logger = logging.getLogger("sequoia_ui.css")

FORBIDDEN_PROPERTIES = {
    "filter": "GTK 3.24 does not support CSS filter",
    "backdrop-filter": "GTK 3.24 does not support backdrop-filter; use Picom or translucent rgba() colors",
    "gap": "GTK 3.24 does not support gap; use margin, padding, or GtkBox spacing",
    "row-gap": "GTK 3.24 does not support row-gap; use GtkGrid row-spacing",
    "column-gap": "GTK 3.24 does not support column-gap; use GtkGrid column-spacing",
    "display": "GTK 3.24 does not support CSS display property; use GTK container widgets",
    "transform": "GTK 3.24 does not support CSS transform",
    "z-index": "GTK 3.24 does not support z-index; window hierarchy is managed via X11 / GtkOverlay",
    "will-change": "GTK 3.24 does not support will-change",
}

MINIMAL_FALLBACK_CSS = """
window.sequoia-window {
    background-color: rgba(30, 30, 30, 0.92);
    color: #FFFFFF;
    border-radius: 16px;
    border: 1px solid rgba(255, 255, 255, 0.15);
}
label {
    color: #FFFFFF;
    font-family: Inter, Cantarell, Sans;
}
button {
    background-color: rgba(255, 255, 255, 0.1);
    color: #FFFFFF;
    border-radius: 8px;
    border: none;
    padding: 6px 12px;
}
button:hover {
    background-color: rgba(255, 255, 255, 0.18);
}
"""


class CSSError:
    def __init__(self, line: int, col: int, message: str, snippet: str = ""):
        self.line = line
        self.col = col
        self.message = message
        self.snippet = snippet

    def __str__(self):
        return f"Line {self.line}, Col {self.col}: {self.message} (snippet: '{self.snippet}')"


def validate_gtk3_css(css_text: str) -> Tuple[bool, List[CSSError]]:
    """
    Validates that css_text strictly conforms to GTK 3.24 supported CSS syntax.
    Returns (is_valid, list_of_errors).
    """
    errors: List[CSSError] = []
    lines = css_text.splitlines()

    for line_idx, line in enumerate(lines, start=1):
        clean = line.strip()
        # Ignore comments and empty lines
        if not clean or clean.startswith("/*") or clean.startswith("*"):
            continue

        # Check for CSS custom properties declaration (--foo: bar;)
        var_decl_match = re.search(r"(--[a-zA-Z0-9_-]+)\s*:", line)
        if var_decl_match:
            col = var_decl_match.start() + 1
            errors.append(CSSError(
                line=line_idx,
                col=col,
                message="CSS custom property definition is not supported in GTK3; use @define-color instead",
                snippet=var_decl_match.group(0),
            ))

        # Check for var(--foo) usage
        var_usage_match = re.search(r"var\(\s*--[a-zA-Z0-9_-]+\s*\)", line)
        if var_usage_match:
            col = var_usage_match.start() + 1
            errors.append(CSSError(
                line=line_idx,
                col=col,
                message="CSS var(...) function is not supported in GTK3; use @color_name defined via @define-color",
                snippet=var_usage_match.group(0),
            ))

        # Check for forbidden properties
        prop_match = re.search(r"([a-zA-Z0-9_-]+)\s*:", line)
        if prop_match:
            prop_name = prop_match.group(1).lower()
            if prop_name in FORBIDDEN_PROPERTIES:
                col = prop_match.start() + 1
                errors.append(CSSError(
                    line=line_idx,
                    col=col,
                    message=f"Forbidden property '{prop_name}': {FORBIDDEN_PROPERTIES[prop_name]}",
                    snippet=line.strip(),
                ))

    is_valid = len(errors) == 0
    return is_valid, errors


def load_css(css_text: str, screen=None) -> bool:
    """
    Loads and applies css_text to the given Gdk.Screen using Gtk.CssProvider.
    Validates CSS first; if invalid, logs all violations with line/col and applies safe fallback.
    """
    is_valid, errors = validate_gtk3_css(css_text)
    if not is_valid:
        for err in errors:
            logger.warning("[GTK3 CSS VALIDATION ERROR] %s", err)
            print(f" [GTK3 CSS VALIDATION ERROR] {err}")
        css_text = MINIMAL_FALLBACK_CSS

    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        from gi.repository import Gtk, Gdk

        if screen is None:
            screen = Gdk.Screen.get_default()

        if screen is None:
            return True

        provider = Gtk.CssProvider()
        provider.load_from_data(css_text.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_screen(
            screen,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )
        return True
    except Exception as e:
        logger.error("Failed to load CSS provider: %s", e)
        return False
