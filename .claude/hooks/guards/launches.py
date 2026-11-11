"""Godot, Blender and browser launches: pinned copies only, no window or speakers taken from the person at the
machine, a browser probe through `gds quiet`, and no shared tool killed by name (docs/engines/godot/no-focus.md)."""

from __future__ import annotations

import re
from typing import Any

from .shell import program
from .workspace import matches


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
