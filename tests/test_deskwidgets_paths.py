"""Test deskwidgets.paths ensure_dirs with temporary HOME."""
import importlib
import os
import sys
import tempfile
import unittest

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_DIR = os.path.join(REPO_DIR, "lib", "deskwidgets")
if LIB_DIR not in sys.path:
    sys.path.insert(0, LIB_DIR)


class TestDeskWidgetsPaths(unittest.TestCase):
    def test_ensure_dirs_with_temporary_home(self):
        with tempfile.TemporaryDirectory() as tmp_home:
            old_home = os.environ.get("HOME")
            old_xdg_config = os.environ.get("XDG_CONFIG_HOME")
            old_xdg_cache = os.environ.get("XDG_CACHE_HOME")
            old_xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")

            try:
                os.environ["HOME"] = tmp_home
                os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp_home, ".config")
                os.environ["XDG_CACHE_HOME"] = os.path.join(tmp_home, ".cache")
                os.environ["XDG_RUNTIME_DIR"] = os.path.join(tmp_home, "run")

                import deskwidgets.paths as paths
                importlib.reload(paths)

                # Assert PREVIEWS is defined
                self.assertTrue(hasattr(paths, "PREVIEWS"), "paths.PREVIEWS must be defined")
                self.assertTrue(paths.PREVIEWS.startswith(os.environ["XDG_CACHE_HOME"]))

                # Call ensure_dirs()
                paths.ensure_dirs()

                # Verify all directories were created
                for d in (paths.CONFIG, paths.USER_WIDGETS, paths.CACHE, paths.PREVIEWS, paths.RUN):
                    self.assertTrue(os.path.isdir(d), f"Directory {d} should exist after ensure_dirs()")
            finally:
                if old_home is not None:
                    os.environ["HOME"] = old_home
                if old_xdg_config is not None:
                    os.environ["XDG_CONFIG_HOME"] = old_xdg_config
                elif "XDG_CONFIG_HOME" in os.environ:
                    del os.environ["XDG_CONFIG_HOME"]
                if old_xdg_cache is not None:
                    os.environ["XDG_CACHE_HOME"] = old_xdg_cache
                elif "XDG_CACHE_HOME" in os.environ:
                    del os.environ["XDG_CACHE_HOME"]
                if old_xdg_runtime is not None:
                    os.environ["XDG_RUNTIME_DIR"] = old_xdg_runtime
                elif "XDG_RUNTIME_DIR" in os.environ:
                    del os.environ["XDG_RUNTIME_DIR"]


if __name__ == "__main__":
    unittest.main()
