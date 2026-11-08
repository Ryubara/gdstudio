"""The checks of rules kept in topic sections (docs/studio/rules.md), and the mistakes glossary built from them.

    python .github/scripts/mistakes.py check [--base REF]   fail on what the rules refuse (below)
    python .github/scripts/mistakes.py render [PATH]        print the glossary (or write it to PATH); never committed
    python .github/scripts/mistakes.py backfill             add `areas:` front matter, placed by keyword, to old
                                                            lesson files without it

`check` refuses, from the checkout alone: a page over the size limit, a rule without its four parts or too long or in a
section without an explicit anchor, a malformed or repeated anchor, a corrections-log row that quotes the maintainer or
links no section, and an old lesson file without areas or dated after the old folder closed. Against a base commit
(`--base REF`; by default where the branch left origin/main, skipped with a note when that is not known) it also
refuses a file added to docs/lessons/ and a new heading without a reason line. It runs in pre-commit, in pytest and in
the docs job of CI (`--base HEAD^1` on the merge commit of a pull request). Standard library only; the logic is
python/src/gds_tools/lessons.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python" / "src"))

from gds_tools import lessons  # noqa: E402


def check(argv: list[str]) -> int:
    areas = lessons.Areas.load(ROOT / lessons.AREAS_FILE)
    found = lessons.problems(ROOT, areas)
    base = argv[argv.index("--base") + 1] if "--base" in argv[:-1] else lessons.default_base(ROOT)
    if base is None:
        print("note: origin/main is not known here, so new sections and new lesson files were not checked",
              file=sys.stderr)
    else:
        try:
            found += lessons.base_problems(ROOT, base)
        except lessons.LessonsError as error:
            found.append(str(error))
    if not found:
        lessons.build(ROOT)  # raises when a page or a lesson cannot be read
    print("\n".join(found), file=sys.stderr)
    return 1 if found else 0


def main(argv: list[str]) -> int:
    command = argv[0] if argv else "check"
    if command == "backfill":
        changed = lessons.backfill(ROOT, lessons.Areas.load(ROOT / lessons.AREAS_FILE))
        print(f"{len(changed)} lesson(s) given areas")
        return 0
    if command == "check":
        return check(argv[1:])
    if command == "render":
        found = lessons.problems(ROOT, lessons.Areas.load(ROOT / lessons.AREAS_FILE))
        if found:
            print("\n".join(found), file=sys.stderr)
            return 1
        text = lessons.build(ROOT)
        if len(argv) > 1:
            Path(argv[1]).write_text(text, encoding="utf-8", newline="\n")
            print(f"written: {argv[1]}")
        else:
            sys.stdout.reconfigure(encoding="utf-8", newline="\n")
            sys.stdout.write(text)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
