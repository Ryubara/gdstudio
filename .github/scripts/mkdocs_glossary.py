"""MkDocs hook: add the mistakes glossary to the site, built from the lessons (never a file in the repository).

`docs/research/mistakes-by-area.md` is generated from every lesson's `areas:` front matter and the corrections rows. It
used to be committed, so each lesson pull request rewrote it and the second of two concurrent ones went stale. Now the
build creates it (`mkdocs.yml`: `hooks:`), and `python .github/scripts/mistakes.py check` only checks the lessons.
"""

from __future__ import annotations

import sys
from pathlib import Path

from mkdocs.structure.files import File

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python" / "src"))

from gds_tools import lessons  # noqa: E402


def on_files(files, config):
    """Replace (or add) the glossary page with the one built from the lessons."""
    src_uri = lessons.GLOSSARY.relative_to("docs").as_posix()  # relative to docs_dir
    old = files.get_file_from_path(src_uri)
    if old is not None:
        files.remove(old)
    files.append(File.generated(config, src_uri, content=lessons.build(ROOT)))
    return files
