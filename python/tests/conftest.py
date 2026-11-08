"""The tripwire of the suites that delete: a probe of the kit has already reached a real service (docs/lessons), and
`gh` and the process list are default arguments, so a test that forgets its fake runs the real thing. With this fixture
it fails instead. `test_disk.py` proves the real routes pass through it."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from skip_allowlist import (  # noqa: F401 - the hooks of the skip allowlist (--allowed-skips)
    pytest_addoption,
    pytest_collectreport,
    pytest_runtest_logreport,
    pytest_sessionfinish,
    pytest_terminal_summary,
)

REAL_SERVICES = frozenset({"gh", "powershell", "pwsh", "ps"})


@pytest.fixture
def no_real_services(monkeypatch: pytest.MonkeyPatch) -> None:
    """Any `gh` or process listing that reaches `subprocess.run` fails the test. Git still runs, on temporary trees."""
    real = subprocess.run

    def guarded(argv, *args, **kwargs):
        program = Path(str(argv[0] if isinstance(argv, (list, tuple)) else argv)).stem.lower()
        if program in REAL_SERVICES:
            raise AssertionError(f"a test reached the real `{program}`: {argv}")
        return real(argv, *args, **kwargs)

    monkeypatch.setattr(subprocess, "run", guarded)
