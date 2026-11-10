"""Git repositories made once a session and copied by the tests (kit #945).

A test that needs "a repository with one commit and a remote" used to run `git init`, `add`, `commit`, `remote add`,
`push` and `clone` for itself: about ten processes, 50 to 100 ms each on Windows, in 150 tests. A seed is built the
same way once; `relocate` copies it to the test's folder and rewrites the absolute paths git wrote into the
repositories' `config` files (a `remote add origin <path>`, a clone's origin), with no process at all."""

from __future__ import annotations

import shutil
from pathlib import Path


def _spellings(path: Path) -> list[str]:
    """How git may have written `path` into a config file: as given, with forward slashes, with backslashes doubled."""
    given = str(path)
    return [given, path.as_posix(), given.replace("\\", "\\\\")]


def slim(seed: Path) -> Path:
    """Remove the sample hooks `git init` writes (thirteen files in every repository, which a copy would copy)."""
    for sample in seed.rglob("*.sample"):
        sample.unlink()
    return seed


def relocate(seed: Path, dest: Path) -> Path:
    """Copy the folder `seed` (repositories and all) into `dest` (which may exist) and make every path in a git
    `config` file under it that names `seed` name `dest` instead. Fails when a config still names the seed afterwards,
    so a repository whose origin did not move is found here and not by a test that reads the seed's remote."""
    shutil.copytree(seed, dest, dirs_exist_ok=True)
    pairs = list(zip(_spellings(seed), _spellings(dest), strict=True))
    for config in dest.rglob("config"):
        if config.parent.name != ".git" and not config.parent.name.endswith(".git"):
            continue
        text = config.read_text(encoding="utf-8")
        for old, new in pairs:
            text = text.replace(old, new)
        config.write_text(text, encoding="utf-8")
        assert not any(old in text for old, _ in pairs), f"{config} still names the seed {seed}"
    return dest
