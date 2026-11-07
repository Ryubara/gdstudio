"""The mistakes glossary: lessons and corrections rows by area (docs/research/mistakes-by-area.md).

Every lesson (`docs/lessons/<date>-<slug>.md`) names its areas in a front-matter line, `areas: [net, web]`. This module
reads the lessons and the rows of the corrections page, and writes one page with a section per area: the mistake, the
check, the link. The page is never committed: two lesson pull requests would both rewrite it and the second would
conflict or go stale. It is built from the lessons wherever it is read (the MkDocs build through
`.github/scripts/mkdocs_glossary.py`, `gds lessons <area>`, the SubagentStart hook), and a test (and a pre-commit hook)
fails when a lesson has no area. Standard library only.
"""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

GENERAL = "general"
GLOSSARY = Path("docs") / "research" / "mistakes-by-area.md"  # where the site shows the built page; never a file
AREAS_FILE = Path("docs") / "lessons" / "areas.toml"
CORRECTIONS = Path("docs") / "research" / "maintainer-corrections.md"
LESSONS = Path("docs") / "lessons"

_FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
_AREAS_LINE = re.compile(r"^areas:\s*\[(.*?)\]\s*$", re.MULTILINE)
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_LESSON_LINK = re.compile(r"lessons/(20\d\d-[\w-]+)\.md")


class LessonsError(Exception):
    """The lessons or the glossary are inconsistent."""


@dataclass(frozen=True)
class Areas:
    """`docs/lessons/areas.toml`: the area names with their descriptions, the label map and the placement keywords."""

    names: dict[str, str]
    labels: dict[str, list[str]]
    keywords: dict[str, list[str]]

    @classmethod
    def load(cls, path: Path) -> Areas:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        return cls(dict(data["areas"]), dict(data.get("labels", {})), dict(data.get("keywords", {})))

    def for_labels(self, labels: list[str] | set[str] | frozenset[str]) -> list[str]:
        """The areas of an issue's labels, in the order of the label map; `general` is always there."""
        found = [GENERAL]
        for label in sorted(labels):
            found += [a for a in self.labels.get(label, []) if a not in found]
        return found

    def classify(self, text: str) -> list[str]:
        """The (at most two) areas whose keywords the text mentions most; `general` when none does."""
        lower = f" {text.lower()} "
        scores = {a: sum(lower.count(k) for k in words) for a, words in self.keywords.items() if a in self.names}
        best = sorted((a for a, s in scores.items() if s), key=lambda a: (-scores[a], list(self.names).index(a)))
        return best[:2] or [GENERAL]


@dataclass(frozen=True)
class Lesson:
    path: Path
    title: str
    areas: list[str]
    fix: str
    cause: str = ""


def split_front_matter(text: str) -> tuple[str, str]:
    """(front matter, body) of a Markdown file; the front matter is '' when the file has none."""
    found = _FRONT.match(text.replace("\r\n", "\n"))
    return (found.group(1), text.replace("\r\n", "\n")[found.end() :]) if found else ("", text.replace("\r\n", "\n"))


def parse_lesson(path: Path) -> Lesson:
    front, body = split_front_matter(path.read_text(encoding="utf-8"))
    line = _AREAS_LINE.search(front)
    areas = [a.strip() for a in line.group(1).split(",") if a.strip()] if line else []
    title = next((ln[2:].strip() for ln in body.splitlines() if ln.startswith("# ")), path.stem)
    return Lesson(path, title, areas, _bullet(body, "Fix"), _bullet(body, "Cause"))


def _bullet(body: str, name: str) -> str:
    """The text of a lesson's `- **<name>...:**` bullet (`**Fix:**`, `**Fix (Deadnight #364):**`), its wrapped lines
    joined."""
    head = re.compile(r"^- \*\*" + name + r"[^:*]*:\*\*\s*(.*)")
    out, on = [], False
    for line in body.splitlines():
        found = head.match(line)
        if found:
            on = True
            out.append(found.group(1).strip())
        elif on and (line.startswith("- **") or not line.strip()):
            break
        elif on:
            out.append(line.strip())
    return " ".join(out)


def lessons_in(root: Path) -> list[Lesson]:
    """Every lesson of a kit checkout, oldest first by file name."""
    return [parse_lesson(p) for p in sorted((root / LESSONS).glob("20*.md"))]


def problems(root: Path, areas: Areas) -> list[str]:
    """Lessons without areas, or naming an area that does not exist, and quoted rows of the corrections page."""
    found = []
    for lesson in lessons_in(root):
        if not lesson.areas:
            found.append(f"{lesson.path.name}: no `areas: [...]` front matter")
        found += [f"{lesson.path.name}: unknown area {a!r}" for a in lesson.areas if a not in areas.names]
    corrections = root / CORRECTIONS
    if corrections.exists():
        found += quoted_rows(corrections.read_text(encoding="utf-8"))
    return found


def backfill(root: Path, areas: Areas) -> list[Path]:
    """Give every lesson without areas a front-matter line placed by keyword (a script, not by hand). Returns the
    files changed."""
    changed = []
    for path in sorted((root / LESSONS).glob("20*.md")):
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        front, body = split_front_matter(text)
        if _AREAS_LINE.search(front):
            continue
        title = next((ln[2:] for ln in body.splitlines() if ln.startswith("# ")), "")
        placed = areas.classify(f"{title} " * 3 + body[:2500])  # the title counts three times
        line = f"areas: [{', '.join(placed)}]"
        new = f"---\n{front}\n{line}\n---\n{body}" if front else f"---\n{line}\n---\n{text}"
        path.write_text(new, encoding="utf-8", newline="\n")
        changed.append(path)
    return changed


# --------------------------------------------------------------------------------------------------------------------
# The corrections rows
# --------------------------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Row:
    mistake: str
    check: str
    section: str  # the page heading's anchor
    lesson_names: list[str] = field(default_factory=list)


def slug(heading: str) -> str:
    """The anchor MkDocs gives a heading."""
    return re.sub(r"\s+", "-", re.sub(r"[^\w\s-]", "", heading.lower()).strip())


def cells(line: str) -> list[str]:
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def corrections_rows(text: str) -> list[Row]:
    """The rows of the corrections page's tables: what went wrong, and the check it became."""
    rows, heading, header = [], "", []
    for line in text.replace("\r\n", "\n").splitlines():
        if line.startswith("## "):
            heading, header = slug(line[3:]), []
        elif line.startswith("| ---"):
            continue
        elif line.startswith("|") and not header:
            header = cells(line)
        elif line.startswith("|"):
            parts = cells(line)
            if len(parts) != len(header) or len(parts) < 3:
                continue
            first = header[0].lower()
            mistake, check = (parts[0], parts[2]) if first.startswith("what went wrong") else (parts[1], parts[-1])
            rows.append(Row(mistake, check, heading, _LESSON_LINK.findall(line)))
        elif not line.strip():
            header = []
    return rows


_QUOTES = "\"'“”‘’«»"  # straight, curly and guillemet quotation marks


def quoted_rows(text: str) -> list[str]:
    """Rows of the corrections page whose first cell starts with a quotation mark. A row says what the maintainer
    pointed out in our words, with its source; the maintainer's prompts are never quoted in a public repository
    (gdstudio #780). Header and separator lines are not rows."""
    found, header = [], False
    for number, line in enumerate(text.replace("\r\n", "\n").splitlines(), 1):
        if not line.startswith("|"):
            header = False
            continue
        if line.startswith("| ---"):
            continue
        if not header:
            header = True
            continue
        first = cells(line)[0]
        if first[:1] in _QUOTES:
            found.append(
                f"{CORRECTIONS.as_posix()}:{number}: the row quotes the maintainer ({first[:40]}...); "
                "say what was pointed out in our words, with its source, never the prompt"
            )
    return found


# --------------------------------------------------------------------------------------------------------------------
# The glossary page
# --------------------------------------------------------------------------------------------------------------------


def brief(text: str, limit: int) -> str:
    """One table cell of text: links reduced to their words, cut at a word near `limit`; `|` and `<` become entities."""
    text = " ".join(_LINK.sub(r"\1", text).split())
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0].rstrip(",;:(") + " ..."
    parts = text.split("`")  # the odd parts are code spans, which keep their `<` as it is
    text = "`".join(p.replace("<", "&lt;") if i % 2 == 0 else p for i, p in enumerate(parts))
    return text.replace("|", "&#124;")


HEADER = """# Mistakes by area

<!-- Built from the lessons' `areas:` front matter and the rows of the corrections page when the site is built (and by
`python .github/scripts/mistakes.py render`, which prints it): edit those, not this page. It is not a file in the
repository. -->

Read the sections of your task's areas before you start: each line is a mistake we already made and the check that
would have caught it. A lesson names its areas in front matter (`areas: [net, web]`; the names are in
[areas.toml](../lessons/areas.toml)); a corrections row without a lesson is placed by keyword. `gds issue start` records
an issue's areas from its labels and the hooks put these sections into the agent's context; `gds lessons <area>` prints
one.
"""


def build(root: Path) -> str:
    """The text of the glossary for the lessons and corrections rows of a kit checkout."""
    areas = Areas.load(root / AREAS_FILE)
    lessons = lessons_in(root)
    by_name = {p.path.stem: p for p in lessons}
    sections: dict[str, list[tuple[str, str, str]]] = {a: [] for a in areas.names}
    for lesson in reversed(lessons):  # newest first
        link = f"[lesson](../lessons/{lesson.path.name})"
        for area in lesson.areas or [GENERAL]:
            sections.setdefault(area, []).append(
                (brief(lesson.title, 150), brief(lesson.fix or lesson.cause or "see the lesson", 260), link)
            )
    corrections = root / CORRECTIONS
    for row in corrections_rows(corrections.read_text(encoding="utf-8")) if corrections.exists() else []:
        placed = [a for n in row.lesson_names if n in by_name for a in by_name[n].areas]
        link = f"[row](maintainer-corrections.md#{row.section})"
        for area in dict.fromkeys(placed) or areas.classify(f"{row.mistake} {row.check}"):
            sections.setdefault(area, []).append((brief(row.mistake, 170), brief(row.check, 260), link))
    out = [HEADER]
    for area, description in areas.names.items():
        items = sections.get(area, [])
        out.append(f"## {area}\n\n{description} ({len(items)})\n")
        if items:
            out.append("| Mistake | Check | Source |\n| --- | --- | --- |")
            out += [f"| {m} | {c} | {s} |" for m, c, s in items]
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def _plain(cell: str) -> str:
    return cell.replace("\\|", "|").replace("&#124;", "|").replace("&lt;", "<")


def section(glossary: str, area: str) -> list[tuple[str, str]]:
    """The (mistake, check) pairs of one area in the glossary's text."""
    items, on = [], False
    for line in glossary.replace("\r\n", "\n").splitlines():
        if line.startswith("## "):
            on = line[3:].strip() == area
        elif on and line.startswith("| ") and not line.startswith(("| Mistake", "| ---")):
            parts = cells(line)
            if len(parts) == 3:
                items.append((_plain(parts[0]), _plain(parts[1])))
    return items


def checks_text(glossary: str, wanted: list[str], per_area: int = 12) -> str:
    """The checks of some areas as plain text for an agent's context: the newest `per_area` of each."""
    lines = []
    for area in wanted:
        items = section(glossary, area)[:per_area]
        if items:
            lines.append(f"[{area}]")
            lines += [f"- {mistake}: {check}" for mistake, check in items]
    return "\n".join(lines)
