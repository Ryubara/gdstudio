"""The skip allowlist: with `--allowed-skips <toml>`, a run fails on a skip the file does not name for this platform,
and on a named skip that ran instead (the entry is stale). CI passes the option, so a test that skips there has a
stated reason, and the skip count on each runner is the count of the entries for its platform (kit #797).

The hooks are imported into `conftest.py`. An entry names the test by file and function (`test_x.py::test_y`, every
parameter of it), the platforms it may skip on (`sys.platform`: `win32`, `linux`, `darwin`) and why.
"""

from __future__ import annotations

import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

import pytest

_skips: dict[str, str] = {}  # the run's skipped tests (as `file::function`) and the reason pytest gave
_ran: set[str] = set()  # the tests that ran to the end without a skip
_problems: list[str] = []


@dataclass(frozen=True)
class Entry:
    test: str
    platforms: tuple[str, ...]
    reason: str


def key(nodeid: str) -> str:
    """`tests/test_x.py::test_y[a-1]` -> `test_x.py::test_y`: the file's name and the function, parameters dropped."""
    path, _, rest = nodeid.partition("::")
    name = Path(path).name
    return f"{name}::{rest.split('[', 1)[0]}" if rest else name


def load(path: Path) -> list[Entry]:
    """The entries of an allowlist file; ValueError on an entry without a test, a platform or a reason."""
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    entries = []
    for i, raw in enumerate(data.get("skip", [])):
        test, platforms, reason = raw.get("test", ""), raw.get("platforms", []), raw.get("reason", "").strip()
        if not test or not platforms or not reason:
            raise ValueError(f"{path}: entry {i + 1} needs a test, its platforms and a reason")
        entries.append(Entry(test, tuple(platforms), reason))
    return entries


def judge(entries: list[Entry], skipped: dict[str, str], ran: set[str], platform: str) -> list[str]:
    """What is wrong with a run: each skip no entry allows here, and each entry for here whose test ran instead."""
    allowed = {e.test for e in entries if platform in e.platforms}
    problems = [
        f"{test} skipped and is not on the allowlist for {platform}: {reason}"
        for test, reason in sorted(skipped.items())
        if test not in allowed
    ]
    problems += [
        f"{test} is on the allowlist for {platform} but ran: remove the entry or the platform"
        for test in sorted(allowed & ran - skipped.keys())
    ]
    return problems


def _reason(report: pytest.TestReport | pytest.CollectReport) -> str:
    longrepr = report.longrepr
    if isinstance(longrepr, tuple) and len(longrepr) == 3:
        return str(longrepr[2]).removeprefix("Skipped: ")
    return str(longrepr)


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--allowed-skips",
        metavar="TOML",
        help="fail on a skip this file does not allow for the platform, and on an allowed skip that ran (kit #797)",
    )


def pytest_collectreport(report: pytest.CollectReport) -> None:
    if report.skipped:  # a whole module skipped (`importorskip` at the top)
        _skips[key(report.nodeid)] = _reason(report)


def pytest_runtest_logreport(report: pytest.TestReport) -> None:
    if hasattr(report, "wasxfail"):
        return
    name = key(report.nodeid)
    if report.skipped:
        _skips[name] = _reason(report)
    elif report.when == "call":
        _ran.add(name)


@pytest.hookimpl(tryfirst=True)
def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    option = session.config.getoption("--allowed-skips")
    if not option or session.config.option.collectonly:
        return
    _problems[:] = judge(load(Path(option)), _skips, _ran, sys.platform)
    if _problems and exitstatus == pytest.ExitCode.OK:
        session.exitstatus = pytest.ExitCode.TESTS_FAILED


def pytest_terminal_summary(terminalreporter) -> None:  # noqa: ANN001 - pytest's TerminalReporter
    if _problems:
        terminalreporter.section("skip allowlist", red=True)
        for line in _problems:
            terminalreporter.line(line)
