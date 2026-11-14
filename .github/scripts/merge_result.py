"""The limit checks on the result of merging a head into the default branch (docs/studio/ci.md#merge-result).

    python .github/scripts/merge_result.py [--base REF] [--head REF] [--summary FILE] [--no-pre-commit]
    python .github/scripts/merge_result.py --base REF --sweep PRS.json --results RESULTS.json [--remote NAME]

Two pull requests that each pass a limit can break it together, and a head green on an older `main` can land after
`main` moved. This builds the merge the way a squash would land it (`git merge-tree --write-tree`, nothing touched in
the checkout), checks it out in a throwaway worktree and runs, there, the checks a combination can break:

- `mistakes.py check --base <base>`: page size, entry form, new sections against the base (the tree's own copy);
- every pre-commit hook of the tree's own `.pre-commit-config.yaml` on the files the merge changes against the base
  (`pre-commit run --from-ref <base> --to-ref <merge>`): gdlint and its max-file-lines, gdformat, ruff, markdownlint,
  the large-file limit, the conventions render. `topic-sections` is skipped there: the step above runs it.

A conflict is a failure too: the head needs `gds merge-main`. The base defaults to origin/main and the head to HEAD;
fetch first (`git fetch origin main`). Pre-commit is `$MERGE_RESULT_PRE_COMMIT` when set (words split on spaces),
else `pre-commit` from PATH, else `uvx pre-commit@4.7.0`. `--summary` writes a short Markdown report (the sweep in
`.github/workflows/merge-result.yml` posts it as the check's output). Exit 0 when everything passes, 1 when a check
fails or the merge conflicts, 2 on a usage or git error. Standard library only.

`--sweep` is the sweep of the workflow (a push to `main` or a dispatch): PRS.json is a list of `{"number", "sha"}`.
Each pull request's head is fetched from `--remote` (`refs/pull/<number>/head`) and checked as above, one at a time,
and RESULTS.json gets a `{"number", "sha", "conclusion", "summary"}` per pull request: `success`, `failure` (a check
failed, the merge conflicts with the files named, or the head could not be fetched or merged) or `skip` (pushed since
the list was read: its own pull request run checks the new head). One pull request's answer never stops the sweep;
it exits 0 once every pull request has one, 2 when PRS.json is malformed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

PRE_COMMIT_PIN = "pre-commit@4.7.0"
# Hooks the pre-commit step leaves out: topic-sections is mistakes.py check, run first with the explicit base.
SKIPPED_HOOKS = "topic-sections"
# Enough of a failing check's output to see why, short enough for a check run's summary (65,535 characters).
TAIL = 4000
# commit-tree needs an identity; the merge commit is never pushed.
IDENTITY = {
    "GIT_AUTHOR_NAME": "merge-result",
    "GIT_AUTHOR_EMAIL": "merge-result@localhost",
    "GIT_COMMITTER_NAME": "merge-result",
    "GIT_COMMITTER_EMAIL": "merge-result@localhost",
}


class GitError(RuntimeError):
    pass


@dataclass
class Step:
    name: str
    ok: bool
    output: str = ""


@dataclass
class Result:
    base: str
    head: str
    merge: str | None = None
    conflicts: list[str] = field(default_factory=list)
    steps: list[Step] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return (
            not self.conflicts
            and self.merge is not None
            and all(step.ok for step in self.steps)
        )

    def summary(self) -> str:
        lines = [f"Merge of head `{self.head[:12]}` into base `{self.base[:12]}`."]
        if self.conflicts:
            lines += [
                "",
                "The merge conflicts; merge the base in first (`gds merge-main`):",
                "",
            ]
            lines += [f"- `{path}`" for path in self.conflicts]
            return "\n".join(lines) + "\n"
        for step in self.steps:
            lines += ["", f"- {'pass' if step.ok else 'FAIL'}: {step.name}"]
            if not step.ok and step.output.strip():
                lines += ["", "```text", step.output.strip()[-TAIL:], "```"]
        return "\n".join(lines) + "\n"


def git(
    repo: Path, *args: str, env: dict[str, str] | None = None, check: bool = True
) -> subprocess.CompletedProcess:
    done = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env={**os.environ, **(env or {})},
    )
    if check and done.returncode != 0:
        raise GitError(f"git {' '.join(args)}: {(done.stderr or done.stdout).strip()}")
    return done


def build_merge(repo: Path, base: str, head: str) -> tuple[str | None, list[str]]:
    """The merge commit of head into base (base first, as a squash lands it), or None and the conflicted paths."""
    done = git(
        repo,
        "merge-tree",
        "--write-tree",
        "--name-only",
        "--no-messages",
        base,
        head,
        check=False,
    )
    lines = [line for line in done.stdout.splitlines() if line.strip()]
    if done.returncode == 1:
        return None, sorted(set(lines[1:]))
    if done.returncode != 0 or not lines:
        raise GitError(
            f"git merge-tree {base} {head}: {(done.stderr or done.stdout).strip()}"
        )
    tree = lines[0]
    message = f"Merge result of {head[:12]} into {base[:12]}"
    merge = git(
        repo, "commit-tree", tree, "-p", base, "-p", head, "-m", message, env=IDENTITY
    ).stdout.strip()
    return merge, []


def pre_commit_command() -> list[str]:
    configured = os.environ.get("MERGE_RESULT_PRE_COMMIT", "").strip()
    if configured:
        return shlex.split(configured)
    if shutil.which("pre-commit"):
        return ["pre-commit"]
    return ["uvx", PRE_COMMIT_PIN]


def run_step(
    name: str, cmd: list[str], cwd: Path, env: dict[str, str] | None = None
) -> Step:
    print(f"==> {name}", flush=True)
    try:
        done = subprocess.run(
            cmd,
            check=False,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env={**os.environ, **(env or {})},
        )
    except OSError as error:
        return Step(name, False, f"could not run {cmd[0]}: {error}")
    output = (done.stdout or "") + (done.stderr or "")
    print(output, end="" if output.endswith("\n") or not output else "\n", flush=True)
    return Step(name, done.returncode == 0, output)


def check_tree(tree: Path, base: str, merge: str, pre_commit: bool) -> list[Step]:
    steps = [
        run_step(
            "page sizes and topic sections (mistakes.py check)",
            [sys.executable, ".github/scripts/mistakes.py", "check", "--base", base],
            tree,
        )
    ]
    if pre_commit and (tree / ".pre-commit-config.yaml").is_file():
        steps.append(
            run_step(
                "pre-commit hooks on the files the merge changes (gdlint max-file-lines, file size, conventions)",
                [
                    *pre_commit_command(),
                    "run",
                    "--from-ref",
                    base,
                    "--to-ref",
                    merge,
                    "--color",
                    "never",
                ],
                tree,
                env={"SKIP": SKIPPED_HOOKS, "PRE_COMMIT_COLOR": "never"},
            )
        )
    return steps


def merge_result(
    repo: Path, base_ref: str, head_ref: str, pre_commit: bool = True
) -> Result:
    base = git(repo, "rev-parse", "--verify", f"{base_ref}^{{commit}}").stdout.strip()
    head = git(repo, "rev-parse", "--verify", f"{head_ref}^{{commit}}").stdout.strip()
    result = Result(base, head)
    result.merge, result.conflicts = build_merge(repo, base, head)
    if result.merge is None:
        return result
    folder = Path(tempfile.mkdtemp(prefix="merge-result-"))
    tree = folder / "tree"
    # No LFS download: no check reads an LFS file, and the sweep has no LFS credentials to spend.
    git(
        repo,
        "worktree",
        "add",
        "--detach",
        str(tree),
        result.merge,
        env={"GIT_LFS_SKIP_SMUDGE": "1"},
    )
    try:
        result.steps = check_tree(tree, base, result.merge, pre_commit)
    finally:
        git(repo, "worktree", "remove", "--force", str(tree), check=False)
        shutil.rmtree(folder, ignore_errors=True)
        git(repo, "worktree", "prune", check=False)
    return result


SHA = re.compile(r"[0-9a-f]{40}")


def read_prs(path: Path) -> list[tuple[int, str]]:
    """The sweep's pull requests: a JSON list of {number, sha}; anything else is a usage error."""
    rows = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        rows = [rows]  # refused below as a row: a list of rows is the only form
    prs = []
    for row in rows:
        number, sha = (
            (row.get("number"), row.get("sha"))
            if isinstance(row, dict)
            else (None, None)
        )
        if not isinstance(number, int) or isinstance(number, bool) or number <= 0:
            raise ValueError(f"unexpected row {row!r}")
        if not isinstance(sha, str) or not SHA.fullmatch(sha):
            raise ValueError(f"unexpected row {row!r}")
        prs.append((number, sha))
    return prs


def sweep_one(
    repo: Path, base: str, number: int, sha: str, remote: str, pre_commit: bool
) -> dict:
    """One pull request's answer; never raises, so the next pull request is checked whatever this one gives."""
    row = {"number": number, "sha": sha}
    ref = f"refs/remotes/pr/{number}"
    fetched = git(
        repo,
        "fetch",
        "--no-tags",
        remote,
        f"+refs/pull/{number}/head:{ref}",
        check=False,
    )
    if fetched.returncode != 0:
        error = (fetched.stderr or fetched.stdout).strip()
        return {
            **row,
            "conclusion": "failure",
            "summary": f"The sweep could not fetch #{number}: {error}\n",
        }
    if (
        git(
            repo, "rev-parse", "--verify", f"{ref}^{{commit}}", check=False
        ).stdout.strip()
        != sha
    ):
        return {
            **row,
            "conclusion": "skip",
            "summary": f"#{number} was pushed to since the list was read.\n",
        }
    try:
        result = merge_result(repo, base, sha, pre_commit=pre_commit)
    except Exception as error:  # noqa: BLE001 - any error is this pull request's answer, not the sweep's end
        text = f"The sweep could not build the merge of `{sha[:12]}` with `{base[:12]}`: {error}\n"
        return {**row, "conclusion": "failure", "summary": text}
    return {
        **row,
        "conclusion": "success" if result.ok else "failure",
        "summary": result.summary()[-TAIL:],
    }


def sweep(
    repo: Path,
    base_ref: str,
    prs: list[tuple[int, str]],
    remote: str = "origin",
    pre_commit: bool = True,
):
    """Every pull request's answer, in order; a conflict or a failed check on one leaves the rest to be checked."""
    base = git(repo, "rev-parse", "--verify", f"{base_ref}^{{commit}}").stdout.strip()
    actions = bool(os.environ.get("GITHUB_ACTIONS"))
    results = []
    for number, sha in prs:
        if actions:
            print(f"::group::#{number} ({sha})", flush=True)
        row = sweep_one(repo, base, number, sha, remote, pre_commit)
        print(row["summary"], end="", flush=True)
        if actions:
            print("::endgroup::", flush=True)
        print(f"#{number}: {row['conclusion']}", flush=True)
        results.append(row)
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--base",
        default="origin/main",
        help="the branch the head lands on (default origin/main)",
    )
    parser.add_argument(
        "--head", default="HEAD", help="the pull request's head (default HEAD)"
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path.cwd(),
        help="the repository (default the current folder)",
    )
    parser.add_argument("--summary", type=Path, help="write a Markdown report here")
    parser.add_argument(
        "--no-pre-commit", action="store_true", help="run mistakes.py check only"
    )
    parser.add_argument(
        "--sweep",
        type=Path,
        help="a JSON list of {number, sha}: check each pull request's head",
    )
    parser.add_argument(
        "--results",
        type=Path,
        help="with --sweep: write each pull request's answer here (JSON)",
    )
    parser.add_argument(
        "--remote",
        default="origin",
        help="with --sweep: where refs/pull/<n>/head is fetched from",
    )
    args = parser.parse_args(argv)
    if args.sweep:
        if not args.results:
            parser.error("--sweep needs --results")
        try:
            prs = read_prs(args.sweep)
            results = sweep(
                args.repo,
                args.base,
                prs,
                remote=args.remote,
                pre_commit=not args.no_pre_commit,
            )
        except (ValueError, OSError, GitError) as error:
            print(f"merge-result: {error}", file=sys.stderr)
            return 2
        args.results.write_text(json.dumps(results), encoding="utf-8")
        return 0
    try:
        result = merge_result(
            args.repo, args.base, args.head, pre_commit=not args.no_pre_commit
        )
    except GitError as error:
        print(f"merge-result: {error}", file=sys.stderr)
        return 2
    text = result.summary()
    print(text, end="")
    if args.summary:
        args.summary.write_text(text, encoding="utf-8")
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
