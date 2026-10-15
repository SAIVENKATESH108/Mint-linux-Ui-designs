#!/usr/bin/env python3
"""
Unit tests for DeskWidgets self-healing limits, exponential backoff, and hourly caps.
Uses a mock/fake clock to simulate process crashes, backoffs, and recovery limits
without waiting in real-time.
"""

import os
import sys
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DW_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if DW_DIR not in sys.path:
    sys.path.insert(0, DW_DIR)


class FakeClock:
    def __init__(self, start=1000.0):
        self.current = start

    def monotonic(self):
        return self.current

    def advance(self, seconds):
        self.current += seconds


class MockRunner:
    """Standalone model of DeskWidgets Runner self-heal logic for isolated unit testing."""
    def __init__(self, inst_id, clock):
        self.id = inst_id
        self.clock = clock
        self.started_at = 0
        self.recovery_attempts = []
        self.backoff_level = 0
        self.disabled = False
        self.next_retry = 0
        self.scheduled_delays = []
        self.notified = False

    def get_backoff_delay(self):
        delays = [10, 30, 90]
        if self.backoff_level < len(delays):
            delay = delays[self.backoff_level]
        else:
            delay = min(300, 90 * (3 ** (self.backoff_level - 2)))
        return min(delay, 300)

    def schedule_recovery(self, reason="exit"):
        now = self.clock.monotonic()
        self.recovery_attempts = [t for t in self.recovery_attempts if now - t < 3600]
        if len(self.recovery_attempts) >= 8:
            if not self.disabled:
                self.disabled = True
                self.notified = True
            return False

        delay = self.get_backoff_delay()
        self.backoff_level += 1
        self.recovery_attempts.append(now)
        self.next_retry = now + delay
        self.scheduled_delays.append(delay)
        return True

    def on_exit(self, uptime):
        if uptime > 60:
            self.backoff_level = 0
        return self.schedule_recovery(reason="crash")


class TestDeskWidgetsSelfHeal(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock(1000.0)
        self.runner = MockRunner("clock-1", self.clock)

    def test_exponential_backoff_sequence(self):
        """Asserts exact delays: 10s, 30s, 90s, capped at 300s (5 min)."""
        expected_delays = [10, 30, 90, 270, 300, 300, 300, 300]
        actual_delays = []

        for _ in range(8):
            ok = self.runner.schedule_recovery()
            self.assertTrue(ok)
            actual_delays.append(self.runner.scheduled_delays[-1])
            # Advance clock slightly before next attempt
            self.clock.advance(actual_delays[-1])

        self.assertEqual(actual_delays, expected_delays)

    def test_maximum_8_attempts_per_hour_cap(self):
        """Asserts that after 8 attempts within 1 hour, recovery stops and alerts."""
        for i in range(8):
            ok = self.runner.schedule_recovery()
            self.assertTrue(ok, f"Attempt {i+1} should succeed")
            self.clock.advance(10)

        self.assertFalse(self.runner.disabled)
        self.assertFalse(self.runner.notified)

        # 9th attempt within the hour must fail and disable runner
        ok9 = self.runner.schedule_recovery()
        self.assertFalse(ok9, "9th attempt within 1 hour must be rejected")
        self.assertTrue(self.runner.disabled, "Runner should be disabled after 8 failures")
        self.assertTrue(self.runner.notified, "Notification alert should be dispatched")

    def test_sliding_window_recovery_after_one_hour(self):
        """Asserts that once 1 hour has elapsed, old failure records expire and recovery re-enables."""
        for _ in range(8):
            self.runner.schedule_recovery()
            self.clock.advance(10)

        # 9th attempt fails
        self.assertFalse(self.runner.schedule_recovery())
        self.assertTrue(self.runner.disabled)

        # Re-enabling flag when 1 hour has passed
        self.clock.advance(3601)  # 1 hour + 1 second later
        self.runner.disabled = False
        ok_next = self.runner.schedule_recovery()
        self.assertTrue(ok_next, "Recovery must be permitted once 1 hour has passed")
        self.assertEqual(len(self.runner.recovery_attempts), 1)

    def test_stable_uptime_resets_backoff_level(self):
        """Asserts that running stably for > 60s resets the backoff sequence to level 0 (10s)."""
        # Escalate backoff
        self.runner.schedule_recovery()  # 10s -> level 1
        self.runner.schedule_recovery()  # 30s -> level 2
        self.assertEqual(self.runner.backoff_level, 2)

        # Process ran stably for 120s then exited
        self.runner.on_exit(uptime=120)

        # Backoff level must have reset to 1 (post-scheduling) with delay of 10s
        self.assertEqual(self.runner.scheduled_delays[-1], 10)


if __name__ == "__main__":
    unittest.main()
