"""The guards behind dispatch.py (docs/studio/hooks.md). Each check returns the reasons it refuses a call, with what to
do
instead; an empty list lets it through. Standard library only."""

from __future__ import annotations

import contextlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import tomllib
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote

SHELL_TOOLS = ("Bash", "PowerShell")
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
AGENT_TOOLS = ("Agent", "Task")
MARKER = ".gdstudio-workspace"

# --------------------------------------------------------------------------------------------------------------------
# Helpers: shell commands, globs, git, the workspace
# --------------------------------------------------------------------------------------------------------------------

_HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")
_HERESTRING = re.compile(r"@(['\"])\r?\n.*?\r?\n\1@", re.DOTALL)


def strip_heredocs(command: str) -> str:
    """The command without heredoc bodies (bash `<<EOF ... EOF`) or PowerShell here-strings: they are data fed to a
    program, not commands, and judging their lines as commands refuses harmless text."""
    command = _HERESTRING.sub("''", command)
    lines, out, end = command.split("\n"), [], None
    for line in lines:
        if end is not None:
            if line.strip() == end:
                end = None
            continue
        out.append(line)
        found = _HEREDOC.search(line)
        if found:
            end = found.group(2)
    return "\n".join(out)


def split_commands(command: str) -> list[str]:
    """A shell line cut at `&&`, `||`, `;`, `|` and newlines that sit outside quotes."""
    parts, current, quote, i = [], [], None, 0
    while i < len(command):
        ch = command[i]
        if quote:
            if ch == quote:
                quote = None
            current.append(ch)
        elif ch in "'\"":
            quote = ch
            current.append(ch)
        elif command.startswith(("&&", "||"), i):
            parts.append("".join(current))
            current, i = [], i + 2
            continue
        elif ch in ";|\n":
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
        i += 1
    parts.append("".join(current))
    return parts


def segments(command: str) -> list[list[str]]:
    """The simple commands of a shell line, each as words (quotes removed; a word that will not split stays whole)."""
    out: list[list[str]] = []
    for part in split_commands(strip_heredocs(command)):
        part = part.strip()
        if not part:
            continue
        try:  # backslashes as path separators (Windows), not shell escapes: these checks read paths
            words = shlex.split(part.replace("\\", "/"), posix=True)
        except ValueError:
            words = part.split()
        while words and (words[0] in ("&", ".", "call", "exec", "time", "sudo") or re.fullmatch(r"\w+=\S*", words[0])):
            words = words[1:]
        if words:
            out.append(words)
    return out


def program(words: list[str]) -> str:
    """A command's program name: the first word's file name, lower-case, without `.exe`."""
    name = PurePosixPath(words[0].replace("\\", "/")).name.lower()
    return name.removesuffix(".exe")


def glob_regex(pattern: str) -> re.Pattern[str]:
    """A glob as a regex over forward-slash paths: `**` any folders, `*` within a folder; a leading `**/` matches at
    any depth, otherwise the pattern is anchored at the start."""
    out, i = "", 0
    lead = pattern.startswith("**/")
    body = pattern[3:] if lead else pattern
    while i < len(body):
        if body.startswith("**", i):
            out, i = out + ".*", i + 2
        elif body[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif body[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(body[i]), i + 1
    return re.compile(("(?:^|.*/)" if lead else "^") + out + "$")


def matches(path: str, patterns: list[str]) -> bool:
    """True when `path` (any slashes) matches one of the globs."""
    norm = path.replace("\\", "/")
    return any(glob_regex(p).match(norm) for p in patterns)


def git(cwd: Path, *args: str) -> str:
    """A git command's output, '' when it fails (not a repository, git missing)."""
    try:
        result = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def workspace_of(path: Path) -> Path | None:
    """The GDStudio workspace holding `path`, by its marker file."""
    for folder in (path, *path.parents):
        if (folder / MARKER).exists():
            return folder
    return None


def git_dir_of(words: list[str], cwd: Path) -> tuple[Path, list[str]]:
    """For a `git` command: the folder it runs in (`-C`) and its words after the global options."""
    i, here = 1, cwd
    while i < len(words) and words[i].startswith("-"):
        if words[i] == "-C" and i + 1 < len(words):
            here = (cwd / words[i + 1]).resolve()
            i += 2
        elif words[i] in ("-c", "--git-dir", "--work-tree") and i + 1 < len(words):
            i += 2
        else:
            i += 1
    return here, words[i:]


# --------------------------------------------------------------------------------------------------------------------
# PreToolUse guards
# --------------------------------------------------------------------------------------------------------------------


def check_agents(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """No agent without instructions: `general-purpose` (and an Agent call naming no type, which starts it)."""
    kind = (payload.get("tool_input") or {}).get("subagent_type") or "general-purpose"
    if kind not in config.get("agents", {}).get("refused", []):
        return []
    project = Path(payload.get("cwd") or ".")
    defined = sorted(p.stem for p in (project / ".claude" / "agents").glob("*.md"))
    allowed = defined + config["agents"].get("helpers", [])
    return [f"the agent type {kind!r} has no instructions or enforced rules; start one of: {', '.join(allowed)}"]


# --------------------------------------------------------------------------------------------------------------------
# Issue order: a task agent works on a started issue (or an open pull request), and the labels that say so are not set
# by hand (docs/studio/hooks.md#issues)
# --------------------------------------------------------------------------------------------------------------------

# `Issue: owner/repo#N` or `PR: owner/repo#N` at the start of a line of an agent's prompt (a list bullet, a quote mark
# or backticks around the reference are fine).
_WORK_LINE = re.compile(r"(?im)^[ \t>*-]*(Issue|PR)[ \t]*:[ \t]*`?([\w.-]+/[\w.-]+)#(\d+)`?")
IN_PROGRESS = "S-in-progress"
CRITICAL = "P-critical"
HOLD = "S-hold"  # merge.hold.label in .github/conventions.yml; a test keeps them equal


def ledger_key(repo: str, number: int | str) -> str:
    """The key `gds issue start` writes to the ledger for an issue (python/src/gds_tools/issues.py builds the same)."""
    return f"{repo}#{number}".lower()


def read_ledger(workspace: Path, config: dict[str, Any]) -> dict[str, Any]:
    """The started issues of `<workspace>/cache/issues-started.json` by key; empty when the file is missing."""
    path = workspace / config.get("issues", {}).get("ledger", "cache/issues-started.json")
    try:
        started = json.loads(path.read_text(encoding="utf-8")).get("started", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return started if isinstance(started, dict) else {}


def pr_state(repo: str, number: str) -> str | None:
    """`OPEN`, `MERGED` or `CLOSED` for a pull request, `MISSING` when GitHub has none, None when it cannot tell (no
    network, no `gh`): a guard that cannot look lets the call through."""
    try:
        out = subprocess.run(
            ["gh", "pr", "view", number, "-R", repo, "--json", "state", "--jq", ".state"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode == 0:
        return out.stdout.strip() or None
    text = out.stderr.lower()
    return "MISSING" if "could not resolve" in text or "no pull requests found" in text else None


def check_issue(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent starts on a started issue (`Issue: owner/repo#N`, in the ledger of `gds issue start`) or on an open
    pull request it continues (`PR: owner/repo#N`: a review, a red main, a conflict). Helpers are exempt."""
    rules = config.get("issues", {})
    inp = payload.get("tool_input") or {}
    kind = inp.get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *rules.get("exempt", [])]
    if not rules.get("enforce", True) or kind in exempt or kind in config.get("agents", {}).get("refused", []):
        return []
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return []
    ledger = read_ledger(workspace, config)
    wanted = _WORK_LINE.findall(inp.get("prompt") or "")
    reasons = []
    for label, repo, number in wanted:
        if label.lower() == "issue" and ledger_key(repo, number) not in ledger:
            reasons.append(
                f"{repo}#{number} was not started with `gds issue start`: run `uv run --project "
                f"{(workspace / 'repos' / 'gdstudio' / 'python').as_posix()} gds issue start {repo}#{number} "
                f"--agent <name>` (it refuses an issue that is not among the oldest ready ones and lists those)"
            )
        elif label.lower() == "pr" and pr_state(repo, number) in ("MISSING", "MERGED", "CLOSED"):
            reasons.append(f"{repo}#{number} is not an open pull request: name an issue started with `gds issue start`")
    if not wanted:
        reasons.append(
            f"the agent type {kind!r} works on one task, and its prompt names none: start the issue with `gds issue "
            f"start <owner/repo>#N --agent <name>` (oldest ready issues first, `gds issue list` shows them) and put "
            f"`Issue: <owner/repo>#N` on a line of the prompt. Work on an existing open pull request (a review, a red "
            f"main, a conflict) names it instead: `PR: <owner/repo>#N`"
        )
    return reasons


# `Read: page.md#anchor[, page.md#anchor ...]` on a line of an agent's prompt or report (a list bullet, a quote mark or
# bold around the label are fine), and the list lines right under it.
_READ_LINE = re.compile(r"(?im)^[ \t>*_-]*Read[*_]*[ \t]*:[*_]*(.*)$")
_LIST_LINE = re.compile(r"^[ \t]*[-*][ \t]+\S")


def read_lines(text: str) -> str:
    """The text of every `Read:` line of a prompt or report, with the list lines under one (`- page.md#anchor`)."""
    lines = text.replace("\r\n", "\n").split("\n")
    out = []
    for i, line in enumerate(lines):
        found = _READ_LINE.match(line)
        if not found:
            continue
        out.append(found.group(1))
        for after in lines[i + 1 :]:
            if not _LIST_LINE.match(after) or _READ_LINE.match(after):
                break
            out.append(after)
    return "\n".join(out)


def without_read_lines(text: str) -> str:
    """A report without its `Read:` lines and the list lines under them: a section the agent read is not one it
    updated, so the Mistakes check (`sections_named`) never counts it."""
    lines = text.replace("\r\n", "\n").split("\n")
    out, skipping = [], False
    for line in lines:
        if _READ_LINE.match(line):
            skipping = True
            continue
        if skipping and _LIST_LINE.match(line):
            continue
        skipping = False
        out.append(line)
    return "\n".join(out)


def check_read(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent's prompt names the sections of the docs it reads before it starts, as `Read: page.md#anchor`
    lines (`gds brief <owner/repo>#N` proposes them), and every one exists in the kit's docs. Helpers, the reviewer
    and `general-purpose` (refused by `check_agents`) are exempt, as for `check_issue`. A kit whose `lessons.py`
    cannot be loaded checks only that a line names a section."""
    rules = config.get("brief", {})
    inp = payload.get("tool_input") or {}
    kind = inp.get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if not rules.get("enforce", True) or kind in exempt or kind in config.get("agents", {}).get("refused", []):
        return []
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return []
    prompt = inp.get("prompt") or ""
    work = _WORK_LINE.search(prompt)
    ref = f"{work.group(2)}#{work.group(3)}" if work else "<owner/repo>#N"
    gds = f"uv run --project {(workspace / 'repos' / 'gdstudio' / 'python').as_posix()} gds"
    kit = kit_root(workspace)
    module = lessons_module(kit)
    listed = read_lines(prompt)
    refs = module.refs_in(listed) if module else re.findall(r"[\w./-]+\.md#[\w-]+", listed)
    if not refs:
        return [
            f"the agent type {kind!r} starts with the sections of the docs it reads first, and its prompt names none: "
            f"run `{gds} brief {ref}` and put the `Read: <page>.md#<anchor>` lines it prints in the prompt (add or "
            f"drop sections as the task needs; `--why` says why each is proposed)"
        ]
    missing = module.missing_refs(kit, listed) if module else []
    if missing:
        return [
            f"the prompt's Read: lines name sections that do not exist in {(kit / 'docs').as_posix()}: "
            f"{', '.join(missing)}. Name a section as <page under docs/>.md#<anchor> (docs/studio/rules.md#anchors); "
            f"`{gds} brief {ref}` and `{gds} learn <words>` print real ones"
        ]
    return []


def label_values(words: list[str]) -> list[str]:
    """The labels a `gh issue|pr edit|create` command adds (`--add-label X`, `--label=X`, `-l X`, comma lists)."""
    found: list[str] = []
    for i, word in enumerate(words):
        flag, _, inline = word.partition("=")
        if flag in ("--add-label", "--label", "-l"):
            value = inline or (words[i + 1] if i + 1 < len(words) else "")
            found += [v.strip() for v in value.split(",") if v.strip()]
    return found


def check_labels(words: list[str]) -> list[str]:
    """`S-in-progress` is set only by `gds issue start` and never on a pull request; only the maintainer sets
    `P-critical`. Covers `gh issue|pr edit|create` and a `gh api` call that writes labels."""
    if len(words) < 3 or program(words) != "gh":
        return []
    area, verb = words[1], words[2]
    if area in ("issue", "pr") and verb in ("edit", "create"):
        added = label_values(words)
    elif area == "api" and any(w in ("-f", "-F", "--field", "--raw-field", "--input", "-X", "--method") for w in words):
        # a write: any word naming the label counts (labels[]=..., labels=..., a path) unless it is a read
        read = any(w.upper() == "GET" for w in words)
        added = [] if read else [t for w in words for t in re.split(r"[=,\s\"'\[\]]+", w) if t]
    else:
        return []
    reasons = []
    if IN_PROGRESS in added:
        reasons.append(
            "a pull request is in progress by existing and never carries S-in-progress"
            if area == "pr"
            else "`S-in-progress` is set only by `gds issue start <owner/repo>#N --agent <name>`, which keeps the "
            "oldest-first order and writes the ledger the hooks read; `gds issue release` puts an issue back"
        )
    if CRITICAL in added:
        reasons.append("only the maintainer sets P-critical: report an issue that should have it instead")
    return reasons


def flag_values(words: list[str], flags: tuple[str, ...]) -> list[str]:
    """Every value given to any of `flags` (`--flag value` or `--flag=value`)."""
    found: list[str] = []
    for i, word in enumerate(words):
        flag, eq, inline = word.partition("=")
        if flag in flags:
            if eq:
                found.append(inline)
            elif i + 1 < len(words):
                found.append(words[i + 1])
    return found


_HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
_IMAGE = re.compile(r"!\[[^\]]*\]\(|<img[ >]")


def section_text(body: str, name: str) -> str:
    """The text of the `## name` section of a pull request body, without comments ('' when there is none)."""
    body = _HTML_COMMENT.sub("", body.replace("\r\n", "\n"))
    match = re.search(rf"^##[ \t]+{re.escape(name)}[ \t]*$", body, re.MULTILINE)
    if not match:
        return ""
    rest = body[match.end() :]
    following = re.search(r"^##[ \t]+\S", rest, re.MULTILINE)
    return rest[: following.start()] if following else rest


def label_line(text: str, label: str) -> re.Match[str] | None:
    """Where a `Label:` (bare, bulleted or in bold) starts a line of `text`."""
    bare = re.escape(label.rstrip(":"))
    return re.search(rf"^[ \t]*(?:[-*][ \t]*)?(?:\*\*{bare}:?\*\*:?|{bare}:)", text, re.MULTILINE)


_MARKDOWN_TARGET = re.compile(r"\]\(\s*([^)\s]+)\s*\)")
_DRIVE_PATH = re.compile(r"^[A-Za-z]:/")


def file_key(path: str, cwd: Path, lost: bool = False) -> str | None:
    """Which file `path` names when `gh` is run in `cwd`: its absolute, normalised path with forward slashes, or None
    when it cannot be told (a relative path after a `cd` the hook could not follow, or a web address). `gh --attach`
    rewrites a `](path)` reference in the body only when it names the same file as an `--attach` path
    (docs/studio/hooks.md#attach-paths), so both are placed this way before they are compared with `same_file`."""
    path = path.replace("\\", "/")
    if "://" in path:
        return None
    if os.name == "nt" and (drive := _MSYS_DRIVE.match(path)):  # Git Bash's /c/dir is C:/dir
        path = f"{drive.group(1).upper()}:{path[drive.end() :] or '/'}"
    if not (path.startswith("/") or _DRIVE_PATH.match(path)):
        if lost:
            return None
        path = f"{cwd.as_posix()}/{path}"
    return os.path.normpath(path).replace("\\", "/")


def same_file(first: str | None, second: str | None) -> bool:
    """True when two `file_key`s name one file (a file system that ignores case ignores it here)."""
    return first is not None and second is not None and os.path.normcase(first) == os.path.normcase(second)


def references_to(spec: str, text: str, cwd: Path, lost: bool = False) -> list[re.Match[str]]:
    """The markdown references `](path)` in `text` that `gh --attach <spec>` swaps for the upload: those naming the
    same file as `spec` once both are placed in `cwd` (`file_key`)."""
    wanted = file_key(spec, cwd, lost)
    if wanted is None:
        return []
    return [m for m in _MARKDOWN_TARGET.finditer(text) if same_file(file_key(m.group(1), cwd, lost), wanted)]


def references_by_name(name: str, text: str) -> list[str]:
    """The `](path)` targets in `text` whose file name is `name`, wherever they point."""
    return [
        m.group(1) for m in _MARKDOWN_TARGET.finditer(text) if PurePosixPath(m.group(1).replace("\\", "/")).name == name
    ]


_CD_PROGRAMS = ("cd", "chdir", "pushd", "set-location", "sl")
_CD_FLAGS = ("/d", "-p", "-l", "--", "-path", "-literalpath")
_MSYS_DRIVE = re.compile(r"^/([A-Za-z])(?=/|$)")


def change_dir(words: list[str], cwd: Path) -> tuple[bool, Path | None]:
    """(True, folder) for a plain `cd <dir>` (also `cd /d`, `pushd`, `Set-Location [-Path]`) as it moves `cwd`; (True,
    None) for a `cd` this cannot follow (`cd`, `cd -`, `cd $DIR`, a glob, more than one folder); (False, None) when the
    command is not a `cd`. The target is joined to `cwd` when relative, as the shell does."""
    if words[0].lower() not in _CD_PROGRAMS:
        return False, None
    args = [w for w in words[1:] if w.lower() not in _CD_FLAGS]
    if len(args) != 1 or args[0] == "-" or any(ch in args[0] for ch in "$`*?%(){}"):
        return True, None
    target = args[0]
    if target == "~" or target.startswith("~/"):
        target = os.path.expanduser(target)
    elif os.name == "nt" and (drive := _MSYS_DRIVE.match(target)):  # Git Bash's /c/dir is C:/dir
        target = f"{drive.group(1).upper()}:{target[drive.end() :] or '/'}"
    try:
        return True, (cwd / target).resolve()
    except (OSError, ValueError):
        return True, None


def body_of(words: list[str], cwd: Path, lost: bool = False) -> tuple[str | None, str]:
    """The body a `gh pr create|edit` command sends: (text, "") when it can be read here, else (None, why not).
    A relative `--body-file` is read from `cwd`, the folder the command's own `cd` moved to (the way `gh` reads it);
    `lost` says a `cd` before it could not be followed, so a relative path cannot be placed."""
    sources = flag_values(words, ("--body-file", "-F"))
    inline = flag_values(words, ("--body", "-b"))
    if sources:
        if sources[0] == "-":
            return None, "the body comes from standard input, which cannot be read here"
        path = Path(sources[0])
        if not path.is_absolute():
            if lost:
                return None, (
                    f"the body file {sources[0]} is relative to a folder this hook cannot follow (the `cd` before "
                    f"it is not a plain `cd <dir>`): use an absolute path"
                )
            path = cwd / path
        if not path.is_file():
            return None, (
                f"the body file {sources[0]} does not exist yet (looked for {path.as_posix()}; a relative path is "
                f"read from the folder the command is in after its `cd`: an absolute path always works)"
            )
        return path.read_text(encoding="utf-8", errors="replace"), ""
    if inline and "$(" not in inline[0] and "`" not in inline[0]:
        return inline[0], ""
    return None, "no body file is named (`--body-file <file>`)"


def pr_command(words: list[str]) -> str | None:
    """`create` or `edit` for a `gh pr create|edit` command, else None."""
    if len(words) < 3 or program(words) != "gh" or words[1] != "pr" or words[2] not in ("create", "edit"):
        return None
    return words[2]


def check_pr_body(words: list[str], cwd: Path, config: dict[str, Any], lost: bool = False) -> list[str]:
    """What a `gh pr create|edit` command sends, judged before it runs: the body is read once (`body_of`) and both
    checks use it, the images of `--attach` (`check_attach`) and the description rules of `pr-rules` (`check_body`)."""
    if pr_command(words) is None:
        return []
    read = body_of(words, cwd, True) if lost else body_of(words, cwd)
    return check_attach(words, cwd, config, read, lost) + check_body(words, cwd, config, read, lost)


def attached_paths(words: list[str]) -> list[str]:
    """The files `--attach` uploads, as written (`path#label` loses its label)."""
    return [v.split("#", 1)[0] for v in flag_values(words, ("--attach",))]


#: Where `--attach` puts an upload (`github.com/user-attachments/...`); a stand-in for the check below, never sent.
UPLOAD_STAND_IN = "https://github.com/user-attachments/assets/00000000-0000-0000-0000-000000000000"


def as_uploaded(body: str, files: list[str], cwd: Path, lost: bool = False) -> str:
    """The body as it reads after `--attach` has run: each `](path)` reference that names an attached file (the same
    file once both are placed in `cwd`, `file_key`) is the upload's address, which is what the description rules
    (`pr-rules`) count as a capture. Any other reference stays a local path and is still refused there: `gh` leaves
    it alone and appends the upload at the end of the body instead."""
    wanted = [file_key(spec, cwd, lost) for spec in files]

    def swap(match: re.Match[str]) -> str:
        here = file_key(match.group(1), cwd, lost)
        return f"]({UPLOAD_STAND_IN})" if any(same_file(here, key) for key in wanted) else match.group(0)

    return _MARKDOWN_TARGET.sub(swap, body)


def check_attach(
    words: list[str],
    cwd: Path,
    config: dict[str, Any],
    read: tuple[str | None, str] | None = None,
    lost: bool = False,
) -> list[str]:
    """`gh pr create|edit --attach` appends every image at the end of the body, after `## AI use`, unless the body
    already refers to it as `![alt](<path>)` with the path of the attached file: then that reference becomes the upload
    in place. `gh` compares the two as files, with relative paths taken from the folder it runs in, so a reference
    `./x.png` matches `--attach /scratch/x.png` only when the command runs in `/scratch`. Each attached file needs such
    a reference inside `## Screenshots`, a before capture between the `Before:` and `After:` lines and an after capture
    below `After:`. The body is read from `--body-file` (or a literal `--body`) before the command runs, so the
    refusal comes before a pull request with images in the wrong place exists."""
    rule = config.get("attach", {})
    if pr_command(words) is None:
        return []
    if not rule.get("enforce", True):
        return []
    files = attached_paths(words)
    if not files:
        return []
    section = rule.get("section", "Screenshots")
    sample = PurePosixPath(files[-1].replace("\\", "/")).name
    what = f"`gh pr {words[2]} --attach` puts an image the body does not refer to at the end, after `## AI use`"
    body, why = read or body_of(words, cwd, lost)
    if body is None:
        return [
            f"{what}, and {why}: write the whole body with the Write tool to a file, with `![after](./{sample})` on "
            f"the After: line of ## {section} (and `![before](./<file>)` on the Before: line), then run the command "
            f"with `--body-file <file>` next to `--attach` (an existing body is read with "
            f"`gh pr view N --json body -q .body`)"
        ]
    text = section_text(body, section)
    missing = [spec for spec in files if not references_to(spec, text, cwd, lost)]
    if missing:
        names = [PurePosixPath(spec.replace("\\", "/")).name for spec in missing]
        wrong = [
            f"`--attach {spec}` is a different file from `{target}` (`gh` finds that one at {where})"
            for spec, name in zip(missing, names, strict=True)
            for target in references_by_name(name, text)
            for where in [file_key(target, cwd, lost) or "a folder this hook cannot follow"]
        ]
        if wrong:
            return [
                f"{what}, and the body's reference does not name the attached file: {'; '.join(wrong)}. `gh` swaps a "
                f"`![alt](path)` reference only when it is the same file as an `--attach` path, a relative path taken "
                f"from the folder the command runs in ({cwd.as_posix() if not lost else 'unknown after this `cd`'}); "
                f"otherwise the reference stays a local path, the upload lands after `## AI use` and `pr-rules` finds "
                f"no capture. Run the command from the folder that holds the images (`cd <dir> && gh pr {words[2]} "
                f"... --attach ./<file name>`, a plain `cd`), or write the reference with the same absolute path as "
                f"`--attach`. Read the body back afterwards (`gh pr view N --json body -q .body`)"
            ]
        wanted = " and ".join(f"`![{PurePosixPath(n).stem}](./{n})`" for n in names)
        return [
            f"{what}, unless the body already refers to the file inside ## {section}: the body has no reference for "
            f"{', '.join(names)}. Write {wanted} in ## {section}: the before capture on the Before: line, the after "
            f"capture on the After: line, below it. Then run the same command; `--attach` swaps each reference for the "
            f"upload in place. Read the body back afterwards (`gh pr view N --json body -q .body`)"
        ]
    reasons = []
    before, after = label_line(text, "Before:"), label_line(text, "After:")
    if before and after and before.start() < after.start():
        between = text[before.end() : after.start()].strip()
        if not between.lower().startswith("none") and not _IMAGE.search(between):
            reasons.append(
                f"the Before: line of ## {section} has no image between it and the After: line: put the "
                f"before capture's reference (`![before](./<file>)`) right after `Before:`, above `After:`, or write "
                f"`Before: none (reason)` for something new"
            )
        if not _IMAGE.search(text[after.end() :]):
            reasons.append(
                f"no image comes after the After: line of ## {section}: put the after capture's reference "
                f"(`![after](./<file>)`) on or under it"
            )
    return reasons


_PR_MODULE = "_gds_pr_for_hooks"


def load_pr_module() -> Any:
    """`python/src/gds_tools/pr.py` of the kit, loaded by file (the hooks run without the `gds` package); None when it
    cannot be."""
    source = KIT / "python" / "src" / "gds_tools" / "pr.py"
    try:
        spec = importlib.util.spec_from_file_location(_PR_MODULE, source)
        module = importlib.util.module_from_spec(spec)
        sys.modules[_PR_MODULE] = module  # a dataclass looks its module up here
        spec.loader.exec_module(module)
        return module
    except Exception:  # a hook never locks a session out
        sys.modules.pop(_PR_MODULE, None)
        return None


def here_checkout(cwd: Path) -> Path | None:
    """The git checkout around `cwd`."""
    top = git(cwd, "rev-parse", "--show-toplevel")
    return Path(top) if top else None


def pr_checkout(words: list[str], cwd: Path) -> Path | None:
    """The checkout whose `.github/conventions.yml` judges a `gh pr` command: the one around `cwd`, or, when `-R
    owner/name` names another repository, `<workspace>/repos/<name>`."""
    top = git(cwd, "rev-parse", "--show-toplevel")
    here = Path(top) if top else None
    named = flag_values(words, ("-R", "--repo"))
    if not named:
        return here
    name = named[0].rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")
    if here and git(here, "remote", "get-url", "origin").removesuffix(".git").endswith(f"/{name}"):
        return here
    workspace = workspace_of(cwd)
    other = workspace / "repos" / name if workspace else None
    return other if other and other.is_dir() else None


def check_body(
    words: list[str],
    cwd: Path,
    config: dict[str, Any],
    read: tuple[str | None, str] | None = None,
    lost: bool = False,
) -> list[str]:
    """`gh pr create|edit` with a body that `pr-rules` would refuse after the push is refused now, with the command to
    run (`gds pr check-body`, the same `groundwork.py check-body` function CI uses, in the repository's own checkout so
    a game's own conventions apply). A body that cannot be read here (standard input, a file not written yet) is not
    judged; neither is one when the checker cannot run: no checks beat a locked session."""
    rule = config.get("pr_body", {})
    if pr_command(words) is None or not rule.get("enforce", True):
        return []
    if not flag_values(words, ("--body", "-b", "--body-file", "-F")):
        return []
    body, _ = read or body_of(words, cwd, lost)
    if body is None:
        return []
    body = as_uploaded(body, attached_paths(words), cwd, lost)
    repo = pr_checkout(words, cwd)
    module = load_pr_module()
    if repo is None or module is None:
        return []
    titles = flag_values(words, ("--title", "-t"))
    try:
        changed, why = module.branch_changes(repo) if repo == here_checkout(cwd) else ([], "another checkout")
        result = module.check_body(repo, body, titles[0] if titles else None, kit=KIT, changed=None if why else changed)
        if result.ok and repo == here_checkout(cwd):  # the docs rule reads the branch checked out here
            result = module.check_docs(repo, body, kit=KIT)  # (`unknown` is not a refusal: pr-rules judges it)
    except Exception:  # the checker is missing, slow or broken: let the command through
        return []
    if result.ok:
        return []
    source = flag_values(words, ("--body-file", "-F"))
    named_file = source[0] if source and source[0] != "-" else "<body file>"
    title = " --title <title file>" if titles else ""
    run = f"uv run --project {KIT.as_posix()}/python gds pr check-body {named_file}{title}"
    return [
        f"`gh pr {words[2]}` sends a description that `pr-rules` refuses ({repo.name}): "
        + "; ".join(result.reasons)
        + f". Fix the body file (write it with the Write tool) and check it with `{run}` until it passes, then run "
        f"the same command"
    ]


def check_git(words: list[str], cwd: Path, config: dict[str, Any]) -> list[str]:
    """Commits and pushes: never on a protected branch, never forced, never past the hooks."""
    here, rest = git_dir_of(words, cwd)
    if not rest:
        return []
    verb, args = rest[0], rest[1:]
    protected = config.get("git", {}).get("protected_branches", ["main"])
    reasons: list[str] = []
    if verb == "worktree" and args[:1] == ["add"]:
        refused = disk_refusal(here, config, "a new worktree")
        if refused:
            reasons.append(refused)
    if verb in ("commit", "push") and ("--no-verify" in args or (verb == "commit" and "-n" in args)):
        reasons.append(f"`git {verb} --no-verify` skips the checks; fix what they report instead")
    if verb == "commit":
        branch = git(here, "rev-parse", "--abbrev-ref", "HEAD")
        if branch in protected:
            reasons.append(
                f"`{branch}` takes no commits: `git switch -c <branch>` (or a worktree under "
                f"<workspace>/worktrees/<repo>/<branch>/) and open a pull request"
            )
    if verb == "push":
        if any(
            a in ("--force", "-f", "--force-with-lease", "--force-if-includes")
            or a.startswith("--force")
            or (not a.startswith("-") and a.startswith("+"))
            for a in args
        ):
            reasons.append("force-pushing is a maintainer decision; push a new commit instead")
        refspecs = [a for a in args if not a.startswith("-")][1:]  # the first is the remote
        targets = {r.split(":")[-1].removeprefix("refs/heads/").lstrip("+") for r in refspecs}
        if not refspecs:
            targets = {git(here, "rev-parse", "--abbrev-ref", "HEAD")}
        hit = sorted(t for t in targets if t in protected)
        if hit:
            reasons.append(f"`{hit[0]}` takes no pushes: push your branch and open a pull request")
    return reasons


def manual_paths(repo: Path) -> list[str]:
    """merge.manual_paths of the repository's conventions (read with a regex: no YAML reader here)."""
    conv = repo / ".github" / "conventions.yml"
    if not conv.exists():
        return []
    found = re.search(
        r"^\s*manual_paths:\s*\[(.*?)\]",
        conv.read_text(encoding="utf-8"),
        re.MULTILINE | re.DOTALL,
    )
    return [p.strip().strip("'\"") for p in found.group(1).split(",") if p.strip()] if found else []


def check_merge(words: list[str], cwd: Path) -> list[str]:
    """`gh pr merge`: never `--admin`, and never on a pull request that changes a manual path (a maintainer merges
    those by hand, merge.manual_paths)."""
    if len(words) < 3 or words[1:3] != ["pr", "merge"]:
        return []
    args = words[3:]
    if "--admin" in args:
        return ["`gh pr merge --admin` bypasses the branch rules; let the required checks pass"]
    if "--disable-auto" in args:
        return []
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    paths = manual_paths(repo)
    if not paths:
        return []
    target = next((a for a in args if not a.startswith("-")), None)
    try:
        cmd = [
            "gh",
            "pr",
            "view",
            *([target] if target else []),
            "--json",
            "files",
            "--jq",
            ".files[].path",
        ]
        out = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    hits = [f for f in out.stdout.split() if any(f == p or (p.endswith("/") and f.startswith(p)) for p in paths)]
    if hits:
        return [f"this pull request changes {', '.join(hits[:5])}: a maintainer merges it by hand; report it instead"]
    return []


_API_MERGE = re.compile(r"repos/([\w.-]+/[\w.-]+)/pulls/(\d+)/merge\b")
_API_ISSUE = re.compile(r"repos/([\w.-]+/[\w.-]+)/issues/(\d+)(/labels)?(?:[/?]|$)")
_API_LABEL = re.compile(r"/labels/([^/?\s]+)")
_MERGE_MUTATIONS = re.compile(r"\b(mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest)\b")
_LABEL_MUTATIONS = re.compile(r"\b(removeLabelsFromLabelable|clearLabelsFromLabelable|updateLabel|deleteLabel)\b")
_VALUE_FLAGS = ("-R", "--repo", "-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email")
_HELD = f"a maintainer holds it (`{HOLD}`): stop and report; only the maintainer takes the label off"
_API_FIELD_FLAGS = ("-f", "-F", "--field", "--raw-field", "--input")
_API_VALUE_FLAGS = (*_API_FIELD_FLAGS, "-X", "--method", "-H", "--header", "-q", "--jq", "-t", "--template")
_API_VALUE_FLAGS += ("-p", "--preview", "--hostname", "--cache")


def held(target: str, repo: str | None, cwd: Path) -> bool | None:
    """Whether a pull request (its number, URL or branch) carries the hold label; None when GitHub cannot be asked. A
    guard that cannot look lets the call through: GitHub's required `hold` check is the rule, this explains it."""
    command = ["gh", "pr", "view", *([target] if target else []), *(["-R", repo] if repo else [])]
    try:
        out = subprocess.run(
            [*command, "--json", "labels", "--jq", ".labels[].name"],
            cwd=cwd if cwd.is_dir() else None,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return HOLD in out.stdout.split() if out.returncode == 0 else None


def api_call(words: list[str]) -> tuple[str, list[str], list[str]]:
    """A `gh api` call as gh reads it: its upper-case HTTP method (`-X`, or POST when it sends fields or `--input`, else
    GET), its endpoints and the values of its fields (an `--input` file counts as a field with no text to read)."""
    method, endpoints, fields, i = "", [], [], 2
    while i < len(words):
        word = re.sub(r"^-i+(?=[^-])", "-", words[i])  # `-i` takes no value, so it can lead a cluster: `-iX POST`
        i += 1
        if not word.startswith("-") or word == "-":
            endpoints.append(word)
            continue
        flag, has_value, value = word.partition("=") if word.startswith("--") else (word[:2], len(word) > 2, word[2:])
        value = value.removeprefix("=")
        if flag in _API_VALUE_FLAGS and not has_value and i < len(words):
            value = words[i]
            i += 1
        if flag in ("-X", "--method"):
            method = value.upper()
        elif flag in _API_FIELD_FLAGS:
            fields.append(value)
    return method or ("POST" if fields else "GET"), endpoints, fields


def api_method(words: list[str]) -> str:
    """The HTTP method of a `gh api` call."""
    return api_call(words)[0]


def check_hold_api(words: list[str], cwd: Path) -> list[str]:
    """`gh api`: a merge of a held pull request, or any write that would take the label off it or off the repository."""
    if words[2] == "graphql":
        text = " ".join(words[3:])
        if _MERGE_MUTATIONS.search(text) or _LABEL_MUTATIONS.search(text):
            return [f"a GraphQL mutation cannot be read for `{HOLD}`: use `gh pr merge` or `gh pr edit` instead"]
        return []
    method, reasons = api_method(words), []
    if method == "GET":
        return []
    for word in words[2:]:
        path = unquote(word)
        merge = _API_MERGE.search(path)
        if merge and held(merge.group(2), merge.group(1), cwd):
            reasons.append(f"{merge.group(1)}#{merge.group(2)}: {_HELD}")
        label = _API_LABEL.search(path)
        if label:
            if label.group(1) == HOLD and method in ("DELETE", "PATCH"):
                reasons.append(f"`{HOLD}` is taken off only by the maintainer, by hand on the pull request's page")
            continue
        issue = _API_ISSUE.search(path)
        if not issue:
            continue
        replaces = method in ("DELETE", "PUT") if issue.group(3) else method == "PATCH" and "labels" in " ".join(words)
        if replaces and held(issue.group(2), issue.group(1), cwd):
            reasons.append(f"this replaces the labels of {issue.group(1)}#{issue.group(2)}: {_HELD}")
    return reasons


def check_hold(words: list[str], cwd: Path) -> list[str]:
    """The hook's half of the hold (docs/studio/hooks.md#hold): no merge command on a pull request carrying the label,
    and no
    removal of the label by a session. The label is what GitHub enforces; this says why, and it is what stops a session
    taking the label off, since a token cannot tell an agent from the maintainer."""
    if len(words) < 3:
        return []
    area, verb = words[1], words[2]
    if area == "api":
        return check_hold_api(words, cwd)
    if area == "label" and verb in ("delete", "edit") and HOLD in words[3:]:
        return [f"`{HOLD}` is the label GitHub's hold reads: it is not deleted or renamed"]
    if area in ("pr", "issue") and verb == "edit":
        removed = [name.strip() for value in flag_values(words, ("--remove-label",)) for name in value.split(",")]
        if HOLD in removed:
            return [f"`{HOLD}` is taken off only by the maintainer, on the pull request's page: report it instead"]
    if area == "pr" and verb == "merge" and "--disable-auto" not in words:
        positional = [
            word for i, word in enumerate(words[3:], 3) if not word.startswith("-") and words[i - 1] not in _VALUE_FLAGS
        ]
        named = flag_values(words, ("-R", "--repo"))
        target = positional[0] if positional else ""
        if held(target, named[0] if named else None, cwd):
            return [f"{target or 'this pull request'}: {_HELD}"]
    return []


# The commands that exist to post (`gh help` of gh 2.102), and those that post when they carry `--comment` or `-c`.
_COMMENT_COMMANDS = {("issue", "comment"), ("pr", "comment"), ("discussion", "comment"), ("pr", "review")}
_CLOSING_COMMANDS = {("issue", "close"), ("pr", "close"), ("issue", "reopen"), ("pr", "reopen")}
# The mutations of GitHub's schema that add, edit or submit a comment or a review.
_COMMENT_MUTATIONS = re.compile(
    r"\b(addComment|addDiscussionComment|addPullRequestReview\w*|dismissPullRequestReview|submitPullRequestReview"
    r"|updateDiscussionComment|updateIssueComment|updatePullRequestReview\w*)\b"
)
_NO_COMMENTS = (
    "nothing is posted as a comment or review under the maintainer's GitHub account (their decision of 2026-10-12). "
    "Run the command without the text (`gh issue close N`) and put the text in your scratch folder and your report, "
    "for the maintainer to post; a capture goes on a pull request or a new issue with `--attach` "
    "(docs/studio/hooks.md#comments)"
)
# Words that start another program on the same line, and the arguments they take before it.
_LAUNCHERS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "try", "env", "command", "timeout"}
_LAUNCHERS |= {"nohup", "xargs"}
_LAUNCHER_ARG = re.compile(r"[-\d{]|\w+=")
_SHELLS = {"bash", "sh", "zsh", "dash", "pwsh", "powershell", "cmd", "eval"}
_SHELL_FLAG = re.compile(r"-\w+|/[a-zA-Z]")
_CONTINUATION = re.compile(r"(?:\\|(?<=\s)`)\r?\n")  # a line continued in bash, or in PowerShell
_SINGLE_QUOTED = re.compile(r"'[^'\n]*'")
_INNER_GH = re.compile(r"(?:\$\(|`|\{\s)\s*(?=(?:[^\s'\"(){}]*[/\\])?gh(?:\.exe)?\s)")


def launched(words: list[str]) -> list[str]:
    """The words from the program a simple command runs: past `then`, `(`, `env X=1`, `timeout 30`, `xargs -n1`."""
    words = [words[0].lstrip("("), *words[1:]]
    i = 0
    while i < len(words) and (words[i] in _LAUNCHERS or (i and _LAUNCHER_ARG.match(words[i]))):
        i += 1
    return words[i:]


def gh_calls(command: str) -> list[list[str]]:
    """Every `gh` command a shell line runs, also inside `bash -c '...'`, `eval` and `$(...)`, as words. Text that only
    mentions one is left out: an `echo`, a commit message, a `grep`, a single-quoted body, a heredoc."""
    text = _CONTINUATION.sub(" ", strip_heredocs(command))
    found: list[list[str]] = []
    for simple in segments(text):
        words = launched(simple)
        if not words:
            continue
        name = program(words)
        if name == "gh":
            found.append(words)
        elif name in _SHELLS:
            args = words[1:]
            while args and _SHELL_FLAG.fullmatch(args[0]):
                args = args[1:]
            found += gh_calls(" ".join(args))
    bare = _SINGLE_QUOTED.sub("''", text)
    for inner in _INNER_GH.finditer(bare):
        found += gh_calls(re.split(r"[)`}\n]", bare[inner.end() :], maxsplit=1)[0])
    return found


def gh_route(words: list[str]) -> tuple[str, ...]:
    """The group and the command of a `gh` command. `-R` and a misplaced `--comment` may stand before them: gh takes
    `gh issue -R o/r close 5`, and cobra hands a flag it finds there to the command."""
    route: list[str] = []
    i = 1
    while i < len(words) and len(route) < 2:
        word = words[i]
        i += 1
        if word in ("-R", "--repo", "--comment", "-c"):
            i += 1
        elif not word.startswith("-"):
            route.append(word.rstrip(")"))
    return tuple(route)


def comment_flag(words: list[str]) -> str | None:
    """`--comment` or `-c` as gh reads it on a close or reopen (`--comment=x`, `-cx`, `-c=x`, the cluster `-dc x`), or
    None. The value of an option that takes one is not read as an option: `--reason -c`, `-Rco/r`."""
    i = 1
    while i < len(words):
        word = words[i]
        i += 1
        if word == "--":
            return None
        if word.startswith("--"):
            flag, has_value, _ = word.partition("=")
            if flag == "--comment":
                return flag
            i += flag in ("--repo", "--reason", "--duplicate-of") and not has_value
        elif word.startswith("-"):
            for position, letter in enumerate(word[1:], 2):
                if letter == "c":
                    return "-c"
                if letter in "Rr":
                    i += position == len(word)  # the value is the next word, or the rest of this one
                    break
    return None


def api_comment(words: list[str]) -> str | None:
    """What is wrong with a `gh api` call that posts a comment or a review: a write to a path with a `comments` or
    `reviews` part, a mutation that posts one, or a GraphQL query that is not on the command line to be read."""
    method, endpoints, fields = api_call(words)
    paths = [unquote(re.split(r"[?#]", endpoint, maxsplit=1)[0]) for endpoint in endpoints]
    if any(path.rstrip("/").endswith("graphql") for path in paths):
        found = _COMMENT_MUTATIONS.search(" ".join(fields))
        if found:
            return f"the GraphQL mutation `{found.group(1)}` posts one"
        if not any(field.startswith("query=") and "{" in field.replace("${", "") for field in fields):
            return "a GraphQL query from a file or a variable cannot be read for a comment: write it in the command"
        return None
    if method in ("POST", "PATCH", "PUT") and any({"comments", "reviews"} & set(path.split("/")) for path in paths):
        return f"`gh api -X {method}` to a comments or reviews path posts one"
    return None


def comment_route(words: list[str]) -> str | None:
    """How a `gh` command posts a comment or a review, or None when it posts neither."""
    route = gh_route(words)
    if route[:1] == ("api",):
        return api_comment(words)
    if route in _COMMENT_COMMANDS:
        return f"`gh {' '.join(route)}` posts one"
    if route in _CLOSING_COMMANDS:
        flag = comment_flag(words)
        return f"`gh {' '.join(route)} {flag}` posts one" if flag else None
    if route == ("alias", "set"):  # an alias would hide the route from this guard on every later use
        calls = [call for text in words[3:] for call in gh_calls(f"gh {text}") + gh_calls(text.lstrip("!"))]
        return next(filter(None, map(comment_route, calls)), None)
    return None


def check_comments(command: str) -> list[str]:
    """The rule against comments under the maintainer's account (docs/studio/hooks.md#comments), judged on what `gh`
    would do,
    not on a list of the commands named `comment`: `gh issue close --comment` put one on #691."""
    routes = filter(None, map(comment_route, gh_calls(command)))
    return [f"{route}: {_NO_COMMENTS}" for route in routes]


def check_tools(words: list[str], config: dict[str, Any]) -> list[str]:
    """Godot and Blender only from the workspace's pinned copies."""
    names = config.get("tools", {}).get("names", [])
    first = words[0].replace("\\", "/").lower()
    if "$" in first or "%" in first:  # a variable the guard cannot expand: judge only what it can see
        return []
    if any(n in first for n in names) and "steamapps" in first:
        return ["Steam's copy updates itself; use the pinned one: `gds tool path godot|blender`"]
    if program(words) in names and "/tools/" not in first:
        return [
            f"`{program(words)}` from PATH is not the pinned copy; run "
            f"`$(uv run --project <kit>/python gds tool path {program(words)})`"
        ]
    return []


_GODOT_VARIABLE = re.compile(r"\$(?:\{|env:)?\w*godot\w*\}?", re.IGNORECASE)
_WINDOWLESS = ("--headless", "--version", "--help", "-h")


def launches_godot(words: list[str]) -> bool:
    """True for a command that starts Godot itself: its program, a variable named like it (`$GODOT`) or a
    `$(... gds tool path godot)` substitution; false for `gds godot`, `gds tool path godot` and the like."""
    first = words[0]
    if program(words).startswith("godot") or _GODOT_VARIABLE.fullmatch(first):
        return True
    return first.startswith(("$(", "`")) and "tool path godot" in " ".join(words[:14])


def check_godot_window(words: list[str], config: dict[str, Any]) -> list[str]:
    """A windowed Godot started straight from a shell takes the keyboard and cursor from the person at the machine."""
    flags = tuple(config.get("tools", {}).get("windowless_flags", _WINDOWLESS))
    if not launches_godot(words) or any(w in flags for w in words[1:]):
        return []
    return [
        "a windowed Godot takes the keyboard focus from the person at the machine; run it with "
        "`uv run --project <kit>/python gds godot -- <arguments>` (or `gds capture frames`), or add --headless "
        "when nothing needs to be drawn (docs/engines/godot/no-focus.md)"
    ]


def runs_gds_godot(words: list[str]) -> bool:
    """True for a command run through `gds godot` (any `gds` program followed by `godot`)."""
    return any(program([w]) == "gds" and nxt == "godot" for w, nxt in zip(words, words[1:], strict=False))


def audio_driver(words: list[str]) -> str | None:
    """The value of the `--audio-driver` option in a command, lower-case, or None when it does not set one."""
    for word, nxt in zip(words, [*words[1:], ""], strict=False):
        if word == "--audio-driver":
            return nxt.lower()
        if word.startswith("--audio-driver="):
            return word.partition("=")[2].lower()
    return None


def check_godot_audio(words: list[str], config: dict[str, Any]) -> list[str]:
    """A Godot an agent starts plays through the speakers of the person at the machine unless its audio driver is
    Dummy. `--headless` and Movie Maker force Dummy and `gds godot` adds it, so only a launch that asks for another
    driver (or for `gds godot --with-audio`, which a person types in their own shell) is refused."""
    if not (launches_godot(words) or runs_gds_godot(words)):
        return []
    driver = audio_driver(words)
    wants_sound = (driver is not None and driver != "dummy") or (runs_gds_godot(words) and "--with-audio" in words)
    if not wants_sound:
        return []
    return [
        "agents never listen, and a Godot with a real audio driver plays through the speakers of the person at the "
        "machine; drop `--audio-driver` / `--with-audio`: `gds godot`, `--headless` and Movie Maker use "
        "`--audio-driver Dummy`, which still runs the mixer the audio checks read "
        "(docs/engines/godot/no-focus.md#sound)"
    ]


_RUNNERS = {"python", "python3", "py", "node", "npx", "pnpm", "bunx", "playwright"}
_NOT_A_RUN = {"install", "install-deps", "uninstall", "--version", "-V", "--help", "-h", "show-report"}


def wrapped_in_quiet(words: list[str]) -> bool:
    """True for a command run through `gds quiet` (any `gds` program followed by `quiet`)."""
    return any(program([w]) == "gds" and nxt == "quiet" for w, nxt in zip(words, words[1:], strict=False))


def runs_browser_probe(words: list[str], config: dict[str, Any]) -> bool:
    """True for a command that runs a local browser probe: a script on a probe path (`tools/web_smoke/*.py`) or a
    Playwright run (`playwright test`, `npx playwright ...`, `uv run --with playwright ... python x.py`)."""
    rules = config.get("tools", {})
    names = [program([w]) for w in words]
    runner = next((i for i, n in enumerate(names) if n in _RUNNERS), None)
    if runner is None:
        return False
    after = words[runner + 1 :]
    if any(matches(w, rules.get("browser_probes", ["**/web_smoke/*.py"])) for w in after):
        return True
    if not any(m in w.lower() for w in words for m in rules.get("browser_markers", ["playwright"])):
        return False
    if any(w in _NOT_A_RUN for w in words[1:]):  # `playwright install chromium`, `pip install playwright`: no browser
        return False
    if names[runner] in ("python", "python3", "py"):
        return "-c" in after or any(w.endswith(".py") for w in after)
    return True


def check_browser_probe(words: list[str], config: dict[str, Any]) -> list[str]:
    """A local browser probe under pointer lock clips the person's real cursor to its hidden window."""
    if wrapped_in_quiet(words) or not runs_browser_probe(words, config):
        return []
    return [
        "a headless browser under pointer lock clips the real cursor of the person at the machine to its hidden "
        "window; run the probe with `uv run --project <kit>/python gds quiet -- <command>` "
        "(docs/engines/godot/no-focus.md)"
    ]


_DUMPS = {"env", "printenv"}
_PRINTERS = {
    "echo",
    "printf",
    "write-output",
    "write-host",
    "print",
    "cat",
    "type",
    "printenv",
}


def check_kill(words: list[str], config: dict[str, Any]) -> list[str]:
    """No killing a shared tool by name: every agent's Godot or Blender run on the machine dies with it."""
    names = config.get("tools", {}).get("names", [])
    name = program(words)
    args = [w.lower() for w in words[1:]]
    by_name = False
    if name == "taskkill":
        by_name = any(a in ("/im", "-im") for a in args)
    elif name in ("pkill", "killall"):
        by_name = True
    elif name in ("stop-process", "spps", "kill") and any(a.startswith("-n") for a in args):
        by_name = True  # Stop-Process -Name (and its alias kill/spps); a bare `kill <pid>` has no -Name
    if by_name and any(n in a for a in args for n in names):
        return ["killing by name stops every agent's run on this machine; kill your own process by its PID"]
    return []


def check_secrets(words: list[str], command: str, config: dict[str, Any]) -> list[str]:
    """Nothing that prints a secret into the transcript: an echo of a key-like variable, or an environment dump."""
    name = program(words)
    pattern = config.get("protect", {}).get("secret_names")
    if name in _DUMPS and len(words) == 1:
        return ["dumping the environment would print secrets; read the one variable you need without printing it"]
    if name in ("get-childitem", "gci", "ls", "dir") and any(w.lower().rstrip("\\/") in ("env:",) for w in words[1:]):
        return ["listing env: would print secrets; test for the variable instead (`[bool]$env:NAME`)"]
    if pattern and name in _PRINTERS and re.search(pattern, " ".join(words[1:])):
        return ['that would print a secret into the transcript; check it is set (`[ -n "$NAME" ]`) instead']
    return []


def check_edit(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """Protected and generated files are never edited by hand."""
    inp = payload.get("tool_input") or {}
    path = inp.get("file_path") or inp.get("notebook_path") or ""
    if not path:
        return []
    rules = config.get("protect", {})
    if matches(path, rules.get("paths", [])):
        return [f"{path} is protected (secrets, caches, git internals or a pinned tool)"]
    project = Path(payload.get("cwd") or ".")
    try:
        rel = Path(path).resolve().relative_to(project.resolve()).as_posix()
    except ValueError:
        return []
    if matches(rel, rules.get("generated", [])):
        return [f"{rel}: {rules.get('generated_hint', 'it is generated')}"]
    return []


def pre_tool_use(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """Every reason to refuse this tool call."""
    tool = payload.get("tool_name", "")
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace:
        start_disk_guard(workspace, config)  # throttled: one stat of a stamp file when it is not yet time
    if tool in AGENT_TOOLS:
        return (
            check_agents(payload, config)
            + check_issue(payload, config)
            + check_read(payload, config)
            + check_disk_agent(payload, config)
        )
    if tool in EDIT_TOOLS:
        return check_edit(payload, config)
    if tool not in SHELL_TOOLS:
        return []
    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = Path(payload.get("cwd") or ".")
    reasons = check_comments(command)
    lost = False  # a `cd` this cannot follow came before: a relative path no longer has a known folder
    for words in segments(command):
        moved, folder = change_dir(words, cwd)
        if moved:
            if folder is None:
                lost = True  # and it stays so for the rest of the line, whatever a later `cd` says
            else:
                cwd = folder
            continue
        name = program(words)
        if name == "git":
            reasons += check_git(words, cwd, config)
        elif name == "gh":
            reasons += check_merge(words, cwd)
            reasons += check_hold(words, cwd)
            reasons += check_labels(words)
            reasons += check_pr_body(words, cwd, config, lost)
        reasons += check_tools(words, config)
        reasons += check_godot_window(words, config)
        reasons += check_godot_audio(words, config)
        reasons += check_browser_probe(words, config)
        reasons += check_kill(words, config)
        reasons += check_secrets(words, command, config)
    return list(dict.fromkeys(reasons))


# --------------------------------------------------------------------------------------------------------------------
# Stop: no visual change ends a session without a capture; no correction ends it unrecorded
# --------------------------------------------------------------------------------------------------------------------


def changed_files(repo: Path, protected: list[str]) -> list[str]:
    """Files changed on this branch (against the default branch) and in the working tree."""
    files = set()
    for line in git(repo, "status", "--porcelain", "--untracked-files=all").splitlines():
        files.add(line[3:].split(" -> ")[-1].strip('"'))
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    if branch and branch not in protected:
        base = git(repo, "merge-base", "HEAD", "origin/main") or git(repo, "merge-base", "HEAD", "main")
        if base:
            files.update(git(repo, "diff", "--name-only", f"{base}..HEAD").splitlines())
    return sorted(f for f in files if f)


def scratch_folder(repo: Path) -> Path | None:
    """<workspace>/scratch/<repo>/<branch>/, where a branch's captures and reports go."""
    workspace = workspace_of(repo)
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD") or "detached"
    name = repo.name if repo.parent.name == "repos" else repo.parent.name  # a worktree: worktrees/<repo>/<branch>
    return workspace / "scratch" / name / branch.replace("/", "-") if workspace else None


def stop(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Every reason to hold the session back once (the proof gate, the lessons queue), or None. A session already
    held by a Stop hook (`stop_hook_active`) is let go, so the gates never loop."""
    idle = stop_idle(payload, config)  # counts its own refusals, so it ignores stop_hook_active
    if payload.get("stop_hook_active"):
        return idle
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace:
        pull_mains(workspace, config)
        start_sweep(workspace, config)
        start_disk_guard(workspace, config)
    reasons = [
        r for r in (stop_proof(payload, config), stop_queue(payload, config), stop_kit_docs(payload, config), idle) if r
    ]
    return "\n\n".join(reasons) or None


def stop_proof(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The proof gate: a session that changed visual files of a game ends only once a newer capture exists."""
    cwd = Path(payload.get("cwd") or ".")
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    if not (repo / "game" / "project.godot").exists():
        return None
    rules = config.get("proof", {})
    visual = [
        f
        for f in changed_files(repo, config.get("git", {}).get("protected_branches", ["main"]))
        if matches(f, rules.get("visual", [])) and (repo / f).exists()
    ]
    if not visual:
        return None
    newest = max((repo / f).stat().st_mtime for f in visual)
    folder = scratch_folder(repo)
    if folder is None:
        return None
    shots = (
        [p for p in folder.rglob("*") if p.is_file() and matches(p.name, rules.get("captures", []))]
        if folder.exists()
        else []
    )
    if any(p.stat().st_mtime >= newest for p in shots):
        return None
    return (
        f"Visual files changed ({', '.join(visual[:4])}{'...' if len(visual) > 4 else ''}) with no capture "
        f"newer than them in {folder}. Capture the result (Godot's Movie Maker: `--write-movie "
        f"{folder.as_posix()}/<name>.png --fixed-fps 10 --quit-after 5`), look at it, then finish; attach it to "
        f"the pull request with `gh pr create|edit --attach`."
    )


# --------------------------------------------------------------------------------------------------------------------
# Local mains: every main checkout in <workspace>/repos/ follows origin after a merge (docs/studio/hooks.md#mains)
# --------------------------------------------------------------------------------------------------------------------

_MERGE_API = re.compile(r"/pulls/\d+/merge\b")


def is_merge(words: list[str]) -> bool:
    """`gh pr merge ...` or `gh api ... repos/<o>/<r>/pulls/<n>/merge`: a command that merges a pull request."""
    if program(words) != "gh" or len(words) < 2:
        return False
    if words[1:3] == ["pr", "merge"]:
        return True
    return words[1] == "api" and any(_MERGE_API.search(w) for w in words[2:])


def pull_mains(workspace: Path, config: dict[str, Any], force: bool = False) -> list[str]:
    """Fast-forward each repository under `<workspace>/repos/` that has `main` checked out, at most once every
    `[mains] every_seconds` unless `force`. Never discards anything: a checkout with local changes in the way, or one
    on another branch, is left as it is and named. Returns one line per repository that moved or could not."""
    rules = config.get("mains", {})
    if not rules.get("pull", True):
        return []
    stamp = workspace / rules.get("stamp", "cache/mains-pulled")
    now = time.time()
    if not force and stamp.exists() and now - stamp.stat().st_mtime < float(rules.get("every_seconds", 120)):
        return []
    try:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.touch()
    except OSError:
        pass
    notes: list[str] = []
    repos = workspace / "repos"
    mains = config.get("git", {}).get("protected_branches", ["main"])
    for repo in sorted(p for p in repos.iterdir() if (p / ".git").is_dir()) if repos.is_dir() else []:
        if git(repo, "rev-parse", "--abbrev-ref", "HEAD") not in mains:
            continue
        before = git(repo, "rev-parse", "HEAD")
        try:
            result = subprocess.run(
                ["git", "-C", str(repo), "pull", "--ff-only", "--quiet"], capture_output=True, text=True, timeout=30
            )
        except (OSError, subprocess.SubprocessError) as error:
            notes.append(f"{repo.name}: main not pulled ({type(error).__name__})")
            continue
        if result.returncode != 0:
            why = (result.stderr.strip().splitlines() or ["git pull --ff-only failed"])[0]
            notes.append(f"{repo.name}: main not pulled, {why} (local changes are left alone: ask before discarding)")
        elif git(repo, "rev-parse", "HEAD") != before:
            notes.append(f"{repo.name}: main pulled to {git(repo, 'log', '-1', '--format=%h %s')}")
    return notes


# --------------------------------------------------------------------------------------------------------------------
# The disk guard (docs/studio/hooks.md#disk): a background `gds disk guard`, and no new agent or worktree under the
# hard limit
# --------------------------------------------------------------------------------------------------------------------

GB = 1024**3


def free_bytes(path: Path) -> int | None:
    """Free bytes of the disk holding `path`; None when it cannot be read (a guard that cannot look lets it pass)."""
    try:
        return shutil.disk_usage(path).free
    except OSError:
        return None


def disk_status(workspace: Path, config: dict[str, Any]) -> dict[str, Any]:
    """The last `gds disk guard` run's status file; empty when there is none."""
    path = workspace / config.get("disk", {}).get("status", "cache/disk-guard.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def disk_level(workspace: Path, config: dict[str, Any]) -> tuple[str, float | None]:
    """(`hard` | `soft` | `ok`, free GB) of the workspace's disk; `ok` when the guard is off or the disk unreadable."""
    rules = config.get("disk", {})
    free = free_bytes(workspace)
    if not rules.get("enabled", True) or free is None:
        return "ok", None if free is None else free / GB
    gb = free / GB
    if gb < float(rules.get("hard_gb", 10)):
        return "hard", gb
    if gb < float(rules.get("soft_gb", 40)):
        return "soft", gb
    return "ok", gb


def disk_refusal(cwd: Path, config: dict[str, Any], what: str) -> str | None:
    """Why `what` may not start: the workspace's disk is under `[disk] hard_gb`. None outside a workspace or above."""
    workspace = workspace_of(cwd)
    if workspace is None:
        return None
    state, gb = disk_level(workspace, config)
    if state != "hard" or gb is None:
        return None
    hard = config.get("disk", {}).get("hard_gb", 10)
    biggest = disk_status(workspace, config).get("biggest", [])[:5]
    names = "; ".join(f"{b.get('path')} {b.get('gb')} GB" for b in biggest if isinstance(b, dict))
    return (
        f"{what} is refused: the disk has {gb:.1f} GB free, under the hard limit of {hard} GB "
        f"(docs/studio/hooks.md#disk). "
        f"Nothing new starts until space is back. `gds disk guard` frees what the rules allow (finished worktrees, "
        f"idle import caches, scratch downloads past their pull request); report what is left to the coordinator and "
        f"the maintainer." + (f" The biggest folders: {names}." if names else "")
    )


def check_disk_agent(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent does not start under the hard limit; helpers (read-only) and `[disk] exempt` agents do."""
    kind = (payload.get("tool_input") or {}).get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("disk", {}).get("exempt", [])]
    if kind in exempt:
        return []
    refused = disk_refusal(Path(payload.get("cwd") or "."), config, f"starting a {kind} agent")
    return [refused] if refused else []


def disk_note(workspace: Path, config: dict[str, Any]) -> str:
    """The line an agent or a session is told when the disk is under the soft limit."""
    state, gb = disk_level(workspace, config)
    if state == "ok" or gb is None:
        return ""
    line = disk_status(workspace, config).get("line", "")
    return (
        f"Disk {state.upper()}: {gb:.1f} GB free{f' ({line})' if line else ''}. Keep what you write small: reduce "
        f"downloaded CI artifacts to their numbers and delete them in the same task, delete raw captures once a clip "
        f"or sheet is made, and name what can go in your scratch topic's SCRATCH.md (docs/studio/workspace.md#disk)."
    )


def start_disk_guard(workspace: Path, config: dict[str, Any], force: bool = False) -> bool:
    """Start `gds disk guard` in the background at most once every `[disk] every_seconds` (unless `force`); its report
    is appended to `[disk] log`. The guard takes its own lock. Returns whether it was started."""
    rules = config.get("disk", {})
    if not rules.get("enabled", True):
        return False
    return start_background(
        workspace, rules, ["disk", "guard"], "cache/disk-guard-started", "scratch/disk-guard.log", 300, force
    )


# --------------------------------------------------------------------------------------------------------------------
# Finished worktrees: swept in the background (docs/studio/hooks.md#sweep)
# --------------------------------------------------------------------------------------------------------------------


def start_sweep(workspace: Path, config: dict[str, Any], force: bool = False) -> bool:
    """Start `gds worktree sweep` in the background (it never blocks the hook), at most once every `[sweep]
    every_seconds` unless `force`; its report is appended to `[sweep] log`. The sweep takes its own lock, so two
    sessions starting at once run one. Returns whether a sweep was started."""
    rules = config.get("sweep", {})
    if not rules.get("enabled", True):
        return False
    return start_background(
        workspace,
        rules,
        ["worktree", "sweep", *rules.get("args", [])],
        "cache/worktree-sweep-started",
        "scratch/worktree-sweep.log",
        600,
        force,
    )


def start_background(
    workspace: Path,
    rules: dict[str, Any],
    gds_args: list[str],
    default_stamp: str,
    default_log: str,
    default_every: float,
    force: bool,
) -> bool:
    """Start `gds <gds_args>` in the background, at most once every `rules["every_seconds"]` (a stamp file's age)
    unless `force`, its output appended to `rules["log"]`. Returns whether it was started."""
    stamp = workspace / rules.get("stamp", default_stamp)
    try:
        recent = time.time() - stamp.stat().st_mtime < float(rules.get("every_seconds", default_every))
    except OSError:
        recent = False
    if recent and not force:
        return False
    uv, kit = shutil.which("uv"), kit_root(workspace)
    if not uv or not (kit / "python").is_dir():
        return False
    log = workspace / rules.get("log", default_log)
    command = [uv, "run", "--project", str(kit / "python"), "gds", *gds_args]
    try:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.touch()
        log.parent.mkdir(parents=True, exist_ok=True)
        if log.exists() and log.stat().st_size > int(rules.get("max_log_bytes", 1_000_000)):
            os.replace(log, log.with_suffix(".old.log"))
        with log.open("ab") as out:
            # Windows: no console window for it or its git children; a job object of the hook runner may forbid
            # breaking away from it, so that flag is tried first and dropped when refused.
            flags = [0x08000000 | 0x00000200 | 0x01000000, 0x08000000 | 0x00000200] if os.name == "nt" else [0]
            for creation in flags:
                try:
                    subprocess.Popen(
                        command,
                        cwd=str(workspace),
                        stdin=subprocess.DEVNULL,
                        stdout=out,
                        stderr=subprocess.STDOUT,
                        creationflags=creation,
                        start_new_session=os.name != "nt",
                    )
                    return True
                except PermissionError:
                    continue
    except OSError:
        pass
    return False


_PULL_URL = re.compile(r"^\s*(https://github\.com/[\w.-]+/[\w.-]+/pull/\d+)\s*$", re.MULTILINE)
_LOCAL_IMAGE = re.compile(
    r"!\[[^\]]*\]\(\s*(?!https?://)[^)\s]+\.(?:png|jpe?g|gif|webp|mp4|webm|mov)\s*\)", re.IGNORECASE
)


def tool_output(payload: dict[str, Any]) -> str:
    """What a shell command printed, from a PostToolUse payload (`tool_response` is a string or a dict of streams)."""
    response = payload.get("tool_response")
    if isinstance(response, dict):
        return "\n".join(str(response.get(key) or "") for key in ("stdout", "output", "stderr"))
    return str(response or "")


def local_images(body: str) -> list[str]:
    """The `![alt](local path)` image references of a description (comments left out): none of them is an upload."""
    return [m.group(0) for m in _LOCAL_IMAGE.finditer(_HTML_COMMENT.sub("", body))]


def local_images_in(url: str) -> list[str]:
    """The local image references still in the pull request's description, by `gh pr view` (empty when GitHub cannot
    be asked: no check beats a stalled session)."""
    try:
        result = subprocess.run(
            ["gh", "pr", "view", url, "--json", "body", "-q", ".body"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    return local_images(result.stdout)


def check_opened_body(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """The second line of defence for `--attach` (docs/studio/hooks.md#attach-paths): the guard before `gh pr
    create|edit` can
    only read the command it is shown, so a pull request opened through a script, an alias or a path the guard did not
    place reaches GitHub with whatever body it had. After any shell command that created or edited a pull request (or
    printed a pull request's address as its last word), the description is read back, and a local `![x](./x.png)`
    image reference that was never swapped for an upload is named at once, before `pr-rules` finds it."""
    rule = config.get("attach", {})
    if not rule.get("readback", True):
        return ""
    command = (payload.get("tool_input") or {}).get("command", "")
    words = segments(command)
    edited = any(pr_command(w) for w in words)
    urls = _PULL_URL.findall(tool_output(payload))
    if not urls or not (edited or "--attach" in command or len(words) == 1 and program(words[0]) != "gh"):
        return ""
    local = local_images_in(urls[-1])
    if not local:
        return ""
    shown = ", ".join(f"`{ref}`" for ref in local[:4]) + (" ..." if len(local) > 4 else "")
    return (
        f"{urls[-1]} was sent with local image references that are not uploads: {shown}. `gh --attach` swaps a "
        "`![alt](path)` reference only when it is the same file as an `--attach` path (a relative path is read "
        "from the folder `gh` runs in); otherwise it appends the upload after `## AI use` and leaves the reference "
        "local, and `pr-rules` fails on a missing Before:/After: capture. Fix it now: read the body back "
        "(`gh pr view N --json body -q .body`), then `cd <the images' folder> && gh pr edit N --body-file <body> "
        "--attach ./<file>` for each image (docs/studio/hooks.md#attach-paths) and delete the appended copies."
    )


def post_tool_use(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """After a shell command: pull every local main when it merged a pull request; name local image references left in
    a pull request description it opened or edited."""
    if payload.get("tool_name") not in SHELL_TOOLS:
        return ""
    notes = [check_opened_body(payload, config)]
    command = (payload.get("tool_input") or {}).get("command", "")
    if any(is_merge(words) for words in segments(command)):
        workspace = workspace_of(Path(payload.get("cwd") or "."))
        if workspace:
            start_sweep(workspace, config, force=True)
        merged = pull_mains(workspace, config, force=True) if workspace else []
        if merged:
            notes.append("Local mains after the merge: " + "; ".join(merged))
    return "\n".join(note for note in notes if note)


# --------------------------------------------------------------------------------------------------------------------
# SessionStart: where this session is and the rules it works under
# --------------------------------------------------------------------------------------------------------------------


def session_start(payload: dict[str, Any], config: dict[str, Any]) -> str:
    cwd = Path(payload.get("cwd") or ".")
    workspace = workspace_of(cwd)
    if workspace is None:
        return ""
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    lines = [f"GDStudio workspace {workspace.as_posix()}; repository {repo.name}, branch {branch or '?'}."]
    local = workspace / "gdstudio.local.toml"
    if local.exists():
        tools = tomllib.loads(local.read_text(encoding="utf-8")).get("tools", {})
        lines += [f"Pinned {name}: {path}" for name, path in tools.items()]
    folder = scratch_folder(repo)
    if folder:
        lines.append(f"Captures and reports for this branch go in {folder.as_posix()}/ (never in a repository).")
    lines.append("Work on a branch, open a pull request; visual work attaches captures (`gh ... --attach`).")
    lines += pull_mains(workspace, config, force=True)
    start_sweep(workspace, config)
    start_disk_guard(workspace, config)
    lines.append(disk_note(workspace, config))
    lines.append(lesson_text("session", config, workspace))
    return "\n".join(line for line in lines if line)


# --------------------------------------------------------------------------------------------------------------------
# The learning loop: what the maintainer corrects is written into the docs in the same session
# (docs/studio/hooks.md#learning)
# --------------------------------------------------------------------------------------------------------------------

KIT = Path(__file__).resolve().parents[2]


def lesson_text(kind: str, config: dict[str, Any], workspace: Path | None) -> str:
    """One of the learning-loop texts of hooks.toml (`prompt`, `session`, `subagent`) with its paths filled in."""
    rules = config.get("lessons", {})
    text = rules.get(kind, "")
    if not text:
        return ""
    queue = Path(rules.get("queue", "scratch/kit-lessons-queue"))
    kit = workspace / "repos" / "gdstudio" if workspace and (workspace / "repos" / "gdstudio").is_dir() else KIT
    return text.format(
        corrections=(kit / "docs" / "studio" / "maintainer-corrections.md").as_posix(),
        lessons=(kit / "docs" / "lessons" / "index.md").as_posix(),
        rules=(kit / "docs" / "studio" / "rules.md").as_posix(),
        queue=((workspace / queue) if workspace else queue).as_posix(),
    )


def user_prompt_submit(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """The short reminder added to every message in a GDStudio workspace: a correction becomes a row in this session."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    return lesson_text("prompt", config, workspace) if workspace else ""


def subagent_start(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """What a starting agent is told: read the sections its prompt's `Read:` lines name (the Agent guard made sure
    there are some, and that they exist), and how a mistake updates a section. Read-only helpers (and the forks that
    carry the parent's context) are left alone."""
    if payload.get("agent_type") in config.get("agents", {}).get("helpers", []):
        return ""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if not workspace:
        return ""
    start_disk_guard(workspace, config)
    return "\n\n".join(t for t in (lesson_text("subagent", config, workspace), disk_note(workspace, config)) if t)


def pending_lessons(workspace: Path, config: dict[str, Any]) -> list[Path]:
    """Queued lesson rows that are neither published (moved to `published/`) nor waiting on a cause (`Waiting on:`)."""
    rules = config.get("lessons", {})
    folder = workspace / rules.get("queue", "scratch/kit-lessons-queue")
    if not folder.is_dir():
        return []
    waiting = re.compile(rules.get("waiting", r"(?im)^\s*waiting on:\s*\S"))
    return [
        path
        for path in sorted(folder.glob("*.md"))
        if path.name.lower() != "readme.md" and not waiting.search(path.read_text(encoding="utf-8", errors="replace"))
    ]


def stop_queue(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The learning gate: queued corrections whose cause is known are published first (a rule and a log line)."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    pending = pending_lessons(workspace, config) if workspace else []
    if not pending:
        return None
    names = ", ".join(p.name for p in pending[:6]) + ("..." if len(pending) > 6 else "")
    return (
        f"Corrections are queued in {pending[0].parent.as_posix()} and not published: {names}. Publish each as an "
        f"entry in the topic section it belongs to (docs/studio/rules.md) and a line on the corrections log, in a kit "
        f"pull request, then move its file to published/; or, if its cause is not known yet, add a `Waiting on: #N` "
        f"line naming the issue. Ones that are not yours: say so and finish."
    )


# --------------------------------------------------------------------------------------------------------------------
# Docs ship with the change: the sections named are read first, kit docs are never left unpublished
# (docs/studio/hooks.md#docs)
# --------------------------------------------------------------------------------------------------------------------

_INLINE_NONE = re.compile(r"(?i)^\W*(none|n/?a|nothing|no mistakes?|-|no)\W*$")


def kit_root(workspace: Path | None) -> Path:
    """The kit checkout of the workspace (its docs are the ones agents read), else the kit this file belongs to."""
    if workspace and (workspace / "repos" / "gdstudio").is_dir():
        return workspace / "repos" / "gdstudio"
    return KIT


def lessons_module(kit: Path) -> Any:
    """python/src/gds_tools/lessons.py of a kit checkout, loaded by path; None when it cannot be loaded."""
    source = kit / "python" / "src" / "gds_tools" / "lessons.py"
    name = "_gds_lessons_for_hooks"
    try:
        spec = importlib.util.spec_from_file_location(name, source)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module  # a dataclass looks its module up here
        spec.loader.exec_module(module)
        return module
    except Exception:  # a hook never locks a session out: no checks beat a crash
        sys.modules.pop(name, None)
        return None


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


def unpublished_kit_branches(workspace: Path, config: dict[str, Any]) -> dict[str, str]:
    """Branches of the kit's worktrees (`<workspace>/worktrees/gdstudio/*`) with commits ahead of `origin/main` and no
    pull request, open or merged (docs written and left for a batch), each mapped to '' ; and branches whose pull
    request merged and which then got a commit that is not on `origin/main` (pushed after the merge, so lost), each
    mapped to the merged tip. Empty when GitHub cannot be asked."""
    folder = workspace / config.get("docs", {}).get("kit_worktrees", "worktrees/gdstudio")
    protected = config.get("git", {}).get("protected_branches", ["main"])
    ahead = {}
    for tree in sorted(p for p in folder.iterdir() if (p / ".git").exists()) if folder.is_dir() else []:
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


def stop_kit_docs(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The docs gate of Stop: kit branches with commits and no pull request hold the session back once."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    branches = unpublished_kit_branches(workspace, config) if workspace else []
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


# --------------------------------------------------------------------------------------------------------------------
# Agent stalls: a task agent whose turn ends without a report is finished for good (docs/studio/hooks.md#stall)
# --------------------------------------------------------------------------------------------------------------------


def reads_as_report(text: str, config: dict[str, Any]) -> bool:
    """True when a final message names a pull request, lists mistakes (a report section) or says it is blocked."""
    return re.search(config.get("stop_check", {}).get("report", r"(?!)"), text) is not None


def refusal_key(payload: dict[str, Any]) -> str:
    """What identifies one agent run across its stop attempts: its id, else its transcript, else its type."""
    return str(payload.get("agent_id") or payload.get("agent_transcript_path") or payload.get("agent_type") or "?")


def _refusal_runs(path: Path, now: float) -> dict[str, Any]:
    """The refusal counts of the agent runs younger than a day; empty when the file is missing or unreadable."""
    try:
        return {k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items() if now - v.get("time", 0) < 86400}
    except (OSError, ValueError, AttributeError):
        return {}


def _write_refusal_runs(path: Path, runs: dict[str, Any]) -> None:
    with contextlib.suppress(OSError):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(runs), encoding="utf-8")


def count_refusal(workspace: Path, payload: dict[str, Any], config: dict[str, Any]) -> int:
    """Records one more refusal for this agent run and returns how many there have been (this one included). Runs older
    than a day are dropped. When the file cannot be written the count is 1 every time, which only means the gate
    could hold an agent longer on a read-only disk, never that it breaks."""
    path = workspace / config.get("stop_check", {}).get("counter", "cache/stop-check.json")
    now = time.time()
    runs = _refusal_runs(path, now)
    key = refusal_key(payload)
    count = int(runs.get(key, {}).get("count", 0)) + 1
    runs[key] = {"count": count, "time": now}
    _write_refusal_runs(path, runs)
    return count


def clear_refusals(workspace: Path, payload: dict[str, Any], config: dict[str, Any]) -> None:
    """Forgets this agent run's refusals once its end is let through (a report, or the limit reached): a run that is
    resumed (SendMessage) and stalls again gets its own refusals instead of the spent count of the first stall."""
    path = workspace / config.get("stop_check", {}).get("counter", "cache/stop-check.json")
    runs = _refusal_runs(path, time.time())
    if runs.pop(refusal_key(payload), None) is not None:
        _write_refusal_runs(path, runs)


def stop_stall(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Refuses the end of a task agent (`[stop_check] agents`) whose final message is not a report: a background agent
    that ends its turn on "Now the autopilot." is never woken again. Let go when the message names a pull request or a
    blocker, when a background task of the agent is still running (it is waiting for the notification), when there is
    no message to judge, and after `max_refusals` refusals, so no agent is held forever. An end that is let through
    because it reads as a report or because the limit was reached resets the agent's count, so a resumed agent that
    stalls again is refused again. Does not look at `stop_hook_active`: that flag cannot count past one."""
    rules = config.get("stop_check", {})
    if payload.get("agent_type") not in rules.get("agents", []) or payload.get("background_tasks"):
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    report = report_of(payload).strip()
    if workspace is None or not report:
        return None
    if reads_as_report(report, config):
        clear_refusals(workspace, payload, config)
        return None
    limit = int(rules.get("max_refusals", 2))
    count = count_refusal(workspace, payload, config)
    if count > limit:
        clear_refusals(workspace, payload, config)
        return None
    tail = report.splitlines()[-1][:120]
    return (
        f'You ended your turn on "{tail}" without a report. A background agent whose turn ends is finished: nothing '
        f"wakes it, so whatever you announced never runs, and the pull request never opens. Do the step now, in this "
        f"turn, with a tool call; or start a background command that notifies you when it ends and wait for it. When "
        f"the task is done, end with the report: the pull request link (https://github.com/<owner>/<repo>/pull/<n>) "
        f"and your Mistakes section. When you cannot go on, end with one line `Blocked: <what stops you>`. "
        f"(Refusal {count} of {limit}; after that the end is allowed.)"
    )


# --------------------------------------------------------------------------------------------------------------------
# Idle issues: the coordinator does not stop while an issue that can start has no agent (docs/studio/hooks.md#idle)
# --------------------------------------------------------------------------------------------------------------------

IDLE_CACHE = "idle-check.json"  # beside the ledger; `gds issue` commands remove it (gds_tools.issues.IDLE_CACHE)
IDLE_COUNTER = "cache/idle-check-refusals.json"
_GITHUB_URL = re.compile(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?/?$")


def issues_module(kit: Path) -> Any:
    """`gds_tools/issues.py` of the kit, loaded by path (it is standard library only), so the hook computes the window
    with the code `gds issue start` uses. None when it cannot be loaded."""
    name = "_gds_issues_for_hooks"
    if name in sys.modules:
        return sys.modules[name]
    try:
        spec = importlib.util.spec_from_file_location(name, kit / "python" / "src" / "gds_tools" / "issues.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module  # a dataclass looks its module up here
        spec.loader.exec_module(module)
        return module
    except Exception:  # a hook never locks a session out
        sys.modules.pop(name, None)
        return None


def workspace_repositories(kit: Path) -> list[tuple[str, str]]:
    """(`owner/repo`, folder name) of every repository in the kit's workspace.toml that has a GitHub URL."""
    try:
        repos = tomllib.loads((kit / "workspace.toml").read_text(encoding="utf-8")).get("repos", {})
    except (OSError, ValueError):
        return []
    found = []
    for name, entry in repos.items():
        match = _GITHUB_URL.search(str((entry or {}).get("url", "")))
        if match:
            found.append((match.group(1), name))
    return found


class IdleCache:
    """The `gh` reads of one check, kept `seconds` in a file so a Stop every few seconds asks GitHub once a minute.
    `gds issue start|block|unblock|release` remove the file, so a change made through them shows at once."""

    def __init__(self, path: Path, seconds: float, budget: float):
        self.path, self.seconds, self.deadline = path, seconds, time.time() + budget
        try:
            self.entries = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.entries = {}
        if not isinstance(self.entries, dict):
            self.entries = {}

    def __call__(self, args: list[str]) -> str:
        """The output of `gh <args>`; raises (OSError, RuntimeError) when GitHub cannot be asked."""
        key, now = " ".join(args), time.time()
        entry = self.entries.get(key)
        if isinstance(entry, dict) and 0 <= now - entry.get("time", 0) < self.seconds:
            return str(entry.get("out", ""))
        left = self.deadline - now
        if left < 2:
            raise RuntimeError("the time for GitHub reads is used up")
        done = subprocess.run(
            ["gh", *args], capture_output=True, text=True, encoding="utf-8", timeout=min(20.0, left), check=False
        )
        if done.returncode != 0:
            raise RuntimeError(f"gh {' '.join(args[:3])} failed")
        self.entries[key] = {"time": now, "out": done.stdout}
        return done.stdout

    def save(self) -> None:
        now = time.time()
        fresh = {k: v for k, v in self.entries.items() if isinstance(v, dict) and 0 <= now - v.get("time", 0) < 600}
        with contextlib.suppress(OSError):
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(fresh), encoding="utf-8")


def idle_issues(workspace: Path, config: dict[str, Any], gh: Any = None) -> list[tuple[str, int, str, str]]:
    """The issues of every repository in workspace.toml that nobody works on and that may start: the window's "May start
    now", plus blocked ones whose blocker closed, as (repository, number, title, kind) with kind `start` or `unblock`.
    A repository GitHub cannot answer for is left out: a check that cannot look finds nothing. A paused repository
    (`paused` in workspace.toml) offers only its `P-critical` issues, and no unblocked ones."""
    kit = kit_root(workspace)
    issues = issues_module(kit)
    if issues is None:
        return []
    rules = config.get("idle", {})
    ledger = workspace / config.get("issues", {}).get("ledger", "cache/issues-started.json")
    cache = None
    if gh is None:
        cache = gh = IdleCache(
            ledger.with_name(IDLE_CACHE), float(rules.get("cache_seconds", 60)), float(rules.get("budget_seconds", 40))
        )
    found: list[tuple[str, int, str, str]] = []
    paused = getattr(issues, "paused_repositories", lambda kit: {})(kit)  # an older kit checkout has none
    for repo, name in workspace_repositories(kit):
        try:
            game = workspace / "repos" / name
            size = issues.load_settings(kit, game if game.is_dir() else None).window
            open_issues, prs = issues.fetch(repo, gh)
            reason = paused.get(repo.lower(), "")
            window = issues.compute_window(repo, open_issues, prs, size, *([reason] if reason else []))
        except Exception:  # offline, rate limited, bad JSON, no access to the repository: fail open
            continue
        found += [(repo, i.number, i.title, "start") for i in window.allowed]
        if not getattr(window, "paused", ""):
            found += [(repo, i.number, i.title, "unblock") for i in getattr(window, "unblocked", [])]
    if cache:
        cache.save()
    return found


def idle_message(workspace: Path, found: list[tuple[str, int, str, str]], count: int, limit: int) -> str:
    """The refusal: the idle issues, and both ways out (start them, or block them with a reason)."""
    gds = f"uv run --project {(kit_root(workspace) / 'python').as_posix()} gds issue"

    def lines(kind: str) -> list[str]:
        items = [f"  {repo}#{number}  {title[:90]}" for repo, number, title, k in found if k == kind]
        return items[:8] + ([f"  ... and {len(items) - 8} more"] if len(items) > 8 else [])

    text = []
    if lines("start"):
        text += ["These issues may start now and no agent has them:", *lines("start")]
    if lines("unblock"):
        text += ["These issues are still blocked, but what they waited on has closed:", *lines("unblock")]
    text += [
        "Everything that can run in parallel runs (docs/studio/starting-work.md#parallel). Before you end the turn, "
        "for each:",
        f"- start it (`{gds} start <repo>#N --agent <name>`, then give an agent the Issue and Worktree lines);",
        f'- or take it out of the line with its reason: `{gds} block <repo>#N --on <#N|maintainer> --why "<text>"` '
        "(`--on #N` only when its body names #N as a dependency, in `### Blocked by`, `Depends on:`, "
        "`Starts after` or `Carried from`, or add "
        "`--conflict <path>...` naming the files both would edit in ways a merge cannot settle; or it waits on the "
        "maintainer. Same subsystem, same agent and in order are not reasons: docs/studio/starting-work.md#parallel). "
        "A block writes `S-blocked` and a `Blocked (...)` line;",
        f"- an unblocked one: `{gds} unblock <repo>#N`, then start it.",
        f"(Refusal {count} of {limit} in a row; after that the end is allowed until nothing is idle, or for an hour.)",
    ]
    return "\n".join(text)


def stop_idle(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Refuses the end of the main session's turn while an issue that may start has no agent. Only `Stop`, which task
    agents never send (they send `SubagentStop`); a session started as an agent (`agent_type`) is not the coordinator.
    Like `stop_stall` it counts its own refusals (`stop_hook_active` cannot count past one) and gives up after
    `[idle] max_refusals` in a row: the count resets when nothing is idle, and lapses an hour after the last refusal."""
    rules = config.get("idle", {})
    if not rules.get("enforce", True) or payload.get("agent_type"):
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return None
    path = workspace / rules.get("counter", IDLE_COUNTER)
    key = str(payload.get("session_id") or "coordinator")
    now = time.time()
    runs = {k: v for k, v in _refusal_runs(path, now).items() if now - v.get("time", 0) < 3600}
    found = idle_issues(workspace, config)
    if not found:
        if runs.pop(key, None) is not None:
            _write_refusal_runs(path, runs)
        return None
    limit = int(rules.get("max_refusals", 2))
    count = int(runs.get(key, {}).get("count", 0))
    if count >= limit:
        return None
    runs[key] = {"count": count + 1, "time": now}
    _write_refusal_runs(path, runs)
    return idle_message(workspace, found, count + 1, limit)


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


def subagent_stop(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """An agent may not finish while its kit docs are unpublished, while its report lists mistakes and names no
    section its kit branch edits, or while a task agent's report leaves out the sections it read and the gaps it found
    (held back once: `stop_hook_active` lets the next finish through), or while it ends on a step instead of a report
    (`stop_stall`, which counts its own refusals). Helpers and the reviewer are exempt."""
    stalled = stop_stall(payload, config)
    if payload.get("stop_hook_active"):
        return stalled
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if payload.get("agent_type") in exempt:
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return None
    start_disk_guard(workspace, config)
    reasons = [stalled, stop_kit_docs(payload, config)]
    report = report_of(payload)
    if payload.get("agent_type") in config.get("stop_check", {}).get("agents", []) and report.strip():
        reasons.append(read_report_reason(report, config))
    if mistakes_text(report) and not sections_named(workspace, without_read_lines(report)):
        reasons.append(
            "Your report has a Mistakes section but names no topic section that your kit branch updates. Update the "
            "topic section each mistake belongs to with an entry (the approach, what to watch out for, where it was "
            "seen): `gds learn <words>` finds the closest; make a new section only when none fits, with a reason line "
            "(docs/studio/rules.md). Open the kit pull request and name the section in your Mistakes section as "
            "`page.md#anchor`; or, if nothing went wrong, write `Mistakes: none`. Lesson pages are gone: none is "
            "written."
        )
    return "\n\n".join(r for r in reasons if r) or None
