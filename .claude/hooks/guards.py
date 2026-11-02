"""The guards behind dispatch.py (docs/hooks.md). Each check returns the reasons it refuses a call, with what to do
instead; an empty list lets it through. Standard library only."""

from __future__ import annotations

import contextlib
import importlib.util
import json
import re
import shlex
import subprocess
import sys
import time
import tomllib
from pathlib import Path, PurePosixPath
from typing import Any

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
# by hand (docs/hooks.md#issues)
# --------------------------------------------------------------------------------------------------------------------

# `Issue: owner/repo#N` or `PR: owner/repo#N` at the start of a line of an agent's prompt (a list bullet, a quote mark
# or backticks around the reference are fine).
_WORK_LINE = re.compile(r"(?im)^[ \t>*-]*(Issue|PR)[ \t]*:[ \t]*`?([\w.-]+/[\w.-]+)#(\d+)`?")
IN_PROGRESS = "S-in-progress"
CRITICAL = "P-critical"


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


def reference_to(name: str, text: str) -> re.Match[str] | None:
    """A markdown reference `](./name)` (or `](name)`) to an attached file: what `--attach` swaps for the upload."""
    return re.search(rf"\]\(\s*(?:\./)?{re.escape(name)}\s*\)", text)


def body_of(words: list[str], cwd: Path) -> tuple[str | None, str]:
    """The body a `gh pr create|edit` command sends: (text, "") when it can be read here, else (None, why not)."""
    sources = flag_values(words, ("--body-file", "-F"))
    inline = flag_values(words, ("--body", "-b"))
    if sources:
        if sources[0] == "-":
            return None, "the body comes from standard input, which cannot be read here"
        path = Path(sources[0])
        path = path if path.is_absolute() else cwd / path
        if not path.is_file():
            return None, f"the body file {sources[0]} does not exist yet"
        return path.read_text(encoding="utf-8", errors="replace"), ""
    if inline and "$(" not in inline[0] and "`" not in inline[0]:
        return inline[0], ""
    return None, "no body file is named (`--body-file <file>`)"


def check_attach(words: list[str], cwd: Path, config: dict[str, Any]) -> list[str]:
    """`gh pr create|edit --attach` appends every image at the end of the body, after `## AI use`, unless the body
    already refers to it as `![alt](./<file name>)`: then that reference becomes the upload in place. So each attached
    file needs such a reference inside `## Screenshots`, a before capture between the `Before:` and `After:` lines and
    an after capture below `After:`. The body is read from `--body-file` (or a literal `--body`) before the command
    runs, so the refusal comes before a pull request with images in the wrong place exists."""
    rule = config.get("attach", {})
    if len(words) < 3 or program(words) != "gh" or words[1] != "pr" or words[2] not in ("create", "edit"):
        return []
    if not rule.get("enforce", True):
        return []
    files = [PurePosixPath(v.split("#", 1)[0]).name for v in flag_values(words, ("--attach",))]
    if not files:
        return []
    section = rule.get("section", "Screenshots")
    sample = files[-1]
    what = f"`gh pr {words[2]} --attach` puts an image the body does not refer to at the end, after `## AI use`"
    body, why = body_of(words, cwd)
    if body is None:
        return [
            f"{what}, and {why}: write the whole body with the Write tool to a file, with `![after](./{sample})` on "
            f"the After: line of ## {section} (and `![before](./<file>)` on the Before: line), then run the command "
            f"with `--body-file <file>` next to `--attach` (an existing body is read with "
            f"`gh pr view N --json body -q .body`)"
        ]
    text = section_text(body, section)
    missing = [name for name in files if not reference_to(name, text)]
    if missing:
        wanted = " and ".join(f"`![{PurePosixPath(n).stem}](./{n})`" for n in missing)
        return [
            f"{what}, unless the body already refers to the file inside ## {section}: the body has no reference for "
            f"{', '.join(missing)}. Write {wanted} in ## {section}: the before capture on the Before: line, the after "
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


def check_git(words: list[str], cwd: Path, config: dict[str, Any]) -> list[str]:
    """Commits and pushes: never on a protected branch, never forced, never past the hooks."""
    here, rest = git_dir_of(words, cwd)
    if not rest:
        return []
    verb, args = rest[0], rest[1:]
    protected = config.get("git", {}).get("protected_branches", ["main"])
    reasons: list[str] = []
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
        "when nothing needs to be drawn (docs/godot/no-focus.md)"
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
        "`--audio-driver Dummy`, which still runs the mixer the audio checks read (docs/godot/no-focus.md#sound)"
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
        "window; run the probe with `uv run --project <kit>/python gds quiet -- <command>` (docs/godot/no-focus.md)"
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
    if tool in AGENT_TOOLS:
        reasons = check_agents(payload, config) + check_issue(payload, config)
        if not reasons:
            note_agent_start(payload, config)
        return reasons
    if tool in EDIT_TOOLS:
        return check_edit(payload, config)
    if tool not in SHELL_TOOLS:
        return []
    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = Path(payload.get("cwd") or ".")
    reasons: list[str] = []
    for words in segments(command):
        if words[0] == "cd" and len(words) > 1:
            cwd = (cwd / words[1]).resolve()
            continue
        name = program(words)
        if name == "git":
            reasons += check_git(words, cwd, config)
        elif name == "gh":
            reasons += check_merge(words, cwd)
            reasons += check_labels(words)
            reasons += check_attach(words, cwd, config)
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
# Local mains: every main checkout in <workspace>/repos/ follows origin after a merge (docs/hooks.md#mains)
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


def post_tool_use(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """After a shell command that merged a pull request: pull every local main at once."""
    if payload.get("tool_name") not in SHELL_TOOLS:
        return ""
    command = (payload.get("tool_input") or {}).get("command", "")
    if not any(is_merge(words) for words in segments(command)):
        return ""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    notes = pull_mains(workspace, config, force=True) if workspace else []
    return ("Local mains after the merge: " + "; ".join(notes)) if notes else ""


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
    lines.append(lesson_text("session", config, workspace))
    return "\n".join(line for line in lines if line)


# --------------------------------------------------------------------------------------------------------------------
# The learning loop: what the maintainer corrects is written into the docs in the same session (docs/hooks.md#learning)
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
        corrections=(kit / "docs" / "research" / "maintainer-corrections.md").as_posix(),
        lessons=(kit / "docs" / "lessons" / "index.md").as_posix(),
        queue=((workspace / queue) if workspace else queue).as_posix(),
    )


def user_prompt_submit(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """The short reminder added to every message in a GDStudio workspace: a correction becomes a row in this session."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    return lesson_text("prompt", config, workspace) if workspace else ""


def subagent_start(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """What a starting agent is told: read the corrections and lessons that touch its task. Read-only helpers (and
    the forks that carry the parent's context) are left alone."""
    if payload.get("agent_type") in config.get("agents", {}).get("helpers", []):
        return ""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if not workspace:
        return ""
    areas = take_agent_note(workspace, payload.get("agent_type") or "", config)
    return "\n\n".join(
        t for t in (lesson_text("subagent", config, workspace), area_checks(workspace, areas, config)) if t
    )


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
    """The learning gate: rows queued to become corrections or lessons, whose cause is known, are published first."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    pending = pending_lessons(workspace, config) if workspace else []
    if not pending:
        return None
    names = ", ".join(p.name for p in pending[:6]) + ("..." if len(pending) > 6 else "")
    return (
        f"Lesson rows are queued in {pending[0].parent.as_posix()} and not published: {names}. Publish each as a row "
        f"on the corrections page (and a lesson when the cause is general) in a kit pull request, then move its file "
        f"to published/; or, if its cause is not known yet, add a `Waiting on: #N` line naming the issue. Rows that "
        f"are not yours: say so and finish."
    )


# --------------------------------------------------------------------------------------------------------------------
# Docs ship with the change: areas' checks are read first, kit docs are never left unpublished (docs/hooks.md#docs)
# --------------------------------------------------------------------------------------------------------------------

GENERAL = "general"
_INLINE_NONE = re.compile(r"(?i)^\W*(none|n/?a|nothing|no mistakes?|-|no)\W*$")


def kit_root(workspace: Path | None) -> Path:
    """The kit checkout of the workspace (its docs are the ones agents read), else the kit this file belongs to."""
    if workspace and (workspace / "repos" / "gdstudio").is_dir():
        return workspace / "repos" / "gdstudio"
    return KIT


def glossary_items(text: str, area: str) -> list[tuple[str, str]]:
    """The (mistake, check) rows of one area's section of the built glossary (docs/research/mistakes-by-area.md)."""
    items, on = [], False
    for line in text.replace("\r\n", "\n").splitlines():
        if line.startswith("## "):
            on = line[3:].strip() == area
        elif on and line.startswith("| ") and not line.startswith(("| Mistake", "| ---")):
            parts = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
            if len(parts) == 3:
                items.append(
                    tuple(p.replace("\\|", "|").replace("&#124;", "|").replace("&lt;", "<") for p in parts[:2])
                )
    return items


def build_glossary(kit: Path) -> str:
    """The glossary built from the lessons and corrections rows of a kit checkout (it is not a committed file: two
    lesson pull requests would both rewrite it). Loads python/src/gds_tools/lessons.py by path; '' when it cannot."""
    source = kit / "python" / "src" / "gds_tools" / "lessons.py"
    name = "_gds_lessons_for_hooks"
    try:
        spec = importlib.util.spec_from_file_location(name, source)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module  # a dataclass looks its module up here
        spec.loader.exec_module(module)
        return module.build(kit)
    except Exception:  # a hook never locks a session out: no checks beat a crash
        sys.modules.pop(name, None)
        return ""


def area_checks(workspace: Path | None, areas: list[str], config: dict[str, Any]) -> str:
    """The checks of some areas as plain text for an agent's context: the newest `inject_limit` of each, cut at
    `inject_chars` altogether. Empty when the glossary cannot be built."""
    rules = config.get("docs", {})
    kit = kit_root(workspace)
    text = build_glossary(kit)
    if not text:
        return ""
    lines = []
    for area in areas:
        items = glossary_items(text, area)[: int(rules.get("inject_limit", 12))]
        if items:
            lines.append(f"[{area}]")
            lines += [f"- {mistake}: {check}" for mistake, check in items]
    body = "\n".join(lines)
    limit = int(rules.get("inject_chars", 7000))
    if len(body) > limit:
        body = body[:limit].rsplit("\n", 1)[0] + "\n... (cut; the full list is in the glossary)"
    if not body:
        return ""
    return (
        f"Mistakes already made in your areas ({', '.join(areas)}), each with the check that catches it. Apply them "
        f"before you start; the full list is built from "
        f"{(kit / 'docs' / 'lessons').as_posix()} (`gds lessons <area>` prints one):\n{body}"
    )


def pending_path(workspace: Path, config: dict[str, Any]) -> Path:
    return workspace / config.get("docs", {}).get("pending", "cache/subagent-pending.json")


def note_agent_start(payload: dict[str, Any], config: dict[str, Any]) -> None:
    """An Agent call that passed the guards leaves a note of the areas of its issue: SubagentStart (which does not see
    the prompt) reads it to inject those areas' checks. Notes older than ten minutes are dropped."""
    inp = payload.get("tool_input") or {}
    kind = inp.get("subagent_type") or ""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if workspace is None or not kind or kind in exempt:
        return
    ledger = read_ledger(workspace, config)
    areas = [GENERAL]
    for label, repo, number in _WORK_LINE.findall(inp.get("prompt") or ""):
        if label.lower() == "issue":
            areas += [a for a in ledger.get(ledger_key(repo, number), {}).get("areas", []) if a not in areas]
    path, now = pending_path(workspace, config), time.time()
    try:
        notes = [n for n in json.loads(path.read_text(encoding="utf-8")) if now - n.get("time", 0) < 600]
    except (OSError, ValueError, TypeError):
        notes = []
    notes.append({"agent_type": kind, "areas": areas, "time": now})
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(notes), encoding="utf-8")
    except OSError:
        pass


def take_agent_note(workspace: Path, agent_type: str, config: dict[str, Any]) -> list[str]:
    """The areas of the oldest unread note for this agent type (and the note is used up); `general` when none."""
    path, now = pending_path(workspace, config), time.time()
    try:
        notes = [n for n in json.loads(path.read_text(encoding="utf-8")) if now - n.get("time", 0) < 600]
    except (OSError, ValueError, TypeError):
        return [GENERAL]
    for i, note in enumerate(notes):
        if note.get("agent_type") == agent_type:
            del notes[i]
            with contextlib.suppress(OSError):
                path.write_text(json.dumps(notes), encoding="utf-8")
            return note.get("areas") or [GENERAL]
    return [GENERAL]


def kit_remote(kit: Path) -> str:
    """`owner/repo` of the kit's origin remote, '' when it is not a GitHub one."""
    found = re.search(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?$", git(kit, "remote", "get-url", "origin"))
    return found.group(1) if found else ""


def kit_pr_heads(repo: str) -> set[str] | None:
    """The branches that have an open or a merged pull request in `repo`; None when GitHub cannot be asked."""
    try:
        out = subprocess.run(
            ["gh", "pr", "list", "-R", repo, "--state", "all", "--limit", "300", "--json", "headRefName,state"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode != 0:
            return None
        return {p["headRefName"] for p in json.loads(out.stdout or "[]") if p.get("state") in ("OPEN", "MERGED")}
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return None


def unpublished_kit_branches(workspace: Path, config: dict[str, Any]) -> list[str]:
    """Branches of the kit's worktrees (`<workspace>/worktrees/gdstudio/*`) with commits ahead of `origin/main` and no
    pull request, open or merged: docs written and left for a batch. Empty when GitHub cannot be asked."""
    folder = workspace / config.get("docs", {}).get("kit_worktrees", "worktrees/gdstudio")
    protected = config.get("git", {}).get("protected_branches", ["main"])
    ahead = []
    for tree in sorted(p for p in folder.iterdir() if (p / ".git").exists()) if folder.is_dir() else []:
        branch = git(tree, "rev-parse", "--abbrev-ref", "HEAD")
        base = "origin/main" if git(tree, "rev-parse", "--verify", "-q", "origin/main") else "main"
        count = git(tree, "rev-list", "--count", f"{base}..HEAD")
        if branch and branch != "HEAD" and branch not in protected and count.isdigit() and int(count) > 0:
            ahead.append(branch)
    if not ahead:
        return []
    heads = kit_pr_heads(kit_remote(kit_root(workspace)))
    return [b for b in ahead if b not in heads] if heads is not None else []


def unpublished_message(branches: list[str]) -> str:
    names = ", ".join(branches[:5]) + ("..." if len(branches) > 5 else "")
    return (
        f"Kit branches with commits and no pull request: {names}. Docs left unpublished are lost: push each branch and "
        f"open its pull request now (`gh pr create`), in the same task that found what it documents, never for a later "
        f"batch. A branch that is not yours: say so and finish."
    )


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
            if re.match(r"^\s*#{1,6}\s", after) or label or (body[0] and not after.strip()):
                break  # the next heading or label; a one-line "Mistakes: text" ends at its paragraph
            body.append(after.strip())
        text = " ".join(b for b in body if b).strip()
        return "" if not text or _INLINE_NONE.match(text) else text
    return ""


def lesson_files_named(workspace: Path, report: str) -> list[str]:
    """The `docs/lessons/<file>.md` paths of a report that exist in the kit checkout or one of its worktrees."""
    roots = [kit_root(workspace)]
    folder = workspace / "worktrees" / "gdstudio"
    roots += [p for p in sorted(folder.iterdir()) if p.is_dir()] if folder.is_dir() else []
    names = dict.fromkeys(re.findall(r"docs/lessons/(20\d\d-[\w.-]+\.md)", report))
    return [n for n in names if any((root / "docs" / "lessons" / n).exists() for root in roots)]


# --------------------------------------------------------------------------------------------------------------------
# Agent stalls: a task agent whose turn ends without a report is finished for good (docs/hooks.md#stall)
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
# Idle issues: the coordinator does not stop while an issue that can start has no agent (docs/hooks.md#idle)
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
    A repository GitHub cannot answer for is left out: a check that cannot look finds nothing."""
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
    for repo, name in workspace_repositories(kit):
        try:
            game = workspace / "repos" / name
            size = issues.load_settings(kit, game if game.is_dir() else None).window
            open_issues, prs = issues.fetch(repo, gh)
            window = issues.compute_window(repo, open_issues, prs, size)
        except Exception:  # offline, rate limited, bad JSON, no access to the repository: fail open
            continue
        found += [(repo, i.number, i.title, "start") for i in window.allowed]
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
        "Everything that can run in parallel runs (docs/starting-work.md#parallel). Before you end the turn, for each:",
        f"- start it (`{gds} start <repo>#N --agent <name>`, then give an agent the Issue and Worktree lines);",
        f'- or take it out of the line with its reason: `{gds} block <repo>#N --on <#N|maintainer> --why "<text>"` '
        "(it conflicts with an issue an agent has, same files or mechanic: `--on` that issue and give both to one "
        "agent in sequence; or it waits on the maintainer). A block writes `S-blocked` and a `Blocked (...)` line;",
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


def subagent_stop(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """An agent may not finish while its kit docs are unpublished, or while its report lists mistakes and no lesson
    file (held back once: `stop_hook_active` lets the next finish through), or while it ends on a step instead of a
    report (`stop_stall`, which counts its own refusals). Helpers and the reviewer are exempt."""
    stalled = stop_stall(payload, config)
    if payload.get("stop_hook_active"):
        return stalled
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if payload.get("agent_type") in exempt:
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return None
    reasons = [stalled, stop_kit_docs(payload, config)]
    report = report_of(payload)
    if mistakes_text(report) and not lesson_files_named(workspace, report):
        reasons.append(
            "Your report has a Mistakes section but names no lesson file. Write what went wrong, its cause and the fix "
            "as a lesson (docs/lessons/<yyyy-mm-dd>-<slug>.md with `areas: [...]` front matter, in a kit branch), open "
            "its pull request, and name the file in your report; or, if nothing went wrong, write `Mistakes: none`."
        )
    return "\n\n".join(r for r in reasons if r) or None
