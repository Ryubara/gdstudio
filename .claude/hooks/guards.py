"""The guards behind dispatch.py (docs/hooks.md). Each check returns the reasons it refuses a call, with what to do
instead; an empty list lets it through. Standard library only."""

from __future__ import annotations

import re
import shlex
import subprocess
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

_SPLIT = re.compile(r"\s*(?:&&|\|\||;|\||\n)\s*")


def segments(command: str) -> list[list[str]]:
    """The simple commands of a shell line, each as words (quotes removed; a word that will not split stays whole)."""
    out: list[list[str]] = []
    for part in _SPLIT.split(command):
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
        return check_agents(payload, config)
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
        reasons += check_tools(words, config)
        reasons += check_secrets(words, command, config)
    return list(dict.fromkeys(reasons))


# --------------------------------------------------------------------------------------------------------------------
# Stop: no visual change ends a session without a capture
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
    """The proof gate: a session that changed visual files of a game ends only once a newer capture exists."""
    if payload.get("stop_hook_active"):
        return None
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
    return "\n".join(lines)
