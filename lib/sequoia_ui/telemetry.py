"""
Telemetry helper for Sequoia UI applications.
Measures:
- Window geometry (x, y, w, h) and alignment gap below 28px panel
- Exact dismissal reason (Escape, focus-out, inactivity, window-close, shortcut, toggle)
- First paint latency / open duration
- Resident Set Size (RSS) memory in MB (from /proc/self/statm)
Writes persistent JSON telemetry to ~/.cache/sequoia/{app_name}-status.json.
"""

import json
import os
import time
from typing import Dict, Any, Optional, Tuple


def get_process_rss_mb() -> float:
    """Returns the current process RSS memory consumption in MB."""
    try:
        with open("/proc/self/statm", "r") as f:
            parts = f.read().split()
            if len(parts) >= 2:
                pages = int(parts[1])
                page_size = os.sysconf("SC_PAGE_SIZE")
                return round((pages * page_size) / (1024 * 1024), 2)
    except Exception:
        pass

    try:
        import resource
        usage = resource.getrusage(resource.RUSAGE_SELF)
        # Linux ru_maxrss is in KB
        return round(usage.ru_maxrss / 1024.0, 2)
    except Exception:
        return 0.0


def record_telemetry(
    app_name: str,
    mapped: bool,
    reason: str = "open",
    map_time: Optional[float] = None,
    paint_time: Optional[float] = None,
    pos: Optional[Tuple[int, int]] = None,
    size: Optional[Tuple[int, int]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Records application telemetry snapshot to ~/.cache/sequoia/{app_name}-status.json."""
    cache_dir = os.path.expanduser("~/.cache/sequoia")
    os.makedirs(cache_dir, exist_ok=True)
    status_file = os.path.join(cache_dir, f"{app_name}-status.json")

    open_dur = 0.0
    if map_time:
        open_dur = round(time.time() - map_time, 2)

    first_paint_ms = 0.0
    if paint_time and map_time:
        first_paint_ms = round((paint_time - map_time) * 1000.0, 1)

    pos_x, pos_y = pos if pos else (0, 0)
    size_w, size_h = size if size else (0, 0)
    top_bar_gap = pos_y - 28 if pos_y >= 28 else 0

    data = {
        "app": app_name,
        "pid": os.getpid(),
        "mapped": mapped,
        "reason": reason,
        "time_open_sec": open_dur,
        "time_to_first_paint_ms": first_paint_ms,
        "rss_mb": get_process_rss_mb(),
        "x": pos_x,
        "y": pos_y,
        "w": size_w,
        "h": size_h,
        "top_bar_gap": top_bar_gap,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    if extra:
        data.update(extra)

    try:
        with open(status_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass

    return data
