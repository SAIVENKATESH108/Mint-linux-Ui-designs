"""
Worker-thread helper for Sequoia UI.
Executes background tasks (file search, AST calculation, data querying)
with a strict timeout budget (default 5.0s), cancellation support,
and safe delivery to the GTK main loop via GLib.idle_add.
"""

import concurrent.futures
import threading
from typing import Callable, Optional, Any


class CancellationToken:
    def __init__(self):
        self._cancelled = threading.Event()

    def cancel(self):
        self._cancelled.set()

    @property
    def is_cancelled(self) -> bool:
        return self._cancelled.is_set()


class WorkerPool:
    def __init__(self, max_workers: int = 4):
        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)

    def submit(
        self,
        task_fn: Callable[..., Any],
        *args,
        timeout: float = 5.0,
        callback: Optional[Callable[[Any], None]] = None,
        on_error: Optional[Callable[[Exception], None]] = None,
        cancel_token: Optional[CancellationToken] = None,
    ):
        """
        Submits task_fn(*args) to thread pool.
        Delivers result to callback(result) on GTK main loop via GLib.idle_add.
        If timeout is exceeded, on_error(TimeoutError) is called.
        """
        def _wrapper():
            if cancel_token and cancel_token.is_cancelled:
                return

            try:
                future = self._executor.submit(task_fn, *args)
                result = future.result(timeout=timeout)

                if cancel_token and cancel_token.is_cancelled:
                    return

                if callback:
                    self._post_to_gtk(callback, result)
            except concurrent.futures.TimeoutError as te:
                if on_error and (not cancel_token or not cancel_token.is_cancelled):
                    self._post_to_gtk(on_error, te)
            except Exception as e:
                if on_error and (not cancel_token or not cancel_token.is_cancelled):
                    self._post_to_gtk(on_error, e)

        t = threading.Thread(target=_wrapper, daemon=True)
        t.start()

    def _post_to_gtk(self, fn: Callable, arg: Any):
        try:
            from gi.repository import GLib
            GLib.idle_add(fn, arg)
        except Exception:
            fn(arg)

    def shutdown(self, wait: bool = False):
        self._executor.shutdown(wait=wait)
