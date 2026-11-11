"""Docs ship with the change: the sections named are read first, kit docs are never left unpublished, and a report says
what it read and what it got wrong (docs/studio/hooks.md#docs)."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

from .agents import _READ_LINE, read_lines
from .issues import _WORK_LINE, ledger_key, read_ledger
from .workspace import git, kit_root, lessons_module, workspace_of

_INLINE_NONE = re.compile(r"(?i)^\W*(none|n/?a|nothing|no mistakes?|-|no)\W*$")


def kit_remote(kit: Path) -> str:
    """`owner/repo` of the kit's origin remote, '' when it is not a GitHub one."""
    found = re.search(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?$", git(kit, "remote", "get-url", "origin"))
    return found.group(1) if found else ""


def kit_pr_heads(repo: str) -> dict[str, str] | None:
    """The branches that have an open or a merged pull request in `repo`, each mapped to the tip commit its last merged
    pull request landed ('' while a pull request is open, or when the tip is unknown); None when GitHub cannot be
    asked."""
    try:
        out = subprocess.run(
            [
                "gh",
                "pr",
                "list",
                "-R",
                repo,
                "--state",
                "all",
                "--limit",
                "300",
                "--json",
                "headRefName,state,headRefOid,mergedAt",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode != 0:
            return None
        prs = [p for p in json.loads(out.stdout or "[]") if p.get("state") in ("OPEN", "MERGED")]
        open_heads = {p["headRefName"] for p in prs if p["state"] == "OPEN"}  # an open pull request covers the branch
        heads: dict[str, str] = {name: "" for name in open_heads}
        for pr in sorted(prs, key=lambda p: p.get("mergedAt") or ""):  # the latest merge wins
            if pr["state"] == "MERGED" and pr["headRefName"] not in open_heads:
                heads[pr["headRefName"]] = pr.get("headRefOid") or ""
        return heads
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return None


def content_on_base(tree: Path, base: str, commit: str) -> bool:
    """Whether every path `commit` touches has, on `base`, the blob the commit left (or is missing on both sides, for a
    deletion). A late commit rescued in a pull request that squashed it with other commits has a new patch id but the
    same blobs, so this reads the content, with no checkout and no worktree side effect."""
    paths = [p for p in git(tree, "diff-tree", "-r", "-z", "--no-commit-id", "--name-only", commit).split("\x00") if p]
    return bool(paths) and all(
        git(tree, "rev-parse", "--verify", "-q", f"{commit}:{p}")
        == git(tree, "rev-parse", "--verify", "-q", f"{base}:{p}")
        for p in paths
    )


def stranded_after_merge(tree: Path, base: str, tip: str) -> list[str]:
    """The commits of `tree`'s branch made after its pull request merged at `tip` whose changes are not on `base`.
    A squash merge rewrites the hashes, so a commit is first compared to `base` by patch id (`git cherry`), then, when
    it still shows as new, by content: a commit squashed together with others has a new patch id but its files are the
    same on `base`. Empty when `tip` is unknown here (the branch was rewritten): the hook cannot tell, so it lets go."""
    if not tip or not git(tree, "rev-parse", "--verify", "-q", f"{tip}^{{commit}}"):
        return []
    try:
        ancestor = subprocess.run(
            ["git", "-C", str(tree), "merge-base", "--is-ancestor", tip, "HEAD"], capture_output=True, timeout=15
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if ancestor.returncode:
        return []
    cherry = git(tree, "cherry", base, "HEAD", tip).splitlines()
    new = [line[2:] for line in cherry if line.startswith("+ ")]
    return [c for c in new if not content_on_base(tree, base, c)]


def unpublished_kit_branches(workspace: Path, config: dict[str, Any], owned: set[str] | None = None) -> dict[str, str]:
    """Branches of the kit's worktrees (`<workspace>/worktrees/gdstudio/*`) with commits ahead of `origin/main` and no
    pull request, open or merged (docs written and left for a batch), each mapped to '' ; and branches whose pull
    request merged and which then got a commit that is not on `origin/main` (pushed after the merge, so lost), each
    mapped to the merged tip. Empty when GitHub cannot be asked. With `owned` (worktree keys, `tree_key`), only those
    worktrees are looked at: the others belong to other sessions."""
    folder = workspace / config.get("docs", {}).get("kit_worktrees", "worktrees/gdstudio")
    protected = config.get("git", {}).get("protected_branches", ["main"])
    ahead = {}
    for tree in sorted(p for p in folder.iterdir() if (p / ".git").exists()) if folder.is_dir() else []:
        if owned is not None and tree_key(tree) not in owned:
            continue
        branch = git(tree, "rev-parse", "--abbrev-ref", "HEAD")
        base = "origin/main" if git(tree, "rev-parse", "--verify", "-q", "origin/main") else "main"
        count = git(tree, "rev-list", "--count", f"{base}..HEAD")
        if branch and branch != "HEAD" and branch not in protected and count.isdigit() and int(count) > 0:
            ahead[branch] = (tree, base)
    if not ahead:
        return {}
    heads = kit_pr_heads(kit_remote(kit_root(workspace)))
    if heads is None:
        return {}
    found = {}
    for branch, (tree, base) in ahead.items():
        if branch not in heads:
            found[branch] = ""
        elif stranded_after_merge(tree, base, heads[branch]):
            found[branch] = heads[branch]
    return found


def unpublished_message(branches: dict[str, str]) -> str:
    """The gate's text: a branch with no pull request, and a branch with commits made after its pull request merged."""
    unpublished = [b for b, tip in branches.items() if not tip]
    stranded = [b for b, tip in branches.items() if tip]
    parts = []
    if unpublished:
        names = ", ".join(unpublished[:5]) + ("..." if len(unpublished) > 5 else "")
        parts.append(
            f"Kit branches with commits and no pull request: {names}. Docs left unpublished are lost: push each branch "
            f"and open its pull request now (`gh pr create`), in the same task that found what it documents, never for "
            f"a later batch. A branch that is not yours: say so and finish."
        )
    if stranded:
        names = ", ".join(f"{b} (merged at {branches[b][:9]})" for b in stranded[:5]) + (
            "..." if len(stranded) > 5 else ""
        )
        parts.append(
            f"Kit branches with commits made after their pull request merged: {names}. A commit pushed to a merged "
            f"branch never reaches main and is lost: make a new branch from `origin/main`, cherry-pick the commit, "
            f"open a new pull request now, then `git reset --hard <merged tip>` on the old branch so it holds nothing "
            f"more. A branch that is not yours: say so and finish."
        )
    return " ".join(parts)


def tree_key(path: Path | str) -> str:
    """A worktree path as one comparable string: forward slashes, no trailing slash, lower case (Windows paths)."""
    return str(path).replace("\\", "/").rstrip("/").lower()


_COMMIT_WORDS = re.compile(r"\bgit\b[^\n]*\b(commit|worktree\s+add|merge)\b")


def transcript_entries(session: dict[str, Any]) -> list[dict[str, Any]]:
    """The entries of the session's transcript (`agent_transcript_path`, else `transcript_path`); [] when unreadable."""
    path = session.get("agent_transcript_path") or session.get("transcript_path")
    try:
        lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines() if path else []
    except OSError:
        return []
    entries = []
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def transcript_blocks(entry: dict[str, Any]) -> list[dict[str, Any]]:
    """The content blocks of a transcript entry's message (a plain string is one text block)."""
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        return [{"type": "text", "text": content, "role": message.get("role")}]
    blocks = [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []
    return [{**b, "role": message.get("role")} for b in blocks]


def owned_kit_worktrees(payload: dict[str, Any], workspace: Path, config: dict[str, Any]) -> set[str]:
    """The kit worktrees (`tree_key`s) the stopping session owns, the only ones its docs gate may name:

    - the worktree its `cwd` is in;
    - the worktree its prompt names (`Worktree: <path>`), and the worktree the ledger of `gds issue start` holds for
      the issue its prompt names (`Issue: owner/repo#N`), the first user messages of its transcript;
    - a worktree it made commits in or added: an absolute path of a kit worktree in one of its own `git commit`,
      `git worktree add` or `git merge` commands.

    A session that owns none (an eval run, the coordinator between tasks) is held for no one's branch (#895)."""
    folder = workspace / config.get("docs", {}).get("kit_worktrees", "worktrees/gdstudio")
    if not folder.is_dir():
        return set()
    trees = {tree_key(p): p for p in folder.iterdir() if (p / ".git").exists()}
    owned: set[str] = set()
    here = tree_key(Path(payload.get("cwd") or "."))
    owned.update(key for key in trees if here == key or here.startswith(key + "/"))
    ledger = read_ledger(workspace, config)
    seen_prompt = False
    for entry in transcript_entries(payload):
        for block in transcript_blocks(entry):
            if block.get("role") == "user" and block.get("type") == "text" and not seen_prompt:
                seen_prompt = True  # the first user message is the prompt the agent was started with
                text = str(block.get("text") or "")
                for found in re.findall(r"(?im)^[ \t>*-]*Worktree[ \t]*:[ \t]*`?([^\s`]+)", text):
                    owned.update(key for key in trees if key == tree_key(found))
                for _label, repo, number in _WORK_LINE.findall(text):
                    tree = (ledger.get(ledger_key(repo, number)) or {}).get("worktree")
                    owned.update(key for key in trees if tree and key == tree_key(tree))
            command = (block.get("input") or {}).get("command") if block.get("type") == "tool_use" else None
            if isinstance(command, str) and _COMMIT_WORDS.search(command):
                said = tree_key(command)
                owned.update(key for key in trees if key in said)
    return owned


def stop_kit_docs(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The docs gate of Stop: the stopping session's own kit branches with commits and no pull request hold it back
    once. Other sessions' branches are theirs to publish, so they are never named here (gdstudio #895)."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    owned = owned_kit_worktrees(payload, workspace, config) if workspace else set()
    branches = unpublished_kit_branches(workspace, config, owned) if workspace and owned else {}
    return unpublished_message(branches) if branches else None


def report_of(payload: dict[str, Any]) -> str:
    """What the agent ended with: `last_assistant_message`, else the last assistant text of its transcript."""
    text = payload.get("last_assistant_message")
    if isinstance(text, str) and text:
        return text
    path = payload.get("agent_transcript_path") or payload.get("transcript_path")
    try:
        lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines() if path else []
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get("message") if isinstance(entry, dict) else None
        if isinstance(message, dict) and message.get("role") == "assistant":
            content = message.get("content")
            if isinstance(content, list):
                content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
            if isinstance(content, str) and content.strip():
                return content
    return ""


def mistakes_text(report: str) -> str:
    """What a report's "Mistakes" section says (a heading or a bold label, up to the next heading), '' when there is
    none or it says there were none."""
    lines = report.replace("\r\n", "\n").split("\n")
    for i, line in enumerate(lines):
        head = re.match(r"^\s*(?:#{1,6}\s*|\*\*|__)?\s*mistakes?\b[^\n]*", line, re.IGNORECASE)
        if not head:
            continue
        inline = re.sub(r"^\s*(?:#{1,6}\s*|\*\*|__)?\s*mistakes?\b[\s*_:.-]*", "", line, flags=re.IGNORECASE)
        body = [inline.strip().strip("*_ ")]
        for after in lines[i + 1 :]:
            label = re.match(r"^\s*(?:\*\*|__)[^*_\n]{1,40}(?:\*\*|__)", after)
            ends = _READ_LINE.match(after) or _GAPS_LINE.match(after)  # the report's next lines (gdstudio #771)
            if re.match(r"^\s*#{1,6}\s", after) or label or ends or (body[0] and not after.strip()):
                break  # the next heading, label or line; a one-line "Mistakes: text" ends at its paragraph
            body.append(after.strip())
        text = " ".join(b for b in body if b).strip()
        return "" if not text or _INLINE_NONE.match(text) else text
    return ""


def sections_named(workspace: Path, report: str) -> list[str]:
    """The sections a report names (`page.md#anchor`, docs/studio/rules.md#anchors) that a kit worktree has and changes
    against origin/main: the rule was written into them. The kit's main checkout counts when it has local changes."""
    module = lessons_module(kit_root(workspace))
    if module is None:
        return []
    roots = [kit_root(workspace)]
    folder = workspace / "worktrees" / "gdstudio"
    roots += [p for p in sorted(folder.iterdir()) if p.is_dir()] if folder.is_dir() else []
    found = []
    for page, anchor in module.refs_in(report):
        if page.startswith("lessons/") or page.endswith("maintainer-corrections.md"):
            continue  # the old folder and the log are not where a rule lives
        for root in roots:
            if anchor in module.anchors(root / "docs" / page) and page_changed(root, f"docs/{page}"):
                found.append(f"{page}#{anchor}")
                break
    return found


def page_changed(root: Path, page: str) -> bool:
    """True when `page` differs from origin/main in the checkout `root` (committed on its branch or not, or a new file
    git does not track yet); True as well when git cannot tell, so a hook never holds an agent on its own failure."""
    try:
        done = subprocess.run(
            ["git", "-C", str(root), "diff", "--quiet", "origin/main", "--", page], capture_output=True, timeout=15
        )
        if done.returncode != 0:
            return True
        listed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard", "--", page],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return True
    return bool(listed.stdout.strip())


_GAPS_LINE = re.compile(r"(?im)^[ \t>*_#-]*docs gaps?[*_]*[ \t]*:")
_PR_NAMED = re.compile(r"(?i)github\.com/[\w.-]+/[\w.-]+/pull/\d+|\b(?:PR|pull request)\s*#\d+")


def read_report_reason(report: str, config: dict[str, Any]) -> str | None:
    """Why a task agent's report of finished work (it names a pull request) is held back: it does not say which
    sections it read (`Read: page.md#anchor, ...`) or what it found missing or wrong in them (`Docs gaps: ...`, or
    `Docs gaps: none`). None when it says both; a `Blocked:` end or a stall is not judged here (`stop_stall` judges a
    stall). `[brief] report = false` turns it off."""
    if not config.get("brief", {}).get("report", True) or not _PR_NAMED.search(report):
        return None
    missing = []
    if not re.search(r"[\w./-]+\.md#[\w-]+", read_lines(report)):
        missing.append("a `Read: <page>.md#<anchor>, ...` line naming the sections of the docs you read")
    if not _GAPS_LINE.search(report):
        missing.append(
            "a `Docs gaps:` line naming each section you found missing, wrong or out of date for this task, as "
            "`page.md#anchor: what` (or the page a missing section belongs on), or `Docs gaps: none`"
        )
    if not missing:
        return None
    return (
        "Your report does not say what you read. Add "
        + " and ".join(missing)
        + ". The coordinator uses it to fix the docs and the next brief (docs/studio/starting-work.md#the-report)."
    )
