#!/usr/bin/env python3
"""
Unit tests for DeskWidgets layout, anchoring, and non-overlapping geometry.
Asserts that all widget windows sit strictly within the 1280x1024 monitor workarea,
below the 28px top bar, with 16px margins and 16px gaps, and have ZERO overlaps.
"""

import os
import sys
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)

from deskwidgets.grid import Grid, BASE_MARGIN, BASE_CELL


class TestDeskWidgetsLayout(unittest.TestCase):
    def setUp(self):
        # 1280x1024 monitor geometry, 28px top bar, 16px outer margin, 16px gap
        self.screen_w = 1280
        self.screen_h = 1024
        self.top_bar_h = 28
        self.settings = {
            'scale': 1.0,
            'gap': 16,
            'margin_top': 44,      # 28px top bar + 16px outer margin
            'margin_side': 16,     # 16px right outer margin
            'margin_bottom': 72,   # 72px dock margin
        }
        self.grid = Grid(self.screen_w, self.screen_h, self.settings)

        # Standard 5-widget suite
        self.instances = [
            {'id': 'clock-1', 'size': 'small', 'col': 4, 'row': 0},
            {'id': 'calendar-1', 'size': 'small', 'col': 5, 'row': 0},
            {'id': 'weather-1', 'size': 'medium', 'col': 4, 'row': 1},
            {'id': 'system-1', 'size': 'medium', 'col': 4, 'row': 2},
            {'id': 'media-1', 'size': 'medium', 'col': 4, 'row': 3},
        ]

    def test_minimized_transparent_padding(self):
        """Asserts that window transparent padding is minimized (<= 4px) to eliminate ghost outlines."""
        self.assertLessEqual(BASE_MARGIN, 4, f"BASE_MARGIN is {BASE_MARGIN}, expected <= 4px")
        self.assertLessEqual(self.grid.margin, 4, f"Grid margin is {self.grid.margin}, expected <= 4px")

    def test_system_widget_position_not_centered(self):
        """Asserts that system widget is right-anchored in the widget stack and NOT misplaced at x=639."""
        wx, wy, ww, wh = self.grid.window_rect(4, 2, 'medium')
        cx, cy, cw, ch = self.grid.card_rect(4, 2, 'medium')

        self.assertNotEqual(wx, 639, "System widget window x is 639 (centered anomaly), expected right-anchored column")
        self.assertNotEqual(cx, 639, "System widget card x is 639, expected right-anchored column")

        # Card right edge must align exactly with monitor right margin (1280 - 16 = 1264)
        self.assertEqual(cx + cw, self.screen_w - 16, f"Card right edge is {cx + cw}, expected {self.screen_w - 16}")

    def test_all_widgets_right_anchored_with_16px_margin(self):
        """Asserts that the rightmost edge of every row aligns with screen_w - 16px."""
        expected_right_edge = self.screen_w - self.settings['margin_side']  # 1264

        # Row 0: calendar-1 is in column 5
        cx_cal, _, cw_cal, _ = self.grid.card_rect(5, 0, 'small')
        self.assertEqual(cx_cal + cw_cal, expected_right_edge)

        # Rows 1, 2, 3: medium widgets in column 4 (span cols 4 and 5)
        for inst in [self.instances[2], self.instances[3], self.instances[4]]:
            cx, _, cw, _ = self.grid.card_rect(inst['col'], inst['row'], inst['size'])
            self.assertEqual(cx + cw, expected_right_edge, f"{inst['id']} right edge misaligned")

    def test_windows_must_not_overlap(self):
        """Calculates bounding rectangles for all widget windows and asserts ZERO overlaps."""
        rects = []
        for inst in self.instances:
            wx, wy, ww, wh = self.grid.window_rect(inst['col'], inst['row'], inst['size'])
            rects.append({'id': inst['id'], 'x': wx, 'y': wy, 'w': ww, 'h': wh})

        overlaps = []
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                r1 = rects[i]
                r2 = rects[j]
                # Overlap condition: intersection in both X and Y
                if (r1['x'] < r2['x'] + r2['w'] and r1['x'] + r1['w'] > r2['x'] and
                    r1['y'] < r2['y'] + r2['h'] and r1['y'] + r1['h'] > r2['y']):
                    overlaps.append(f"{r1['id']} overlaps with {r2['id']}")

        self.assertEqual(overlaps, [], f"Found overlapping widget windows: {overlaps}")

    def test_cards_vertical_gaps_are_16px(self):
        """Asserts that the vertical gap between consecutive rows is exactly 16px."""
        # Row 0 vs Row 1
        _, cy0, _, ch0 = self.grid.card_rect(4, 0, 'small')
        _, cy1, _, ch1 = self.grid.card_rect(4, 1, 'medium')
        self.assertEqual(cy1 - (cy0 + ch0), 16, f"Gap between row 0 and row 1 is {cy1 - (cy0 + ch0)}")

        # Row 1 vs Row 2
        _, cy2, _, ch2 = self.grid.card_rect(4, 2, 'medium')
        self.assertEqual(cy2 - (cy1 + ch1), 16, f"Gap between row 1 and row 2 is {cy2 - (cy1 + ch1)}")

        # Row 2 vs Row 3
        _, cy3, _, ch3 = self.grid.card_rect(4, 3, 'medium')
        self.assertEqual(cy3 - (cy2 + ch2), 16, f"Gap between row 2 and row 3 is {cy3 - (cy2 + ch2)}")

    def test_all_widgets_within_screen_and_below_top_bar(self):
        """Asserts that all windows sit entirely below the 28px bar and inside 1280x1024."""
        for inst in self.instances:
            wx, wy, ww, wh = self.grid.window_rect(inst['col'], inst['row'], inst['size'])
            self.assertGreaterEqual(wy, self.top_bar_h, f"{inst['id']} overlaps with top bar (y={wy})")
            self.assertGreaterEqual(wx, 0, f"{inst['id']} off-screen left (x={wx})")
            self.assertLessEqual(wx + ww, self.screen_w, f"{inst['id']} off-screen right (x2={wx+ww})")
            self.assertLessEqual(wy + wh, self.screen_h, f"{inst['id']} off-screen bottom (y2={wy+wh})")


if __name__ == "__main__":
    unittest.main()
