"""The mistakes glossary of the kit (docs/research/mistakes-by-area.md): render it, check it, place lessons in areas.

    python .github/scripts/mistakes.py render      write the glossary from the lessons and the corrections page
    python .github/scripts/mistakes.py check       fail when a lesson has no (or an unknown) area or the page is stale
    python .github/scripts/mistakes.py backfill    add `areas:` front matter, placed by keyword, to lessons without it

Standard library only; the logic is python/src/gds_tools/lessons.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python" / "src"))

from gds_tools import lessons  # noqa: E402


def main(argv: list[str]) -> int:
    command = argv[0] if argv else "check"
    areas = lessons.Areas.load(ROOT / lessons.AREAS_FILE)
    if command == "backfill":
        changed = lessons.backfill(ROOT, areas)
        print(f"{len(changed)} lesson(s) given areas")
        return 0
    found = lessons.problems(ROOT, areas)
    page = ROOT / lessons.GLOSSARY
    if command == "render":
        if found:
            print("\n".join(found), file=sys.stderr)
            return 1
        page.write_text(lessons.build(ROOT), encoding="utf-8", newline="\n")
        print(f"written: {page.relative_to(ROOT).as_posix()}")
        return 0
    if command == "check":
        if not found and (not page.exists() or page.read_text(encoding="utf-8") != lessons.build(ROOT)):
            found.append(f"{lessons.GLOSSARY.as_posix()} is stale: run `python .github/scripts/mistakes.py render`")
        print("\n".join(found), file=sys.stderr)
        return 1 if found else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
