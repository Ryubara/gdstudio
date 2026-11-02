"""The mistakes glossary: areas of lessons, the rows of the corrections page, the generated page, and that the real
lessons and page of the kit agree (a lesson with no area, or a stale page, fails here and in pre-commit)."""

from __future__ import annotations

from pathlib import Path

import pytest

from gds_tools import lessons

KIT = Path(__file__).resolve().parents[2]

AREAS = """
[areas]
general = "Anything else."
net = "The network."
web = "The browser."
tests = "Tests."
[labels]
A-net = ["net", "web"]
A-tests = ["tests"]
[keywords]
net = ["server", "packet"]
web = ["browser"]
tests = ["test"]
"""

LESSON = """# {title}

2026-11-02

- **Saw:** a packet was dropped by the server.
- **Cause:** a guard.
- **Fix:** {fix}
  wrapped on a second line.
- **Docs:** [x](../x.md).
"""

CORRECTIONS = """# Page

## Corrections and the checks they become

| The maintainer said | Blind spot | Check for next time |
| --- | --- | --- |
| "Add mobile controls" | We planned desktop only | Name every device |

## Found by playing: concepts and details we missed

| The maintainer said | Concept | Detail | Check |
| --- | --- | --- | --- |
| "Join is wrong" | Players play with friends | A raw address | Walk the flow ([lesson](../lessons/2026-11-02-b.md)) |

## Done wrong first, caught by our own checks

| What went wrong first | What caught it | Check |
| --- | --- | --- |
| A merge doubled a step | The night suite | Read the diff of every test file |
"""


@pytest.fixture()
def kit(tmp_path: Path) -> Path:
    (tmp_path / "docs" / "lessons").mkdir(parents=True)
    (tmp_path / "docs" / "research").mkdir(parents=True)
    (tmp_path / lessons.AREAS_FILE).write_text(AREAS, encoding="utf-8")
    (tmp_path / lessons.CORRECTIONS).write_text(CORRECTIONS, encoding="utf-8")
    a = LESSON.format(title="A packet filter dropped a valid packet", fix="Count the bytes.")
    b = "---\nareas: [web, net]\n---\n" + LESSON.format(title="The browser decoded twice", fix="Decode once | only.")
    (tmp_path / "docs" / "lessons" / "2026-11-01-a.md").write_text(a, encoding="utf-8")
    (tmp_path / "docs" / "lessons" / "2026-11-02-b.md").write_text(b, encoding="utf-8")
    return tmp_path


def test_the_kits_lessons_all_have_areas_and_the_page_is_current():
    areas = lessons.Areas.load(KIT / lessons.AREAS_FILE)
    assert lessons.problems(KIT, areas) == []
    page = (KIT / lessons.GLOSSARY).read_text(encoding="utf-8")
    assert page == lessons.build(KIT), "run `python .github/scripts/mistakes.py render`"


def test_labels_map_to_areas_and_general_is_always_there(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    assert areas.for_labels({"A-net", "bug"}) == ["general", "net", "web"]
    assert areas.for_labels({"A-tests", "A-net"}) == ["general", "net", "web", "tests"]
    assert areas.for_labels(set()) == ["general"]


def test_keywords_place_text_in_at_most_two_areas(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    assert areas.classify("the server dropped a packet in the server") == ["net"]
    assert areas.classify("a browser test of the server") == ["net", "web"]
    assert areas.classify("nothing to match") == ["general"]


def test_problems_name_a_lesson_without_areas_and_an_unknown_area(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    assert lessons.problems(kit, areas) == ["2026-11-01-a.md: no `areas: [...]` front matter"]
    path = kit / "docs" / "lessons" / "2026-11-02-b.md"
    path.write_text(path.read_text(encoding="utf-8").replace("web, net", "web, nope"), encoding="utf-8")
    assert "unknown area 'nope'" in lessons.problems(kit, areas)[-1]


def test_backfill_adds_areas_by_keyword_and_leaves_the_rest(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    changed = lessons.backfill(kit, areas)
    assert [p.name for p in changed] == ["2026-11-01-a.md"]
    text = (kit / "docs" / "lessons" / "2026-11-01-a.md").read_text(encoding="utf-8")
    assert text.startswith("---\nareas: [net]\n---\n# A packet filter")
    assert lessons.backfill(kit, areas) == []  # nothing left to place
    assert lessons.parse_lesson(kit / "docs" / "lessons" / "2026-11-02-b.md").areas == ["web", "net"]


def test_corrections_rows_of_all_three_table_shapes():
    rows = lessons.corrections_rows(CORRECTIONS)
    assert [(r.mistake, r.check) for r in rows] == [
        ("We planned desktop only", "Name every device"),
        ("Players play with friends", "Walk the flow ([lesson](../lessons/2026-11-02-b.md))"),
        ("A merge doubled a step", "Read the diff of every test file"),
    ]
    assert rows[1].lesson_names == ["2026-11-02-b"]
    assert rows[1].section == "found-by-playing-concepts-and-details-we-missed"


def test_the_glossary_has_a_section_per_area_with_lessons_and_rows(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    lessons.backfill(kit, areas)
    page = lessons.build(kit)
    assert [ln for ln in page.splitlines() if ln.startswith("## ")] == ["## general", "## net", "## web", "## tests"]
    net = lessons.section(page, "net")
    # newest lesson first; the row that links lesson b inherits its areas; pipes inside a cell survive
    assert net[0] == ("The browser decoded twice", "Decode once | only. wrapped on a second line.")
    assert net[1][0] == "A packet filter dropped a valid packet"
    assert ("Players play with friends", "Walk the flow (lesson)") in net
    assert lessons.section(page, "web")[0][0] == "The browser decoded twice"
    assert "(../lessons/2026-11-02-b.md)" in page and "(maintainer-corrections.md#" in page
    assert page.endswith("\n") and not page.endswith("\n\n")


def test_checks_text_takes_the_newest_per_area_and_skips_empty_areas(kit):
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    lessons.backfill(kit, areas)
    page = lessons.build(kit)
    text = lessons.checks_text(page, ["net", "nope"], per_area=1)
    assert text.startswith("[net]\n- The browser decoded twice: ") and "[nope]" not in text
    assert text.count("\n- ") == 1


def test_angle_brackets_outside_code_are_escaped_in_the_page():
    assert lessons.brief("use <owner> or `<repo>`", 80) == "use &lt;owner> or `<repo>`"
    assert lessons.brief("a " * 200, 20).endswith(" ...")
