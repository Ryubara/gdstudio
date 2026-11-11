"""Pull request bodies: what `gh pr create|edit` sends is judged before it runs (the rules of `gds pr check-body`, and
the paths `--attach` uploads), and once more after it ran (docs/studio/hooks.md#attach-paths)."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any

from .shell import _MSYS_DRIVE, flag_values, program, segments
from .workspace import KIT, git, load_pr_module, workspace_of

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
