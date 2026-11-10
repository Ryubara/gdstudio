"""The `service` kind of agent evals: a backend delivered in `service/`, judged by its own tests, lint, a contract suite
run against the live process and what it logs (docs/studio/agent-evals.md#a-task).

The contract is HTTP and the environment, so the delivery may use any framework: it starts from `service/` with
`uv run python -m lobby` (the project's own `pyproject.toml`), takes its settings from environment variables, and the
task's `acceptance/test_acceptance.py` (standard library only) talks to it like any client.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path

Log = Callable[[str], None]
RUFF = "ruff==0.17.3"  # the kit's pin (python/uv.lock)
RUFF_ARGS = ["--isolated", "--line-length", "120", "--target-version", "py312"]
RUFF_RULES = "E,F,W,I,UP,B,SIM"
TOKEN = "eval-token-4f9c1b7a2d"
HOST = "games.example.test"
PORT_BASE = 7000
SETTINGS = ("PORT", "API_TOKEN", "GAME_SERVER_HOST", "GAME_SERVER_PORT_BASE")
START_WAIT = 120  # seconds for the first start: `uv run` may install the delivery's dependencies


def prepare(folder: Path, target: Path) -> None:
    """The eval folder of a service task: the brief is already there; the delivery goes in `service/`."""
    (target / "service").mkdir(exist_ok=True)


def _row(rows: list[dict], name: str, value, op: str, limit) -> None:
    ok = {"==": lambda: value == limit, "<=": lambda: value <= limit, ">=": lambda: value >= limit}[op]()
    rows.append({"name": name, "value": value, "op": op, "limit": limit, "unit": "", "pass": bool(ok)})


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _run(cmd: list[str], cwd: Path, timeout: int, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout, env=env
    )


def start(service: Path, port: int, log_path: Path, token: str | None = TOKEN) -> subprocess.Popen:
    """Start the delivery in `service/` on `port` with the task's environment, its output going to `log_path`."""
    env = {k: v for k, v in os.environ.items() if k not in SETTINGS}
    env.update({"PORT": str(port), "GAME_SERVER_HOST": HOST, "GAME_SERVER_PORT_BASE": str(PORT_BASE)})
    env["PYTHONUNBUFFERED"] = "1"
    if token is not None:
        env["API_TOKEN"] = token
    out = log_path.open("wb")
    flags = {"start_new_session": True} if sys.platform != "win32" else {}
    return subprocess.Popen(
        ["uv", "run", "--project", str(service), "python", "-m", "lobby"],
        cwd=service,
        env=env,
        stdout=out,
        stderr=subprocess.STDOUT,
        **flags,
    )


def stop(proc: subprocess.Popen) -> None:
    """End the process and everything it started (`uv run` starts the server as a child)."""
    if proc.poll() is None:
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        else:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()


def wait_healthy(url: str, proc: subprocess.Popen, seconds: float) -> bool:
    """True once `GET /health` answers 200 while the process is still running."""
    end = time.monotonic() + seconds
    while time.monotonic() < end and proc.poll() is None:
        try:
            with urllib.request.urlopen(url + "/health", timeout=2) as response:
                if response.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            time.sleep(0.3)
    return False


_CASE = re.compile(r"^(test\w+) \(.*\) \.\.\. (ok|FAIL|ERROR|skipped.*)$")


def parse_unittest(output: str) -> tuple[int, list[str]]:
    """(cases run, names of the cases that failed or errored) from `python -m unittest -v` output."""
    ran = 0
    failed = []
    for line in output.splitlines():
        match = _CASE.match(line.strip())
        if match and not match.group(2).startswith("skipped"):
            ran += 1
            if match.group(2) != "ok":
                failed.append(match.group(1))
    return ran, failed


def log_numbers(text: str, token: str) -> tuple[int, int]:
    """(structured request lines with method, path and status, lines that carry the token)."""
    structured = leaked = 0
    for line in text.splitlines():
        if token in line:
            leaked += 1
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and {"method", "path", "status"} <= entry.keys():
            structured += 1
    return structured, leaked


def median_latency_ms(url: str, token: str, count: int = 100) -> float:
    """Median milliseconds of `count` sequential authorised `GET /lobbies` calls."""
    times = []
    for _ in range(count):
        request = urllib.request.Request(url + "/lobbies", headers={"Authorization": f"Bearer {token}"})
        started = time.perf_counter()
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
        times.append((time.perf_counter() - started) * 1000)
    return round(statistics.median(times), 2)


def check_service(name: str, folder: Path, target: Path, limits: dict, log: Log) -> dict:
    """Measure the delivery in `target/service`; the rows in the shape every check writes."""
    rows: list[dict] = []
    errors: list[str] = []
    service = target / "service"
    present = (service / "pyproject.toml").is_file()
    _row(rows, "service/pyproject.toml present", present, "==", True)
    if not present:
        errors.append("no service/pyproject.toml in the eval folder")
        return {"task": name, "passed": 0, "total": len(rows), "rows": rows, "errors": errors}
    lint = _run(["uvx", "--from", RUFF, "ruff", "check", *RUFF_ARGS, "--select", RUFF_RULES, "."], service, 300)
    _row(
        rows,
        "ruff check problems",
        0 if lint.returncode == 0 else len(re.findall(r"^\S+:\d+:\d+:", lint.stdout, re.M)) or 1,
        "==",
        0,
    )
    if lint.returncode != 0:
        errors.append(f"ruff check: {lint.stdout[-500:]}")
    fmt = _run(["uvx", "--from", RUFF, "ruff", "format", "--check", *RUFF_ARGS, "."], service, 300)
    _row(
        rows,
        "files ruff would reformat",
        0 if fmt.returncode == 0 else len(re.findall(r"^Would reformat", fmt.stdout, re.M)) or 1,
        "==",
        0,
    )
    tests = _run(["uv", "run", "--project", str(service), "pytest", "-q", "-p", "no:cacheprovider"], service, 600)
    passed = re.search(r"(\d+) passed", tests.stdout)
    _row(rows, "own tests pass (pytest exit code)", tests.returncode, "==", 0)
    _row(rows, "own test cases", int(passed.group(1)) if passed else 0, ">=", limits.get("min_tests", 8))
    if tests.returncode != 0:
        errors.append(f"pytest: {(tests.stdout + tests.stderr)[-500:]}")
    readme = (service / "README.md").read_text(encoding="utf-8") if (service / "README.md").is_file() else ""
    _row(rows, "settings documented in service/README.md", sum(s in readme for s in SETTINGS), "==", len(SETTINGS))
    docker = (service / "Dockerfile").read_text(encoding="utf-8") if (service / "Dockerfile").is_file() else ""
    _row(rows, "service/Dockerfile with a HEALTHCHECK", "HEALTHCHECK" in docker, "==", True)
    bare = start(service, free_port(), target / "bare.log", token=None)
    try:
        code = bare.wait(timeout=60)
    except subprocess.TimeoutExpired:
        code = None
    stop(bare)
    _row(rows, "refuses to start without API_TOKEN (exit code is not 0)", code is not None and code != 0, "==", True)
    port = free_port()
    url = f"http://127.0.0.1:{port}"
    server_log = target / "service.log"
    proc = start(service, port, server_log)
    try:
        healthy = wait_healthy(url, proc, START_WAIT)
        _row(rows, "service answers GET /health after start", healthy, "==", True)
        if healthy:
            env = {**os.environ, "LOBBY_URL": url, "LOBBY_TOKEN": TOKEN, "LOBBY_HOST": HOST}
            env["LOBBY_PORT_BASE"] = str(PORT_BASE)
            suite = folder / "acceptance"
            run = _run([sys.executable, "-W", "ignore", "-m", "unittest", "-v", "test_acceptance"], suite, 600, env)
            cases, failed = parse_unittest(run.stderr + run.stdout)
            _row(rows, "acceptance cases run", cases, ">=", limits.get("min_acceptance", 15))
            _row(rows, "acceptance cases failed", len(failed) if cases else -1, "==", 0)
            errors += [f"acceptance failed: {case}" for case in failed]
            if failed:
                errors.append((run.stderr + run.stdout)[-900:])
            rows.append(
                {
                    "name": "median ms of GET /lobbies",
                    "value": median_latency_ms(url, TOKEN),
                    "op": "info",
                    "limit": "",
                    "unit": "",
                    "pass": True,
                }
            )
    finally:
        stop(proc)
    text = server_log.read_text(encoding="utf-8", errors="replace") if server_log.is_file() else ""
    structured, leaked = log_numbers(text, TOKEN)
    _row(rows, "structured request log lines (method, path, status)", structured, ">=", limits.get("min_log_lines", 50))
    _row(rows, "log lines that carry the token", leaked, "==", 0)
    shutil.rmtree(service / ".pytest_cache", ignore_errors=True)
    passed_rows = sum(1 for r in rows if r["pass"])
    return {"task": name, "passed": passed_rows, "total": len(rows), "rows": rows, "errors": errors}
