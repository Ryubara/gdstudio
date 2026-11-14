"""`gds brief` and `gds learn` follow a moved section to the page that holds it, and find the sections the words of a
task fit (gdstudio #1471): a split leaves a pointer behind (`Moved to [..](new.md#anchor)`, or a `<!-- moved -->` note
and a link), and a brief or a learn result names the new page instead; an issue that names an anchor its page no longer
has is sent to the one section that has it now. The real-kit cases are the words of the issue and of the agents'
reports of 2026-11-13, each with the section it should bring."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from gds_tools import brief, lessons

KIT = Path(__file__).resolve().parents[2]

OLD_PAGE = """# Own animation

The plan for our own clips.

## Weight and follow-through {#research-weight}

Moved to [Weight and follow-through](animation-research.md#research-weight).

## The clip toolkit {#toolkit}

<!-- moved: the page went past its size when the gaits' entries landed; the anchor stays for the links -->

The toolkit our own clips are made with, how a clip or a gait is added and what building them taught:
[The clip toolkit](clip-toolkit.md#toolkit).

## Feel {#feel}

A clip of our own is never mirrored: one foot ahead, the knees at different heights, the hands doing different things,
so a walk reads as a person and not a puppet.

## Related {#related}

See also [the toolkit](clip-toolkit.md#toolkit) for building clips, which is a different page with its own anchor.
"""

RESEARCH_PAGE = """# Animation research

## Weight, overlap and follow-through {#research-weight}

What the research says about weight in a walk: the hips drop after the heel strikes, the arms follow the shoulders a
few frames late, and the head settles last. Follow-through sells the weight of a body.
"""

TOOLKIT_PAGE = """# The clip toolkit

## The toolkit {#toolkit}

Every clip of our own is built with the toolkit: a gait is a table of keys, solved on each body, checked for the
loop seam and the feet on the floor, and exported with the build script.
"""


@pytest.fixture()
def moved_kit(tmp_path: Path) -> Path:
    blender = tmp_path / "docs" / "tools" / "blender"
    blender.mkdir(parents=True)
    (tmp_path / "docs" / "studio").mkdir(parents=True)
    (blender / "own-animation.md").write_text(OLD_PAGE, encoding="utf-8")
    (blender / "animation-research.md").write_text(RESEARCH_PAGE, encoding="utf-8")
    (blender / "clip-toolkit.md").write_text(TOOLKIT_PAGE, encoding="utf-8")
    return tmp_path


def refs_of(found: list[lessons.Proposal]) -> list[str]:
    return [p.section.ref for p in found]


def test_a_pointer_section_names_where_it_moved(moved_kit):
    by_ref = {s.ref: s for s in lessons.sections_in(moved_kit)}
    old = "tools/blender/own-animation.md"
    research = ("tools/blender/animation-research.md", "research-weight")
    assert lessons.moved_to(by_ref[f"{old}#research-weight"]) == research
    assert lessons.moved_to(by_ref[f"{old}#toolkit"]) == ("tools/blender/clip-toolkit.md", "toolkit")
    assert lessons.moved_to(by_ref[f"{old}#feel"]) is None  # a section with text of its own
    assert lessons.moved_to(by_ref[f"{old}#related"]) is None  # a link to another anchor, with no moved note


def test_a_brief_follows_a_named_moved_section_to_its_new_page(moved_kit):
    found = lessons.propose(
        moved_kit, "blender: Fix the walk's weight", "See tools/blender/own-animation.md#research-weight.", limit=3
    )
    assert refs_of(found)[0] == "tools/blender/animation-research.md#research-weight"
    assert found[0].why == "named in the issue (moved from tools/blender/own-animation.md#research-weight)"
    assert "tools/blender/own-animation.md#research-weight" not in refs_of(found)


def test_a_brief_finds_an_anchor_whose_page_no_longer_has_it(moved_kit):
    """The pointer itself was removed later (own-animation.md#research-weight on the kit today): the one section that
    has the anchor now is named, preferring the named page's folder."""
    page = moved_kit / "docs" / "tools" / "blender" / "own-animation.md"
    pointer = OLD_PAGE[OLD_PAGE.index("## Weight") : OLD_PAGE.index("## The clip")]
    page.write_text(OLD_PAGE.replace(pointer, ""), encoding="utf-8")
    body = "Read tools/blender/own-animation.md#research-weight."
    found = lessons.propose(moved_kit, "blender: Fix it", body, limit=2)
    assert refs_of(found)[0] == "tools/blender/animation-research.md#research-weight"
    assert "moved from tools/blender/own-animation.md#research-weight" in found[0].why


def test_a_brief_by_words_names_the_new_page_not_the_pointer(moved_kit):
    found = lessons.propose(moved_kit, "blender: Add a gait with the clip toolkit", limit=6)
    assert "tools/blender/clip-toolkit.md#toolkit" in refs_of(found)
    assert "tools/blender/own-animation.md#toolkit" not in refs_of(found)


def test_learn_names_the_new_page_not_the_pointer(moved_kit):
    refs = [m.section.ref for m in lessons.learn(moved_kit, "clip toolkit")]
    assert "tools/blender/clip-toolkit.md#toolkit" in refs[:2]  # beside the page's own title
    assert "tools/blender/own-animation.md#toolkit" not in refs and len(refs) == len(set(refs))
    text = lessons.learn_text(moved_kit, "clip toolkit")
    assert ". tools/blender/clip-toolkit.md#toolkit  The toolkit" in text
    assert "(moved from tools/blender/own-animation.md#toolkit)" in text


def test_learn_puts_a_named_section_first_and_follows_it(moved_kit):
    refs = [m.section.ref for m in lessons.learn(moved_kit, "tools/blender/own-animation.md#research-weight")]
    assert refs[0] == "tools/blender/animation-research.md#research-weight"


SCATTERED = """# Test speed

## Time-driven values {#time-driven}

A test that waits on the clock runs slower in a full suite: every test shares the clock, and a value read against time
can fail when the frame is late. Measure it alone first. A timing test may fail once in a long run; alone, the same
test passes. Keep each test's run short, and in a long run read the frame count, not the time, so no test can fail on
a late frame.
"""

PHRASED = """# UI input tests

## Leaks between suites {#leaks}

When a UI test passes alone and fails in a full run, an earlier suite left global state behind: bisect to the pair
and print what it left before forming a theory.
"""


def test_learn_ranks_the_section_that_says_the_words_side_by_side(tmp_path, monkeypatch):
    """A long section with every word of the query scattered through it outranked the one that says the query's phrase
    ("fails in a full run", "passes alone") until adjacent pairs counted (`PAIR_BONUS`, gdstudio #1471)."""
    godot = tmp_path / "docs" / "engines" / "godot"
    godot.mkdir(parents=True)
    (godot / "test-speed.md").write_text(SCATTERED, encoding="utf-8")
    (godot / "ui-input-tests.md").write_text(PHRASED, encoding="utf-8")
    words = "a test fails in a full run and passes alone"
    leaks, scattered = "engines/godot/ui-input-tests.md#leaks", "engines/godot/test-speed.md#time-driven"
    monkeypatch.setattr(lessons, "PAIR_BONUS", 0.0)
    assert [m.section.ref for m in lessons.learn(tmp_path, words)][:2] == [scattered, leaks]  # words alone
    monkeypatch.undo()
    assert [m.section.ref for m in lessons.learn(tmp_path, words)][:2] == [leaks, scattered]


# --- the kit's own docs: the cases of gdstudio #1471 and the agents' reports of 2026-11-13 --------------------------


@pytest.mark.parametrize(
    ("old", "new"),
    [
        ("tools/blender/own-animation.md#research-weight", "tools/blender/animation-research.md#research-weight"),
        ("tools/blender/own-animation.md#audit-gaits", "tools/blender/library-clip-audit.md#audit-gaits"),
        ("tools/blender/own-animation.md#audit-clips", "tools/blender/library-clip-audit.md#audit-clips"),
        ("tools/blender/animation.md#toolkit", "tools/blender/clip-toolkit.md#toolkit"),
    ],
)
def test_the_kit_briefs_a_moved_section_by_its_new_page(old, new):
    found = refs_of(lessons.propose(KIT, "blender: Fix a clip", f"Read: {old}", limit=6))
    assert found[0] == new and old not in found


def test_the_kit_learns_the_new_page_of_a_split():
    blender = "tools/blender"
    for words, new, old in (
        ("audit gaits", f"{blender}/library-clip-audit.md#audit-gaits", f"{blender}/own-animation.md#audit-gaits"),
        ("clip toolkit", f"{blender}/clip-toolkit.md#toolkit", f"{blender}/animation.md#toolkit"),
    ):
        # The five `gds learn` prints; the order among the new page's own sections and its neighbours moves as the
        # kit's pages grow (0.03 apart on 2026-11-13), so `test_learn_names_the_new_page_not_the_pointer` pins it.
        refs = [m.section.ref for m in lessons.learn(KIT, words)]
        assert new in refs and old not in refs and len(refs) == len(set(refs))


def test_no_pointer_section_of_the_kit_points_nowhere():
    sections = lessons.sections_in(KIT)
    by_ref = {s.ref: s for s in sections}
    pointers = [(s.ref, lessons.moved_to(s)) for s in sections if lessons.moved_to(s)]
    assert len(pointers) >= 4  # own-animation.md, animation.md, audio.md, multiplayer.md ...
    assert [ref for ref, (page, anchor) in pointers if f"{page}#{anchor}" not in by_ref] == []


def test_the_kit_learns_import_checks_for_nothing_left_for_git():
    refs = [m.section.ref for m in lessons.learn(KIT, "nothing the build made is left for git")]
    assert refs[0] == "tools/blender/export.md#import-checks"


def test_the_kit_learns_leaks_for_a_test_that_fails_in_a_full_run_and_passes_alone():
    refs = [m.section.ref for m in lessons.learn(KIT, "a test fails in a full run and passes alone")]
    assert "engines/godot/ui-input-tests.md#leaks" in refs[:3]


def test_the_kit_briefs_leaks_for_gdstudio_1357():
    data = json.loads((Path(__file__).parent / "fixtures" / "issue_bodies" / "gdstudio-1357.json").read_text("utf-8"))
    subject = brief.Subject("Ryubara/gdstudio", 1357, data["title"], data["body"], data["labels"])
    assert "engines/godot/ui-input-tests.md#leaks" in refs_of(brief.propose(KIT, subject))


@pytest.mark.parametrize(
    "words",
    ["weapon hold node count", "node count pin", "peek lean adds a node to the character"],
)
def test_the_kit_learns_parts_cost_for_a_part_that_moves_the_node_count(words):
    refs = [m.section.ref for m in lessons.learn(KIT, words)]  # the five `gds learn` prints
    assert "engines/godot/third-person/parts-cost.md#parts-cost" in refs


def test_the_kit_briefs_parts_cost_for_a_hold_or_peek_task():
    data = json.loads((Path(__file__).parent / "fixtures" / "issue_bodies" / "gdstudio-1435.json").read_text("utf-8"))
    subject = brief.Subject("Ryubara/gdstudio", 1435, data["title"], data["body"], data["labels"])
    assert "engines/godot/third-person/parts-cost.md#parts-cost" in refs_of(brief.propose(KIT, subject))


#: What gdstudio #1449 (PR open on 2026-11-13) adds to the reflection-probes section, as its pull request writes it;
#: until it lands the section has none of the words an agent searched by, so the case plants them on the real section.
PROBES_1449 = (Path(__file__).parent / "fixtures" / "sections" / "reflection-probes-1449.txt").read_text("utf-8")


def test_the_kit_learns_reflection_probes_for_dark_frames_in_several_worlds(monkeypatch):
    real = lessons.sections_in
    probes = "engines/godot/first-use-hitches.md#reflection-probes"

    def with_1449(root: Path) -> list[lessons.Section]:
        out = []
        for s in real(root):
            if s.ref == probes and "several" not in s.body:
                s = lessons.Section(s.page, s.level, s.title, s.anchor, s.explicit, s.line, s.body + "\n" + PROBES_1449)
            out.append(s)
        return out

    monkeypatch.setattr(lessons, "sections_in", with_1449)
    assert [m.section.ref for m in lessons.learn(KIT, "dark frames, several worlds in one process")][0] == probes
    found = refs_of(lessons.propose(KIT, "godot: Fix the dark bodies early in the online rig's captures"))
    assert probes in found
