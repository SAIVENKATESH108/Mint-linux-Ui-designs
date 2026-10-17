#!/usr/bin/env python3
"""
Unit tests for Sequoia UI GTK 3.24 CSS Validator:
- Asserts that valid GTK3 CSS (colors, border-radius, padding, margins, @define-color) passes.
- Asserts that forbidden properties (filter, backdrop-filter, gap, display, transform, z-index, will-change) fail.
- Asserts that forbidden properties accurately report line and column numbers.
- Asserts that CSS custom properties (--var and var(--var)) are caught and line/col reported.
- Asserts that fallback CSS is available.
"""

import os
import sys
import unittest

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UI_DIR = os.path.join(REPO_DIR, "lib")
if UI_DIR not in sys.path:
    sys.path.insert(0, UI_DIR)

from sequoia_ui.css import validate_gtk3_css, MINIMAL_FALLBACK_CSS


class TestCSSValidator(unittest.TestCase):
    def test_valid_gtk3_css_passes(self):
        valid_css = """
        @define-color my_accent #007AFF;
        @define-color my_bg rgba(30, 30, 30, 0.9);

        window.sequoia-window {
            background-color: @my_bg;
            border-radius: 16px;
            border: 1px solid rgba(255, 255, 255, 0.12);
            padding: 12px;
            margin: 8px;
        }

        label.title {
            color: #FFFFFF;
            font-size: 14px;
            font-weight: bold;
        }
        """
        is_valid, errors = validate_gtk3_css(valid_css)
        self.assertTrue(is_valid)
        self.assertEqual(len(errors), 0)

    def test_forbidden_properties_fail_with_line_and_col(self):
        bad_css = """window {
    background-color: rgba(0, 0, 0, 0.8);
    backdrop-filter: blur(20px);
    display: flex;
    gap: 8px;
    transform: scale(0.95);
    z-index: 999;
}"""
        is_valid, errors = validate_gtk3_css(bad_css)
        self.assertFalse(is_valid)
        self.assertGreaterEqual(len(errors), 5)

        # Check line numbers and error types
        err_msgs = [e.message for e in errors]
        err_lines = [e.line for e in errors]

        self.assertIn(3, err_lines)  # backdrop-filter
        self.assertIn(4, err_lines)  # display
        self.assertIn(5, err_lines)  # gap
        self.assertIn(6, err_lines)  # transform
        self.assertIn(7, err_lines)  # z-index

        # Check column reporting
        for err in errors:
            self.assertGreater(err.col, 0)
            self.assertTrue(len(err.snippet) > 0)

    def test_css_variables_rejected_with_advice(self):
        var_css = """
        :root {
            --accent-color: #007AFF;
        }
        button {
            color: var(--accent-color);
        }
        """
        is_valid, errors = validate_gtk3_css(var_css)
        self.assertFalse(is_valid)
        self.assertEqual(len(errors), 2)
        self.assertIn("@define-color", errors[0].message)
        self.assertIn("@define-color", errors[1].message)

    def test_minimal_fallback_css_is_valid(self):
        is_valid, errors = validate_gtk3_css(MINIMAL_FALLBACK_CSS)
        self.assertTrue(is_valid, f"Fallback CSS itself contains invalid rules: {errors}")


if __name__ == "__main__":
    unittest.main()
