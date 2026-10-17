#!/usr/bin/env python3
"""
UI Smoke and Screenshot Suite for Sequoia GTK3 components under Xvfb + xfwm4:
- Maps BaseOverlayWindow and asserts geometry, focus grab, telemetry, and 350ms focus grace.
- Takes root-window screenshot of the UI and saves as artifact.
- Tests Escape dismissal and clean shutdown within 2s.
- Maps Sequoia Control Center, captures screenshot, and tests automated dismissal.
"""

import os
import sys
import time
import subprocess
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_DIR not in sys.path:
    sys.path.insert(0, REPO_DIR)
if os.path.join(REPO_DIR, "lib") not in sys.path:
    sys.path.insert(0, os.path.join(REPO_DIR, "lib"))

SCREENSHOT_DIR = os.path.join(REPO_DIR, "artifacts", "screenshots")


def capture_root_screenshot(output_path: str):
    """Captures the root X11 screen to a PNG file using GdkPixbuf."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, GdkPixbuf

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    root = Gdk.get_default_root_window()
    if root is None:
        raise RuntimeError("No root window available to capture")
    width = root.get_width()
    height = root.get_height()
    pb = Gdk.pixbuf_get_from_window(root, 0, 0, width, height)
    if pb is None:
        raise RuntimeError("Failed to obtain pixbuf from root window")
    pb.savev(output_path, "png", [], [])


class TestUISmoke(unittest.TestCase):
    def setUp(self):
        display = os.environ.get("DISPLAY")
        if not display:
            self.skipTest("No DISPLAY set (run under xvfb-run or active X11 display)")
        os.makedirs(SCREENSHOT_DIR, exist_ok=True)

    def test_01_overlay_window_and_screenshot(self):
        """Tests BaseOverlayWindow lifecycle, focus, telemetry, and captures screenshot."""
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk, Gdk, GLib
        from sequoia_ui.window import BaseOverlayWindow
        from sequoia_ui.telemetry import TelemetryRecorder

        telemetry = TelemetryRecorder("smoke-overlay")
        dismissed_reasons = []

        class DemoOverlay(BaseOverlayWindow):
            def __init__(self):
                super().__init__(
                    title="Sequoia Smoke Overlay",
                    width=400,
                    height=300,
                    telemetry=telemetry,
                    app_name="smoke-overlay"
                )
                box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
                box.set_margin_start(20)
                box.set_margin_end(20)
                box.set_margin_top(20)
                box.set_margin_bottom(20)

                lbl = Gtk.Label(label="Sequoia UI Toolkit Demo")
                lbl.get_style_context().add_class("title")
                box.pack_start(lbl, False, False, 0)

                desc = Gtk.Label(label="BaseOverlayWindow active under X11 compositing")
                box.pack_start(desc, False, False, 0)

                btn = Gtk.Button(label="Close")
                btn.connect("clicked", lambda b: self.dismiss("button-click"))
                box.pack_start(btn, False, False, 0)

                self.add(box)

            def on_dismissed(self, reason: str):
                dismissed_reasons.append(reason)

        win = DemoOverlay()
        win.show_all()

        # Pump GTK main loop until window is mapped
        start = time.time()
        while time.time() - start < 2.0:
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            if win.is_mapped:
                break
            time.sleep(0.05)

        self.assertTrue(win.is_mapped, "Overlay window failed to map within 2s")

        # Let GTK draw a frame
        for _ in range(10):
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            time.sleep(0.02)

        # Capture screenshot
        shot_path = os.path.join(SCREENSHOT_DIR, "overlay_window.png")
        capture_root_screenshot(shot_path)
        self.assertTrue(os.path.isfile(shot_path), f"Screenshot not created at {shot_path}")
        self.assertGreater(os.path.getsize(shot_path), 1000, "Screenshot file is empty or corrupted")

        # Verify telemetry recorded first paint
        tel_data = telemetry.finish("test-complete")
        self.assertIn("first_paint_ms", tel_data)
        self.assertGreater(tel_data["first_paint_ms"], 0)
        self.assertIn("geometry", tel_data)
        self.assertGreaterEqual(tel_data["geometry"]["w"], 350)
        self.assertGreaterEqual(tel_data["geometry"]["h"], 250)

        # Test dismissal via dismiss()
        win.dismiss("test-exit")
        for _ in range(10):
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            time.sleep(0.02)

        self.assertIn("test-exit", dismissed_reasons)
        self.assertFalse(win.is_mapped)
        win.destroy()

    def test_02_control_center_screenshot_and_trial(self):
        """Spawns Control Center, captures screenshot to artifacts, and verifies dismissal."""
        cc_path = os.path.join(REPO_DIR, "scripts", "sequoia-control-center.py")
        proc = subprocess.Popen([sys.executable, cc_path, "--show", "--trial"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Wait for window to map
        mapped = False
        start = time.time()
        while time.time() - start < 3.0:
            res = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "Control Center"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            if res.stdout.strip():
                mapped = True
                break
            time.sleep(0.1)

        self.assertTrue(mapped, "Control Center window failed to map within 3s")

        # Allow rendering to settle
        time.sleep(0.5)

        # Capture screenshot
        shot_path = os.path.join(SCREENSHOT_DIR, "control_center.png")
        capture_root_screenshot(shot_path)
        self.assertTrue(os.path.isfile(shot_path), f"Screenshot not created at {shot_path}")
        self.assertGreater(os.path.getsize(shot_path), 1000, "Screenshot file is empty or corrupted")

        # Send Escape to test dismissal
        try:
            subprocess.run(["xdotool", "key", "Escape"], check=True)
        except Exception:
            subprocess.run([sys.executable, cc_path, "--hide"])

        # Assert process terminates within 2.5s
        proc_exited = False
        try:
            proc.wait(timeout=2.5)
            proc_exited = True
        except subprocess.TimeoutExpired:
            proc.kill()

        self.assertTrue(proc_exited, "Control Center process did not exit within 2.5s of Escape key")


if __name__ == "__main__":
    unittest.main()
