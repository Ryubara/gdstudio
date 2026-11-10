"""The tripwire of the suites that delete: a probe of the kit has already reached a real service (docs/lessons), and
`gh` and the process list are default arguments, so a test that forgets its fake runs the real thing. With this fixture
it fails instead. `test_disk.py` proves the real routes pass through it."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
from git_seed import relocate
from new_game_kit import GITHUB_KIT_FILES, KIT_FILES, build_kit, git_environment, run_git
from skip_allowlist import (  # noqa: F401 - the hooks of the skip allowlist (--allowed-skips)
    pytest_addoption,
    pytest_collectreport,
    pytest_runtest_logreport,
    pytest_sessionfinish,
    pytest_terminal_summary,
)

REAL_SERVICES = frozenset({"gh", "powershell", "pwsh", "ps"})


@pytest.fixture
def no_real_services(monkeypatch: pytest.MonkeyPatch) -> None:
    """Any `gh` or process listing that reaches `subprocess.run` fails the test. Git still runs, on temporary trees."""
    real = subprocess.run

    def guarded(argv, *args, **kwargs):
        program = Path(str(argv[0] if isinstance(argv, (list, tuple)) else argv)).stem.lower()
        if program in REAL_SERVICES:
            raise AssertionError(f"a test reached the real `{program}`: {argv}")
        return real(argv, *args, **kwargs)

    monkeypatch.setattr(subprocess, "run", guarded)


@pytest.fixture(scope="session")
def small_kit_seed(tmp_path_factory) -> Path:
    """The small kit, made once; a test copies it."""
    return build_kit(
        tmp_path_factory.mktemp("small-kit") / "kit", real_templates=False, files=KIT_FILES + GITHUB_KIT_FILES
    )


@pytest.fixture(scope="session")
def small_git_kit_seed(small_kit_seed, tmp_path_factory) -> Path:
    """The small kit as a git checkout with one commit and an `origin` that is a local bare repository, made once
    (`<seed>/kit` and `<seed>/kit-origin.git`); a test gets a copy with the paths rewritten (git_seed.relocate)."""
    seed = tmp_path_factory.mktemp("small-kit-git")
    kit, origin = seed / "kit", seed / "kit-origin.git"
    shutil.copytree(small_kit_seed, kit)
    with pytest.MonkeyPatch.context() as patch:
        git_environment(patch, seed / "gitconfig")
        run_git("init", "-q", "-b", "main", cwd=kit)
        run_git("add", "-A", cwd=kit)
        run_git("commit", "-q", "-m", "kit", cwd=kit)
        run_git("clone", "-q", "--bare", str(kit), str(origin))
        run_git("remote", "add", "origin", str(origin), cwd=kit)
        run_git("fetch", "-q", "origin", cwd=kit)
        run_git("branch", "-q", "--set-upstream-to=origin/main", "main", cwd=kit)
    return seed


@pytest.fixture
def small_kit(small_kit_seed, tmp_path) -> Path:
    """A writable copy of the small kit: a test that records a remote or adds a template writes to the copy."""
    return shutil.copytree(small_kit_seed, tmp_path / "kit")


@pytest.fixture
def small_git_kit(small_git_kit_seed, tmp_path) -> Path:
    """The small kit as a git checkout whose `origin` is a local bare repository, copied from the seed with no git
    process (it was a bare clone, a clone and a `remote set-url` for every test)."""
    return relocate(small_git_kit_seed, tmp_path / "git-kit") / "kit"
