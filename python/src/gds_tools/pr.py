"""Check a pull request description on this machine, before `gh pr create|edit` sends it (docs/studio/hooks.md#pr-body).

`pr-rules` runs `groundwork.py check-body` on the description after the push, and an agent whose body failed found out
there. `check_body` runs the same function, from the checkout of the repository the pull request is for: every
repository has its own `.github/conventions.yml` (a game's differs from the kit's), so the checker is run with that
folder as its working directory and that file as its conventions, and the repository's own copy of `groundwork.py` is
preferred over the kit's. Used by `gds pr check-body` and, loaded by file, by the Git/GitHub guard in
`.claude/hooks/guards/bodies.py`, so this module uses the standard library only.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

GROUNDWORK = Path(".github") / "scripts" / "groundwork.py"
CONVENTIONS = Path(".github") / "conventions.yml"
#: A cold `uv run --with pyyaml` can take a while; a check that cannot finish is not an answer.
TIMEOUT_SECONDS = 45


#: `merge.hold` of the conventions (a test keeps them equal).
HOLD_LABEL = "S-hold"
HOLD_CHECK = "hold"
#: How long `hold` waits for the check to go red: the job takes seconds, unless the runners are all busy.
HOLD_TIMEOUT_SECONDS = 180
HOLD_POLL_SECONDS = 3


class PrCheckError(Exception):
    """The check cannot be run here (no checker, no conventions, no program to run it with)."""


@dataclass
class BodyCheck:
    """The result of one check: `ok`, and the reasons the checker printed when it refused. `unknown` is why the check
    could not be made at all (then `ok` is True only in the sense that nothing was refused): it is never an "ok"."""

    ok: bool
    reasons: list[str]
    unknown: str = ""


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


def check_body(
    repo: Path, body: str, title: str | None = None, kit: Path | None = None, changed: list[str] | None = None
) -> BodyCheck:
    """Run `groundwork.py check-body` for a description (and a title, which turns on the screenshots, failed-first and
    lessons rules) in the checkout `repo`. The pull request's history is not asked (no network): a pull request that
    GitHub knows failed an earlier check or closes a bug issue is still judged by `pr-rules` alone on that part.
    `changed` (the branch's files, `branch_changes`) lets the `Lessons:` rule see that its section's page changes."""
    conventions = repo / CONVENTIONS
    if not conventions.is_file():
        raise PrCheckError(f"{CONVENTIONS.as_posix()} is missing in {repo}")
    checker = checker_for(repo, kit)
    with tempfile.TemporaryDirectory(prefix="gds-pr-body-") as folder:
        body_file = Path(folder) / "body.md"
        body_file.write_text(body, encoding="utf-8", newline="\n")
        arguments = ["check-body", "--body", str(body_file)]
        if title is not None:
            title_file = Path(folder) / "title.txt"
            title_file.write_text(title, encoding="utf-8", newline="\n")
            arguments += ["--title", str(title_file)]
        if changed is None:
            return _run_checker(repo, checker, arguments)
        changed_file = Path(folder) / "changed.txt"
        changed_file.write_text("\n".join(changed) + "\n", encoding="utf-8", newline="\n")
        try:
            return _run_checker(repo, checker, [*arguments, "--changed", str(changed_file)])
        except PrCheckError:  # a game's older groundwork.py has no `check-body --changed`
            return _run_checker(repo, checker, arguments)


def _run_checker(repo: Path, checker: Path, arguments: list[str]) -> BodyCheck:
    """Run one `groundwork.py` sub-command in `repo` with its conventions: 0 is ok, 1 is a refusal with reasons, any
    other result is an error (`PrCheckError`)."""
    command = [*_python_command(), str(checker), "--conventions", str(repo / CONVENTIONS), *arguments]
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


#: What a branch is compared to, as `pr-rules` does (the pull request's files are the branch's changes since it left
#: the default branch).
BASE = "origin/main"


def _git(repo: Path, *args: str) -> tuple[int, str]:
    try:
        done = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        return 1, str(error)
    return done.returncode, done.stdout


def branch_changes(repo: Path) -> tuple[list[str], str]:
    """(the files the branch changed since it left origin/main, "") as `git diff --name-only origin/main...HEAD`, the
    files of the pull request; ([], why) when that cannot be told: a detached head, the default branch itself, no
    origin/main, or no commit yet."""
    code, branch = _git(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    branch = branch.strip()
    if code != 0 or not branch:
        return [], "the head is detached or has no branch"
    if branch in ("main", "master"):
        return [], f"the checkout is on {branch}, not on the pull request's branch"
    code, _ = _git(repo, "rev-parse", "--verify", "--quiet", BASE)
    if code != 0:
        return [], f"{BASE} is not known here (git fetch origin)"
    code, out = _git(repo, "diff", "--name-only", f"{BASE}...HEAD")
    if code != 0:
        return [], f"git diff {BASE}...HEAD failed"
    return [line.strip() for line in out.splitlines() if line.strip()], ""


def check_docs(repo: Path, body: str, kit: Path | None = None) -> BodyCheck:
    """The docs rule of `pr-rules` (`groundwork.py check-docs`: a change to code needs a change to docs or a
    `Docs: none` line) against the files the branch of `repo` changed since origin/main. It shares the rule with CI by
    running the same sub-command on the same kind of file list. When the branch cannot be told, the result says why in
    `unknown` and is never a pass."""
    changed, why = branch_changes(repo)
    if why:
        return BodyCheck(True, [], unknown=why)
    if not (repo / CONVENTIONS).is_file():
        raise PrCheckError(f"{CONVENTIONS.as_posix()} is missing in {repo}")
    checker = checker_for(repo, kit)
    with tempfile.TemporaryDirectory(prefix="gds-pr-docs-") as folder:
        body_file, changed_file = Path(folder) / "body.md", Path(folder) / "changed.txt"
        body_file.write_text(body, encoding="utf-8", newline="\n")
        changed_file.write_text("\n".join(changed) + "\n", encoding="utf-8", newline="\n")
        try:
            return _run_checker(repo, checker, ["check-docs", "--body", str(body_file), "--changed", str(changed_file)])
        except PrCheckError as error:  # an older groundwork.py without `check-docs`, or one that cannot run
            return BodyCheck(True, [], unknown=f"the docs checker failed: {error}")


def hold(
    repo: str,
    number: int,
    *,
    gh: Callable[[list[str]], str],
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    timeout: float = HOLD_TIMEOUT_SECONDS,
) -> list[str]:
    """Put the hold label on a pull request and wait until GitHub's required `hold` check is red on its head
    (docs/studio/hooks.md#hold). The label stops nothing by itself: until the check has gone red, the green run before
    it
    still counts, so a hold is only reported once it holds. Raises when the pull request is not open, or merged in the
    wait."""

    def view() -> dict:
        fields = "state,headRefOid,labels,autoMergeRequest"
        return json.loads(gh(["pr", "view", str(number), "-R", repo, "--json", fields]))

    def conclusion(sha: str) -> str:
        path = f"repos/{repo}/commits/{sha}/check-runs?check_name={HOLD_CHECK}&per_page=100"
        return gh(["api", path, "--jq", '[.check_runs[]] | max_by(.id) | .conclusion // ""']).strip()

    ref, pull = f"{repo}#{number}", view()
    if pull["state"] != "OPEN":
        raise PrCheckError(f"{ref} is {pull['state'].lower()}: there is nothing left to hold")
    if HOLD_LABEL not in [label["name"] for label in pull["labels"]]:
        gh(["pr", "edit", str(number), "-R", repo, "--add-label", HOLD_LABEL])
    deadline = clock() + timeout
    while True:
        pull = view()
        if pull["state"] != "OPEN":
            raise PrCheckError(f"{ref} is {pull['state'].lower()}: it went through before the hold took effect")
        if conclusion(pull["headRefOid"]) == "failure":
            break
        if clock() >= deadline:
            raise PrCheckError(
                f"{ref} carries {HOLD_LABEL}, but `{HOLD_CHECK}` is not red after {timeout:.0f} s: it is not held yet"
            )
        sleep(HOLD_POLL_SECONDS)
    lines = [f"{ref} is held: `{HOLD_CHECK}` is red, and no route merges it while {HOLD_LABEL} is on."]
    if pull.get("autoMergeRequest"):
        lines.append("Auto-merge is on: it stays on, and the pull request merges the moment the label comes off.")
    return lines
