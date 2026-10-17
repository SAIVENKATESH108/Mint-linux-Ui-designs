"""
Conky dry-run output parser, environment builder, and classifier.
Classifies lines into INFO, WARN, and ERROR according to explicit regex patterns:
- INFO: Known benign conky startup/geometry lines, X11 subwindow reports, normal log lines.
- WARN: Fontconfig configuration notices, non-fatal deprecation warnings.
- ERROR: Fatal errors (cannot open, lua error, attempt to index/concat nil, segfault, signal).

The check fails ONLY on ERROR or non-zero exit code, and reports which line caused the failure.
Warnings are printed as warnings without failing the test run.
"""

import argparse
import json
import os
import re
import subprocess
import sys

# Explicit classification patterns
PATTERNS_INFO = [
    re.compile(r"^conky:\s+desktop window\b", re.IGNORECASE),
    re.compile(r"^conky:\s+window type\b", re.IGNORECASE),
    re.compile(r"^conky:\s+drawing to\b", re.IGNORECASE),
    re.compile(r"^conky:\s+forked to background\b", re.IGNORECASE),
    re.compile(r"^conky:\s+X [0-9]+\b", re.IGNORECASE),
    re.compile(r"^conky:\s+.*\b(starting up|compiled|version)\b", re.IGNORECASE),
    re.compile(r"^deskwidgets:\s+.*", re.IGNORECASE),
    re.compile(r"^\s*$"),
]

PATTERNS_WARN = [
    re.compile(r"^Fontconfig\s+error:\s+Cannot load default config file", re.IGNORECASE),
    re.compile(r"^Fontconfig\s+warning:", re.IGNORECASE),
    re.compile(r"^Fontconfig\s+error:", re.IGNORECASE),
    re.compile(r".*\b(deprecated|deprecation)\b.*", re.IGNORECASE),
    re.compile(r".*\bGLib-GObject-WARNING\b.*", re.IGNORECASE),
    re.compile(r".*\bdbind-WARNING\b.*", re.IGNORECASE),
]

PATTERNS_ERROR = [
    re.compile(r".*\bcannot open\b.*", re.IGNORECASE),
    re.compile(r".*\battempt to (concatenate|index|call|perform arithmetic)\b.*", re.IGNORECASE),
    re.compile(r".*\blua error\b.*", re.IGNORECASE),
    re.compile(r".*\bsyntax error\b.*", re.IGNORECASE),
    re.compile(r".*\b(segfault|segmentation fault)\b.*", re.IGNORECASE),
    re.compile(r".*\b(terminat|abort|kill).*signal\s+\d+.*", re.IGNORECASE),
    re.compile(r".*\bfailed to (load|execute|parse|open)\b.*", re.IGNORECASE),
    re.compile(r".*\bfatal\b.*", re.IGNORECASE),
    re.compile(r".*\bNo such file or directory\b.*", re.IGNORECASE),
]


def classify_conky_line(line: str) -> str:
    """Classifies an individual conky output line as 'ERROR', 'WARN', or 'INFO'."""
    line_clean = line.strip()
    if not line_clean:
        return "INFO"

    # Check fatal errors first
    for pat in PATTERNS_ERROR:
        if pat.search(line_clean):
            return "ERROR"

    # Check non-fatal warnings next
    for pat in PATTERNS_WARN:
        if pat.search(line_clean):
            return "WARN"

    # Check known info lines
    for pat in PATTERNS_INFO:
        if pat.search(line_clean):
            return "INFO"

    # Unrecognized lines default to INFO
    return "INFO"


def evaluate_conky_output(exit_code: int, raw_output: str) -> dict:
    """
    Evaluates conky dry-run exit code and output text.
    Returns dict:
      status: 'PASS', 'PASS_WARN', or 'FAIL'
      reason: Explanatory human-readable summary
      info_lines: list of INFO strings
      warn_lines: list of WARN strings
      error_lines: list of ERROR strings
    """
    lines = raw_output.splitlines()
    info_lines = []
    warn_lines = []
    error_lines = []

    for ln in lines:
        c = classify_conky_line(ln)
        if c == "ERROR":
            error_lines.append(ln.strip())
        elif c == "WARN":
            warn_lines.append(ln.strip())
        else:
            if ln.strip():
                info_lines.append(ln.strip())

    if exit_code != 0:
        status = "FAIL"
        reason = f"Exit code {exit_code}"
    elif error_lines:
        status = "FAIL"
        reason = f"Error detected in output: {error_lines[0]}"
    elif warn_lines:
        status = "PASS_WARN"
        reason = f"Exit code 0, 1 test iteration completed with {len(warn_lines)} warning(s)"
    else:
        status = "PASS"
        reason = "Exit code 0, 1 test iteration completed, zero errors"

    return {
        "status": status,
        "reason": reason,
        "info_lines": info_lines,
        "warn_lines": warn_lines,
        "error_lines": error_lines,
    }


def read_proc_environ(pid: int) -> dict:
    """Reads /proc/<pid>/environ returning environment key-value pairs."""
    env_file = f"/proc/{pid}/environ"
    if not os.path.exists(env_file):
        return {}
    try:
        with open(env_file, "rb") as f:
            data = f.read()
        entries = data.split(b"\0")
        env = {}
        for entry in entries:
            if not entry:
                continue
            try:
                k, v = entry.decode("utf-8", errors="replace").split("=", 1)
                env[k] = v
            except ValueError:
                pass
        return env
    except OSError:
        return {}


def read_proc_cwd(pid: int) -> str:
    """Reads /proc/<pid>/cwd returning the target directory."""
    cwd_link = f"/proc/{pid}/cwd"
    try:
        return os.readlink(cwd_link)
    except OSError:
        return ""


def compare_environments(target_env: dict, base_env: dict, keys_to_check: list = None) -> list:
    """Returns human-readable diff list between target_env and base_env."""
    if keys_to_check is None:
        keys_to_check = [
            "FONTCONFIG_FILE",
            "MAC_ENGINE",
            "MAC_WIDGET_DIR",
            "MAC_RUN",
            "MAC_CONFIG",
            "XDG_RUNTIME_DIR",
            "DISPLAY",
            "XAUTHORITY",
            "PATH",
        ]
    diffs = []
    for k in keys_to_check:
        vt = target_env.get(k)
        vb = base_env.get(k)
        if vt != vb:
            diffs.append(f"{k} (target: '{vt}' != caller: '{vb}')")
    return diffs


def run_dryrun(conf_path: str, widget_dir: str, env: dict, cwd: str, timeout_sec: float = 3.0) -> tuple:
    """Executes conky -c <conf_path> -i 1 in cwd with env."""
    cmd = ["conky", "-c", conf_path, "-i", "1"]
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_sec,
        )
        return proc.returncode, proc.stdout
    except subprocess.TimeoutExpired:
        return 124, "Dry-run timed out after 3 seconds"
    except FileNotFoundError:
        return 127, "'conky' binary not found in PATH"
    except Exception as e:
        return 1, f"Failed to execute dry-run: {e}"


def main():
    parser = argparse.ArgumentParser(description="Conky dry-run classifier and runner")
    parser.add_argument("exit_code", nargs="?", default=None, help="Exit code if evaluating pre-captured output")
    parser.add_argument("output_source", nargs="?", default=None, help="File path or '-' for stdin")
    parser.add_argument("--run", action="store_true", help="Execute conky dryrun directly")
    parser.add_argument("--conf", help="Path to widget.conf")
    parser.add_argument("--widget-dir", help="Path to widget directory")
    parser.add_argument("--pid", type=int, help="PID of running service or conky instance")
    parser.add_argument("--json", action="store_true", help="Output JSON results")

    args = parser.parse_args()

    # Evaluation mode from file or stdin
    if not args.run:
        if args.exit_code is None or args.output_source is None:
            parser.print_help()
            sys.exit(1)
        try:
            code = int(args.exit_code)
        except ValueError:
            code = 1
        if args.output_source == "-":
            content = sys.stdin.read()
        else:
            try:
                with open(args.output_source, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
            except OSError as e:
                content = f"cannot open {args.output_source}: {e}"
                code = 1
        res = evaluate_conky_output(code, content)
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(f"Status: {res['status']} ({res['reason']})")
        sys.exit(0 if res["status"] in ("PASS", "PASS_WARN") else 1)

    # Runner mode
    conf_path = args.conf or os.path.expanduser("~/.local/share/deskwidgets/engine/widget.conf")
    engine_dir = os.path.dirname(conf_path)
    widget_dir = args.widget_dir or os.path.expanduser("~/.local/share/deskwidgets/widgets/clock")

    # Inherit or build environment
    target_env = os.environ.copy()
    diffs = []
    service_cwd = engine_dir

    if args.pid and os.path.exists(f"/proc/{args.pid}"):
        proc_env = read_proc_environ(args.pid)
        proc_cwd = read_proc_cwd(args.pid)
        if proc_env:
            target_env.update(proc_env)
            diffs = compare_environments(proc_env, os.environ)
        if proc_cwd and os.path.isdir(proc_cwd):
            service_cwd = proc_cwd

    # Ensure required MAC_* and FONTCONFIG_FILE variables are present
    target_env.setdefault("MAC_ENGINE", engine_dir)
    target_env.setdefault("MAC_WIDGET_DIR", widget_dir)
    target_env.setdefault("MAC_ID", "dryrun-clock")
    target_env.setdefault("MAC_TYPE", "clock")
    target_env.setdefault("MAC_SIZE", "small")
    target_env.setdefault("MAC_STYLE", "auto")
    target_env.setdefault("MAC_W", "178")
    target_env.setdefault("MAC_H", "178")
    target_env.setdefault("MAC_X", "0")
    target_env.setdefault("MAC_Y", "0")
    target_env.setdefault("MAC_SCALE", "1.0")
    target_env.setdefault("MAC_LANG", "en")
    target_env.setdefault("MAC_RUN", os.path.expanduser("~/.cache/deskwidgets/run"))
    target_env.setdefault("MAC_CONFIG", os.path.expanduser("~/.config/deskwidgets"))

    # If FONTCONFIG_FILE not set or invalid, use XDG_RUNTIME_DIR/deskwidgets/fonts.conf
    xdg_runtime = target_env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    fc_path = os.path.join(xdg_runtime, "deskwidgets", "fonts.conf")
    if "FONTCONFIG_FILE" not in target_env or not os.path.exists(target_env["FONTCONFIG_FILE"]):
        if os.path.exists(fc_path):
            target_env["FONTCONFIG_FILE"] = fc_path

    code, raw_out = run_dryrun(conf_path, widget_dir, target_env, service_cwd, timeout_sec=3.0)
    res = evaluate_conky_output(code, raw_out)
    res["diffs"] = diffs
    res["cwd"] = service_cwd

    if args.json:
        print(json.dumps(res, indent=2))
    else:
        print(f"CWD: {service_cwd}")
        if diffs:
            print("Environment Diffs vs Caller [MEASURED]:")
            for d in diffs:
                print(f"  • {d}")
        else:
            print("Environment Diffs vs Caller [MEASURED]: (none, identical)")
        print(f"Result: {res['status']} ({res['reason']})")
        if res["warn_lines"]:
            print("Warnings:")
            for w in res["warn_lines"]:
                print(f"  [WARN] {w}")
        if res["error_lines"]:
            print("Errors:")
            for e in res["error_lines"]:
                print(f"  [ERROR] {e}")

    sys.exit(0 if res["status"] in ("PASS", "PASS_WARN") else 1)


if __name__ == "__main__":
    main()
