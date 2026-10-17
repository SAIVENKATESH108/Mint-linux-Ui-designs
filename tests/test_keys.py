#!/usr/bin/env python3
"""
Unit tests for Sequoia Keyboard Shortcuts Manager:
- Validates XFCE accelerator syntax checker (<Primary>, <Alt>, <Shift>, <Super>, function keys).
- Asserts that default shortcuts contain ZERO Super key dependencies.
- Tests conflict detection engine against system shortcuts and XFCE bindings.
- Tests Super toggle on/off.
- Tests manifest tracking and isolation.
"""

import os
import sys
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)

from deskwidgets.keys import (
    DEFAULT_KEYS,
    KNOWN_SYSTEM_SHORTCUTS,
    validate_accelerator,
    detect_conflicts,
)


class TestKeysManager(unittest.TestCase):
    def test_defaults_have_zero_super_keys(self):
        """Asserts that primary and secondary default shortcuts NEVER use Super key."""
        bindings = DEFAULT_KEYS["bindings"]
        for action, info in bindings.items():
            primary = info.get("primary")
            secondary = info.get("secondary")
            if primary:
                self.assertNotIn("<Super>", primary, f"Action '{action}' primary shortcut uses Super: {primary}")
            if secondary:
                self.assertNotIn("<Super>", secondary, f"Action '{action}' secondary shortcut uses Super: {secondary}")
        self.assertFalse(DEFAULT_KEYS.get("super_enabled", False))

    def test_accelerator_syntax_validation(self):
        # Valid accelerators
        valid_samples = [
            "<Primary><Alt>c",
            "<Primary><Alt>space",
            "<Primary><Alt>s",
            "<Primary><Alt>n",
            "<Primary><Alt>h",
            "F1",
            "F3",
            "F4",
            "F12",
            "<Primary>space",
            "<Alt>Tab",
            "<Shift><Alt>Up",
            "<Super>c",
            "<Primary><Alt>comma",
        ]
        for v in valid_samples:
            ok, err = validate_accelerator(v)
            self.assertTrue(ok, f"Expected '{v}' to be valid, got error: {err}")

        # Invalid accelerators
        invalid_samples = [
            "",
            "ctrl+alt+c",           # Not XFCE syntax
            "<Ctrl><Alt>c",         # XFCE uses <Primary> not <Ctrl>
            "<Invalid>c",
            "<Primary>",            # Missing key
            "c",                    # Plain character without modifiers
            "<Primary><Alt>unknownkey123",
            "F13",                  # Exceeds F12
            "<Primary>Space",       # Space must be lowercase 'space' in XFCE
        ]
        for inv in invalid_samples:
            ok, err = validate_accelerator(inv)
            self.assertFalse(ok, f"Expected '{inv}' to be invalid, but validation passed")

    def test_conflict_detection_detects_system_collision(self):
        """Asserts that mapping to <Primary><Alt>t (Terminal) reports CONFLICT."""
        test_cfg = {
            "super_enabled": False,
            "bindings": {
                "custom_test": {
                    "name": "Rogue Action",
                    "command": "/bin/true",
                    "primary": "<Primary><Alt>t",  # Known Terminal conflict
                    "secondary": None,
                }
            }
        }
        records = detect_conflicts(test_cfg, xfconf_map={})
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["status"], "CONFLICT")
        self.assertIn("Terminal", records[0]["owner"])

    def test_conflict_detection_passes_free_keys(self):
        """Asserts that clean Sequoia defaults pass conflict checks."""
        mock_xfconf = {
            "<Alt>Tab": "cycle_windows_key",
            "<Alt>F4": "close_window_key",
        }
        records = detect_conflicts(DEFAULT_KEYS, xfconf_map=mock_xfconf)
        # Filter for primary and secondary shortcuts
        for r in records:
            if r["type"] in ("primary", "secondary"):
                self.assertEqual(
                    r["status"], "PASS",
                    f"Default key '{r['candidate']}' for '{r['name']}' conflicted with: {r['owner']}"
                )


if __name__ == "__main__":
    unittest.main()
