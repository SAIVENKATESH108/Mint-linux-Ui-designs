#!/usr/bin/env python3
"""
Unit tests for DeskWidgets geometry settling and size verification:
- Tests that settle_and_check_geometry waits for transient (1x1) windows to reach true size.
- Tests that size mismatches (e.g. w=1 h=1 vs w=364 h=178) fail the check and report both values.
- Tests that perfectly matched positions and sizes pass with dx, dy, dw, dh <= 4.
"""

import os
import sys
import unittest
from unittest.mock import patch

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)

from deskwidgets.cli import settle_and_check_geometry


class DummyGrid:
    def window_rect(self, col, row, size):
        if size == 'medium':
            return (904, 598, 364, 178)
        return (904, 40, 178, 178)


class TestGeometrySettle(unittest.TestCase):
    def setUp(self):
        self.grid = DummyGrid()
        self.instances = [
            {'id': 'clock-1', 'type': 'clock', 'size': 'small', 'col': 0, 'row': 0},
            {'id': 'media-1', 'type': 'media', 'size': 'medium', 'col': 0, 'row': 3},
        ]

    @patch('deskwidgets.cli.get_live_widget_windows')
    def test_geometry_size_mismatch_fails(self, mock_get_windows):
        """Tests that a 1x1 geometry for media-1 fails the check even if position matches."""
        # media-1 has correct x,y (904, 598) but 1x1 size instead of 364x178
        mock_get_windows.return_value = (1280, 1024, {
            'clock-1': {'x': 904, 'y': 40, 'w': 178, 'h': 178, 'pid': 1001},
            'media-1': {'x': 904, 'y': 598, 'w': 1, 'h': 1, 'pid': 1002},
        })

        all_ok, passed_count, total_count, details = settle_and_check_geometry(
            self.grid, self.instances, timeout=0.1, poll_interval=0.01
        )

        self.assertFalse(all_ok)
        self.assertEqual(passed_count, 1)
        self.assertEqual(total_count, 2)

        media_detail = next(d for d in details if d['id'] == 'media-1')
        self.assertEqual(media_detail['status'], 'FAIL')
        self.assertIn('GEOMETRY MISMATCH', media_detail['reason'])
        self.assertIn('dw=', media_detail['reason'])
        self.assertEqual(media_detail['real'], (904, 598, 1, 1))
        self.assertEqual(media_detail['calc'], (904, 598, 364, 178))

    @patch('deskwidgets.cli.get_live_widget_windows')
    def test_geometry_settles_from_transient_1x1_to_full(self, mock_get_windows):
        """Tests that settle loop waits and passes once transient 1x1 window reaches full size."""
        call_count = [0]

        def side_effect():
            call_count[0] += 1
            if call_count[0] < 3:
                # Still initializing (1x1)
                return (1280, 1024, {
                    'clock-1': {'x': 904, 'y': 40, 'w': 178, 'h': 178, 'pid': 1001},
                    'media-1': {'x': 904, 'y': 598, 'w': 1, 'h': 1, 'pid': 1002},
                })
            else:
                # Settled!
                return (1280, 1024, {
                    'clock-1': {'x': 904, 'y': 40, 'w': 178, 'h': 178, 'pid': 1001},
                    'media-1': {'x': 904, 'y': 598, 'w': 364, 'h': 178, 'pid': 1002},
                })

        mock_get_windows.side_effect = side_effect

        all_ok, passed_count, total_count, details = settle_and_check_geometry(
            self.grid, self.instances, timeout=2.0, poll_interval=0.02
        )

        self.assertTrue(all_ok)
        self.assertEqual(passed_count, 2)
        self.assertGreaterEqual(call_count[0], 3)


if __name__ == '__main__':
    unittest.main()
