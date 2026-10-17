#!/usr/bin/env python3
"""
Unit tests for Conky dry-run classifier and evaluator.
Tests fixtures for INFO, WARN, and ERROR line classifications,
and asserts that WARN yields PASS_WARN (exit 0) while ERROR or non-zero exit yields FAIL.
"""

import os
import sys
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)

from deskwidgets.conky_check import classify_conky_line, evaluate_conky_output, compare_environments

# Fixture outputs representing real Conky console streams
FIXTURE_CLEAN_INFO = """
conky: desktop window (0x280) is subwindow of root window (0x7e0)
conky: window type - normal
conky: drawing to created window (0x2c00001)
conky: drawing to double buffer
deskwidgets: clock-1: layout initialized
"""

FIXTURE_WITH_FONTCONFIG_WARN = """
conky: desktop window (0x280) is subwindow of root window (0x7e0)
conky: window type - normal
Fontconfig error: Cannot load default config file: No such file: (null)
conky: drawing to created window (0x2c00001)
conky: drawing to double buffer
"""

FIXTURE_WITH_DEPRECATION_WARN = """
conky: desktop window (0x280) is subwindow of root window (0x7e0)
(conky:1234): GLib-GObject-WARNING **: g_object_set_property is deprecated
conky: drawing to double buffer
"""

FIXTURE_CANNOT_OPEN_ERROR = """
conky: desktop window (0x280) is subwindow of root window (0x7e0)
deskwidgets: widget: cannot open ./widget.lua: No such file or directory
conky: drawing to created window (0x2c00001)
"""

FIXTURE_LUA_NIL_ERROR = """
conky: desktop window (0x280) is subwindow of root window (0x7e0)
conky: llua_do_call: [string "widget.conf"]:48: attempt to concatenate a nil value
conky: drawing to created window (0x2c00001)
"""


class TestConkyCheckClassifier(unittest.TestCase):
    def test_classify_info_lines(self):
        self.assertEqual(classify_conky_line("conky: desktop window (0x280) is subwindow of root window"), "INFO")
        self.assertEqual(classify_conky_line("conky: window type - normal"), "INFO")
        self.assertEqual(classify_conky_line("conky: drawing to double buffer"), "INFO")
        self.assertEqual(classify_conky_line("deskwidgets: clock-1: layout initialized"), "INFO")

    def test_classify_warn_lines(self):
        self.assertEqual(classify_conky_line("Fontconfig error: Cannot load default config file: No such file: (null)"), "WARN")
        self.assertEqual(classify_conky_line("Fontconfig warning: ignoring unknown font family"), "WARN")
        self.assertEqual(classify_conky_line("warning: g_object_set_property is deprecated"), "WARN")

    def test_classify_error_lines(self):
        self.assertEqual(classify_conky_line("deskwidgets: widget: cannot open ./widget.lua: No such file or directory"), "ERROR")
        self.assertEqual(classify_conky_line("conky: attempt to concatenate a nil value"), "ERROR")
        self.assertEqual(classify_conky_line("conky: lua error in chunk: syntax error"), "ERROR")
        self.assertEqual(classify_conky_line("conky: terminated by signal 11 (segfault)"), "ERROR")

    def test_evaluate_clean_output_passes(self):
        res = evaluate_conky_output(0, FIXTURE_CLEAN_INFO)
        self.assertEqual(res["status"], "PASS")
        self.assertEqual(len(res["error_lines"]), 0)
        self.assertEqual(len(res["warn_lines"]), 0)
        self.assertGreater(len(res["info_lines"]), 0)
        self.assertIn("Exit code 0", res["reason"])

    def test_evaluate_warn_output_passes_with_warning(self):
        """Asserts that Fontconfig warning does NOT fail the test run."""
        res = evaluate_conky_output(0, FIXTURE_WITH_FONTCONFIG_WARN)
        self.assertEqual(res["status"], "PASS_WARN")
        self.assertEqual(len(res["error_lines"]), 0)
        self.assertEqual(len(res["warn_lines"]), 1)
        self.assertIn("Fontconfig error: Cannot load default config file", res["warn_lines"][0])
        self.assertIn("Exit code 0", res["reason"])

    def test_evaluate_deprecation_warn_passes_with_warning(self):
        res = evaluate_conky_output(0, FIXTURE_WITH_DEPRECATION_WARN)
        self.assertEqual(res["status"], "PASS_WARN")
        self.assertEqual(len(res["error_lines"]), 0)
        self.assertEqual(len(res["warn_lines"]), 1)

    def test_evaluate_cannot_open_fails(self):
        """Asserts that 'cannot open ./widget.lua' fails even if conky exited 0."""
        res = evaluate_conky_output(0, FIXTURE_CANNOT_OPEN_ERROR)
        self.assertEqual(res["status"], "FAIL")
        self.assertGreater(len(res["error_lines"]), 0)
        self.assertIn("cannot open ./widget.lua", res["error_lines"][0])
        self.assertIn("Error detected in output", res["reason"])

    def test_evaluate_lua_nil_fails(self):
        res = evaluate_conky_output(0, FIXTURE_LUA_NIL_ERROR)
        self.assertEqual(res["status"], "FAIL")
        self.assertGreater(len(res["error_lines"]), 0)
        self.assertIn("attempt to concatenate a nil value", res["error_lines"][0])

    def test_evaluate_nonzero_exit_fails(self):
        res = evaluate_conky_output(1, FIXTURE_CLEAN_INFO)
        self.assertEqual(res["status"], "FAIL")
        self.assertIn("Exit code 1", res["reason"])

    def test_compare_environments_identifies_diffs(self):
        env_proc = {
            "FONTCONFIG_FILE": "/run/user/1000/deskwidgets/fonts.conf",
            "MAC_ENGINE": "/home/sai/.local/share/deskwidgets/engine",
            "DISPLAY": ":0",
        }
        env_base = {
            "FONTCONFIG_FILE": "/home/sai/.cache/deskwidgets/fontconfig.conf",
            "MAC_ENGINE": "/home/sai/.local/share/deskwidgets/engine",
            "DISPLAY": ":0",
        }
        diffs = compare_environments(env_proc, env_base)
        self.assertEqual(len(diffs), 1)
        self.assertIn("FONTCONFIG_FILE", diffs[0])
        self.assertIn("fonts.conf", diffs[0])

    def test_compare_environments_no_diffs(self):
        env_proc = {"FONTCONFIG_FILE": "/run/user/1000/deskwidgets/fonts.conf"}
        env_base = {"FONTCONFIG_FILE": "/run/user/1000/deskwidgets/fonts.conf"}
        diffs = compare_environments(env_proc, env_base)
        self.assertEqual(len(diffs), 0)


if __name__ == "__main__":
    unittest.main()
