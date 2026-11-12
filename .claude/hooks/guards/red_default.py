"""No merge while the default branch is red (docs/studio/hooks-red-main.md#red-main): an open `CI failing on the
default branch` issue stops every merge command in its repository but the fix forward, whose body says `Fixes #<that
issue>`. Named `red_default`, not `red_main`, so the module does not hide the function `guards.red_main`."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .behind_base import _PR_URL, gh_text
from .merges import merge_asks
from .workspace import WARNINGS

# The title ci-failure.yml gives the issue, before `: <workflow>`.
RED_TITLE = "CI failing on the default branch"
_CLOSES = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b:?\s+(?:([\w.-]+/[\w.-]+))?#(\d+)\b",
    re.IGNORECASE,
)


def red_issues(repo: str, cwd: Path) -> list[tuple[int, str]]:
    """The open issues of `repo` that ci-failure.yml filed for a red default branch, as (number, title). Every open
    issue is listed, not searched: the search index lags a just-filed issue, and a label can be taken off. Raises
    `LookupError(why)` when GitHub cannot be asked."""
    jq = '.[] | "\\(.number)\\t\\(.title)"'
    command = ["gh", "issue", "list", "-R", repo, "--state", "open", "--limit", "1000", "--json", "number,title"]
    out = gh_text([*command, "--jq", jq], cwd, "listing the open issues")
    found = []
    for line in out.splitlines():
        number, _, title = line.partition("\t")
        if number.strip().isdigit() and (title == RED_TITLE or title.startswith(f"{RED_TITLE}:")):
            found.append((int(number), title))
    return found


def pull_request(target: str, repo: str | None, cwd: Path) -> tuple[int, str, str]:
    """A pull request's number, repository and body; raises `LookupError(why)` when GitHub cannot say."""
    view = ["gh", "pr", "view", *([target] if target else []), *(["-R", repo] if repo else [])]
    text = gh_text([*view, "--json", "number,url,body"], cwd, "reading the pull request")
    try:
        pr = json.loads(text)
        return int(pr["number"]), repo or _PR_URL.search(pr["url"]).group(1), pr.get("body") or ""
    except (ValueError, KeyError, TypeError, AttributeError):
        raise LookupError("reading the pull request gave no number, address and body") from None


def fixed_issues(body: str, repo: str) -> set[int]:
    """The issues of `repo` a pull request body closes by a GitHub closing keyword (`Fixes #N`, `Closes o/r#N`, ...)."""
    return {int(number) for named, number in _CLOSES.findall(body) if not named or named.lower() == repo.lower()}


def red_main(target: str, repo: str | None, cwd: Path) -> tuple[dict[str, Any] | None, str]:
    """Whether a merge of this pull request lands on a red default branch: `({repo, number, open, fixes}, '')`, `open`
    the red issues as (number, title) and `fixes` whether the body closes one of them; `(None, why)` when GitHub cannot
    say. With the repository known the issues are asked first, so a green main costs one call."""
    try:
        number = None
        if repo is None:
            number, repo, body = pull_request(target, repo, cwd)
        found = red_issues(repo, cwd)
        if not found:
            return {"repo": repo, "number": number or target, "open": [], "fixes": False}, ""
        if number is None:
            number, repo, body = pull_request(target, repo, cwd)
        fixes = bool(fixed_issues(body, repo) & {n for n, _ in found})
        return {"repo": repo, "number": number, "open": found, "fixes": fixes}, ""
    except LookupError as error:
        return None, str(error)


def red_reason(found: dict[str, Any]) -> str:
    """The refusal for a merge while `found["open"]` red issues are open."""
    repo, issues = found["repo"], found["open"]
    named = ", ".join(f"{repo}#{n} ({title})" for n, title in issues)
    fix = " or ".join(f"`Fixes #{n}`" for n, _ in issues)
    return (
        f"{repo}#{found['number']}: the default branch is red, {named} is open: nothing lands until its fix does; then "
        f"`gds merge-main`, push, and merge once the checks pass on that head. Only the fix forward, whose body says "
        f"{fix}, merges now (docs/studio/starting-work.md#landing)"
    )


def check_red_main(words: list[str], cwd: Path) -> list[str]:
    """A merge command (`gh pr merge`, with or without `--auto`, or a write to `gh api .../pulls/<n>/merge`) while an
    issue titled `CI failing on the default branch` is open in the pull request's repository, unless the pull request's
    body closes that issue. Merging main into a branch is no merge command and is never judged. When GitHub cannot be
    asked the call goes through with a warning, never silently."""
    reasons = []
    for target, repo in merge_asks(words):
        found, why = red_main(target, repo, cwd)
        if found is None:
            WARNINGS.append(
                f"the merge guard could not check for an open `{RED_TITLE}` issue before merging "
                f"{target or 'this pull request'} ({why}); the call goes through, so check it yourself "
                f'(`gh issue list --search "{RED_TITLE}" --state open`)'
            )
        elif found["open"] and not found["fixes"]:
            reasons.append(red_reason(found))
    return reasons
