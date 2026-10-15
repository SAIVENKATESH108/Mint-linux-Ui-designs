"""Small helpers shared by the service, the gallery and the CLI."""
import datetime
import logging
from logging.handlers import RotatingFileHandler
import os
import sys

_logger = None

def _get_logger():
    global _logger
    if _logger is not None:
        return _logger

    _logger = logging.getLogger("deskwidgets")
    _logger.setLevel(logging.INFO)
    _logger.propagate = False

    # Console handler
    ch = logging.StreamHandler(sys.stderr)
    ch.setLevel(logging.INFO)
    formatter = logging.Formatter("[%(asctime)s] [PID %(process)d] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    ch.setFormatter(formatter)
    _logger.addHandler(ch)

    # Rotating file handler: ~/.cache/sequoia/deskwidgets.log (1 MB rotation, 3 backups)
    log_dir = os.path.expanduser("~/.cache/sequoia")
    try:
        os.makedirs(log_dir, exist_ok=True)
        log_file = os.path.join(log_dir, "deskwidgets.log")
        fh = RotatingFileHandler(log_file, maxBytes=1024 * 1024, backupCount=3, encoding="utf-8")
        fh.setLevel(logging.INFO)
        fh.setFormatter(formatter)
        _logger.addHandler(fh)
    except Exception as e:
        sys.stderr.write(f"deskwidgets: warning: cannot initialize file logger in {log_dir}: {e}\n")

    return _logger


def log(msg):
    logger = _get_logger()
    logger.info(msg)


def write_atomic(path, text):
    tmp = f'{path}.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, path)


def clean(s):
    """One-line value for the key=value caches read by the Lua widgets."""
    return ' '.join(str(s).split()).replace('|', '/')
