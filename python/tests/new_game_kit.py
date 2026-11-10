"""What the new-game tests make their games from (kit #918), and the helpers of the fixtures in `conftest.py`."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

# --- The kit the new-game tests make games from (kit #918) -------------------------------------------------------
# `templates/` is 21 MB (480 files). Copying it for every test, and committing it and pushing it in the GitHub tests,
# took 381 s of the 470 s the suite needed on Windows. The tests that are about names, flags, licences, git and GitHub
# steps need a template, not the real one: they get a kit whose `templates/` holds `repo/` (small) and a few-file
# stand-in for 3D Blank, built once a session and copied (or cloned) for each test. The tests that are about the real
# templates make one game from the real folder once a module and only read it.

KIT = Path(__file__).resolve().parents[2]
FIXTURE_TEMPLATES = Path(__file__).parent / "fixtures" / "new_game_templates"
KIT_FOLDERS = ("godot/addons", ".claude/agents", ".github/scripts", ".github/workflows")
KIT_FILES = ("workspace.toml", "tools.toml", ".pre-commit-config.yaml")
GITHUB_KIT_FILES = (".github/conventions.yml", ".github/pull_request_template.md")
_IGNORE = shutil.ignore_patterns(".godot", "__pycache__")


def _small_addons(folder: str):
    """Ignore rule of the small kit: an addon is its files at the top (`plugin.cfg`, `plugin.gd`) and `router/`, not the
    93 files of `gds_ui`, which every test would copy into its kit, its game and its git index (kit #945)."""
    if folder != "godot/addons":
        return _IGNORE

    def ignore(directory: str, names: list[str]) -> set[str]:
        skipped = set(_IGNORE(directory, names))
        parts = Path(directory).relative_to(KIT / folder).parts
        if len(parts) == 1:  # inside an addon: keep its top-level files and `router/`
            skipped |= {n for n in names if (Path(directory) / n).is_dir() and n != "router"}
        return skipped

    return ignore


def build_kit(dest: Path, *, real_templates: bool, files: tuple[str, ...] = KIT_FILES) -> Path:
    """The parts of the kit `gds new game` reads, copied to `dest`: the real `templates/` (21 MB) or `repo/` and the
    small stand-in templates of `fixtures/new_game_templates/`."""
    for rel in KIT_FOLDERS:
        shutil.copytree(KIT / rel, dest / rel, ignore=_IGNORE if real_templates else _small_addons(rel))
    if real_templates:
        shutil.copytree(KIT / "templates", dest / "templates", ignore=_IGNORE)
    else:
        for folder in ("repo", "game"):  # `game/` is what `gds sync` writes into every game (the hook launcher)
            shutil.copytree(KIT / "templates" / folder, dest / "templates" / folder, ignore=_IGNORE)
        shutil.copytree(FIXTURE_TEMPLATES, dest / "templates", ignore=_IGNORE, dirs_exist_ok=True)
    for rel in files:
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(KIT / rel, dest / rel)
    return dest


def git_environment(monkeypatch: pytest.MonkeyPatch, config: Path) -> None:
    """Commits need a name; a test never reads or writes the person's own git configuration."""
    for key, value in {
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "GIT_CONFIG_GLOBAL": str(config),
        "GIT_CONFIG_SYSTEM": str(config),
    }.items():
        monkeypatch.setenv(key, value)


def is_lfs(argv) -> bool:
    """`git lfs ...`: a test does not install Git LFS into the games it makes (two more processes, and a pre-push hook
    that runs on every push of the game), and the result then does not depend on whether LFS is installed here."""
    return "lfs" in [str(a) for a in argv][:5] and argv[0] == "git"


def run_git(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()
