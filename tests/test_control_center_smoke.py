#!/usr/bin/env python3
"""
Smoke test for Sequoia Control Center.
Starts the app under Xvfb + xfwm4 and asserts a mapped window on-screen within 3s.
Tests --show, window presence/mapping, --hide, and --quit.
"""

import os
import sys
import time
import subprocess
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP_PATH = os.path.join(REPO_DIR, "scripts", "sequoia-control-center.py")


class TestControlCenterSmoke(unittest.TestCase):
    def setUp(self):
        display = os.environ.get("DISPLAY")
        if not display:
            self.skipTest("No DISPLAY set (run under xvfb-run or active X11 display)")

    def tearDown(self):
        # Cleanly stop any running daemon instance
        subprocess.run([sys.executable, APP_PATH, "--quit"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.2)

    def _get_mapped_windows(self):
        """Returns list of window records matching Control Center via wmctrl, xdotool, or xwininfo."""
        matched = []
        # Check wmctrl -l
        try:
            res = subprocess.run(["wmctrl", "-l"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            for line in res.stdout.splitlines():
                if "Control Center" in line:
                    matched.append(line)
        except FileNotFoundError:
            pass

        if not matched:
            # Check xdotool search --name "Control Center"
            try:
                res = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "Control Center"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for wid in res.stdout.splitlines():
                    if wid.strip():
                        matched.append(wid.strip())
            except FileNotFoundError:
                pass

        if not matched:
            # Check xwininfo -root -tree
            try:
                res = subprocess.run(["xwininfo", "-root", "-tree"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for line in res.stdout.splitlines():
                    if '"Control Center"' in line:
                        matched.append(line)
            except FileNotFoundError:
                pass

        return matched

    def test_window_mapped_within_3s(self):
        # Launch app with --show
        proc = subprocess.Popen([sys.executable, APP_PATH, "--show"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        start_time = time.time()
        mapped = False
        windows = []

        while time.time() - start_time < 3.0:
            windows = self._get_mapped_windows()
            if windows:
                mapped = True
                break
            time.sleep(0.1)

        elapsed = time.time() - start_time
        self.assertTrue(mapped, f"Window 'Control Center' was not mapped within 3s (elapsed: {elapsed:.2f}s). Windows: {windows}")
        print(f"[TEST PASS] Control Center window successfully mapped in {elapsed:.2f}s: {windows[0]}")

        # Test --status argument
        res = subprocess.run([sys.executable, APP_PATH, "--status"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.assertIn("visible", res.stdout)

        # Test --hide argument
        subprocess.run([sys.executable, APP_PATH, "--hide"], check=True)
        time.sleep(0.3)
        res_hidden = subprocess.run([sys.executable, APP_PATH, "--status"],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.assertIn("hidden", res_hidden.stdout)

        # Test --quit argument
        subprocess.run([sys.executable, APP_PATH, "--quit"], check=True)
        time.sleep(0.3)
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    unittest.main()
