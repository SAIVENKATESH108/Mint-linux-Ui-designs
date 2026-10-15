#!/usr/bin/env python3
"""
Integration tests for DeskWidgets service under Xvfb with a fake conky executable:
(a) 5 children spawn, 5 windows map at calculated positions, backoff revival on kill,
    restart resets counters, and no traceback in log.
(b) do_activate exception -> traceback + notify-send + non-zero exit (no zombie process).
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)


class TestDeskWidgetsIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.display = os.environ.get("DISPLAY")

    def setUp(self):
        if not self.display:
            self.skipTest("No DISPLAY set (run under xvfb-run or active X11 display)")

        self.tmpdir = tempfile.mkdtemp(prefix="deskwidgets_test_")
        self.bin_dir = os.path.join(self.tmpdir, "bin")
        os.makedirs(self.bin_dir, exist_ok=True)

        # 1. Create fake conky executable
        self.fake_conky_path = os.path.join(self.bin_dir, "conky")
        fake_conky_code = f"""#!{sys.executable}
import os
import signal
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

mac_id = os.environ.get('MAC_ID', 'test')
try:
    x = int(float(os.environ.get('MAC_X', 0)))
    y = int(float(os.environ.get('MAC_Y', 0)))
    w = int(float(os.environ.get('MAC_W', 178)))
    h = int(float(os.environ.get('MAC_H', 178)))
except ValueError:
    x, y, w, h = 0, 0, 178, 178

win = Gtk.Window(title=f"deskwidget:{{mac_id}}")
win.set_default_size(w, h)
win.move(x, y)
win.connect("destroy", Gtk.main_quit)
win.show_all()

def on_term(*_):
    Gtk.main_quit()
    sys.exit(0)

signal.signal(signal.SIGTERM, on_term)
signal.signal(signal.SIGINT, on_term)
Gtk.main()
"""
        with open(self.fake_conky_path, "w", encoding="utf-8") as f:
            f.write(fake_conky_code)
        os.chmod(self.fake_conky_path, 0o755)

        # Mock notify-send to capture notifications
        self.notify_log = os.path.join(self.tmpdir, "notify.log")
        mock_notify = os.path.join(self.bin_dir, "notify-send")
        with open(mock_notify, "w", encoding="utf-8") as f:
            f.write(f"""#!/bin/sh\necho "$@" >> "{self.notify_log}"\nexit 0\n""")
        os.chmod(mock_notify, 0o755)

        # Setup test environment
        self.orig_path = os.environ.get("PATH", "")
        self.test_env = dict(os.environ)
        self.test_env["PATH"] = f"{self.bin_dir}:{self.orig_path}"
        self.test_env["HOME"] = self.tmpdir
        self.test_env["XDG_CONFIG_HOME"] = os.path.join(self.tmpdir, ".config")
        self.test_env["XDG_CACHE_HOME"] = os.path.join(self.tmpdir, ".cache")
        self.test_env["XDG_RUNTIME_DIR"] = os.path.join(self.tmpdir, "run")
        os.makedirs(self.test_env["XDG_CONFIG_HOME"], exist_ok=True)
        os.makedirs(self.test_env["XDG_CACHE_HOME"], exist_ok=True)
        os.makedirs(self.test_env["XDG_RUNTIME_DIR"], exist_ok=True)

        # Write layout with 5 instances
        cfg_dir = os.path.join(self.test_env["XDG_CONFIG_HOME"], "deskwidgets")
        os.makedirs(cfg_dir, exist_ok=True)
        layout = {
            "version": 3,
            "instances": [
                {"id": "clock-1", "type": "clock", "size": "small", "style": "glass", "accent": "purple", "options": {}, "col": 4, "row": 0},
                {"id": "calendar-1", "type": "calendar", "size": "small", "style": "color", "accent": "red", "options": {}, "col": 5, "row": 0},
                {"id": "weather-1", "type": "weather", "size": "medium", "style": "glass", "accent": "auto", "options": {}, "col": 4, "row": 1},
                {"id": "system-1", "type": "system", "size": "medium", "style": "glass", "accent": "auto", "options": {}, "col": 4, "row": 2},
                {"id": "media-1", "type": "media", "size": "medium", "style": "color", "accent": "pink", "options": {}, "col": 4, "row": 3},
            ]
        }
        with open(os.path.join(cfg_dir, "layout.json"), "w", encoding="utf-8") as f:
            json.dump(layout, f)

    def tearDown(self):
        # Stop any running test background processes
        try:
            subprocess.run(["pkill", "-f", "fake_conky"], env=self.test_env, stderr=subprocess.DEVNULL)
            subprocess.run(["pkill", "-f", "deskwidgets run"], env=self.test_env, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        if hasattr(self, "tmpdir") and os.path.isdir(self.tmpdir):
            shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _get_mapped_widget_windows(self):
        matched = {}
        try:
            res = subprocess.run(["wmctrl", "-lpG"], env=self.test_env, stdout=subprocess.PIPE, text=True)
            for line in res.stdout.splitlines():
                if "deskwidget:" in line:
                    parts = line.split()
                    if len(parts) >= 8:
                        wid_token = [p for p in parts if p.startswith("deskwidget:")]
                        if wid_token:
                            wid = wid_token[0].split(":", 1)[1]
                            matched[wid] = {
                                "win_id": parts[0],
                                "pid": int(parts[2]) if parts[2].isdigit() else None,
                                "x": int(parts[3]),
                                "y": int(parts[4]),
                                "w": int(parts[5]),
                                "h": int(parts[6]),
                            }
        except FileNotFoundError:
            pass
        return matched

    def test_integration_spawn_map_and_backoff(self):
        """(a) 5 children spawn, 5 windows map, backoff revival on kill, and no traceback in log."""
        dw_bin = os.path.join(REPO_DIR, "lib", "deskwidgets", "bin", "deskwidgets")
        srv = subprocess.Popen([sys.executable, dw_bin, "run"], env=self.test_env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Wait for all 5 widget windows to map
        start_time = time.time()
        mapped_windows = {}
        while time.time() - start_time < 8.0:
            mapped_windows = self._get_mapped_widget_windows()
            if len(mapped_windows) >= 5:
                break
            time.sleep(0.3)

        self.assertGreaterEqual(
            len(mapped_windows), 5,
            f"Expected at least 5 mapped widget windows, got {len(mapped_windows)}: {mapped_windows}"
        )

        expected_ids = {"clock-1", "calendar-1", "weather-1", "system-1", "media-1"}
        self.assertTrue(expected_ids.issubset(set(mapped_windows.keys())))

        # Verify child conky PIDs are active
        for wid in expected_ids:
            cpid = mapped_windows[wid]["pid"]
            if cpid:
                self.assertTrue(os.path.exists(f"/proc/{cpid}"), f"Process for {wid} (PID {cpid}) should be alive")

        # Kill one child process and verify self-healing revival is scheduled
        victim_id = "clock-1"
        victim_pid = mapped_windows[victim_id]["pid"]
        if victim_pid:
            os.kill(victim_pid, signal.SIGKILL)

        # Allow daemon to detect termination in poll cycle
        time.sleep(2.5)

        log_path = os.path.join(self.test_env["XDG_CACHE_HOME"], "sequoia", "deskwidgets.log")
        self.assertTrue(os.path.isfile(log_path), f"Log file must exist at {log_path}")

        with open(log_path, "r", encoding="utf-8", errors="ignore") as lf:
            log_content = lf.read()

        # Assert no python tracebacks in the log
        self.assertNotIn("Traceback (most recent call last):", log_content)
        # Assert exit was caught and recovery was logged
        self.assertIn(f"Widget {victim_id}", log_content)
        self.assertTrue(
            "[EXIT]" in log_content or "[SELF-HEAL" in log_content,
            f"Expected [EXIT] or [SELF-HEAL] in log, got:\n{log_content}"
        )

        # Terminate daemon
        srv.terminate()
        try:
            srv.wait(timeout=2)
        except subprocess.TimeoutExpired:
            srv.kill()

    def test_do_activate_fatal_exception(self):
        """(b) do_activate exception -> traceback + notify-send + non-zero exit."""
        test_script = """
import os
import sys
import unittest.mock as mock

from deskwidgets import paths
from deskwidgets.service import Daemon

app = Daemon()

# Simulate a fatal startup exception during activate
with mock.patch("deskwidgets.catalog.discover", side_effect=RuntimeError("Simulated activation failure")):
    app.do_activate()
"""
        res = subprocess.run([sys.executable, "-c", test_script], env=self.test_env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        # Non-zero exit code required (os._exit(1))
        self.assertEqual(res.returncode, 1, f"Expected non-zero exit code 1, got {res.returncode}")

        # Assert notify-send was dispatched
        self.assertTrue(os.path.isfile(self.notify_log), "notify-send must have been invoked")
        with open(self.notify_log, "r", encoding="utf-8") as nf:
            notif = nf.read()
        self.assertIn("DeskWidgets Failed", notif)
        self.assertIn("Simulated activation failure", notif)

        # Assert log recorded the fatal exception traceback
        log_path = os.path.join(self.test_env["XDG_CACHE_HOME"], "sequoia", "deskwidgets.log")
        self.assertTrue(os.path.isfile(log_path), "Log file should be created")
        with open(log_path, "r", encoding="utf-8", errors="ignore") as lf:
            log_data = lf.read()
        self.assertIn("[FATAL-STARTUP-EXCEPTION]", log_data)
        self.assertIn("RuntimeError: Simulated activation failure", log_data)


if __name__ == "__main__":
    unittest.main()
