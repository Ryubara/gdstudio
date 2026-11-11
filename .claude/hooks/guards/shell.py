"""Shell commands as the guards read them: heredocs left out, a line cut into simple commands of words, the program
a command runs, the folder a `git -C` or a `cd` moves to, and the values given to a flag."""

from __future__ import annotations

import os
import re
import shlex
from pathlib import Path, PurePosixPath

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


_CONTINUED = re.compile(r"[\\`]\r?\n")  # a line continued with `\` (bash) or a backtick (PowerShell)


def split_commands(command: str) -> list[str]:
    """A shell line cut at `&&`, `||`, `;`, `|` and newlines that sit outside quotes; a continued line and an escaped
    separator (find's `-exec ... \\;`) do not cut it."""
    command = _CONTINUED.sub(" ", command)
    parts, current, quote, i = [], [], None, 0
    while i < len(command):
        ch = command[i]
        if quote:
            if ch == quote:
                quote = None
            current.append(ch)
        elif ch == "\\" and command[i + 1 : i + 2] in (";", "|", "&"):
            current.append(command[i : i + 2])
            i += 2
            continue
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


# `NAME=value`, with the value quoted or a `$(...)` that holds spaces (shlex leaves it one word): never a program
_ASSIGNMENT = re.compile(r"[A-Za-z_]\w*=")


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
        while words:
            if words[0] in ("&", ".", "call", "exec", "time", "sudo") or _ASSIGNMENT.match(words[0]):
                words = words[1:]
            elif inner := _launched(words):  # a bare `env` is no launch: it prints the environment
                if program(words) == "cmd" and len(inner) == 1:  # `cmd /c "godot -e && x"`: the quoted line
                    out += segments(inner[0])
                    inner = []
                words = inner
            else:
                break
        if words:
            out.append(words)
    return out


# A launcher starts the program named after its own options: the guards judge that program (gdstudio #1192).
_VALUED = {"env": ("-u", "-C", "--unset", "--chdir"), "nice": ("-n",), "timeout": ("-s", "-k", "--signal")}
_PS_SWITCHES = ("-wait", "-nonewwindow", "-passthru", "-usenewenvironment")


def _launched(words: list[str]) -> list[str] | None:
    """The words of the command a launcher runs (`env`, `nohup`, `nice`, `timeout`, `cmd /c`, `start`,
    `Start-Process`), or None when the first word is no launcher (or a `cmd` without `/c` or `/k`)."""
    name = program(words)
    rest = words[1:]
    if name in ("env", "nohup", "nice", "timeout"):
        while rest and rest[0].startswith("-"):
            rest = rest[2:] if rest[0] in _VALUED.get(name, ()) else rest[1:]
        return rest[1:] if name == "timeout" else rest  # timeout's first word is the duration
    if name == "cmd":
        flags = [w.lower() for w in rest]
        cut = next((i for i, w in enumerate(flags) if w in ("/c", "/k")), None)
        return None if cut is None else rest[cut + 1 :]
    if name == "start":
        while rest and (rest[0] == "" or rest[0].startswith("/") and "/" not in rest[0][1:]):  # /b, /wait, "" title
            rest = rest[1:]
        return rest
    if name in ("start-process", "saps"):
        rest = [part for w in rest if w.lower() not in _PS_SWITCHES for part in w.split()]  # -ArgumentList '-a -b'
        named = flag_values([w.lower() if w.startswith("-") else w for w in rest], ("-filepath", "-file", "-f"))
        if named:
            return [named[0], *rest]
        return rest if rest and not rest[0].startswith("-") else []
    return None


def program(words: list[str]) -> str:
    """A command's program name: the first word's file name, lower-case, without `.exe`."""
    name = PurePosixPath(words[0].replace("\\", "/")).name.lower()
    return name.removesuffix(".exe")


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
