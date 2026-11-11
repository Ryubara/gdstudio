"""Rules kept in topic sections (docs/studio/rules.md, gdstudio #769): sections, anchors and rules; the checks against
the checkout and against a base commit; `gds learn`; the sections proposed for an issue (`gds brief`, gdstudio #771);
the corrections log; and that the kit's own docs pass every check. There are no lesson categories (no areas file)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from gds_tools import lessons

KIT = Path(__file__).resolve().parents[2]

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
## Threads {{#threads}}

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
    (tmp_path / lessons.CORRECTIONS).write_text(CORRECTIONS, encoding="utf-8")
    (tmp_path / "docs" / "engines" / "godot" / "web.md").write_text(PAGE, encoding="utf-8")
    a = LESSON.format(title="A packet filter dropped a valid packet", fix="Count the bytes.")
    b = "---\nareas: [web, net]\n---\n" + LESSON.format(title="The browser decoded twice", fix="Decode once | only.")
    (tmp_path / "docs" / "lessons" / "2026-11-01-a.md").write_text("---\nareas: [net]\n---\n" + a, encoding="utf-8")
    (tmp_path / "docs" / "lessons" / "2026-11-02-b.md").write_text(b, encoding="utf-8")
    return tmp_path


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


def test_the_kits_docs_pass_every_check_and_hold_no_areas_file():
    assert lessons.problems(KIT) == []
    assert not (KIT / "docs" / "lessons" / "areas.toml").exists()  # no lesson categories (gdstudio #771)


def test_the_corrections_log_links_a_section_on_every_row_and_quotes_no_prompt():
    pages = lessons.corrections_pages(KIT)
    assert KIT / lessons.CORRECTIONS_LOG / "found-by-playing.md" in pages  # split by gdstudio #1115
    rows = []
    for path in pages:
        text = path.read_text(encoding="utf-8")
        assert lessons.quoted_rows(text) == [] and lessons.unlinked_rows(text) == []
        rows += [lessons.cells(line)[-1] for _, line in lessons._table_rows(text)]
    sections = {s.ref for s in lessons.sections_in(KIT)}
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
    assert tuple(learning["anchored_folders"]) == lessons.ANCHORED_FOLDERS
    assert learning["legacy_lessons"] == {"folder": lessons.LESSONS.as_posix() + "/"}
    assert learning["format"] == lessons.RULES_DOC.as_posix()
    assert learning["corrections_log"] == lessons.CORRECTIONS.as_posix()


def test_the_page_is_not_a_committed_file():
    """A committed copy goes stale when two pull requests are open (#119): it is built where it is read."""
    tracked = subprocess.run(["git", "-C", str(KIT), "ls-files", "--", "docs"], capture_output=True, text=True)
    assert tracked.returncode == 0 and "mistakes-by-area.md" not in tracked.stdout


def test_the_script_checks_the_kit():
    script = KIT / ".github" / "scripts" / "mistakes.py"
    check = subprocess.run([sys.executable, str(script), "check"], capture_output=True, text=True)
    assert check.returncode == 0, check.stderr
    render = subprocess.run([sys.executable, str(script), "render"], capture_output=True, text=True)
    assert render.returncode == 2  # the glossary is gone with the areas


# --- sections, anchors and rules --------------------------------------------------------------------------------------


def test_sections_have_explicit_or_implicit_anchors_and_code_blocks_are_not_headings():
    sections = lessons.parse_sections("engines/godot/web.md", PAGE)
    assert [(s.level, s.anchor, s.explicit) for s in sections] == [
        (1, "web-export", False),
        (2, "compression", True),
        (2, "threads", True),
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
        (PAGE.replace("{#threads}", "{#compression}"), "anchor #compression is used twice"),
        (PAGE.replace(" {#threads}", ""), "the heading 'Threads' has no explicit {#anchor}; add {#threads}"),
        (PAGE + "\n" + "word " * 11000, "over the 50 KB limit"),
    ],
)
def test_page_problems(page, expected):
    found = lessons.page_problems("engines/godot/web.md", page)
    if expected == []:
        assert found == []
    else:
        assert any(expected in p for p in found), found


def test_only_the_anchored_folders_need_an_anchor_on_every_heading():
    """studio/, engines/, tools/ and gamedev/ name every ## and ### heading's anchor, so a `Read:` line can name any
    section there (gdstudio #815); a game's pages and the home page do not have to."""
    bare = PAGE.replace(" {#threads}", "")
    for page in ("studio/x.md", "engines/godot/web.md", "tools/blender/x.md", "gamedev/x.md"):
        assert any("has no explicit {#anchor}" in p for p in lessons.page_problems(page, bare)), page
    for page in ("games/deadnight/x.md", "index.md"):
        assert lessons.page_problems(page, bare) == [], page


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
    assert lessons.problems(kit) == []


@pytest.mark.parametrize("mark", ['"', "'", "“", "‘", "«"])
def test_a_log_row_that_quotes_the_maintainer_is_a_problem(kit, mark):
    """The maintainer's prompts are never quoted in a public repository (gdstudio #780): a row with a cell that starts
    with a quotation mark fails `problems` (pre-commit, CI)."""
    path = kit / lessons.CORRECTIONS
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("| The browser decoded twice |", f"| {mark}Decode it once{mark} |"), "utf-8")
    found = lessons.problems(kit)
    assert len(found) == 1 and "maintainer-corrections.md:7: the row quotes the maintainer" in found[0]
    # Headers, separators and quotation marks later in a cell are not quotes of a prompt.
    assert lessons.quoted_rows(text) == []
    assert lessons.quoted_rows('| A |\n| --- |\n| A label read "PLAYER 1" |\n') == []


def test_a_log_row_that_links_no_section_is_a_problem(kit):
    path = kit / lessons.CORRECTIONS
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("[web.md#compression](../engines/godot/web.md#compression)", "see above"), "utf-8")
    assert lessons.problems(kit) == [
        "docs/studio/maintainer-corrections.md:7: the row links no section; its last cell names where the rule lives "
        "as a link to page.md#anchor"
    ]


def test_a_row_on_a_page_of_the_log_folder_is_checked_and_named_by_its_page(kit):
    """The log's rows moved to a folder of pages when the page reached the size limit (gdstudio #1115): each page's
    rows get the same checks, and a problem names the page it is on."""
    folder = kit / lessons.CORRECTIONS_LOG
    folder.mkdir()
    (folder / "index.md").write_text("# The corrections log\n\n- [Found by playing](found-by-playing.md)\n", "utf-8")
    page = "# Found by playing\n\n| Recorded | Source | What | Rule |\n| --- | --- | --- | --- |\n"
    (folder / "found-by-playing.md").write_text(page + "| 2026-11-11 | x #1 | “Do it” | see above |\n", "utf-8")
    found = lessons.problems(kit)
    assert [f.split(": the row")[0] for f in found] == ["docs/studio/corrections-log/found-by-playing.md:5"] * 2
    assert "quotes the maintainer" in found[0] and "links no section" in found[1]


def test_the_log_and_its_pages_are_not_where_a_rule_lives():
    for page in (
        "studio/maintainer-corrections.md",
        "docs/studio/corrections-log/found-by-playing.md",
        "studio/corrections-log/index.md",
    ):
        assert lessons.is_corrections_page(page), page
    assert not lessons.is_corrections_page("studio/rules.md")


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
    text = PAGE.replace("## Threads {#threads}", "## Threads in the browser {#threads}")
    page.write_text(text.replace("## Compression {#compression}", "## How responses shrink {#compression}"), "utf-8")
    assert lessons.base_problems(kit, base) == []
    page.write_text(PAGE.replace("## Threads {#threads}", "## Workers"), encoding="utf-8")  # new anchor and words: new
    assert "the new section 'Workers'" in lessons.base_problems(kit, base)[0]


def test_an_old_heading_given_a_shorter_anchor_is_not_new(kit):
    """Anchoring a long heading may choose a shorter anchor than its slug when nothing links to it (rules.md#anchors):
    its words are the base's, so it is not a new section and needs no reason line (gdstudio #815)."""
    page = kit / "docs" / "engines" / "godot" / "web.md"
    page.write_text(PAGE.replace("## Threads {#threads}", "## Threads"), encoding="utf-8")
    base = commit_base(kit)
    page.write_text(PAGE.replace("{#threads}", "{#workers}"), encoding="utf-8")
    assert lessons.base_problems(kit, base) == []


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


def test_learn_prints_the_closest_section_with_its_rules(kit):
    matches = lessons.learn(kit, "browser decoded the gzip response twice")
    assert matches[0].section.ref == "engines/godot/web.md#compression"
    assert all(m.section for m in matches)  # pages only: the old lesson files are gone (gdstudio #770)
    text = lessons.learn_text(kit, "decode a compressed response")
    assert text.splitlines()[2].startswith("1. engines/godot/web.md#compression  Compression")
    assert "   - Decode a response once, in one place." in text
    assert "Old lesson files" not in text
    assert lessons.learn_text(kit, "zzz qqq").startswith("No section mentions")


def test_learn_skips_the_corrections_log_and_the_format_page(kit):
    (kit / lessons.RULES_DOC).write_text("# Rules\n\n## Compression rules {#x}\n\ncompression compression\n", "utf-8")
    folder = kit / lessons.CORRECTIONS_LOG
    folder.mkdir()
    (folder / "rows.md").write_text("# Rows\n\n## Compression rows {#y}\n\ncompression compression\n", "utf-8")
    refs = [m.section.ref for m in lessons.learn(kit, "compression")]
    assert refs and not any(r.startswith("studio/") for r in refs)


def test_terms_drop_short_and_common_words_and_stem():
    assert lessons.terms("The keyframes of looping clips, and a bone") == ["keyframe", "loop", "clip", "bone"]


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
        assert lessons.problems(kit) == []
    rules = [r for s in lessons.sections_in(kit) for r in s.rules()]
    assert any("Rule a" in r for r in rules) and any("Rule b" in r for r in rules)


def test_what_main_already_has_is_not_new_in_a_merge_of_main(kit):
    """Mid-merge, the merge base is still the old main: a section main added since is not the branch's own, so the
    default compares with the merge base and origin/main together (`default_bases`)."""
    old_main = commit_base(kit)
    page = kit / "docs" / "engines" / "godot" / "web.md"
    page.write_text(PAGE + "\n## Workers {#workers}\n\nAdded on main.\n", encoding="utf-8")
    _git(kit, "commit", "-am", "main adds a section")
    new_main = _git(kit, "rev-parse", "HEAD").strip()
    assert "the new section 'Workers'" in lessons.base_problems(kit, old_main)[0]
    assert lessons.base_problems(kit, [old_main, new_main]) == []


# --- gds brief: the sections a task agent reads first -----------------------------------------------------------------

HOOKS_PAGE = """# Hooks

The hooks of the kit.

## The agent guard {#agent-guard}

The PreToolUse guard on the Agent tool refuses a task agent whose prompt names no started issue. It reads
`.claude/hooks/guards.py` and the ledger of started issues.

## Disk {#disk}

The disk guard frees space when the drive is nearly full, and refuses a new worktree under the hard limit.

## Parent {#parent}

### Child {#child}

A subsection with text of its own, long enough to be read as a section rather than a heading over others.
"""


@pytest.fixture()
def brief_kit(kit: Path) -> Path:
    (kit / "docs" / "studio" / "hooks.md").write_text(HOOKS_PAGE, encoding="utf-8")
    return kit


def refs_of(found: list[lessons.Proposal]) -> list[str]:
    return [p.section.ref for p in found]


def test_paths_in_finds_files_and_deep_folders_but_not_refs_urls_or_words():
    text = (
        "Edit `.claude/hooks/guards.py` and tools.toml, see docs/lessons/ and studio/hooks.md#disk, not design/, "
        "e.g. v1.2, or https://example.com/a/b.py"
    )
    assert lessons.paths_in(text) == [".claude/hooks/guards.py", "tools.toml", "docs/lessons/"]


def test_propose_puts_named_sections_then_named_paths_then_words(brief_kit):
    found = lessons.propose(
        brief_kit,
        "hooks: Fix the agent guard",
        "The guard in .claude/hooks/guards.py misreads a prompt; see studio/hooks.md#disk and "
        "docs/engines/godot/web.md for the browser.",
        {"A-hooks": "Claude Code hooks and the guards"},
        limit=4,
    )
    assert refs_of(found)[:2] == ["studio/hooks.md#disk", "studio/hooks.md#agent-guard"]
    assert found[2].section.page == "engines/godot/web.md" and len(found) == 4
    assert [p.why for p in found[:3]] == [
        "named in the issue",
        "mentions .claude/hooks/guards.py",
        "the issue names docs/engines/godot/web.md",
    ]
    assert found[0].line == "Read: studio/hooks.md#disk"


def test_propose_ranks_by_words_skips_headings_over_subsections_and_the_log(brief_kit):
    found = lessons.propose(brief_kit, "net: Fix the disk guard on a full drive", limit=3)
    assert found[0].section.ref == "studio/hooks.md#disk" and found[0].why == "closest to the issue's words"
    assert "studio/hooks.md#parent" not in refs_of(lessons.propose(brief_kit, "parent child subsection", limit=6))
    assert not any(r.startswith("studio/maintainer-corrections.md") for r in refs_of(found))


def test_propose_takes_a_pull_requests_changed_files_and_its_labels(brief_kit):
    found = lessons.propose(brief_kit, "x: Update one thing", "", {}, [".claude/hooks/guards.py"], limit=1)
    assert refs_of(found) == ["studio/hooks.md#agent-guard"]
    label = lessons.propose(brief_kit, "x: Update it", "", {"A-web": "the browser build"}, limit=1)
    assert [p.section.page for p in label] == ["engines/godot/web.md"]  # `web` and `browser` from the label
    assert lessons.propose(brief_kit, "zzz qqq") == []


def test_brief_text_and_missing_refs(brief_kit):
    found = lessons.propose(brief_kit, "the disk guard", limit=1)
    assert lessons.brief_text(found) == "Read: studio/hooks.md#disk"
    assert lessons.brief_text(found, why=True) == "Read: studio/hooks.md#disk  Disk (closest to the issue's words)"
    text = "Read: studio/hooks.md#disk, studio/hooks.md#nope\nRead: docs/nowhere.md#x"
    assert lessons.missing_refs(brief_kit, text) == ["studio/hooks.md#nope", "nowhere.md#x"]


def test_the_kit_proposes_real_sections_for_this_issue():
    found = lessons.propose(
        KIT, "agents: Add gds brief and require Read lines in task prompts", "", {"A-agents": "Agents"}, limit=6
    )
    assert "studio/starting-work.md#starting-an-agent" in refs_of(found)
    assert lessons.missing_refs(KIT, "\n".join(p.line for p in found)) == []
