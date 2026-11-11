"""A browser install in CI fails or falls back within minutes (docs/engines/godot/web-probes.md#running).

`playwright install --with-deps` runs apt, and a stalled Ubuntu mirror once held the kit's `template` job for 39
minutes, until the job's own limit (#1235). Every step that installs a Playwright browser carries a `timeout-minutes`
well under its job's, and every `playwright ... install` call in it runs under `timeout`, so the fallback still runs.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

KIT = Path(__file__).resolve().parents[2]
WORKFLOWS = [KIT / ".github" / "workflows" / "ci.yml", KIT / "templates" / "repo" / ".github" / "workflows" / "ci.yml"]
STEP_LIMIT_MINUTES = 15
INSTALL = re.compile(r"(playwright\S*|\$pw)\s+install\b")
TIMED = re.compile(r"^\s*timeout\s+(-k\s+\d+\s+)?\d+\s+")


def install_steps(workflow: dict):
    for job_name, job in (workflow.get("jobs") or {}).items():
        for step in job.get("steps") or []:
            if install_calls(step.get("run") or ""):
                yield job_name, job, step


def install_calls(run: str) -> list[str]:
    return [line for line in run.splitlines() if INSTALL.search(line)]


@pytest.mark.parametrize("path", WORKFLOWS, ids=lambda p: str(p.relative_to(KIT)))
def test_every_browser_install_has_a_step_limit_and_timed_calls(path: Path):
    workflow = yaml.safe_load(path.read_text(encoding="utf-8"))
    steps = list(install_steps(workflow))
    assert steps, f"{path.relative_to(KIT)} installs no Playwright browser: update this test"
    for job_name, job, step in steps:
        where = f"{path.relative_to(KIT)} job {job_name}, step {step.get('name')!r}"
        limit = step.get("timeout-minutes")
        assert isinstance(limit, int), f"{where} has no timeout-minutes: a stalled apt mirror holds the whole job"
        assert limit <= STEP_LIMIT_MINUTES, f"{where} may take {limit} minutes, over {STEP_LIMIT_MINUTES}"
        assert limit < job.get("timeout-minutes", 360), f"{where}: the step's limit must be under the job's"
        calls = install_calls(step["run"])
        assert calls, f"{where}: no install call found"
        for call in calls:
            assert TIMED.match(call), f"{where}: `{call.strip()}` runs without `timeout`, so its fallback never runs"


@pytest.mark.parametrize(
    ("line", "timed"),
    [
        ("timeout -k 30 240 $pw install --with-deps chromium-headless-shell && exit 0", True),
        ("  timeout 180 $pw install chromium-headless-shell", True),
        ("uvx playwright@1.64.1 install --with-deps chromium-headless-shell && exit 0", False),
    ],
)
def test_the_timed_check_reads_each_form(line: str, timed: bool):
    assert install_calls(line)
    assert bool(TIMED.match(line)) is timed
