#!/usr/bin/env python3
"""
Unit tests for Sequoia UI Toolkit:
- Tests DesignTokens generation (@define-color outputs, light/dark switching).
- Tests Telemetry recording (geometry, gap, dismissal reasons, RSS).
- Tests WorkerPool execution, cancellation, and timeout handling.
"""

import os
import sys
import time
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UI_DIR = os.path.join(REPO_DIR, "lib")
if UI_DIR not in sys.path:
    sys.path.insert(0, UI_DIR)

from sequoia_ui.tokens import DesignTokens
from sequoia_ui.telemetry import record_telemetry, get_process_rss_mb
from sequoia_ui.threads import WorkerPool, CancellationToken


class TestSequoiaUI(unittest.TestCase):
    def test_design_tokens_defines(self):
        tokens = DesignTokens({
            "theme": "dark",
            "profile": "lite",
            "accent": "#007AFF"
        })
        css_defines = tokens.to_gtk_css_defines()
        self.assertIn("@define-color sequoia_accent #007AFF;", css_defines)
        self.assertIn("@define-color sequoia_bg rgba(28, 28, 30, 0.88);", css_defines)
        self.assertIn("@define-color sequoia_fg #FFFFFF;", css_defines)

    def test_design_tokens_light_mode(self):
        tokens = DesignTokens({
            "theme": "light",
            "profile": "lite",
            "accent": "#FF9500"
        })
        css_defines = tokens.to_gtk_css_defines()
        self.assertIn("@define-color sequoia_accent #FF9500;", css_defines)
        self.assertIn("@define-color sequoia_bg rgba(242, 242, 247, 0.90);", css_defines)
        self.assertIn("@define-color sequoia_fg #1C1C1E;", css_defines)

    def test_telemetry_recording(self):
        now = time.time()
        data = record_telemetry(
            app_name="test-app",
            mapped=False,
            reason="Escape",
            map_time=now - 4.5,
            paint_time=now - 4.2,
            pos=(904, 34),
            size=(360, 500),
        )
        self.assertEqual(data["app"], "test-app")
        self.assertFalse(data["mapped"])
        self.assertEqual(data["reason"], "Escape")
        self.assertAlmostEqual(data["time_open_sec"], 4.5, delta=0.5)
        self.assertAlmostEqual(data["time_to_first_paint_ms"], 300.0, delta=50.0)
        self.assertEqual(data["x"], 904)
        self.assertEqual(data["y"], 34)
        self.assertEqual(data["top_bar_gap"], 6)  # 34 - 28 = 6px
        self.assertGreaterEqual(data["rss_mb"], 0.0)

    def test_worker_pool_timeout_handling(self):
        pool = WorkerPool(max_workers=2)
        done_event = [False]
        error_event = [None]

        def slow_task():
            time.sleep(0.5)
            return "done"

        def on_done(res):
            done_event[0] = True

        def on_err(err):
            error_event[0] = err

        # Run with strict 0.05s timeout
        pool.submit(slow_task, timeout=0.05, callback=on_done, on_error=on_err)
        time.sleep(0.2)

        self.assertFalse(done_event[0])
        self.assertIsNotNone(error_event[0])
        pool.shutdown(wait=False)

    def test_worker_pool_cancellation(self):
        pool = WorkerPool(max_workers=2)
        token = CancellationToken()
        token.cancel()

        done_event = [False]

        def dummy_task():
            return "ok"

        def on_done(res):
            done_event[0] = True

        pool.submit(dummy_task, callback=on_done, cancel_token=token)
        time.sleep(0.1)

        self.assertFalse(done_event[0])
        pool.shutdown(wait=False)


if __name__ == "__main__":
    unittest.main()
