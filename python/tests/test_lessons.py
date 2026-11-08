"""Rules kept in topic sections (docs/studio/rules.md, gdstudio #769): sections, anchors and rules; the checks against
the checkout and against a base commit; `gds learn`; the corrections log; the glossary built from the rules and the old
lesson files; and that the kit's own docs pass every check. The glossary is never committed, so two pull requests
cannot conflict on it."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest
import yaml

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
[pages]
"engines/godot/web" = ["web"]
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

RULE = (
    "- **Approach:** Decode a response once, in one place. **Watch out for:** a proxy and the client both decoded it,\n"
    "  so the bytes were garbage. **Seen:** Deadnight #12,\n"
    "  2026-11-03 (fix: the client reads the header first; a test sends a gzipped body).\n"
)

PAGE = f"""# Web export

The browser build.

## Compression {{#compression}}

How responses are compressed.

{RULE}
## Threads

```markdown
## Not a heading {{#inside-code}}
- **Approach:** inside a code block, not an entry.
```
"""

CORRECTIONS = """# What the maintainer caught

## Corrections and the checks they become {#corrections-and-the-checks-they-become}

| Recorded | Source | What the maintainer pointed out | Rule |
| --- | --- | --- | --- |
| 2026-11-01 | Deadnight #1 | The browser decoded twice | [web.md#compression](../engines/godot/web.md#compression) |
"""


@pytest.fixture()
def kit(tmp_path: Path) -> Path:
    (tmp_path / "docs" / "lessons").mkdir(parents=True)
    (tmp_path / "docs" / "studio").mkdir(parents=True)
    (tmp_path / "docs" / "engines" / "godot").mkdir(parents=True)
    (tmp_path / lessons.AREAS_FILE).write_text(AREAS, encoding="utf-8")
    (tmp_path / lessons.CORRECTIONS).write_text(CORRECTIONS, encoding="utf-8")
    (tmp_path / "docs" / "engines" / "godot" / "web.md").write_text(PAGE, encoding="utf-8")
    a = LESSON.format(title="A packet filter dropped a valid packet", fix="Count the bytes.")
    b = "---\nareas: [web, net]\n---\n" + LESSON.format(title="The browser decoded twice", fix="Decode once | only.")
    (tmp_path / "docs" / "lessons" / "2026-11-01-a.md").write_text("---\nareas: [net]\n---\n" + a, encoding="utf-8")
    (tmp_path / "docs" / "lessons" / "2026-11-02-b.md").write_text(b, encoding="utf-8")
    return tmp_path


def areas_of(kit: Path) -> lessons.Areas:
    return lessons.Areas.load(kit / lessons.AREAS_FILE)


def _git(path: Path, *args: str) -> str:
    done = subprocess.run(
        ["git", "-C", str(path), "-c", "user.email=t@t", "-c", "user.name=t", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return done.stdout


def commit_base(kit: Path) -> str:
    _git(kit, "init", "-b", "main")
    _git(kit, "add", "-A")
    _git(kit, "commit", "-m", "base")
    return _git(kit, "rev-parse", "HEAD").strip()


# --- the kit itself ---------------------------------------------------------------------------------------------------


def test_the_kits_docs_pass_every_check_and_the_glossary_builds():
    areas = lessons.Areas.load(KIT / lessons.AREAS_FILE)
    assert lessons.problems(KIT, areas) == []
    page = lessons.build(KIT)
    assert [ln for ln in page.splitlines() if ln.startswith("## ")] == [f"## {a}" for a in areas.names]
    assert len(lessons.section(page, "general")) > 3


def test_the_corrections_log_links_a_section_on_every_row_and_quotes_no_prompt():
    text = (KIT / lessons.CORRECTIONS).read_text(encoding="utf-8")
    assert lessons.quoted_rows(text) == [] and lessons.unlinked_rows(text) == []
    sections = {s.ref for s in lessons.sections_in(KIT)}
    rows = [lessons.cells(line)[-1] for _, line in lessons._table_rows(text)]
    assert len(rows) > 150  # every correction of the old page has its line
    for cell in rows:
        page, anchor = lessons.refs_in(cell)[0]
        assert f"{page}#{anchor}" in sections, cell


def test_the_conventions_hold_the_same_numbers_as_the_checker():
    learning = yaml.safe_load((KIT / ".github" / "conventions.yml").read_text(encoding="utf-8"))["learning"]
    assert learning["max_rule_chars"] == lessons.MAX_RULE_CHARS
    assert learning["max_page_kb"] == lessons.MAX_PAGE_KB
    assert tuple(learning["rule_parts"]) == lessons.RULE_PARTS
    assert learning["reason_line"] == lessons.REASON_LINE
    assert learning["legacy_lessons"] == {"folder": "docs/lessons/", "last_date": lessons.LEGACY_LAST_DATE}
    assert learning["format"] == lessons.RULES_DOC.as_posix()
    assert learning["corrections_log"] == lessons.CORRECTIONS.as_posix()


def test_the_page_is_not_a_committed_file():
    """A committed copy goes stale when two pull requests are open (#119): it is built where it is read."""
    tracked = subprocess.run(["git", "-C", str(KIT), "ls-files", "--", "docs"], capture_output=True, text=True)
    assert tracked.returncode == 0 and "mistakes-by-area.md" not in tracked.stdout


def test_the_script_checks_and_prints_the_page():
    script = KIT / ".github" / "scripts" / "mistakes.py"
    check = subprocess.run([sys.executable, str(script), "check"], capture_output=True, text=True)
    assert check.returncode == 0, check.stderr
    render = subprocess.run([sys.executable, str(script), "render"], capture_output=True, text=True, encoding="utf-8")
    assert render.returncode == 0 and render.stdout == lessons.build(KIT)


# --- sections, anchors and rules --------------------------------------------------------------------------------------


def test_sections_have_explicit_or_implicit_anchors_and_code_blocks_are_not_headings():
    sections = lessons.parse_sections("engines/godot/web.md", PAGE)
    assert [(s.level, s.anchor, s.explicit) for s in sections] == [
        (1, "web-export", False),
        (2, "compression", True),
        (2, "threads", False),
    ]
    assert sections[1].ref == "engines/godot/web.md#compression"
    assert len(sections[1].rules()) == 1 and sections[2].rules() == []
    assert lessons.implicit_anchor("A `code` word, and [a link](x.md): done!") == "a-code-word-and-a-link-done"


def test_an_entry_has_its_three_parts_in_order():
    rule = lessons.rule_items(RULE)[0][1]
    parts = lessons.rule_parts(rule)
    assert parts["Approach"] == "Decode a response once, in one place."
    assert parts["Watch out for"] == "a proxy and the client both decoded it, so the bytes were garbage."
    assert parts["Seen"].startswith("Deadnight #12, 2026-11-03 (fix:")
    assert lessons.rule_parts("**Approach:** a **Seen:** b **Watch out for:** c") is None  # out of order
    assert lessons.rule_parts("**Approach:** a **Seen:** d") is None  # a part missing


@pytest.mark.parametrize(
    ("page", "expected"),
    [
        (PAGE, []),
        (PAGE.replace("## Compression {#compression}", "## Compression"), "without an explicit {#anchor}"),
        (
            PAGE.replace("**Watch out for:**", "**Beware:**"),
            "**Approach:**, **Watch out for:**, **Seen:** in this order",
        ),
        (PAGE + "\n- **Rule:** a. **Why:** b. **Fix:** c. **Seen:** #1.\n", "is the old form"),
        (PAGE.replace("Deadnight #12,\n  2026-11-03 (", "somewhere ("), "names its issue or pull request"),
        (PAGE.replace("one place.", "one place. " + "x" * 900), "characters, over 900"),
        (PAGE.replace("{#compression}", "{#Compression_X}"), "is not lowercase words joined by hyphens"),
        (PAGE.replace("## Threads", "## Threads {#compression}"), "anchor #compression is used twice"),
        (PAGE + "\n" + "word " * 11000, "over the 50 KB limit"),
    ],
)
def test_page_problems(page, expected):
    found = lessons.page_problems("engines/godot/web.md", page)
    if expected == []:
        assert found == []
    else:
        assert any(expected in p for p in found), found


@pytest.mark.parametrize(
    "text",
    [
        "Lessons: engines/godot/web.md#compression",
        "Lessons: docs/engines/godot/web.md#compression (the rule)",
        "see [the rule](../engines/godot/web.md#compression)",
        "https://github.com/Ryubara/gdstudio/blob/main/docs/engines/godot/web.md#compression",
    ],
)
def test_a_reference_names_the_page_under_docs_and_the_anchor(text):
    assert lessons.parse_ref(text) == ("engines/godot/web.md", "compression")


def test_refs_of_the_groundwork_checker_agree_with_the_tools():
    sys.path.insert(0, str(KIT / ".github" / "scripts"))
    import groundwork

    text = "a docs/studio/hooks.md#docs, [b](../engines/godot/web.md#compression) and studio/hooks.md#docs again"
    assert groundwork.section_refs(text) == lessons.refs_in(text)
    assert lessons.refs_in(text) == [("studio/hooks.md", "docs"), ("engines/godot/web.md", "compression")]


def test_anchors_reads_a_page(kit):
    assert lessons.anchors(kit / "docs" / "engines" / "godot" / "web.md") == {"web-export", "compression", "threads"}
    assert lessons.anchors(kit / "docs" / "missing.md") == set()


# --- the checks against the checkout ----------------------------------------------------------------------------------


def test_the_fixture_kit_passes(kit):
    assert lessons.problems(kit, areas_of(kit)) == []


def test_problems_name_an_old_lesson_without_areas_and_an_unknown_area(kit):
    path = kit / "docs" / "lessons" / "2026-11-01-a.md"
    path.write_text(path.read_text(encoding="utf-8").replace("---\nareas: [net]\n---\n", ""), encoding="utf-8")
    assert lessons.problems(kit, areas_of(kit)) == ["2026-11-01-a.md: no `areas: [...]` front matter"]
    path = kit / "docs" / "lessons" / "2026-11-02-b.md"
    path.write_text(path.read_text(encoding="utf-8").replace("web, net", "web, nope"), encoding="utf-8")
    assert "unknown area 'nope'" in lessons.problems(kit, areas_of(kit))[-1]


def test_a_lesson_dated_after_the_old_folder_closed_is_refused_without_git(kit):
    text = "---\nareas: [net]\n---\n" + LESSON.format(title="New", fix="x")
    (kit / "docs" / "lessons" / "2026-11-08-new.md").write_text(text, encoding="utf-8")
    found = lessons.problems(kit, areas_of(kit))
    assert len(found) == 1 and "no new file goes in the old lessons folder" in found[0] and "gds learn" in found[0]


@pytest.mark.parametrize("mark", ['"', "'", "“", "‘", "«"])
def test_a_log_row_that_quotes_the_maintainer_is_a_problem(kit, mark):
    """The maintainer's prompts are never quoted in a public repository (gdstudio #780): a row with a cell that starts
    with a quotation mark fails `problems` (pre-commit, CI)."""
    path = kit / lessons.CORRECTIONS
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("| The browser decoded twice |", f"| {mark}Decode it once{mark} |"), "utf-8")
    found = lessons.problems(kit, areas_of(kit))
    assert len(found) == 1 and "maintainer-corrections.md:7: the row quotes the maintainer" in found[0]
    # Headers, separators and quotation marks later in a cell are not quotes of a prompt.
    assert lessons.quoted_rows(text) == []
    assert lessons.quoted_rows('| A |\n| --- |\n| A label read "PLAYER 1" |\n') == []


def test_a_log_row_that_links_no_section_is_a_problem(kit):
    path = kit / lessons.CORRECTIONS
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("[web.md#compression](../engines/godot/web.md#compression)", "see above"), "utf-8")
    assert lessons.problems(kit, areas_of(kit)) == [
        "docs/studio/maintainer-corrections.md:7: the row links no section; its last cell names where the rule lives "
        "as a link to page.md#anchor"
    ]


# --- the checks against a base commit ---------------------------------------------------------------------------------


def test_a_file_added_to_the_old_lessons_folder_is_refused(kit):
    base = commit_base(kit)
    assert lessons.base_problems(kit, base) == []
    (kit / "docs" / "lessons" / "2026-11-03-c.md").write_text("---\nareas: [net]\n---\n# C\n", encoding="utf-8")
    found = lessons.base_problems(kit, base)
    assert len(found) == 1 and "docs/lessons/2026-11-03-c.md: no new file goes in the old lessons folder" in found[0]


def test_a_new_section_needs_a_reason_line_and_its_subsections_do_not(kit):
    base = commit_base(kit)
    page = kit / "docs" / "engines" / "godot" / "web.md"
    page.write_text(PAGE + "\n## Workers {#workers}\n\nText.\n\n### Pools {#pools}\n\nMore.\n", encoding="utf-8")
    found = lessons.base_problems(kit, base)
    assert len(found) == 1 and "web.md:20: the new section 'Workers' needs a reason line" in found[0]
    page.write_text(
        PAGE + "\n## Workers {#workers}\n\n<!-- new section: nothing covered threads in a worker -->\n\n### Pools\n",
        encoding="utf-8",
    )
    assert lessons.base_problems(kit, base) == []


def test_an_anchor_added_to_an_old_heading_or_a_reworded_heading_is_not_new(kit):
    base = commit_base(kit)
    page = kit / "docs" / "engines" / "godot" / "web.md"
    text = PAGE.replace("## Threads", "## Threads in the browser {#threads}")
    page.write_text(text.replace("## Compression {#compression}", "## How responses shrink {#compression}"), "utf-8")
    assert lessons.base_problems(kit, base) == []
    page.write_text(PAGE.replace("## Threads", "## Workers"), encoding="utf-8")  # the anchor changed: a new section
    assert "the new section 'Workers'" in lessons.base_problems(kit, base)[0]


def test_a_new_page_needs_its_reason_line_under_the_title(kit):
    base = commit_base(kit)
    new = kit / "docs" / "gamedev" / "net.md"
    new.parent.mkdir(parents=True)
    new.write_text("# Netcode\n\nText.\n\n## Lag {#lag}\n", encoding="utf-8")  # untracked files count too
    assert "the new page 'Netcode' needs a reason line" in lessons.base_problems(kit, base)[0]
    new.write_text("# Netcode\n\n<!-- new section: no page held netcode -->\n\n## Lag {#lag}\n", encoding="utf-8")
    assert lessons.base_problems(kit, base) == []


def test_an_unknown_base_is_an_error(kit):
    commit_base(kit)
    with pytest.raises(lessons.LessonsError, match="not a commit"):
        lessons.base_problems(kit, "no-such-ref")


# --- gds learn --------------------------------------------------------------------------------------------------------


def test_learn_prints_the_closest_section_with_its_rules_then_old_lessons(kit):
    matches = lessons.learn(kit, "browser decoded the gzip response twice", legacy=3)
    assert matches[0].section.ref == "engines/godot/web.md#compression"
    assert [m.lesson.path.name for m in matches if m.lesson][0] == "2026-11-02-b.md"
    assert all(m.section for m in lessons.learn(kit, "browser decoded the gzip response twice"))  # pages only
    text = lessons.learn_text(kit, "decode a compressed response", legacy=3)
    assert text.splitlines()[2].startswith("1. engines/godot/web.md#compression  Compression")
    assert "   - Decode a response once, in one place." in text
    assert "Old lesson files on the same subject" in text
    assert lessons.learn_text(kit, "zzz qqq").startswith("No section mentions")


def test_learn_skips_the_corrections_log_and_the_format_page(kit):
    (kit / lessons.RULES_DOC).write_text("# Rules\n\n## Compression rules {#x}\n\ncompression compression\n", "utf-8")
    refs = [m.section.ref for m in lessons.learn(kit, "compression", legacy=0)]
    assert refs and not any(r.startswith("studio/") for r in refs)


def test_terms_drop_short_and_common_words_and_stem():
    assert lessons.terms("The keyframes of looping clips, and a bone") == ["keyframe", "loop", "clip", "bone"]


# --- areas and the glossary -------------------------------------------------------------------------------------------


def test_labels_map_to_areas_and_general_is_always_there(kit):
    areas = areas_of(kit)
    assert areas.for_labels({"A-net", "bug"}) == ["general", "net", "web"]
    assert areas.for_labels({"A-tests", "A-net"}) == ["general", "net", "web", "tests"]
    assert areas.for_labels(set()) == ["general"]


def test_keywords_and_page_prefixes_place_text_in_areas(kit):
    areas = areas_of(kit)
    assert areas.classify("the server dropped a packet in the server") == ["net"]
    assert areas.classify("a browser test of the server") == ["net", "web"]
    assert areas.classify("nothing to match") == ["general"]
    assert areas.for_page("engines/godot/web.md", "a server packet") == ["web"]
    assert areas.for_page("studio/x.md", "a server packet") == ["net"]


def test_backfill_adds_areas_by_keyword_and_leaves_the_rest(kit):
    path = kit / "docs" / "lessons" / "2026-11-01-a.md"
    path.write_text(LESSON.format(title="A packet filter dropped a valid packet", fix="x"), encoding="utf-8")
    changed = lessons.backfill(kit, areas_of(kit))
    assert [p.name for p in changed] == ["2026-11-01-a.md"]
    assert path.read_text(encoding="utf-8").startswith("---\nareas: [net]\n---\n# A packet filter")
    assert lessons.backfill(kit, areas_of(kit)) == []  # nothing left to place
    assert lessons.parse_lesson(kit / "docs" / "lessons" / "2026-11-02-b.md").areas == ["web", "net"]


def test_the_glossary_has_the_rules_of_the_sections_first_then_the_old_lessons(kit):
    page = lessons.build(kit)
    assert [ln for ln in page.splitlines() if ln.startswith("## ")] == ["## general", "## net", "## web", "## tests"]
    web = lessons.section(page, "web")
    assert web[0] == (
        "Decode a response once, in one place.",
        "a proxy and the client both decoded it, so the bytes were garbage.",
    )
    assert web[1] == ("The browser decoded twice", "Decode once | only. wrapped on a second line.")
    assert lessons.section(page, "net")[0][0] == "The browser decoded twice"  # newest old lesson first
    assert "(../engines/godot/web.md#compression)" in page and "(../lessons/2026-11-02-b.md)" in page
    assert page.endswith("\n") and not page.endswith("\n\n")


def test_checks_text_takes_the_first_per_area_and_skips_empty_areas(kit):
    text = lessons.checks_text(lessons.build(kit), ["web", "nope"], per_area=1)
    assert text.startswith("[web]\n- Decode a response once, in one place.: ") and "[nope]" not in text
    assert text.count("\n- ") == 1


def test_two_rule_branches_from_the_same_main_merge_clean_in_either_order(kit):
    """Two pull requests add rules to different sections; neither rewrites a shared generated file, so both merge
    without a re-render and the tree stays valid (the failure of #119 was a committed glossary)."""
    commit_base(kit)
    page = "docs/engines/godot/web.md"
    for name, old in (("a", "How responses are compressed."), ("b", "## Threads")):
        _git(kit, "checkout", "-b", f"rule-{name}", "main")
        path = kit / page
        new_rule = RULE.replace("Decode a response once", f"Rule {name}")
        text = path.read_text(encoding="utf-8").replace(
            old, f"{new_rule}\n{old}" if name == "b" else f"{old}\n\n{new_rule}"
        )
        path.write_text(text, encoding="utf-8")
        _git(kit, "commit", "-am", f"rule {name}")
    _git(kit, "checkout", "main")
    for name in ("a", "b"):
        _git(kit, "merge", "--no-ff", "-m", f"merge {name}", f"rule-{name}")
        assert lessons.problems(kit, areas_of(kit)) == []
    rules = [r for s in lessons.sections_in(kit) for r in s.rules()]
    assert any("Rule a" in r for r in rules) and any("Rule b" in r for r in rules)


def test_angle_brackets_outside_code_are_escaped_in_the_page():
    assert lessons.brief("use <owner> or `<repo>`", 80) == "use &lt;owner> or `<repo>`"
    assert lessons.brief("a " * 200, 20).endswith(" ...")
