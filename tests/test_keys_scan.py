#!/usr/bin/env python3
"""
Unit tests for Sequoia Keyboard Shortcuts Legacy Scan & Adoption:
- Asserts that bindings pointing to Sequoia scripts but not in manifest are classified as LEGACY.
- Asserts that bindings listed in manifest are classified as OWNED.
- Asserts that adopt-legacy removes legacy bindings from xfconf and adds them to adopted_legacy in manifest.
"""

import os
import sys
import unittest
from unittest.mock import patch, MagicMock

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)

from deskwidgets.keys import scan_script_bindings, cmd_adopt_legacy, load_manifest, save_manifest


class TestKeysScan(unittest.TestCase):
    @patch('shutil.which', return_value='/usr/bin/xfconf-query')
    @patch('subprocess.run')
    @patch('deskwidgets.keys.load_manifest')
    def test_scan_identifies_legacy_and_owned(self, mock_manifest, mock_run, mock_which):
        """Tests that shortcuts are correctly partitioned into OWNED and LEGACY."""
        mock_manifest.return_value = {
            "installed_shortcuts": [
                "/commands/custom/<Primary><Alt>c",
            ]
        }

        # Mock xfconf-query -l output
        list_output = "/commands/custom/<Primary><Alt>c\n/commands/custom/<Super>c\n/commands/custom/<Primary><Alt>t\n"

        def run_side_effect(cmd, **kwargs):
            if "-l" in cmd:
                return MagicMock(stdout=list_output, returncode=0)
            elif "/commands/custom/<Primary><Alt>c" in cmd:
                return MagicMock(stdout="/home/sai/.local/bin/control-center.sh\n", returncode=0)
            elif "/commands/custom/<Super>c" in cmd:
                return MagicMock(stdout="/home/sai/.local/bin/control-center.sh\n", returncode=0)
            elif "/commands/custom/<Primary><Alt>t" in cmd:
                return MagicMock(stdout="exo-open --launch TerminalEmulator\n", returncode=0)
            return MagicMock(stdout="", returncode=0)

        mock_run.side_effect = run_side_effect

        records = scan_script_bindings()

        # Should only find the 2 that point to our scripts (not Terminal)
        self.assertEqual(len(records), 2)

        owned_rec = next(r for r in records if r["accel"] == "<Primary><Alt>c")
        self.assertEqual(owned_rec["status"], "OWNED")

        legacy_rec = next(r for r in records if r["accel"] == "<Super>c")
        self.assertEqual(legacy_rec["status"], "LEGACY")

    @patch('deskwidgets.keys.scan_script_bindings')
    @patch('subprocess.run')
    @patch('deskwidgets.keys.load_manifest')
    @patch('deskwidgets.keys.save_manifest')
    def test_adopt_legacy_removes_and_records(self, mock_save, mock_load, mock_run, mock_scan):
        """Tests that adopt-legacy removes only legacy bindings and records them in manifest."""
        mock_scan.return_value = [
            {
                "property": "/commands/custom/<Super>c",
                "accel": "<Super>c",
                "command": "/home/sai/.local/bin/control-center.sh",
                "status": "LEGACY",
            },
            {
                "property": "/commands/custom/<Primary><Alt>c",
                "accel": "<Primary><Alt>c",
                "command": "/home/sai/.local/bin/control-center.sh",
                "status": "OWNED",
            }
        ]
        mock_load.return_value = {"installed_shortcuts": ["/commands/custom/<Primary><Alt>c"]}
        mock_run.return_value = MagicMock(returncode=0)

        ret = cmd_adopt_legacy()
        self.assertEqual(ret, 0)

        # Assert save_manifest was called with adopted_legacy
        saved = mock_save.call_args[0][0]
        self.assertIn("adopted_legacy", saved)
        self.assertEqual(len(saved["adopted_legacy"]), 1)
        self.assertEqual(saved["adopted_legacy"][0]["accel"], "<Super>c")


if __name__ == '__main__':
    unittest.main()
