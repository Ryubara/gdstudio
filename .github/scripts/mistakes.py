"""The checks of what is learned in topic sections (docs/studio/rules.md).

    python .github/scripts/mistakes.py check [--base REF]   fail on what the rules refuse (below)

`check` refuses, from the checkout alone: a page over the size limit, an entry without its three parts (Approach,
Watch out for, Seen) or in the old form or too long or in a section without an explicit anchor, a malformed or repeated
anchor, a ##/### heading without an explicit anchor on a page under studio/, engines/, tools/ or gamedev/, a
corrections-log row that quotes the maintainer or links no section, and an old lesson file dated after the old folder
closed. Against a base (`--base REF`; by default where the branch left origin/main and origin/main itself,
skipped with a note when they are not known) it also refuses a file added to docs/lessons/ and a new heading without a
reason line. It runs in pre-commit, in pytest and in the docs job of CI (`--base HEAD^1` on the merge commit of a pull
request). Standard library only; the logic is python/src/gds_tools/lessons.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python" / "src"))

from gds_tools import lessons  # noqa: E402


def check(argv: list[str]) -> int:
    found = lessons.problems(ROOT)
    base = [argv[argv.index("--base") + 1]] if "--base" in argv[:-1] else lessons.default_bases(ROOT)
    if not base:
        print("note: origin/main is not known here, so new sections and new lesson files were not checked",
              file=sys.stderr)
    else:
        try:
            found += lessons.base_problems(ROOT, base)
        except lessons.LessonsError as error:
            found.append(str(error))
    print("\n".join(found), file=sys.stderr)
    return 1 if found else 0


def main(argv: list[str]) -> int:
    command = argv[0] if argv else "check"
    if command == "check":
        return check(argv[1:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
