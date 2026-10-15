#!/usr/bin/env python3
"""
Unit test for Sequoia Control Center CSS parsing.
Ensures that both dark and light mode stylesheets load cleanly into
Gtk.CssProvider without any syntax errors, invalid properties, or parse warnings.
"""

import os
import sys
import unittest

# Ensure scripts directory is in sys.path
REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS_DIR = os.path.join(REPO_DIR, "scripts")
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

import importlib
scc = importlib.import_module("sequoia-control-center")


class TestControlCenterCSS(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Initialize GTK
        Gtk.init_check(None)

    def _parse_css(self, css_text):
        provider = Gtk.CssProvider()
        errors = []

        def _on_parsing_error(prov, section, err):
            try:
                line = section.get_start_line() + 1
                col = section.get_start_position() + 1
            except Exception:
                line = "?"
                col = "?"
            errors.append(f"Line {line}, Col {col}: {err.message}")

        provider.connect("parsing-error", _on_parsing_error)
        try:
            provider.load_from_data(css_text.encode("utf-8"))
        except GLib.GError as gerr:
            errors.append(f"GLib.GError: {gerr.message}")

        return errors

    def test_dark_mode_css_clean(self):
        css = scc.build_css("dark")
        errors = self._parse_css(css)
        self.assertEqual(errors, [], f"Dark mode CSS has parsing errors: {errors}")

    def test_light_mode_css_clean(self):
        css = scc.build_css("light")
        errors = self._parse_css(css)
        self.assertEqual(errors, [], f"Light mode CSS has parsing errors: {errors}")

    def test_safe_fallback_css_clean(self):
        errors = self._parse_css(scc.SAFE_FALLBACK_CSS)
        self.assertEqual(errors, [], f"Fallback CSS has parsing errors: {errors}")

    def test_load_css_safely_on_invalid_css(self):
        provider = Gtk.CssProvider()
        # Deliberately invalid CSS containing unsupported property 'filter'
        invalid_css = "* { filter: blur(5px); }"
        result = scc.load_css_safely(provider, invalid_css)
        # Should return False and apply safe fallback without raising unhandled exception
        self.assertFalse(result)

    def test_load_css_safely_on_valid_css(self):
        provider = Gtk.CssProvider()
        valid_css = scc.build_css("dark")
        result = scc.load_css_safely(provider, valid_css)
        self.assertTrue(result)


if __name__ == "__main__":
    unittest.main()
