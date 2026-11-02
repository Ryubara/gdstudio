"""Check a pull request description on this machine, before `gh pr create|edit` sends it (docs/hooks.md#pr-body).

`pr-rules` runs `groundwork.py check-body` on the description after the push, and an agent whose body failed found out
there. `check_body` runs the same function, from the checkout of the repository the pull request is for: every
repository has its own `.github/conventions.yml` (a game's differs from the kit's), so the checker is run with that
folder as its working directory and that file as its conventions, and the repository's own copy of `groundwork.py` is
preferred over the kit's. Used by `gds pr check-body` and, loaded by file, by the Git/GitHub guard in
`.claude/hooks/guards.py`, so this module uses the standard library only.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

GROUNDWORK = Path(".github") / "scripts" / "groundwork.py"
CONVENTIONS = Path(".github") / "conventions.yml"
#: A cold `uv run --with pyyaml` can take a while; a check that cannot finish is not an answer.
TIMEOUT_SECONDS = 45


class PrCheckError(Exception):
    """The check cannot be run here (no checker, no conventions, no program to run it with)."""


@dataclass
class BodyCheck:
    """The result of one check: `ok`, and the reasons the checker printed when it refused."""

    ok: bool
    reasons: list[str]


def repo_root(start: Path) -> Path | None:
    """The top folder of the git checkout around `start` ('' output, a missing git or no repository: None)."""
    try:
        done = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=15
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return Path(done.stdout.strip()) if done.returncode == 0 and done.stdout.strip() else None


def checker_for(repo: Path, kit: Path | None) -> Path:
    """The `groundwork.py` to run for `repo`: its own copy, else the kit's."""
    for folder in (repo, kit):
        if folder and (folder / GROUNDWORK).is_file():
            return folder / GROUNDWORK
    raise PrCheckError(f"no {GROUNDWORK.as_posix()} in {repo}" + (f" or in the kit {kit}" if kit else ""))


def _python_command() -> list[str]:
    """How to start the checker: this interpreter when it has pyyaml, else `uv run` with it."""
    if importlib.util.find_spec("yaml") is not None:
        return [sys.executable]
    return ["uv", "run", "--no-project", "--with", "pyyaml", "python"]


def check_body(repo: Path, body: str, title: str | None = None, kit: Path | None = None) -> BodyCheck:
    """Run `groundwork.py check-body` for a description (and a title, which turns on the screenshots, failed-first and
    lessons rules) in the checkout `repo`. The pull request's history is not asked (no network): a pull request that
    GitHub knows failed an earlier check or closes a bug issue is still judged by `pr-rules` alone on that part."""
    conventions = repo / CONVENTIONS
    if not conventions.is_file():
        raise PrCheckError(f"{CONVENTIONS.as_posix()} is missing in {repo}")
    checker = checker_for(repo, kit)
    with tempfile.TemporaryDirectory(prefix="gds-pr-body-") as folder:
        body_file = Path(folder) / "body.md"
        body_file.write_text(body, encoding="utf-8", newline="\n")
        command = [*_python_command(), str(checker), "--conventions", str(conventions), "check-body"]
        command += ["--body", str(body_file)]
        if title is not None:
            title_file = Path(folder) / "title.txt"
            title_file.write_text(title, encoding="utf-8", newline="\n")
            command += ["--title", str(title_file)]
        try:
            done = subprocess.run(
                command,
                cwd=repo,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=TIMEOUT_SECONDS,
                stdin=subprocess.DEVNULL,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise PrCheckError(f"the checker could not run: {error}") from error
    if done.returncode == 0:
        return BodyCheck(True, [])
    if done.returncode != 1:
        raise PrCheckError((done.stderr or done.stdout).strip() or f"the checker exited with {done.returncode}")
    reasons = [line.strip()[2:] for line in done.stderr.splitlines() if line.strip().startswith("- ")]
    return BodyCheck(False, reasons or [done.stderr.strip()])
