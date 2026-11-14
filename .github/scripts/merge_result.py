"""The limit checks on the result of merging a head into the default branch (docs/studio/ci.md#merge-result).

    python .github/scripts/merge_result.py [--base REF] [--head REF] [--summary FILE] [--no-pre-commit]

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
"""

from __future__ import annotations

import argparse
import os
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
        return not self.conflicts and self.merge is not None and all(step.ok for step in self.steps)

    def summary(self) -> str:
        lines = [f"Merge of head `{self.head[:12]}` into base `{self.base[:12]}`."]
        if self.conflicts:
            lines += ["", "The merge conflicts; merge the base in first (`gds merge-main`):", ""]
            lines += [f"- `{path}`" for path in self.conflicts]
            return "\n".join(lines) + "\n"
        for step in self.steps:
            lines += ["", f"- {'pass' if step.ok else 'FAIL'}: {step.name}"]
            if not step.ok and step.output.strip():
                lines += ["", "```text", step.output.strip()[-TAIL:], "```"]
        return "\n".join(lines) + "\n"


def git(repo: Path, *args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess:
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
    done = git(repo, "merge-tree", "--write-tree", "--name-only", "--no-messages", base, head, check=False)
    lines = [line for line in done.stdout.splitlines() if line.strip()]
    if done.returncode == 1:
        return None, sorted(set(lines[1:]))
    if done.returncode != 0 or not lines:
        raise GitError(f"git merge-tree {base} {head}: {(done.stderr or done.stdout).strip()}")
    tree = lines[0]
    message = f"Merge result of {head[:12]} into {base[:12]}"
    merge = git(repo, "commit-tree", tree, "-p", base, "-p", head, "-m", message, env=IDENTITY).stdout.strip()
    return merge, []


def pre_commit_command() -> list[str]:
    configured = os.environ.get("MERGE_RESULT_PRE_COMMIT", "").strip()
    if configured:
        return shlex.split(configured)
    if shutil.which("pre-commit"):
        return ["pre-commit"]
    return ["uvx", PRE_COMMIT_PIN]


def run_step(name: str, cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> Step:
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
                [*pre_commit_command(), "run", "--from-ref", base, "--to-ref", merge, "--color", "never"],
                tree,
                env={"SKIP": SKIPPED_HOOKS, "PRE_COMMIT_COLOR": "never"},
            )
        )
    return steps


def merge_result(repo: Path, base_ref: str, head_ref: str, pre_commit: bool = True) -> Result:
    base = git(repo, "rev-parse", "--verify", f"{base_ref}^{{commit}}").stdout.strip()
    head = git(repo, "rev-parse", "--verify", f"{head_ref}^{{commit}}").stdout.strip()
    result = Result(base, head)
    result.merge, result.conflicts = build_merge(repo, base, head)
    if result.merge is None:
        return result
    folder = Path(tempfile.mkdtemp(prefix="merge-result-"))
    tree = folder / "tree"
    # No LFS download: no check reads an LFS file, and the sweep has no LFS credentials to spend.
    git(repo, "worktree", "add", "--detach", str(tree), result.merge, env={"GIT_LFS_SKIP_SMUDGE": "1"})
    try:
        result.steps = check_tree(tree, base, result.merge, pre_commit)
    finally:
        git(repo, "worktree", "remove", "--force", str(tree), check=False)
        shutil.rmtree(folder, ignore_errors=True)
        git(repo, "worktree", "prune", check=False)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="origin/main", help="the branch the head lands on (default origin/main)")
    parser.add_argument("--head", default="HEAD", help="the pull request's head (default HEAD)")
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="the repository (default the current folder)")
    parser.add_argument("--summary", type=Path, help="write a Markdown report here")
    parser.add_argument("--no-pre-commit", action="store_true", help="run mistakes.py check only")
    args = parser.parse_args(argv)
    try:
        result = merge_result(args.repo, args.base, args.head, pre_commit=not args.no_pre_commit)
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
