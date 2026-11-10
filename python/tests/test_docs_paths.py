"""Every `docs/...md` page named in a docstring of the kit's Python exists (the first row of kit #920)."""

from __future__ import annotations

import ast
import re
from pathlib import Path

KIT = Path(__file__).resolve().parents[2]
SOURCES = [KIT / "python" / "src", KIT / ".claude" / "hooks", KIT / ".github" / "scripts"]
PAGE = re.compile(r"\bdocs/[A-Za-z0-9_./-]*?[A-Za-z0-9_-]\.md\b")


def docstrings(path: Path):
    """Every module, class and function docstring of a file as (line, text)."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            text = ast.get_docstring(node, clean=False)
            if text:
                body = node.body[0]
                yield body.lineno, text


def missing_pages() -> list[str]:
    missing = []
    for root in SOURCES:
        for path in sorted(root.rglob("*.py")):
            for line, text in docstrings(path):
                for page in sorted(set(PAGE.findall(text))):
                    if not (KIT / page).is_file():
                        missing.append(f"{path.relative_to(KIT).as_posix()}:{line} names {page}")
    return missing


def test_every_docs_page_named_in_a_docstring_exists():
    assert missing_pages() == []


def test_the_check_finds_a_page_that_does_not_exist():
    assert PAGE.findall("(docs/tools.md) and docs/studio/hooks.md#learning") == [
        "docs/tools.md",
        "docs/studio/hooks.md",
    ]
    assert not (KIT / "docs" / "tools.md").exists()
