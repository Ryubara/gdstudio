"""The root `pytest.ini`: a bare pytest from the checkout's root runs the kit's tests only, with their settings.

A run that names `python/tests` (CI, docs/studio/kit-tests.md#command) reads `python/pyproject.toml`; a bare run from
the root reads `pytest.ini`. The two must agree, and the bare run must never collect the eval acceptance suites.
"""

from __future__ import annotations

import configparser
import subprocess
import sys
import tomllib
from pathlib import Path

KIT = Path(__file__).resolve().parents[2]


def _root_ini() -> configparser.SectionProxy:
    parser = configparser.ConfigParser()
    parser.read(KIT / "pytest.ini", encoding="utf-8")
    return parser["pytest"]


def _project_options() -> dict:
    with (KIT / "python" / "pyproject.toml").open("rb") as handle:
        return tomllib.load(handle)["tool"]["pytest"]["ini_options"]


def test_the_root_config_points_at_the_kit_tests() -> None:
    assert _root_ini()["testpaths"].split() == ["python/tests"]
    assert _project_options()["testpaths"] == ["tests"]


def test_the_root_config_keeps_the_kit_tests_warning_filters() -> None:
    root = [line.strip() for line in _root_ini()["filterwarnings"].splitlines() if line.strip()]
    assert root == _project_options()["filterwarnings"]


def test_a_bare_run_from_the_root_collects_no_eval_suite() -> None:
    run = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", "-p", "no:cacheprovider", "-p", "no:xdist"],
        cwd=KIT,
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    assert run.returncode == 0, run.stdout[-2000:] + run.stderr[-2000:]
    collected = [line for line in run.stdout.splitlines() if "::" in line]
    assert collected, run.stdout[-2000:]
    assert all(line.startswith("python/tests/") for line in collected), [
        line for line in collected if not line.startswith("python/tests/")
    ][:5]
