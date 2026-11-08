"""The mistakes glossary of the kit: build it, check the lessons, place lessons in areas.

    python .github/scripts/mistakes.py render [PATH]   print the glossary built from the lessons and the corrections page
                                                       (or write it to PATH); it is never committed
    python .github/scripts/mistakes.py check           fail when a lesson has no (or an unknown) area, a corrections row
                                                       quotes the maintainer, or the page cannot be built
    python .github/scripts/mistakes.py backfill        add `areas:` front matter, placed by keyword, to lessons without it

The glossary is never a file, so two lesson pull requests never touch the same one: `gds lessons <area>` and the
SubagentStart hook build it from the lessons. `check` runs in pre-commit, in pytest and in the docs job of CI. Standard library only; the logic is python/src/gds_tools/lessons.py.
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
    if command == "render":
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
    if command == "check":
        if not found:
            lessons.build(
                ROOT
            )  # raises when a lesson or the corrections page cannot be read
        print("\n".join(found), file=sys.stderr)
        return 1 if found else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
