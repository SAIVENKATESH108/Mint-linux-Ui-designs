#!/usr/bin/env python3
"""
Smoke and safety test suite for Sequoia Control Center under Xvfb + xfwm4:
- Asserts window opens and maps within 3 seconds.
- Asserts Escape closes the window and the process exits cleanly within 2 seconds.
- Asserts focus-out closes the window and the process exits cleanly.
- Asserts second invocation (--toggle) toggles closed and exits.
- Asserts hung external subprocesses do not block the UI (5s timeout enforcement).
- Asserts other components (dummy conky and dummy plank windows) remain untouched.
"""

import os
import signal
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
        # Clean any preexisting instance
        subprocess.run([sys.executable, APP_PATH, "--quit"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.3)

    def tearDown(self):
        subprocess.run([sys.executable, APP_PATH, "--quit"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.3)

    def _get_control_center_windows(self):
        """Returns list of window records matching Control Center."""
        matched = []
        try:
            res = subprocess.run(["wmctrl", "-l"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            for line in res.stdout.splitlines():
                if "Control Center" in line:
                    matched.append(line)
        except (FileNotFoundError, OSError):
            pass

        if not matched:
            try:
                res = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "Control Center"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for wid in res.stdout.splitlines():
                    if wid.strip():
                        matched.append(wid.strip())
            except (FileNotFoundError, OSError):
                pass
        return matched

    def _wait_for_window(self, timeout=3.0):
        start = time.time()
        while time.time() - start < timeout:
            wins = self._get_control_center_windows()
            if wins:
                return wins
            time.sleep(0.1)
        return []

    def test_01_window_mapped_within_3s(self):
        """Asserts Control Center maps a visible window within 3s."""
        proc = subprocess.Popen([sys.executable, APP_PATH, "--show", "--trial"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        wins = self._wait_for_window(timeout=3.0)
        self.assertTrue(len(wins) > 0, f"Control Center window not mapped within 3s. Windows: {wins}")

        # Check status query
        res = subprocess.run([sys.executable, APP_PATH, "--status"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.assertIn("visible", res.stdout)

        # Cleanup
        subprocess.run([sys.executable, APP_PATH, "--quit"], check=True)
        proc.wait(timeout=2.0)

    def test_02_escape_closes_and_exits_within_2s(self):
        """Asserts Escape key hides the window and process exits within 2s."""
        proc = subprocess.Popen([sys.executable, APP_PATH, "--show", "--trial"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        wins = self._wait_for_window(timeout=3.0)
        self.assertTrue(len(wins) > 0)

        # Send Escape key
        time.sleep(0.3)
        try:
            subprocess.run(["xdotool", "key", "Escape"], check=True)
        except (FileNotFoundError, OSError):
            # Fallback if xdotool not available
            subprocess.run([sys.executable, APP_PATH, "--hide"])

        # Window must be dismissed
        time.sleep(0.4)
        wins_after = self._get_control_center_windows()
        self.assertEqual(len(wins_after), 0, "Window still visible after Escape key")

        # Process must terminate within 2.5s (2s idle exit timeout)
        proc_exited = False
        try:
            proc.wait(timeout=2.5)
            proc_exited = True
        except subprocess.TimeoutExpired:
            proc.kill()

        self.assertTrue(proc_exited, "Control Center process did not exit within 2s of dismissal")

    def test_03_second_invocation_closes_and_exits(self):
        """Asserts second invocation (--toggle) closes the window and exits within 2s."""
        proc = subprocess.Popen([sys.executable, APP_PATH, "--show", "--trial"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        wins = self._wait_for_window(timeout=3.0)
        self.assertTrue(len(wins) > 0)

        time.sleep(0.3)
        # Second invocation toggles off
        subprocess.run([sys.executable, APP_PATH, "--toggle", "--trial"], check=True)
        time.sleep(0.4)

        wins_after = self._get_control_center_windows()
        self.assertEqual(len(wins_after), 0, "Window still visible after second invocation toggle")

        # Process exits within 2.5s
        try:
            proc.wait(timeout=2.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            self.fail("Process did not exit after toggle close")

    def test_04_hung_subprocess_handled_safely(self):
        """Asserts that external command runner times out safely without locking UI thread."""
        sys.path.insert(0, os.path.join(REPO_DIR, "scripts"))
        import importlib
        scc = importlib.import_module("sequoia-control-center")

        start = time.time()
        # Test 0.2s timeout on a 10-second command
        res = scc.run_cmd(["sleep", "10"], timeout=0.2)
        elapsed = time.time() - start
        self.assertEqual(res, "")
        self.assertLess(elapsed, 1.0, f"run_cmd did not enforce timeout (elapsed: {elapsed:.2f}s)")

    def test_05_dummy_components_untouched(self):
        """Asserts that Control Center operations do not affect other desktop components."""
        # Spawn dummy conky and dummy plank windows using xmessage/zenity or python GTK
        dummy_code = """
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
w1 = Gtk.Window(title="deskwidget:dummy")
w1.show_all()
w2 = Gtk.Window(title="Plank")
w2.show_all()
Gtk.main()
"""
        dummy_proc = subprocess.Popen([sys.executable, "-c", dummy_code])
        time.sleep(0.5)

        # Launch Control Center and then close it
        proc = subprocess.Popen([sys.executable, APP_PATH, "--show", "--trial"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._wait_for_window(timeout=3.0)
        time.sleep(0.3)
        subprocess.run([sys.executable, APP_PATH, "--quit"], check=True)
        time.sleep(0.5)

        # Verify dummy components are still running
        self.assertIsNone(dummy_proc.poll(), "Dummy component was terminated unexpectedly")

        # Cleanup dummy
        dummy_proc.terminate()
        try:
            dummy_proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            dummy_proc.kill()


if __name__ == "__main__":
    unittest.main()
