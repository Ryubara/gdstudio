"""The tripwire of the suites that delete: a probe of the kit has already reached a real service (docs/lessons), and
`gh` and the process list are default arguments, so a test that forgets its fake runs the real thing. With this fixture
it fails instead. `test_disk.py` proves the real routes pass through it."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
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
def small_kit_git_seed(small_kit_seed, tmp_path_factory) -> Path:
    """The small kit as a git checkout with one commit, made once; a test clones it."""
    seed = tmp_path_factory.mktemp("small-kit-git") / "kit"
    shutil.copytree(small_kit_seed, seed)
    with pytest.MonkeyPatch.context() as patch:
        git_environment(patch, seed.parent / "gitconfig")
        run_git("init", "-q", "-b", "main", cwd=seed)
        run_git("add", "-A", cwd=seed)
        run_git("commit", "-q", "-m", "kit", cwd=seed)
    return seed


@pytest.fixture
def small_kit(small_kit_seed, tmp_path) -> Path:
    """A writable copy of the small kit: a test that records a remote or adds a template writes to the copy."""
    return shutil.copytree(small_kit_seed, tmp_path / "kit")


@pytest.fixture
def small_git_kit(small_kit_git_seed, tmp_path) -> Path:
    """The small kit as a git checkout whose `origin` is a local bare repository (a clone of the seed, so no file is
    copied, added or committed again)."""
    copy, origin = tmp_path / "kit", tmp_path / "kit-origin.git"
    run_git("clone", "-q", "--bare", str(small_kit_git_seed), str(origin))
    run_git("clone", "-q", str(small_kit_git_seed), str(copy))
    run_git("remote", "set-url", "origin", str(origin), cwd=copy)
    return copy
